begin;

create table public.lote_movimiento_caja (
  id uuid primary key default gen_random_uuid(),
  sesion_caja_id uuid not null,
  caja_id uuid not null,
  local_id uuid not null,
  actor_id uuid not null,
  idempotency_key uuid not null,
  movimientos jsonb not null,
  resultado jsonb not null default '[]'::jsonb,
  creado_en timestamptz not null default now(),
  constraint uq_lote_movimiento_caja_idempotencia unique (sesion_caja_id, actor_id, idempotency_key),
  constraint fk_lote_movimiento_caja_sesion foreign key (sesion_caja_id, caja_id, local_id)
    references public.sesion_caja (id, caja_id, local_id) on delete restrict,
  constraint fk_lote_movimiento_caja_actor foreign key (actor_id)
    references public.perfil_usuario (id) on delete restrict,
  constraint ck_lote_movimiento_caja_array check (jsonb_typeof(movimientos) = 'array')
);

alter table public.lote_movimiento_caja enable row level security;
revoke all on public.lote_movimiento_caja from public, anon, authenticated, service_role;

create function public.rpc_obtener_movimientos_sesion_caja(p_sesion_caja_id uuid)
returns table (
  id uuid, sesion_caja_id uuid, tipo text, importe numeric, motivo text,
  actor_id uuid, actor_nombre text, creado_en timestamptz
)
language plpgsql stable security definer set search_path = pg_catalog as $$
declare v_actor uuid := auth.uid(); v_local uuid; v_rol text;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol
  from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol not in ('CAJA', 'ADMINISTRADOR') then
    raise exception using errcode = '42501', message = 'No autorizado para consultar movimientos';
  end if;
  if not exists (select 1 from public.sesion_caja s where s.id = p_sesion_caja_id and s.local_id = v_local) then
    raise exception using errcode = '42501', message = 'Sesión no disponible';
  end if;
  return query
    select m.id, m.sesion_caja_id, m.tipo, m.importe, m.motivo,
      m.actor_id, p.nombre, m.creado_en
    from public.movimiento_caja m
    join public.perfil_usuario p on p.id = m.actor_id
    where m.sesion_caja_id = p_sesion_caja_id and m.local_id = v_local
    order by m.creado_en, m.id;
end;
$$;

create function public.registrar_movimientos_caja(
  p_sesion_caja_id uuid, p_movimientos jsonb, p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare
  v_actor uuid := auth.uid(); v_local uuid; v_rol text; v_actor_nombre text; v_caja_id uuid;
  v_sesion public.sesion_caja%rowtype; v_lote public.lote_movimiento_caja%rowtype;
  v_movimiento public.movimiento_caja%rowtype; v_item jsonb; v_tipo text; v_motivo text;
  v_importe numeric; v_resultado jsonb := '[]'::jsonb;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol
  from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode = '42501', message = 'No autorizado para registrar movimientos';
  end if;
  select p.nombre into v_actor_nombre from public.perfil_usuario p where p.id = v_actor and p.local_id = v_local;
  if p_sesion_caja_id is null or p_idempotency_key is null or p_movimientos is null
    or jsonb_typeof(p_movimientos) <> 'array' or jsonb_array_length(p_movimientos) < 1
    or jsonb_array_length(p_movimientos) > 50 then
    raise exception using errcode = '22023', message = 'Lote de movimientos inválido';
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
  select l.* into v_lote from public.lote_movimiento_caja l
    where l.sesion_caja_id = v_sesion.id and l.actor_id = v_actor and l.idempotency_key = p_idempotency_key;
  if found then
    if v_lote.movimientos <> p_movimientos then
      raise exception using errcode = '22023', message = 'Clave de lote reutilizada con otros datos';
    end if;
    return v_lote.resultado;
  end if;
  if v_sesion.estado is distinct from 'ABIERTA' then
    raise exception using errcode = '40001', message = 'La sesión de caja ya no está abierta';
  end if;
  insert into public.lote_movimiento_caja
    (sesion_caja_id, caja_id, local_id, actor_id, idempotency_key, movimientos)
  values (v_sesion.id, v_sesion.caja_id, v_sesion.local_id, v_actor, p_idempotency_key, p_movimientos)
  returning * into v_lote;

  for v_item in select value from jsonb_array_elements(p_movimientos) loop
    if jsonb_typeof(v_item) <> 'object' or not (v_item ? 'tipo') or not (v_item ? 'importe') or not (v_item ? 'motivo')
      or v_item->>'tipo' not in ('ENTRADA', 'SALIDA')
      or coalesce(v_item->>'importe', '') !~ '^[0-9]+([.][0-9]{1,2})?$' then
      raise exception using errcode = '22023', message = 'Movimiento inválido en lote';
    end if;
    v_tipo := v_item->>'tipo'; v_importe := (v_item->>'importe')::numeric;
    v_motivo := nullif(btrim(v_item->>'motivo'), '');
    if v_importe <= 0 or v_importe >= 1000000000000 or v_importe <> round(v_importe, 2) or v_motivo is null then
      raise exception using errcode = '22023', message = 'Movimiento inválido en lote';
    end if;
    insert into public.movimiento_caja
      (sesion_caja_id, caja_id, local_id, tipo, importe, motivo, actor_id, idempotency_key)
    values (v_sesion.id, v_sesion.caja_id, v_sesion.local_id, v_tipo, v_importe,
      v_motivo, v_actor, gen_random_uuid()) returning * into v_movimiento;
    insert into public.auditoria_caja
      (tipo, local_id, caja_id, sesion_caja_id, actor_id, creado_en,
       monto_inicial, estado_anterior, estado_nuevo, movimiento_caja_id,
       importe, tipo_movimiento, motivo)
    values (v_tipo, v_local, v_sesion.caja_id, v_sesion.id, v_actor,
      v_movimiento.creado_en, null, 'ABIERTA', 'ABIERTA', v_movimiento.id,
      v_movimiento.importe, v_movimiento.tipo, v_movimiento.motivo);
    v_resultado := v_resultado || jsonb_build_array(jsonb_build_object(
      'id', v_movimiento.id, 'sesion_caja_id', v_movimiento.sesion_caja_id,
      'tipo', v_movimiento.tipo, 'importe', v_movimiento.importe,
      'motivo', v_movimiento.motivo, 'actor_id', v_actor,
      'actor_nombre', v_actor_nombre, 'creado_en', v_movimiento.creado_en));
  end loop;
  update public.lote_movimiento_caja set resultado = v_resultado where id = v_lote.id;
  return v_resultado;
end;
$$;

alter function public.rpc_obtener_movimientos_sesion_caja(uuid) owner to postgres;
alter function public.registrar_movimientos_caja(uuid,jsonb,uuid) owner to postgres;
revoke all on function public.rpc_obtener_movimientos_sesion_caja(uuid),
  public.registrar_movimientos_caja(uuid,jsonb,uuid) from public, anon, authenticated, service_role;
grant execute on function public.rpc_obtener_movimientos_sesion_caja(uuid),
  public.registrar_movimientos_caja(uuid,jsonb,uuid) to authenticated;

comment on table public.lote_movimiento_caja is
  'Cabecera interna de idempotencia para registro atómico de uno o varios movimientos de caja.';
comment on function public.rpc_obtener_movimientos_sesion_caja(uuid) is
  'Lectura cronológica de movimientos y actor legible, restringida a CAJA/ADMINISTRADOR activo del mismo local.';
comment on function public.registrar_movimientos_caja(uuid,jsonb,uuid) is
  'CAJA activo registra atómicamente un lote idempotente de ENTRADA/SALIDA; cada fila conserva auditoría propia.';

commit;
