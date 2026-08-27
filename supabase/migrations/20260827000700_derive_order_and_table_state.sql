begin;

create or replace function public.sincronizar_estado_operativo_pedido(
  p_pedido_id bigint,
  p_usuario_id uuid
)
returns table (
  pedido_estado text,
  mesa_estado text,
  cabecera_actualizada boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $sincronizar_estado_operativo_pedido$
declare
  v_pedido public.pedido%rowtype;
  v_mesa public.mesa%rowtype;
  v_estado_derivado text;
  v_estado_mesa text;
  v_cabecera_actualizada boolean := false;
begin
  if p_pedido_id is null or p_usuario_id is null then
    raise exception using errcode = '22023', message = 'Pedido y actor son obligatorios';
  end if;

  select order_row.*
  into strict v_pedido
  from public.pedido as order_row
  where order_row.id = p_pedido_id
  for update;

  select table_row.*
  into strict v_mesa
  from public.mesa as table_row
  where table_row.id = v_pedido.mesa_id
    and table_row.local_id = v_pedido.local_id
  for update;

  -- ENTREGADO conserva la semántica aprobada en H3 y no se reabre en H4.
  if v_pedido.estado = 'ENTREGADO' then
    return query select v_pedido.estado, v_mesa.estado, false;
    return;
  end if;

  if v_pedido.estado not in (
    'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
  ) then
    raise exception using errcode = '22000', message = 'Pedido fuera del flujo operativo de cocina';
  end if;

  select case
    when pg_catalog.bool_or(detail_row.estado = 'ABIERTO') then 'ABIERTO'
    when pg_catalog.bool_or(detail_row.estado = 'ENVIADO') then 'ENVIADO'
    when pg_catalog.bool_or(detail_row.estado = 'RECIBIDO_COCINA') then 'RECIBIDO_COCINA'
    when pg_catalog.bool_or(detail_row.estado = 'EN_PREPARACION') then 'EN_PREPARACION'
    when pg_catalog.bool_and(detail_row.estado = 'LISTO') then 'LISTO'
    else null
  end
  into v_estado_derivado
  from public.detalle_pedido as detail_row
  where detail_row.pedido_id = v_pedido.id;

  if v_estado_derivado is null then
    raise exception using errcode = '22000', message = 'No se puede derivar un pedido sin detalles';
  end if;

  v_estado_mesa := case
    when v_estado_derivado = 'LISTO' then 'PEDIDO_LISTO'
    else 'OCUPADA'
  end;

  if v_mesa.estado not in ('OCUPADA', 'PEDIDO_LISTO') then
    raise exception using errcode = '22000', message = 'Mesa fuera del flujo operativo de cocina';
  end if;

  if v_pedido.estado is distinct from v_estado_derivado then
    update public.pedido as order_row
    set estado = v_estado_derivado
    where order_row.id = v_pedido.id;

    insert into public.historial_estado (
      pedido_id, estado_anterior, estado_nuevo, usuario_id
    ) values (
      v_pedido.id, v_pedido.estado, v_estado_derivado, p_usuario_id
    );

    v_cabecera_actualizada := true;
  end if;

  if v_mesa.estado is distinct from v_estado_mesa then
    update public.mesa as table_row
    set estado = v_estado_mesa
    where table_row.id = v_mesa.id;
  end if;

  return query
  select v_estado_derivado, v_estado_mesa, v_cabecera_actualizada;
end;
$sincronizar_estado_operativo_pedido$;

alter function public.sincronizar_estado_operativo_pedido(bigint, uuid)
  owner to postgres;
revoke all on function public.sincronizar_estado_operativo_pedido(bigint, uuid)
  from public;
revoke all on function public.sincronizar_estado_operativo_pedido(bigint, uuid)
  from anon;
revoke all on function public.sincronizar_estado_operativo_pedido(bigint, uuid)
  from authenticated;

create or replace function public.agregar_detalle_pedido(
  p_pedido_id bigint,
  p_producto_id uuid,
  p_cantidad integer,
  p_observacion text default null
)
returns table (
  detalle_id bigint,
  pedido_id bigint,
  producto_id uuid,
  cantidad integer,
  precio_unitario numeric,
  observacion text,
  estado text
)
language plpgsql
security definer
set search_path = pg_catalog
as $agregar_detalle_pedido$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_precio public.producto.precio%type;
  v_detalle_id bigint;
  v_detalle public.detalle_pedido%rowtype;
begin
  if v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para agregar productos al pedido';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using errcode = '42501', message = 'No autorizado para agregar productos al pedido';
  end if;
  if p_pedido_id is null or p_producto_id is null then
    raise exception using errcode = '22023', message = 'Pedido y producto son obligatorios';
  end if;
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception using errcode = '22023', message = 'La cantidad debe ser un entero positivo';
  end if;
  if p_observacion is not null and pg_catalog.btrim(p_observacion) = '' then
    raise exception using errcode = '22023', message = 'La observación no puede estar vacía';
  end if;

  perform 1
  from public.pedido as order_row
  where order_row.id = p_pedido_id
    and order_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO', 'ENTREGADO'
    )
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Pedido no disponible para el usuario autenticado';
  end if;

  select product_row.precio
  into v_precio
  from public.producto as product_row
  inner join public.categoria as category_row
    on category_row.id = product_row.categoria_id
    and category_row.local_id = product_row.local_id
  where product_row.id = p_producto_id
    and product_row.local_id = v_local_id
    and product_row.activo = true
    and category_row.activo = true;
  if not found then
    raise exception using errcode = '42501', message = 'Producto no disponible para el pedido';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_pedido_id::text || ':' || p_producto_id::text, 0)
  );

  select detail_row.id
  into v_detalle_id
  from public.detalle_pedido as detail_row
  where detail_row.pedido_id = p_pedido_id
    and detail_row.producto_id = p_producto_id
    and detail_row.estado = 'ABIERTO'
    and nullif(pg_catalog.btrim(detail_row.observacion), '')
      is not distinct from nullif(pg_catalog.btrim(p_observacion), '')
  order by detail_row.id
  limit 1
  for update;

  if v_detalle_id is not null then
    update public.detalle_pedido as detail_row
    set cantidad = detail_row.cantidad + p_cantidad
    where detail_row.id = v_detalle_id
      and detail_row.estado = 'ABIERTO'
    returning detail_row.* into strict v_detalle;
  else
    insert into public.detalle_pedido as detail_row (
      pedido_id, producto_id, cantidad, precio_unitario, observacion, estado
    ) values (
      p_pedido_id, p_producto_id, p_cantidad, v_precio, p_observacion, 'ABIERTO'
    )
    returning detail_row.* into strict v_detalle;
  end if;

  perform public.sincronizar_estado_operativo_pedido(p_pedido_id, v_usuario_id);

  return query
  select v_detalle.id, v_detalle.pedido_id, v_detalle.producto_id,
    v_detalle.cantidad, v_detalle.precio_unitario, v_detalle.observacion,
    v_detalle.estado;
