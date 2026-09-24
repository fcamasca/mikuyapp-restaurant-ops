-- E7-T04 — Lectura de cocina, recepción completa y conflicto por detalle cancelado.
-- Spec: E7-D08, E7-D09, E7-D10, E7-D16.
begin;

-- E7-D10: único cambio en la transición individual H4: detalle cancelado -> PT409.
CREATE OR REPLACE FUNCTION public.actualizar_estado_detalle_cocina(p_detalle_id bigint, p_estado_esperado text, p_estado_nuevo text)
 RETURNS TABLE(detalle_id bigint, estado text, modificado_en timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $actualizar_estado_detalle_cocina$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_pedido_id bigint;
  v_pedido public.pedido%rowtype;
  v_detalle public.detalle_pedido%rowtype;
begin
  if p_detalle_id is null or p_estado_esperado is null
    or p_estado_nuevo is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para actualizar el estado del detalle';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;
  if v_local_id is null or v_rol_codigo is distinct from 'COCINA' then
    raise exception using errcode = '42501', message = 'No autorizado para actualizar el estado del detalle';
  end if;

  select detail_row.pedido_id into v_pedido_id
  from public.detalle_pedido as detail_row where detail_row.id = p_detalle_id;
  if not found then
    -- E7-D10: un detalle cancelado por el mozo se informa como conflicto (PT409) para resincronizar.
    if exists (
      select 1 from public.historial_detalle_pedido as history_row
      where history_row.detalle_id = p_detalle_id
        and history_row.operacion = 'CANCELACION'
        and history_row.local_id = v_local_id
    ) then
      raise exception using errcode = 'PT409', message = 'El detalle fue cancelado por el mozo';
    end if;
    raise exception using errcode = '42501', message = 'Detalle no disponible para cocina';
  end if;

  select order_row.* into v_pedido
  from public.pedido as order_row
  where order_row.id = v_pedido_id
    and order_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
    )
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Pedido no disponible para cocina';
  end if;

  select detail_row.* into v_detalle
  from public.detalle_pedido as detail_row
  where detail_row.id = p_detalle_id and detail_row.pedido_id = v_pedido.id
  for update;
  if not found then
    -- E7-D10: si el mozo lo canceló mientras esta sesión esperaba el lock del pedido.
    if exists (
      select 1 from public.historial_detalle_pedido as history_row
      where history_row.detalle_id = p_detalle_id
        and history_row.operacion = 'CANCELACION'
        and history_row.local_id = v_local_id
    ) then
      raise exception using errcode = 'PT409', message = 'El detalle fue cancelado por el mozo';
    end if;
    raise exception using errcode = 'PT409', message = 'El detalle cambió durante la operación';
  end if;
  if v_detalle.estado is distinct from p_estado_esperado then
    raise exception using errcode = 'PT409', message = 'El detalle fue actualizado por otra sesión';
  end if;
  if not (
    (p_estado_esperado = 'ENVIADO' and p_estado_nuevo = 'RECIBIDO_COCINA')
    or (p_estado_esperado = 'RECIBIDO_COCINA' and p_estado_nuevo = 'EN_PREPARACION')
    or (p_estado_esperado = 'EN_PREPARACION' and p_estado_nuevo = 'LISTO')
  ) then
    raise exception using errcode = '22023', message = 'Transición de cocina no permitida';
  end if;

  update public.detalle_pedido as detail_row
  set estado = p_estado_nuevo
  where detail_row.id = v_detalle.id
  returning detail_row.* into v_detalle;

  perform public.sincronizar_estado_operativo_pedido(v_pedido.id, v_usuario_id);

  return query select v_detalle.id, v_detalle.estado, v_detalle.modificado_en;
end;
$actualizar_estado_detalle_cocina$;

alter function public.actualizar_estado_detalle_cocina(bigint,text,text) owner to postgres;
revoke all on function public.actualizar_estado_detalle_cocina(bigint,text,text) from public, anon;
grant execute on function public.actualizar_estado_detalle_cocina(bigint,text,text) to authenticated;

