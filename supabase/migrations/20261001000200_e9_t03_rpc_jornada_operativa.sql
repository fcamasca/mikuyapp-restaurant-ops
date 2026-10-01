-- E9-T03 — Jornada operativa del local: apertura, cierre y lecturas.
-- Spec aprobado: specs/E9-OperationalDay (E9-D07, D08, D10, D11). Migración aditiva: no modifica
-- RPC operativas existentes (DC-10).
begin;

-- E9-D10: identificación visible derivada, definida en un único lugar (interna).
create function public.fn_formatear_identificacion_jornada(p_fecha_operativa date, p_numero integer)
returns text
language sql
immutable
set search_path = pg_catalog
as $fn_formatear_identificacion_jornada$
  select 'Jornada ' || pg_catalog.to_char(p_fecha_operativa, 'YYYY-MM-DD') || ' (' || p_numero::text || ')';
$fn_formatear_identificacion_jornada$;

-- E9-D07: abre u obtiene la jornada abierta del local (ADMINISTRADOR). Idempotente.
create function public.rpc_abrir_jornada_operativa(p_idempotency_key uuid)
returns table (
  jornada_operativa_id bigint,
  identificacion text,
  fecha_operativa date,
  numero integer,
  estado text,
  abierta_por uuid,
  abierta_en timestamptz,
  ya_existia boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $rpc_abrir_jornada_operativa$
declare
  v_actor uuid := auth.uid();
  v_local uuid;
  v_rol text;
  v_jornada public.jornada_operativa%rowtype;
  v_ahora timestamptz;
  v_fecha date;
  v_constraint text;
begin
  select auth_context.local_id, auth_context.rol_codigo
  into v_local, v_rol
  from public.obtener_contexto_autenticado() as auth_context;
  if v_actor is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then
    raise exception using errcode = '42501', message = 'No autorizado para abrir la jornada operativa';
  end if;
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'La clave de solicitud es obligatoria';
  end if;

  -- Serializa las aperturas del local sin bloquear las comprobaciones de FK de otras transacciones.
  perform 1 from public.local as local_row where local_row.id = v_local for no key update;

  -- Reintento con la misma clave: siempre la misma jornada, aunque ya esté cerrada.
  select day_row.* into v_jornada
  from public.jornada_operativa as day_row
  where day_row.local_id = v_local and day_row.abierta_por = v_actor
    and day_row.idempotency_key = p_idempotency_key;
  if not found then
    -- Doble clic con otra clave o segundo administrador: la abierta existente.
    select day_row.* into v_jornada
    from public.jornada_operativa as day_row
    where day_row.local_id = v_local and day_row.estado = 'ABIERTA';
  end if;
  if found then
    return query select v_jornada.id,
      public.fn_formatear_identificacion_jornada(v_jornada.fecha_operativa, v_jornada.numero),
      v_jornada.fecha_operativa, v_jornada.numero, v_jornada.estado, v_jornada.abierta_por,
      v_jornada.abierta_en, true;
    return;
  end if;

  v_ahora := pg_catalog.clock_timestamp();
  v_fecha := (v_ahora at time zone 'America/Lima')::date;
  begin
    insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
    values (v_local, v_fecha,
      coalesce((select max(day_row.numero) from public.jornada_operativa as day_row
        where day_row.local_id = v_local and day_row.fecha_operativa = v_fecha), 0) + 1,
      v_actor, v_ahora, p_idempotency_key)
    returning * into v_jornada;
  exception when unique_violation then
    -- Defensa (imposible bajo el lock del local): devuelve la abierta existente; nunca 23505 ni 40001.
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint not in ('uq_jornada_operativa_local_abierta', 'uq_jornada_operativa_local_fecha_numero') then
      raise;
    end if;
    select day_row.* into v_jornada
    from public.jornada_operativa as day_row
    where day_row.local_id = v_local and day_row.estado = 'ABIERTA';
    if not found then
      raise exception using errcode = 'PT409', message = 'La jornada operativa cambió; reintente la apertura';
    end if;
    return query select v_jornada.id,
      public.fn_formatear_identificacion_jornada(v_jornada.fecha_operativa, v_jornada.numero),
      v_jornada.fecha_operativa, v_jornada.numero, v_jornada.estado, v_jornada.abierta_por,
      v_jornada.abierta_en, true;
    return;
  end;

  return query select v_jornada.id,
    public.fn_formatear_identificacion_jornada(v_jornada.fecha_operativa, v_jornada.numero),
    v_jornada.fecha_operativa, v_jornada.numero, v_jornada.estado, v_jornada.abierta_por,
    v_jornada.abierta_en, false;
end;
$rpc_abrir_jornada_operativa$;

-- E9-D08: cierra la jornada indicada sólo sin pendientes (ADMINISTRADOR). Idempotente.
create function public.rpc_cerrar_jornada_operativa(p_jornada_operativa_id bigint)
returns table (
  jornada_operativa_id bigint,
  identificacion text,
  estado text,
  abierta_por uuid,
  abierta_en timestamptz,
  cerrada_por uuid,
  cerrada_en timestamptz,
  ya_estaba_cerrada boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $rpc_cerrar_jornada_operativa$
declare
  v_actor uuid := auth.uid();
  v_local uuid;
  v_rol text;
  v_jornada public.jornada_operativa%rowtype;
  v_pedidos bigint;
  v_sesiones bigint;
begin
  select auth_context.local_id, auth_context.rol_codigo
  into v_local, v_rol
  from public.obtener_contexto_autenticado() as auth_context;
  if v_actor is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then
    raise exception using errcode = '42501', message = 'No autorizado para cerrar la jornada operativa';
  end if;
  if p_jornada_operativa_id is null then
    raise exception using errcode = '22023', message = 'La jornada operativa es obligatoria';
  end if;

  -- Conflicto con el FOR SHARE que toma toda creación de pedido o sesión de caja.
  select day_row.* into v_jornada
  from public.jornada_operativa as day_row
  where day_row.id = p_jornada_operativa_id and day_row.local_id = v_local
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Jornada operativa no disponible';
  end if;

  if v_jornada.estado = 'CERRADA' then
    return query select v_jornada.id,
      public.fn_formatear_identificacion_jornada(v_jornada.fecha_operativa, v_jornada.numero),
      v_jornada.estado, v_jornada.abierta_por, v_jornada.abierta_en, v_jornada.cerrada_por,
      v_jornada.cerrada_en, true;
    return;
  end if;

  -- Sentencias nuevas: snapshot posterior a la obtención del lock (READ COMMITTED).
  select count(*) into v_sesiones
  from public.sesion_caja as session_row
  where session_row.jornada_operativa_id = v_jornada.id and session_row.estado = 'ABIERTA';
  select count(*) into v_pedidos
  from public.pedido as order_row
  where order_row.jornada_operativa_id = v_jornada.id and order_row.estado not in ('PAGADO', 'ANULADO');
  if v_pedidos > 0 or v_sesiones > 0 then
    raise exception using errcode = 'PT409',
      message = pg_catalog.format('No se puede cerrar la jornada: %s pedidos pendientes y %s sesiones de caja abiertas',
        v_pedidos, v_sesiones);
  end if;

  update public.jornada_operativa as day_row
  set estado = 'CERRADA',
      cerrada_por = v_actor,
      cerrada_en = greatest(pg_catalog.clock_timestamp(), day_row.abierta_en)
  where day_row.id = v_jornada.id
  returning day_row.* into v_jornada;

  return query select v_jornada.id,
    public.fn_formatear_identificacion_jornada(v_jornada.fecha_operativa, v_jornada.numero),
    v_jornada.estado, v_jornada.abierta_por, v_jornada.abierta_en, v_jornada.cerrada_por,
    v_jornada.cerrada_en, false;
end;
$rpc_cerrar_jornada_operativa$;

-- E9-D10: estado del local para los cuatro roles. Cero filas = local cerrado.
create function public.rpc_obtener_jornada_operativa_actual()
returns table (
  jornada_operativa_id bigint,
  identificacion text,
  fecha_operativa date,
  numero integer,
  abierta_en timestamptz,
  abierta_por_nombre text,
  servidor_ahora timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $rpc_obtener_jornada_operativa_actual$
declare
  v_local uuid;
begin
  select auth_context.local_id into v_local from public.obtener_contexto_autenticado() as auth_context;
  if auth.uid() is null or v_local is null then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  return query
  select day_row.id,
    public.fn_formatear_identificacion_jornada(day_row.fecha_operativa, day_row.numero),
    day_row.fecha_operativa, day_row.numero, day_row.abierta_en, opener.nombre, pg_catalog.now()
  from public.jornada_operativa as day_row
  inner join public.perfil_usuario as opener on opener.id = day_row.abierta_por
  where day_row.local_id = v_local and day_row.estado = 'ABIERTA';
end;
$rpc_obtener_jornada_operativa_actual$;

-- E9-D10: qué impide el cierre (ADMINISTRADOR). Informativa, sin importes.
create function public.rpc_obtener_pendientes_cierre_jornada()
returns table (
  tipo text,
  pedido_id bigint,
  mesa_codigo text,
  estado text,
  sesion_caja_id uuid,
  caja_codigo text,
  abierta_por_nombre text,
  desde timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $rpc_obtener_pendientes_cierre_jornada$
declare
  v_local uuid;
  v_rol text;
begin
  select auth_context.local_id, auth_context.rol_codigo
  into v_local, v_rol
  from public.obtener_contexto_autenticado() as auth_context;
  if auth.uid() is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  return query
  select 'PEDIDO'::text, order_row.id, table_row.codigo, order_row.estado,
    null::uuid, null::text, null::text, order_row.creado_en
  from public.jornada_operativa as day_row
  inner join public.pedido as order_row on order_row.jornada_operativa_id = day_row.id
  inner join public.mesa as table_row on table_row.id = order_row.mesa_id
  where day_row.local_id = v_local and day_row.estado = 'ABIERTA'
    and order_row.estado not in ('PAGADO', 'ANULADO')
  union all
  select 'SESION_CAJA'::text, null::bigint, null::text, session_row.estado,
    session_row.id, cash_row.codigo, opener.nombre, session_row.abierta_en
  from public.jornada_operativa as day_row
  inner join public.sesion_caja as session_row on session_row.jornada_operativa_id = day_row.id
  inner join public.caja as cash_row on cash_row.id = session_row.caja_id
  inner join public.perfil_usuario as opener on opener.id = session_row.abierta_por
  where day_row.local_id = v_local and day_row.estado = 'ABIERTA'
    and session_row.estado = 'ABIERTA'
  order by 1 desc, 8, 2;
end;
$rpc_obtener_pendientes_cierre_jornada$;

-- E9-D10: historial paginado (ADMINISTRADOR). Sin totales ni conteos (E8).
create function public.rpc_obtener_historial_jornadas_operativas(
  p_limite integer default 50,
  p_offset integer default 0
)
returns table (
  jornada_operativa_id bigint,
  identificacion text,
  fecha_operativa date,
  numero integer,
  estado text,
  abierta_por_nombre text,
  abierta_en timestamptz,
  cerrada_por_nombre text,
  cerrada_en timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $rpc_obtener_historial_jornadas_operativas$
declare
  v_local uuid;
  v_rol text;
begin
  select auth_context.local_id, auth_context.rol_codigo
  into v_local, v_rol
  from public.obtener_contexto_autenticado() as auth_context;
  if auth.uid() is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  if p_limite is null or p_limite not between 1 and 200 or p_offset is null or p_offset < 0 then
    raise exception using errcode = '22023', message = 'Paginación inválida';
  end if;
  return query
  select day_row.id,
    public.fn_formatear_identificacion_jornada(day_row.fecha_operativa, day_row.numero),
    day_row.fecha_operativa, day_row.numero, day_row.estado,
    opener.nombre, day_row.abierta_en, closer.nombre, day_row.cerrada_en
  from public.jornada_operativa as day_row
  inner join public.perfil_usuario as opener on opener.id = day_row.abierta_por
  left join public.perfil_usuario as closer on closer.id = day_row.cerrada_por
  where day_row.local_id = v_local
  order by day_row.abierta_en desc, day_row.id desc
  limit p_limite offset p_offset;
end;
$rpc_obtener_historial_jornadas_operativas$;

alter function public.fn_formatear_identificacion_jornada(date, integer) owner to postgres;
alter function public.rpc_abrir_jornada_operativa(uuid) owner to postgres;
alter function public.rpc_cerrar_jornada_operativa(bigint) owner to postgres;
alter function public.rpc_obtener_jornada_operativa_actual() owner to postgres;
alter function public.rpc_obtener_pendientes_cierre_jornada() owner to postgres;
alter function public.rpc_obtener_historial_jornadas_operativas(integer, integer) owner to postgres;

revoke all on function public.fn_formatear_identificacion_jornada(date, integer) from public, anon, authenticated, service_role;
revoke all on function public.rpc_abrir_jornada_operativa(uuid),
  public.rpc_cerrar_jornada_operativa(bigint),
  public.rpc_obtener_jornada_operativa_actual(),
  public.rpc_obtener_pendientes_cierre_jornada(),
  public.rpc_obtener_historial_jornadas_operativas(integer, integer)
  from public, anon, service_role;
grant execute on function public.rpc_abrir_jornada_operativa(uuid),
  public.rpc_cerrar_jornada_operativa(bigint),
  public.rpc_obtener_jornada_operativa_actual(),
  public.rpc_obtener_pendientes_cierre_jornada(),
  public.rpc_obtener_historial_jornadas_operativas(integer, integer)
  to authenticated;

comment on function public.fn_formatear_identificacion_jornada(date, integer) is
  'E9-D10 (interna): identificación visible Jornada YYYY-MM-DD (N).';
comment on function public.rpc_abrir_jornada_operativa(uuid) is
  'E9-D07: ADMINISTRADOR abre la jornada de su local o recibe la abierta existente (ya_existia). Serializa por local; fecha operativa America/Lima y correlativo por fecha; hora de servidor. Reintento con la misma clave: siempre la misma jornada.';
comment on function public.rpc_cerrar_jornada_operativa(bigint) is
  'E9-D08: ADMINISTRADOR cierra la jornada indicada sólo sin sesiones de caja abiertas y con todos sus pedidos PAGADO/ANULADO; si no, PT409 con conteos. Idempotente (ya_estaba_cerrada). Sin cierre forzado.';
comment on function public.rpc_obtener_jornada_operativa_actual() is
  'E9-D10: estado del local para los cuatro roles; cero filas = local cerrado. Incluye servidor_ahora.';
comment on function public.rpc_obtener_pendientes_cierre_jornada() is
  'E9-D10: ADMINISTRADOR; pedidos no terminales y sesiones de caja abiertas de la jornada abierta, sin importes. Informativa: el cierre decide.';
comment on function public.rpc_obtener_historial_jornadas_operativas(integer, integer) is
  'E9-D10: ADMINISTRADOR; historial de jornadas del local (más reciente primero), sin totales ni conteos.';

notify pgrst, 'reload schema';

commit;
