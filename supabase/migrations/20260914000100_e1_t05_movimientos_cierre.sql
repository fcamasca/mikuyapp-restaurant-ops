begin;

create table public.movimiento_caja (
  id uuid not null default gen_random_uuid(),
  sesion_caja_id uuid not null,
  caja_id uuid not null,
  local_id uuid not null,
  tipo text not null,
  importe numeric(14,2) not null,
  motivo text not null,
  actor_id uuid not null default auth.uid(),
  creado_en timestamptz not null default now(),
  idempotency_key uuid not null,
  constraint pk_movimiento_caja primary key (id),
  constraint uq_movimiento_caja_id_sesion unique (id, sesion_caja_id),
  constraint uq_movimiento_caja_idempotencia unique (sesion_caja_id, actor_id, idempotency_key),
  constraint ck_movimiento_caja_tipo check (tipo in ('ENTRADA', 'SALIDA')),
  constraint ck_movimiento_caja_importe check (
    importe > 0 and importe <> 'NaN'::numeric and importe < 1000000000000
      and importe = round(importe, 2)
  ),
  constraint ck_movimiento_caja_motivo check (btrim(motivo) <> ''),
  constraint fk_movimiento_caja_sesion foreign key (sesion_caja_id, caja_id, local_id)
    references public.sesion_caja (id, caja_id, local_id) on delete restrict,
  constraint fk_movimiento_caja_actor foreign key (actor_id)
    references public.perfil_usuario (id) on delete restrict
);
create index idx_movimiento_caja_sesion_creado_en
  on public.movimiento_caja (sesion_caja_id, creado_en, id);
create index idx_movimiento_caja_local_creado_en
  on public.movimiento_caja (local_id, creado_en desc);

create table public.resumen_cierre_sesion_caja (
  sesion_caja_id uuid not null,
  caja_id uuid not null,
  local_id uuid not null,
  cerrado_por uuid not null,
  cerrado_en timestamptz not null,
  tipo_cierre text not null,
  pago_efectivo numeric(14,2) not null,
  propina_efectivo numeric(14,2) not null,
  pago_yape numeric(14,2) not null,
  propina_yape numeric(14,2) not null,
  pago_plin numeric(14,2) not null,
  propina_plin numeric(14,2) not null,
  pago_tarjeta numeric(14,2) not null,
  propina_tarjeta numeric(14,2) not null,
  entradas numeric(14,2) not null,
  salidas numeric(14,2) not null,
  efectivo_esperado numeric(14,2) not null,
  efectivo_contado numeric(14,2) not null,
  diferencia numeric(14,2) not null,
  motivo text null,
  constraint pk_resumen_cierre_sesion_caja primary key (sesion_caja_id),
  constraint ck_resumen_cierre_tipo check (tipo_cierre in ('NORMAL', 'SUPERVISOR')),
  constraint ck_resumen_cierre_totales check (
    pago_efectivo >= 0 and propina_efectivo >= 0 and pago_yape >= 0 and propina_yape >= 0
      and pago_plin >= 0 and propina_plin >= 0 and pago_tarjeta >= 0 and propina_tarjeta >= 0
      and entradas >= 0 and salidas >= 0
      and efectivo_contado >= 0 and diferencia = efectivo_contado - efectivo_esperado
      and efectivo_contado <> 'NaN'::numeric and efectivo_esperado <> 'NaN'::numeric
  ),
  constraint ck_resumen_cierre_motivo check (
    (diferencia = 0 or (motivo is not null and btrim(motivo) <> ''))
      and (tipo_cierre <> 'SUPERVISOR' or (motivo is not null and btrim(motivo) <> ''))
  ),
  constraint fk_resumen_cierre_sesion foreign key (sesion_caja_id, caja_id, local_id)
    references public.sesion_caja (id, caja_id, local_id) on delete restrict,
  constraint fk_resumen_cierre_actor foreign key (cerrado_por)
    references public.perfil_usuario (id) on delete restrict
);
create index idx_resumen_cierre_local_cerrado_en
  on public.resumen_cierre_sesion_caja (local_id, cerrado_en desc);