-- E7-D08: el tablero legado H4 excluye detalles sin cocina (firma sin cambios; en desuso por el frontend).
CREATE OR REPLACE FUNCTION public.obtener_tablero_cocina()
 RETURNS TABLE(pedido_id bigint, pedido_estado text, mesa_id uuid, mesa_codigo text, mesa_nombre text, mesa_estado text, detalle_id bigint, producto_id uuid, producto_codigo text, producto_nombre text, cantidad integer, observacion text, estado text, enviado_en timestamp with time zone, modificado_en timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $obtener_tablero_cocina$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
begin
  if v_usuario_id is null then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para consultar el tablero de cocina';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'COCINA' then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para consultar el tablero de cocina';
  end if;

  return query
  select
    order_row.id,
    order_row.estado,
    table_row.id,
    table_row.codigo,
    table_row.nombre,
    table_row.estado,
    detail_row.id,
    product_row.id,
    product_row.codigo,
    product_row.nombre,
    detail_row.cantidad,
    detail_row.observacion,
    detail_row.estado,
    detail_row.enviado_en,
    detail_row.modificado_en
  from public.detalle_pedido as detail_row
  inner join public.pedido as order_row
    on order_row.id = detail_row.pedido_id
  inner join public.mesa as table_row
    on table_row.id = order_row.mesa_id
  inner join public.producto as product_row
    on product_row.id = detail_row.producto_id
  where order_row.local_id = v_local_id
    and table_row.local_id = v_local_id
    and product_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO',
      'ENVIADO',
      'RECIBIDO_COCINA',
      'EN_PREPARACION',
      'LISTO'
    )
    and detail_row.estado in (
      'ENVIADO',
      'RECIBIDO_COCINA',
      'EN_PREPARACION',
      'LISTO'
    )
    and detail_row.requiere_cocina
  order by detail_row.enviado_en, order_row.id, detail_row.id;
end;
$obtener_tablero_cocina$;

alter function public.obtener_tablero_cocina() owner to postgres;
revoke all on function public.obtener_tablero_cocina() from public, anon;
grant execute on function public.obtener_tablero_cocina() to authenticated;

-- E7-D08: lectura unificada de cocina (una llamada por refresco).
create function public.rpc_obtener_tablero_cocina()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $rpc_obtener_tablero_cocina$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_detalles jsonb;
  v_comandas jsonb;
  v_cancelaciones jsonb;
begin
  if v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para consultar el tablero de cocina';
  end if;
  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;
  if v_local_id is null or v_rol_codigo is distinct from 'COCINA' then
    raise exception using errcode = '42501', message = 'No autorizado para consultar el tablero de cocina';
  end if;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'pedido_id', order_row.id,
      'pedido_estado', order_row.estado,
      'mesa_id', table_row.id,
      'mesa_codigo', table_row.codigo,
      'mesa_nombre', table_row.nombre,
      'mesa_estado', table_row.estado,
      'detalle_id', detail_row.id,
      'producto_id', product_row.id,
      'producto_codigo', product_row.codigo,
      'producto_nombre', product_row.nombre,
      'cantidad', detail_row.cantidad,
      'observacion', detail_row.observacion,
      'estado', detail_row.estado,
      'enviado_en', detail_row.enviado_en,
      'modificado_en', detail_row.modificado_en
    ) order by detail_row.enviado_en, order_row.id, detail_row.id), '[]'::jsonb)
  into v_detalles
  from public.detalle_pedido as detail_row
  inner join public.pedido as order_row on order_row.id = detail_row.pedido_id
  inner join public.mesa as table_row on table_row.id = order_row.mesa_id
  inner join public.producto as product_row on product_row.id = detail_row.producto_id
  where order_row.local_id = v_local_id
    and table_row.local_id = v_local_id
    and product_row.local_id = v_local_id
    and order_row.estado in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO')
    and detail_row.estado in ('ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO')
    and detail_row.requiere_cocina;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'comanda_id', command_row.id,
      'pedido_id', command_row.pedido_id,
      'numero', command_row.numero,
      'mesa_codigo', table_row.codigo,
      'mesa_nombre', table_row.nombre,
      'enviado_en', command_row.enviado_en,
      'creado_en', command_row.creado_en,
      'creado_por_nombre', profile_row.nombre,
      'lineas', command_row.lineas,
      'impresiones', command_row.impresiones,
      'primera_impresion_en', command_row.primera_impresion_en,
      'ultima_impresion_en', command_row.ultima_impresion_en
    ) order by command_row.creado_en, command_row.id), '[]'::jsonb)
  into v_comandas
  from public.comanda as command_row
  inner join public.pedido as order_row on order_row.id = command_row.pedido_id
  inner join public.mesa as table_row on table_row.id = order_row.mesa_id
  inner join public.perfil_usuario as profile_row on profile_row.id = command_row.creado_por
  where command_row.local_id = v_local_id
    and order_row.local_id = v_local_id
    and order_row.estado in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO');

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'pedido_id', history_row.pedido_id,
      'detalle_id', history_row.detalle_id,
      'producto_nombre', product_row.nombre,
      'cantidad', history_row.cantidad,
      'observacion', history_row.observacion,
      'estado_anterior', history_row.estado_anterior,
      'motivo', history_row.motivo,
      'cancelado_en', history_row.creado_en
    ) order by history_row.creado_en desc, history_row.id desc), '[]'::jsonb)
  into v_cancelaciones
  from public.historial_detalle_pedido as history_row
  inner join public.pedido as order_row on order_row.id = history_row.pedido_id
  inner join public.producto as product_row on product_row.id = history_row.producto_id
  where history_row.local_id = v_local_id
    and order_row.local_id = v_local_id
    and history_row.operacion = 'CANCELACION'
    and history_row.requiere_cocina
    and order_row.estado in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO');

  return pg_catalog.jsonb_build_object(
    'detalles', v_detalles,
    'comandas', v_comandas,
    'cancelaciones', v_cancelaciones
  );
