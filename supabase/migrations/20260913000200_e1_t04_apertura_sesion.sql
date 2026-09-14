begin;

-- E1-T04. Migración aditiva: T03 y los contratos H1-H6 no se reescriben.
-- FK compuesta para impedir asociaciones de idempotencia/auditoría caja-local-sesión inválidas.
alter table public.sesion_caja add constraint uq_sesion_caja_id_caja_local
  unique (id, caja_id, local_id);

-- Registro específico de idempotencia de apertura, incluido recuperar una sesión
-- de otro cajero. No es auditoría de una apertura nueva ni autorización genérica.
create table public.solicitud_apertura_caja (
  caja_id uuid not null,
  local_id uuid not null,
  actor_id uuid not null,
  idempotency_key uuid not null,
  monto_solicitado numeric(14,2) not null,
  sesion_caja_id uuid not null,
  creado_en timestamptz not null default now(),
  constraint pk_solicitud_apertura_caja primary key (caja_id, actor_id, idempotency_key),
  constraint ck_solicitud_apertura_caja_monto check (monto_solicitado >= 0 and monto_solicitado <> 'NaN'::numeric),
  constraint fk_solicitud_apertura_caja_sesion foreign key (sesion_caja_id, caja_id, local_id)
    references public.sesion_caja (id, caja_id, local_id) on delete restrict,
  constraint fk_solicitud_apertura_caja_actor foreign key (actor_id)
    references public.perfil_usuario (id) on delete restrict
);
create index idx_solicitud_apertura_caja_sesion on public.solicitud_apertura_caja (sesion_caja_id);
create index idx_solicitud_apertura_caja_actor on public.solicitud_apertura_caja (actor_id);

-- Sólo APERTURA en T04. No anticipa eventos ni lecturas de auditoría integral T11.
-- IDs y valores del snapshot normalizados, sin payload arbitrario del cliente.
create table public.auditoria_caja (
  id uuid not null default gen_random_uuid(),
  tipo text not null,
  local_id uuid not null,
  caja_id uuid not null,
  sesion_caja_id uuid not null,
  actor_id uuid not null,
  creado_en timestamptz not null default now(),
  monto_inicial numeric(14,2) not null,
  estado_anterior text null,
  estado_nuevo text not null,
  constraint pk_auditoria_caja primary key (id),
  constraint uq_auditoria_caja_apertura unique (sesion_caja_id, tipo),
  constraint ck_auditoria_caja_apertura check (
    tipo = 'APERTURA' and estado_anterior is null and estado_nuevo = 'ABIERTA'
    and monto_inicial >= 0 and monto_inicial <> 'NaN'::numeric
  ),
  constraint fk_auditoria_caja_sesion foreign key (sesion_caja_id, caja_id, local_id)
    references public.sesion_caja (id, caja_id, local_id) on delete restrict,
  constraint fk_auditoria_caja_actor foreign key (actor_id)
    references public.perfil_usuario (id) on delete restrict
);
create index idx_auditoria_caja_local_creado_en on public.auditoria_caja (local_id, creado_en);
create index idx_auditoria_caja_actor on public.auditoria_caja (actor_id);

create function public.tgf_apertura_caja_inmutable()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception using errcode = '23514', message = 'El registro de apertura es inmutable';
end;
$$;
alter function public.tgf_apertura_caja_inmutable() owner to postgres;
revoke all on function public.tgf_apertura_caja_inmutable() from public, anon, authenticated, service_role;
create trigger trg_solicitud_apertura_caja_before_write_historia
  before update or delete on public.solicitud_apertura_caja
  for each row execute function public.tgf_apertura_caja_inmutable();
create trigger trg_auditoria_caja_before_write_historia
  before update or delete on public.auditoria_caja
  for each row execute function public.tgf_apertura_caja_inmutable();

alter table public.solicitud_apertura_caja enable row level security;
alter table public.auditoria_caja enable row level security;
revoke all on public.solicitud_apertura_caja, public.auditoria_caja
  from public, anon, authenticated, service_role;

-- Lecturas de dominio únicamente. Las claves de idempotencia no se publican.
grant select on public.caja to authenticated;
grant select (id, caja_id, local_id, abierta_por, abierta_en, monto_inicial,
  estado, cerrada_por, cerrada_en, efectivo_esperado, efectivo_contado, diferencia,
  motivo_diferencia) on public.sesion_caja to authenticated;
create policy pol_caja_select_caja_administrador_local on public.caja
  for select to authenticated using (exists (
    select 1 from public.obtener_contexto_autenticado() c
    where c.local_id = caja.local_id and c.rol_codigo in ('CAJA', 'ADMINISTRADOR')
  ));