create table public.solicitud_cierre_caja (
  sesion_caja_id uuid not null,
  actor_id uuid not null,
  idempotency_key uuid not null,
  efectivo_contado numeric(14,2) not null,
  motivo text null,
  tipo_cierre text not null,
  creado_en timestamptz not null default now(),
  constraint pk_solicitud_cierre_caja primary key (sesion_caja_id, actor_id, idempotency_key),
  constraint ck_solicitud_cierre_tipo check (tipo_cierre in ('NORMAL', 'SUPERVISOR')),
  constraint ck_solicitud_cierre_contado check (
    efectivo_contado >= 0 and efectivo_contado <> 'NaN'::numeric
      and efectivo_contado < 1000000000000 and efectivo_contado = round(efectivo_contado, 2)
  ),
  constraint ck_solicitud_cierre_motivo check (motivo is null or btrim(motivo) <> ''),
  constraint fk_solicitud_cierre_sesion foreign key (sesion_caja_id)
    references public.sesion_caja (id) on delete restrict,
  constraint fk_solicitud_cierre_actor foreign key (actor_id)
    references public.perfil_usuario (id) on delete restrict
);

create function public.tgf_evento_caja_inmutable()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception using errcode = '23514', message = 'El evento financiero es inmutable';
end;
$$;
alter function public.tgf_evento_caja_inmutable() owner to postgres;
revoke all on function public.tgf_evento_caja_inmutable() from public, anon, authenticated, service_role;
create trigger trg_movimiento_caja_before_write
  before update or delete on public.movimiento_caja
  for each row execute function public.tgf_evento_caja_inmutable();
create trigger trg_resumen_cierre_sesion_caja_before_write
  before update or delete on public.resumen_cierre_sesion_caja
  for each row execute function public.tgf_evento_caja_inmutable();
create trigger trg_solicitud_cierre_caja_before_write
  before update or delete on public.solicitud_cierre_caja
  for each row execute function public.tgf_evento_caja_inmutable();

-- T04 sólo admitía APERTURA. T05 amplía exclusivamente los eventos necesarios
-- para ENTRADA/SALIDA y CIERRE; T11 completará el catálogo financiero restante.
alter table public.auditoria_caja
  drop constraint uq_auditoria_caja_apertura,
  drop constraint ck_auditoria_caja_apertura,
  alter column monto_inicial drop not null,
  add column movimiento_caja_id uuid null,
  add column importe numeric(14,2) null,
  add column tipo_movimiento text null,
  add column efectivo_esperado numeric(14,2) null,
  add column efectivo_contado numeric(14,2) null,
  add column diferencia numeric(14,2) null,
  add column motivo text null,
  add constraint fk_auditoria_caja_movimiento foreign key (movimiento_caja_id, sesion_caja_id)
    references public.movimiento_caja (id, sesion_caja_id) on delete restrict,
  add constraint ck_auditoria_caja_t05 check (
    (tipo = 'APERTURA' and movimiento_caja_id is null and monto_inicial is not null
      and monto_inicial >= 0 and monto_inicial <> 'NaN'::numeric
      and importe is null and tipo_movimiento is null and efectivo_esperado is null
      and efectivo_contado is null and diferencia is null and motivo is null
      and estado_anterior is null and estado_nuevo = 'ABIERTA')
    or
    (tipo in ('ENTRADA', 'SALIDA') and movimiento_caja_id is not null and monto_inicial is null
      and importe > 0 and tipo_movimiento = tipo and efectivo_esperado is null
      and efectivo_contado is null and diferencia is null
      and motivo is not null and btrim(motivo) <> ''
      and estado_anterior = 'ABIERTA' and estado_nuevo = 'ABIERTA')
    or
    (tipo in ('CIERRE', 'CIERRE_SUPERVISOR') and movimiento_caja_id is null and monto_inicial is null
      and importe is null and tipo_movimiento is null and efectivo_esperado is not null
      and efectivo_contado is not null and diferencia = efectivo_contado - efectivo_esperado
      and (diferencia = 0 or (motivo is not null and btrim(motivo) <> ''))
      and (tipo <> 'CIERRE_SUPERVISOR' or (motivo is not null and btrim(motivo) <> ''))
      and estado_anterior = 'ABIERTA' and estado_nuevo = 'CERRADA')
  );
create unique index uq_auditoria_caja_apertura
  on public.auditoria_caja (sesion_caja_id) where tipo = 'APERTURA';
create unique index uq_auditoria_caja_movimiento
  on public.auditoria_caja (movimiento_caja_id) where movimiento_caja_id is not null;