end;
$rpc_obtener_tablero_cocina$;

alter function public.rpc_obtener_tablero_cocina() owner to postgres;
revoke all on function public.rpc_obtener_tablero_cocina() from public, anon;
grant execute on function public.rpc_obtener_tablero_cocina() to authenticated;

-- E7-D09: recepción completa transaccional e idempotente.
create function public.rpc_recibir_pedido_cocina(p_pedido_id bigint)
returns table (
  pedido_id bigint,
  detalles_recibidos integer,
  detalle_ids bigint[],
  pedido_estado text
)
language plpgsql
security definer
set search_path = pg_catalog
as $rpc_recibir_pedido_cocina$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_pedido public.pedido%rowtype;
  v_ids bigint[];
  v_estado text;
begin
  if p_pedido_id is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para recibir pedidos en cocina';
  end if;
  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;
  if v_local_id is null or v_rol_codigo is distinct from 'COCINA' then
    raise exception using errcode = '42501', message = 'No autorizado para recibir pedidos en cocina';
  end if;

  -- Orden de locks único: pedido -> detalle -> mesa.
  select order_row.* into v_pedido
  from public.pedido as order_row
  where order_row.id = p_pedido_id
    and order_row.local_id = v_local_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Pedido no disponible para cocina';
  end if;
  if v_pedido.estado not in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO') then
    raise exception using errcode = 'PT409', message = 'El pedido ya no está en cocina';
  end if;

  perform pg_catalog.set_config('mikuyapp.operacion_detalle', 'RECEPCION_COMPLETA', true);
  with recibidos as (
    update public.detalle_pedido as detail_row
    set estado = 'RECIBIDO_COCINA'
    where detail_row.pedido_id = v_pedido.id
      and detail_row.estado = 'ENVIADO'
      and detail_row.requiere_cocina
    returning detail_row.id
  )
  select pg_catalog.array_agg(recibidos.id order by recibidos.id) into v_ids from recibidos;
  perform pg_catalog.set_config('mikuyapp.operacion_detalle', '', true);

  if v_ids is null then
    -- Doble clic, reintento o carrera perdida: éxito sin cambios (sin error ni reintento de PostgREST).
    return query select v_pedido.id, 0, array[]::bigint[], v_pedido.estado;
    return;
  end if;

  select sync_result.pedido_estado into strict v_estado
  from public.sincronizar_estado_operativo_pedido(v_pedido.id, v_usuario_id) as sync_result;

  return query select v_pedido.id, pg_catalog.cardinality(v_ids), v_ids, v_estado;
end;
$rpc_recibir_pedido_cocina$;

alter function public.rpc_recibir_pedido_cocina(bigint) owner to postgres;
revoke all on function public.rpc_recibir_pedido_cocina(bigint) from public, anon;
grant execute on function public.rpc_recibir_pedido_cocina(bigint) to authenticated;

comment on function public.actualizar_estado_detalle_cocina(bigint,text,text) is
  'H4 transición individual de cocina con estado esperado; E7-D10: un detalle cancelado por el mozo responde PT409.';
comment on function public.obtener_tablero_cocina() is
  'H4 tablero legado; E7-D08 excluye detalles sin cocina. En desuso por el frontend desde E7 (usar rpc_obtener_tablero_cocina).';
comment on function public.rpc_obtener_tablero_cocina() is
  'E7-D08: snapshot autoritativo de cocina del local (detalles con cocina, comandas y cancelaciones) en una sola llamada.';
comment on function public.rpc_recibir_pedido_cocina(bigint) is
  'E7-D09: recepción completa ENVIADO -> RECIBIDO_COCINA de los detalles con cocina del pedido; idempotente (0 recibidos sin error) y serializada por lock del pedido.';

notify pgrst, 'reload schema';

commit;