create policy pol_sesion_caja_select_caja_administrador_local on public.sesion_caja
  for select to authenticated using (exists (
    select 1 from public.obtener_contexto_autenticado() c
    where c.local_id = sesion_caja.local_id and c.rol_codigo in ('CAJA', 'ADMINISTRADOR')
  ));

create function public.rpc_abrir_sesion_caja(
  p_caja_id uuid, p_monto_inicial numeric, p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare
  v_actor uuid := auth.uid();
  v_local uuid;
  v_rol text;
  v_sesion public.sesion_caja%rowtype;
  v_solicitud public.solicitud_apertura_caja%rowtype;
  v_creada boolean := false;
  v_constraint text;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  if p_idempotency_key is null or p_monto_inicial is null
    or p_monto_inicial < 0 or p_monto_inicial >= 1000000000000
    or p_monto_inicial <> pg_catalog.round(p_monto_inicial, 2) then
    -- NaN compara mayor que cualquier número; Infinity también se rechaza.
    raise exception using errcode = '22023', message = 'Monto inicial o clave de solicitud inválidos';
  end if;
  -- Orden caja -> sesión. Una segunda RPC espera y después lee el commit ganador.
  perform 1 from public.caja c
    where c.id = p_caja_id and c.local_id = v_local and c.activo for update;
  if not found then
    raise exception using errcode = '42501', message = 'Caja no disponible';
  end if;
  select r.* into v_solicitud from public.solicitud_apertura_caja r
    where r.caja_id = p_caja_id and r.actor_id = v_actor and r.idempotency_key = p_idempotency_key;
  if found then
    if v_solicitud.monto_solicitado <> p_monto_inicial then
      raise exception using errcode = '22023', message = 'Clave de solicitud reutilizada con otro monto';
    end if;
    select s.* into strict v_sesion from public.sesion_caja s where s.id = v_solicitud.sesion_caja_id;
    -- Si cerró después, informa CERRADA: no reabre ni crea otra sesión en un retry.
    return pg_catalog.to_jsonb(v_sesion) - 'idempotency_key';
  end if;

  -- Compatibilidad con una apertura persistida bajo el modelo T03 sin registro
  -- de solicitud T04. No fabrica auditoría retroactiva ni vuelve a abrirla.
  select s.* into v_sesion from public.sesion_caja s
    where s.caja_id = p_caja_id and s.abierta_por = v_actor and s.idempotency_key = p_idempotency_key;
  if found then
    if v_sesion.monto_inicial <> p_monto_inicial then
      raise exception using errcode = '22023', message = 'Clave de solicitud reutilizada con otro monto';
    end if;
    insert into public.solicitud_apertura_caja
      (caja_id, local_id, actor_id, idempotency_key, monto_solicitado, sesion_caja_id)
      values (p_caja_id, v_local, v_actor, p_idempotency_key, p_monto_inicial, v_sesion.id);
    return pg_catalog.to_jsonb(v_sesion) - 'idempotency_key';
  end if;

  select s.* into v_sesion from public.sesion_caja s
    where s.caja_id = p_caja_id and s.local_id = v_local and s.estado = 'ABIERTA' for update;
  if not found then
    begin
      insert into public.sesion_caja (caja_id, local_id, abierta_por, monto_inicial, idempotency_key)
        values (p_caja_id, v_local, v_actor, p_monto_inicial, p_idempotency_key)
        returning * into v_sesion;
      v_creada := true;
    exception when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint <> 'uq_sesion_caja_abierta' then raise; end if;
      -- Defensa ante otro escritor que alcanzó el índice sin el lock de caja.
      -- Nueva sentencia, snapshot fresco bajo READ COMMITTED; no filtra 23505 normal.
      select s.* into v_sesion from public.sesion_caja s
        where s.caja_id = p_caja_id and s.local_id = v_local and s.estado = 'ABIERTA' for update;
      if not found then
        raise exception using errcode = '40001', message = 'La sesión cambió; reintente la solicitud';
      end if;
    end;
  end if;

  if v_creada then
    insert into public.auditoria_caja (tipo, local_id, caja_id, sesion_caja_id,
      actor_id, creado_en, monto_inicial, estado_anterior, estado_nuevo)
    values ('APERTURA', v_local, p_caja_id, v_sesion.id, v_actor,
      v_sesion.abierta_en, v_sesion.monto_inicial, null, 'ABIERTA');
  end if;
  insert into public.solicitud_apertura_caja
    (caja_id, local_id, actor_id, idempotency_key, monto_solicitado, sesion_caja_id)
    values (p_caja_id, v_local, v_actor, p_idempotency_key, p_monto_inicial, v_sesion.id);
  return pg_catalog.to_jsonb(v_sesion) - 'idempotency_key';
end;
$$;

create function public.rpc_obtener_sesion_caja_activa(p_caja_id uuid, p_sesion_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog as $$
declare v_local uuid; v_rol text; v_sesion public.sesion_caja%rowtype;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol from public.obtener_contexto_autenticado() c;
  if auth.uid() is null or v_local is null or v_rol is null or v_rol not in ('CAJA', 'ADMINISTRADOR') then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  perform 1 from public.caja c where c.id = p_caja_id and c.local_id = v_local and c.activo;
  if not found then raise exception using errcode = '42501', message = 'Caja no disponible'; end if;
  select s.* into v_sesion from public.sesion_caja s
    where s.caja_id = p_caja_id and s.local_id = v_local and s.estado = 'ABIERTA';
  if p_sesion_id is not null and (v_sesion.id is null or v_sesion.id <> p_sesion_id) then
    raise exception using errcode = '40001', message = 'Sesión activa no disponible para la caja seleccionada';
  end if;
  if v_sesion.id is null then return null; end if;
  return pg_catalog.to_jsonb(v_sesion) - 'idempotency_key';
end;
$$;

create function public.rpc_obtener_historial_sesiones_caja(
  p_caja_id uuid default null, p_limite integer default 50, p_offset integer default 0
)
returns setof jsonb language plpgsql stable security definer set search_path = pg_catalog as $$
declare v_local uuid; v_rol text;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol from public.obtener_contexto_autenticado() c;
  if auth.uid() is null or v_local is null or v_rol is null or v_rol not in ('CAJA', 'ADMINISTRADOR') then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  if p_limite is null or p_limite not between 1 and 200 or p_offset is null or p_offset < 0 then
    raise exception using errcode = '22023', message = 'Paginación inválida';
  end if;
  -- Histórico también disponible para cajas inactivas del mismo local.
  if p_caja_id is not null and not exists (
    select 1 from public.caja c where c.id = p_caja_id and c.local_id = v_local
  ) then raise exception using errcode = '42501', message = 'Caja no disponible'; end if;
  return query select pg_catalog.to_jsonb(s) - 'idempotency_key'
    from public.sesion_caja s where s.local_id = v_local and (p_caja_id is null or s.caja_id = p_caja_id)
    order by s.abierta_en desc, s.id desc limit p_limite offset p_offset;
end;
$$;

alter function public.rpc_abrir_sesion_caja(uuid,numeric,uuid) owner to postgres;
alter function public.rpc_obtener_sesion_caja_activa(uuid,uuid) owner to postgres;
alter function public.rpc_obtener_historial_sesiones_caja(uuid,integer,integer) owner to postgres;
revoke all on function public.rpc_abrir_sesion_caja(uuid,numeric,uuid),
  public.rpc_obtener_sesion_caja_activa(uuid,uuid), public.rpc_obtener_historial_sesiones_caja(uuid,integer,integer)
  from public, anon, authenticated, service_role;
grant execute on function public.rpc_abrir_sesion_caja(uuid,numeric,uuid),
  public.rpc_obtener_sesion_caja_activa(uuid,uuid), public.rpc_obtener_historial_sesiones_caja(uuid,integer,integer)
  to authenticated;

comment on table public.solicitud_apertura_caja is
  'Idempotencia específica de apertura/recuperación. Conserva sesión resultado por caja, actor y clave, incluso cuando el actor no abrió esa sesión. Nombre semántico.';
comment on table public.auditoria_caja is
  'Eventos financieros append-only. T04 registra únicamente APERTURA real; recuperaciones y reintentos no duplican el evento. Nombre semántico histórico.';
comment on function public.tgf_apertura_caja_inmutable() is
  'Impide editar o borrar auditoría y solicitudes de apertura persistidas; no sustituye restricciones ni permisos.';
comment on function public.rpc_abrir_sesion_caja(uuid,numeric,uuid) is
  'CAJA activo: crea o recupera sesión compartida de su caja/local. Serializa por caja; clave idempotente por actor; apertura y auditoría son atómicas. Devuelve snapshot actual sin clave interna.';
comment on function public.rpc_obtener_sesion_caja_activa(uuid,uuid) is
  'CAJA/ADMINISTRADOR del local: snapshot activo o null; sesión esperada opcional rechaza caja equivocada o sesión cerrada. No altera actores ni sesión.';
comment on function public.rpc_obtener_historial_sesiones_caja(uuid,integer,integer) is
  'Histórico básico paginado del local autenticado para CAJA/ADMINISTRADOR, incluidas cajas inactivas; conserva actores de apertura/cierre y no expone claves internas.';

notify pgrst, 'reload schema';
commit;