create unique index uq_auditoria_caja_cierre
  on public.auditoria_caja (sesion_caja_id) where tipo in ('CIERRE', 'CIERRE_SUPERVISOR');

create function public.fn_totales_sesion_caja(p_sesion_caja_id uuid)
returns table (
  pago_efectivo numeric, propina_efectivo numeric,
  pago_yape numeric, propina_yape numeric,
  pago_plin numeric, propina_plin numeric,
  pago_tarjeta numeric, propina_tarjeta numeric,
  entradas numeric, salidas numeric
)
language sql stable security definer set search_path = pg_catalog as $$
  select
    coalesce(sum(p.importe) filter (where p.medio = 'EFECTIVO'), 0),
    coalesce(sum(p.propina) filter (where p.medio = 'EFECTIVO'), 0),
    coalesce(sum(p.importe) filter (where p.medio = 'YAPE'), 0),
    coalesce(sum(p.propina) filter (where p.medio = 'YAPE'), 0),
    coalesce(sum(p.importe) filter (where p.medio = 'PLIN'), 0),
    coalesce(sum(p.propina) filter (where p.medio = 'PLIN'), 0),
    coalesce(sum(p.importe) filter (where p.medio = 'TARJETA'), 0),
    coalesce(sum(p.propina) filter (where p.medio = 'TARJETA'), 0),
    coalesce((select sum(m.importe) from public.movimiento_caja m
      where m.sesion_caja_id = p_sesion_caja_id and m.tipo = 'ENTRADA'), 0),
    coalesce((select sum(m.importe) from public.movimiento_caja m
      where m.sesion_caja_id = p_sesion_caja_id and m.tipo = 'SALIDA'), 0)
  from public.pago p where p.sesion_caja_id = p_sesion_caja_id;
$$;
alter function public.fn_totales_sesion_caja(uuid) owner to postgres;
revoke all on function public.fn_totales_sesion_caja(uuid) from public, anon, authenticated, service_role;