end;
$agregar_detalle_pedido$;

alter function public.agregar_detalle_pedido(bigint, uuid, integer, text)
  owner to postgres;
revoke all on function public.agregar_detalle_pedido(bigint, uuid, integer, text)
  from public;
revoke all on function public.agregar_detalle_pedido(bigint, uuid, integer, text)
  from anon;
grant execute on function public.agregar_detalle_pedido(bigint, uuid, integer, text)
  to authenticated;

create or replace function public.enviar_pedido_cocina(p_pedido_id bigint)
returns table (
  pedido_id bigint,
  detalles_enviados integer,
  cabecera_actualizada boolean,
  pedido_estado text,
  enviado_en timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $enviar_pedido_cocina$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_pedido public.pedido%rowtype;
  v_detalles_enviados integer;
  v_envio_detalles timestamptz;
  v_estado_derivado text;
  v_cabecera_actualizada boolean;
begin
  if p_pedido_id is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para enviar pedidos';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using errcode = '42501', message = 'No autorizado para enviar pedidos';
  end if;

  select order_row.*
  into v_pedido
  from public.pedido as order_row
  where order_row.id = p_pedido_id
    and order_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO', 'ENTREGADO'
    )
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Pedido no disponible para el usuario autenticado';
  end if;

  v_envio_detalles := pg_catalog.clock_timestamp();
  update public.detalle_pedido as detail_row
  set estado = 'ENVIADO', enviado_en = v_envio_detalles
  where detail_row.pedido_id = v_pedido.id
    and detail_row.estado = 'ABIERTO';
  get diagnostics v_detalles_enviados = row_count;

  if v_detalles_enviados = 0 then
    return query select v_pedido.id, 0, false, v_pedido.estado, v_pedido.enviado_en;
    return;
  end if;

  if v_pedido.enviado_en is null then
    update public.pedido as order_row
    set enviado_en = v_envio_detalles
    where order_row.id = v_pedido.id;
  end if;

  if v_pedido.estado = 'ENTREGADO' then
    return query
    select v_pedido.id, v_detalles_enviados, false, v_pedido.estado,
      pg_catalog.coalesce(v_pedido.enviado_en, v_envio_detalles);
    return;
  end if;

  select sync_result.pedido_estado, sync_result.cabecera_actualizada
  into strict v_estado_derivado, v_cabecera_actualizada
  from public.sincronizar_estado_operativo_pedido(
    v_pedido.id, v_usuario_id
  ) as sync_result;

  return query
  select v_pedido.id, v_detalles_enviados, v_cabecera_actualizada,
    v_estado_derivado, pg_catalog.coalesce(v_pedido.enviado_en, v_envio_detalles);
end;
$enviar_pedido_cocina$;

alter function public.enviar_pedido_cocina(bigint) owner to postgres;
revoke all on function public.enviar_pedido_cocina(bigint) from public;
revoke all on function public.enviar_pedido_cocina(bigint) from anon;
grant execute on function public.enviar_pedido_cocina(bigint) to authenticated;

create or replace function public.actualizar_estado_detalle_cocina(
  p_detalle_id bigint,
  p_estado_esperado text,
  p_estado_nuevo text
)
returns table (detalle_id bigint, estado text, modificado_en timestamptz)
language plpgsql
security definer
set search_path = pg_catalog
as $actualizar_estado_detalle_cocina$
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
    raise exception using errcode = '40001', message = 'El detalle cambió durante la operación';
  end if;
  if v_detalle.estado is distinct from p_estado_esperado then
    raise exception using errcode = '40001', message = 'El detalle fue actualizado por otra sesión';
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

alter function public.actualizar_estado_detalle_cocina(bigint, text, text)
  owner to postgres;
revoke all on function public.actualizar_estado_detalle_cocina(bigint, text, text)
  from public;
revoke all on function public.actualizar_estado_detalle_cocina(bigint, text, text)
  from anon;
grant execute on function public.actualizar_estado_detalle_cocina(bigint, text, text)
  to authenticated;

notify pgrst, 'reload schema';

commit;
