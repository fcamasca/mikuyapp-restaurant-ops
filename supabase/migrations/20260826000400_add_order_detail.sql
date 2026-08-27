begin;

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
begin
  if v_usuario_id is null then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para agregar productos al pedido';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para agregar productos al pedido';
  end if;

  if p_pedido_id is null or p_producto_id is null then
    raise exception using
      errcode = '22023',
      message = 'Pedido y producto son obligatorios';
  end if;

  if p_cantidad is null or p_cantidad <= 0 then
    raise exception using
      errcode = '22023',
      message = 'La cantidad debe ser un entero positivo';
  end if;

  if p_observacion is not null and pg_catalog.btrim(p_observacion) = '' then
    raise exception using
      errcode = '22023',
      message = 'La observación no puede estar vacía';
  end if;

  perform 1
  from public.pedido as order_row
  where order_row.id = p_pedido_id
    and order_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO',
      'ENVIADO',
      'RECIBIDO_COCINA',
      'EN_PREPARACION',
      'LISTO',
      'ENTREGADO'
    )
  for share;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Pedido no disponible para el usuario autenticado';
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
    raise exception using
      errcode = '42501',
      message = 'Producto no disponible para el pedido';
  end if;

  return query
  insert into public.detalle_pedido as detail_row (
    pedido_id,
    producto_id,
    cantidad,
    precio_unitario,
    observacion,
    estado
  )
  values (
    p_pedido_id,
    p_producto_id,
    p_cantidad,
    v_precio,
    p_observacion,
    'ABIERTO'
  )
  returning
    detail_row.id,
    detail_row.pedido_id,
    detail_row.producto_id,
    detail_row.cantidad,
    detail_row.precio_unitario,
    detail_row.observacion,
    detail_row.estado;
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

notify pgrst, 'reload schema';

commit;