create function public.rpc_registrar_movimiento_caja(
  p_sesion_caja_id uuid, p_tipo text, p_importe numeric,
  p_motivo text, p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare
  v_actor uuid := auth.uid(); v_local uuid; v_rol text; v_caja_id uuid;
  v_sesion public.sesion_caja%rowtype; v_movimiento public.movimiento_caja%rowtype;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode = '42501', message = 'No autorizado para registrar movimientos';
  end if;
  if p_sesion_caja_id is null or p_idempotency_key is null
    or p_tipo is null or p_tipo not in ('ENTRADA', 'SALIDA')
    or p_importe is null or p_importe <= 0 or p_importe >= 1000000000000
    or p_importe <> pg_catalog.round(p_importe, 2)
    or p_motivo is null or pg_catalog.btrim(p_motivo) = '' then
    raise exception using errcode = '22023', message = 'Movimiento inválido';
  end if;
  select s.caja_id into v_caja_id from public.sesion_caja s
    where s.id = p_sesion_caja_id and s.local_id = v_local;
  if v_caja_id is null then
    raise exception using errcode = '42501', message = 'Sesión no disponible';
  end if;
  perform 1 from public.caja c
    where c.id = v_caja_id and c.local_id = v_local and c.activo for update;
  if not found then raise exception using errcode = '42501', message = 'Caja no disponible'; end if;
  select s.* into strict v_sesion from public.sesion_caja s
    where s.id = p_sesion_caja_id and s.caja_id = v_caja_id and s.local_id = v_local for update;
  select m.* into v_movimiento from public.movimiento_caja m
    where m.sesion_caja_id = v_sesion.id and m.actor_id = v_actor
      and m.idempotency_key = p_idempotency_key;
  if found then
    if v_movimiento.tipo <> p_tipo or v_movimiento.importe <> p_importe
      or v_movimiento.motivo <> pg_catalog.btrim(p_motivo) then
      raise exception using errcode = '22023', message = 'Clave de solicitud reutilizada con otros datos';
    end if;
    return pg_catalog.to_jsonb(v_movimiento) - 'idempotency_key';
  end if;
  if v_sesion.estado is distinct from 'ABIERTA' then
    raise exception using errcode = '40001', message = 'La sesión de caja ya no está abierta';
  end if;
  insert into public.movimiento_caja
    (sesion_caja_id, caja_id, local_id, tipo, importe, motivo, actor_id, idempotency_key)
  values (v_sesion.id, v_sesion.caja_id, v_sesion.local_id, p_tipo, p_importe,
    pg_catalog.btrim(p_motivo), v_actor, p_idempotency_key)
  returning * into v_movimiento;
  insert into public.auditoria_caja
    (tipo, local_id, caja_id, sesion_caja_id, actor_id, creado_en,
      monto_inicial, estado_anterior, estado_nuevo, movimiento_caja_id,
      importe, tipo_movimiento, motivo)
  values (p_tipo, v_local, v_sesion.caja_id, v_sesion.id, v_actor,
    v_movimiento.creado_en, null, 'ABIERTA', 'ABIERTA', v_movimiento.id,
    v_movimiento.importe, v_movimiento.tipo, v_movimiento.motivo);
  return pg_catalog.to_jsonb(v_movimiento) - 'idempotency_key';
end;
$$;

create function public.fn_cerrar_sesion_caja(
  p_sesion_caja_id uuid, p_efectivo_contado numeric,
  p_motivo text, p_idempotency_key uuid, p_supervisor boolean
)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare
  v_actor uuid := auth.uid(); v_local uuid; v_rol text; v_caja_id uuid;
  v_sesion public.sesion_caja%rowtype; v_solicitud public.solicitud_cierre_caja%rowtype;
  v_totales record; v_esperado numeric(14,2); v_diferencia numeric(14,2);
  v_tipo text := case when p_supervisor then 'SUPERVISOR' else 'NORMAL' end;
  v_evento text := case when p_supervisor then 'CIERRE_SUPERVISOR' else 'CIERRE' end;
  v_motivo text := nullif(pg_catalog.btrim(p_motivo), ''); v_cerrada_en timestamptz;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null
    or (not p_supervisor and v_rol is distinct from 'CAJA')
    or (p_supervisor and v_rol is distinct from 'ADMINISTRADOR') then
    raise exception using errcode = '42501', message = 'No autorizado para cerrar la sesión';
  end if;
  if p_sesion_caja_id is null or p_idempotency_key is null
    or p_efectivo_contado is null or p_efectivo_contado < 0
    or p_efectivo_contado >= 1000000000000
    or p_efectivo_contado <> pg_catalog.round(p_efectivo_contado, 2)
    or (p_supervisor and v_motivo is null) then
    raise exception using errcode = '22023', message = 'Datos de cierre inválidos';
  end if;
  select s.caja_id into v_caja_id from public.sesion_caja s
    where s.id = p_sesion_caja_id and s.local_id = v_local;
  if v_caja_id is null then raise exception using errcode = '42501', message = 'Sesión no disponible'; end if;
  perform 1 from public.caja c
    where c.id = v_caja_id and c.local_id = v_local and c.activo for update;
  if not found then raise exception using errcode = '42501', message = 'Caja no disponible'; end if;
  select s.* into strict v_sesion from public.sesion_caja s
    where s.id = p_sesion_caja_id and s.caja_id = v_caja_id and s.local_id = v_local for update;
  select r.* into v_solicitud from public.solicitud_cierre_caja r
    where r.sesion_caja_id = v_sesion.id and r.actor_id = v_actor
      and r.idempotency_key = p_idempotency_key;
  if found then
    if v_solicitud.efectivo_contado <> p_efectivo_contado
      or v_solicitud.motivo is distinct from v_motivo or v_solicitud.tipo_cierre <> v_tipo then
      raise exception using errcode = '22023', message = 'Clave de cierre reutilizada con otros datos';
    end if;
    return (select pg_catalog.to_jsonb(r) from public.resumen_cierre_sesion_caja r
      where r.sesion_caja_id = v_sesion.id);
  end if;
  if v_sesion.estado is distinct from 'ABIERTA' then
    raise exception using errcode = '40001', message = 'La sesión de caja ya está cerrada';
  end if;
  select * into strict v_totales from public.fn_totales_sesion_caja(v_sesion.id);
  v_esperado := v_sesion.monto_inicial + v_totales.pago_efectivo
    + v_totales.propina_efectivo + v_totales.entradas - v_totales.salidas;
  v_diferencia := p_efectivo_contado - v_esperado;
  if v_diferencia <> 0 and v_motivo is null then
    raise exception using errcode = '22023', message = 'El motivo es obligatorio cuando existe diferencia';
  end if;
  v_cerrada_en := pg_catalog.clock_timestamp();
  insert into public.resumen_cierre_sesion_caja values (
    v_sesion.id, v_sesion.caja_id, v_local, v_actor, v_cerrada_en, v_tipo,
    v_totales.pago_efectivo, v_totales.propina_efectivo,
    v_totales.pago_yape, v_totales.propina_yape,
    v_totales.pago_plin, v_totales.propina_plin,
    v_totales.pago_tarjeta, v_totales.propina_tarjeta,
    v_totales.entradas, v_totales.salidas, v_esperado,
    p_efectivo_contado, v_diferencia, v_motivo
  );
  update public.sesion_caja s set estado = 'CERRADA', cerrada_por = v_actor,
    cerrada_en = v_cerrada_en, efectivo_esperado = v_esperado,
    efectivo_contado = p_efectivo_contado, diferencia = v_diferencia,
    motivo_diferencia = v_motivo where s.id = v_sesion.id;
  insert into public.auditoria_caja
    (tipo, local_id, caja_id, sesion_caja_id, actor_id, creado_en,
      monto_inicial, estado_anterior, estado_nuevo, efectivo_esperado,
      efectivo_contado, diferencia, motivo)
  values (v_evento, v_local, v_sesion.caja_id, v_sesion.id, v_actor,
    v_cerrada_en, null, 'ABIERTA', 'CERRADA', v_esperado,
    p_efectivo_contado, v_diferencia, v_motivo);
  insert into public.solicitud_cierre_caja
    (sesion_caja_id, actor_id, idempotency_key, efectivo_contado, motivo, tipo_cierre, creado_en)
  values (v_sesion.id, v_actor, p_idempotency_key, p_efectivo_contado,
    v_motivo, v_tipo, v_cerrada_en);
  return (select pg_catalog.to_jsonb(r) from public.resumen_cierre_sesion_caja r
    where r.sesion_caja_id = v_sesion.id);
end;
$$;

create function public.rpc_cerrar_sesion_caja(
  p_sesion_caja_id uuid, p_efectivo_contado numeric,
  p_motivo_diferencia text, p_idempotency_key uuid
)
returns jsonb language sql security definer set search_path = pg_catalog as $$
  select public.fn_cerrar_sesion_caja(
    p_sesion_caja_id, p_efectivo_contado, p_motivo_diferencia, p_idempotency_key, false
  );
$$;

create function public.rpc_cerrar_sesion_caja_supervisor(
  p_sesion_caja_id uuid, p_efectivo_contado numeric,
  p_motivo_supervisor text, p_idempotency_key uuid
)
returns jsonb language sql security definer set search_path = pg_catalog as $$
  select public.fn_cerrar_sesion_caja(
    p_sesion_caja_id, p_efectivo_contado, p_motivo_supervisor, p_idempotency_key, true
  );
$$;

create function public.rpc_obtener_resumen_sesion_caja(p_sesion_caja_id uuid)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog as $$
declare
  v_local uuid; v_rol text; v_sesion public.sesion_caja%rowtype;
  v_totales record; v_esperado numeric(14,2);
begin
  select c.local_id, c.rol_codigo into v_local, v_rol from public.obtener_contexto_autenticado() c;
  if auth.uid() is null or v_local is null or v_rol not in ('CAJA', 'ADMINISTRADOR') then
    raise exception using errcode = '42501', message = 'No autorizado para consultar la sesión';
  end if;
  select s.* into v_sesion from public.sesion_caja s
    where s.id = p_sesion_caja_id and s.local_id = v_local;
  if not found then raise exception using errcode = '42501', message = 'Sesión no disponible'; end if;
  if v_sesion.estado = 'CERRADA' then
    return (select pg_catalog.to_jsonb(r) from public.resumen_cierre_sesion_caja r
      where r.sesion_caja_id = v_sesion.id);
  end if;
  select * into strict v_totales from public.fn_totales_sesion_caja(v_sesion.id);
  v_esperado := v_sesion.monto_inicial + v_totales.pago_efectivo
    + v_totales.propina_efectivo + v_totales.entradas - v_totales.salidas;
  return pg_catalog.jsonb_build_object(
    'sesion_caja_id', v_sesion.id, 'caja_id', v_sesion.caja_id,
    'local_id', v_sesion.local_id, 'estado', v_sesion.estado,
    'monto_inicial', v_sesion.monto_inicial,
    'pago_efectivo', v_totales.pago_efectivo,
    'propina_efectivo', v_totales.propina_efectivo,
    'pago_yape', v_totales.pago_yape, 'propina_yape', v_totales.propina_yape,
    'pago_plin', v_totales.pago_plin, 'propina_plin', v_totales.propina_plin,
    'pago_tarjeta', v_totales.pago_tarjeta, 'propina_tarjeta', v_totales.propina_tarjeta,
    'entradas', v_totales.entradas, 'salidas', v_totales.salidas,
    'efectivo_esperado', v_esperado
  );
end;
$$;

alter function public.rpc_registrar_movimiento_caja(uuid,text,numeric,text,uuid) owner to postgres;
alter function public.fn_cerrar_sesion_caja(uuid,numeric,text,uuid,boolean) owner to postgres;
alter function public.rpc_cerrar_sesion_caja(uuid,numeric,text,uuid) owner to postgres;
alter function public.rpc_cerrar_sesion_caja_supervisor(uuid,numeric,text,uuid) owner to postgres;
alter function public.rpc_obtener_resumen_sesion_caja(uuid) owner to postgres;
revoke all on function public.rpc_registrar_movimiento_caja(uuid,text,numeric,text,uuid),
  public.fn_cerrar_sesion_caja(uuid,numeric,text,uuid,boolean),
  public.rpc_cerrar_sesion_caja(uuid,numeric,text,uuid),
  public.rpc_cerrar_sesion_caja_supervisor(uuid,numeric,text,uuid),
  public.rpc_obtener_resumen_sesion_caja(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.rpc_registrar_movimiento_caja(uuid,text,numeric,text,uuid),
  public.rpc_cerrar_sesion_caja(uuid,numeric,text,uuid),
  public.rpc_cerrar_sesion_caja_supervisor(uuid,numeric,text,uuid),
  public.rpc_obtener_resumen_sesion_caja(uuid) to authenticated;

alter table public.movimiento_caja enable row level security;
alter table public.resumen_cierre_sesion_caja enable row level security;
alter table public.solicitud_cierre_caja enable row level security;
revoke all on public.movimiento_caja, public.resumen_cierre_sesion_caja,
  public.solicitud_cierre_caja from public, anon, authenticated, service_role;
grant select on public.movimiento_caja, public.resumen_cierre_sesion_caja to authenticated;
create policy pol_movimiento_caja_select_local on public.movimiento_caja
  for select to authenticated using (exists (
    select 1 from public.obtener_contexto_autenticado() c
    where c.local_id = movimiento_caja.local_id and c.rol_codigo in ('CAJA', 'ADMINISTRADOR')
  ));
create policy pol_resumen_cierre_select_local on public.resumen_cierre_sesion_caja
  for select to authenticated using (exists (
    select 1 from public.obtener_contexto_autenticado() c
    where c.local_id = resumen_cierre_sesion_caja.local_id and c.rol_codigo in ('CAJA', 'ADMINISTRADOR')
  ));

comment on table public.movimiento_caja is
  'Eventos inmutables ENTRADA/SALIDA de una sesión abierta; importe siempre positivo, actor y hora servidor.';
comment on table public.resumen_cierre_sesion_caja is
  'Snapshot autoritativo e inmutable del cierre por medio, propina, movimientos y efectivo; no se recalcula para alterar historia.';
comment on table public.solicitud_cierre_caja is
  'Resultado idempotente del cierre por sesión, actor y clave; no concede autorización ni permite reabrir.';
comment on function public.rpc_registrar_movimiento_caja(uuid,text,numeric,text,uuid) is
  'CAJA activo del local: registra ENTRADA/SALIDA inmutable sobre sesión abierta, con actor, hora, idempotencia y auditoría.';
comment on function public.rpc_cerrar_sesion_caja(uuid,numeric,text,uuid) is
  'CAJA activo del local: cierre normal autoritativo; conserva actores, permite diferencia motivada y pedidos pendientes.';
comment on function public.rpc_cerrar_sesion_caja_supervisor(uuid,numeric,text,uuid) is
  'ADMINISTRADOR activo del local: cierre supervisor DF-07 con motivo obligatorio y auditoría propia.';
comment on function public.rpc_obtener_resumen_sesion_caja(uuid) is
  'CAJA/ADMINISTRADOR del local: resumen vivo autoritativo o snapshot inmutable de cierre.';

notify pgrst, 'reload schema';
commit;
