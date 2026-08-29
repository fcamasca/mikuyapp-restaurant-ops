begin;

create or replace function public.obtener_pedidos_pendientes_pago_caja()
returns table (
  pedido_id bigint,
  pedido_estado text,
  pedido_creado_en timestamptz,
  mesa_id uuid,
  mesa_codigo text,
  mesa_nombre text,
  mesa_estado text,
  detalle_id bigint,
  producto_id uuid,
  producto_nombre text,
  cantidad integer,
  precio_unitario numeric,
  importe_linea numeric,
  total_pedido numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $obtener_pedidos_pendientes_pago_caja$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
begin
  if v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para consultar pedidos pendientes de pago';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'CAJA' then
    raise exception using errcode = '42501', message = 'No autorizado para consultar pedidos pendientes de pago';
  end if;

  return query
  select
    order_row.id,
    order_row.estado,
    order_row.creado_en,
    table_row.id,
    table_row.codigo,
    table_row.nombre,
    table_row.estado,
    detail_row.id,
    product_row.id,
    product_row.nombre,
    detail_row.cantidad,
    detail_row.precio_unitario,
    detail_row.cantidad * detail_row.precio_unitario,
    pg_catalog.sum(
      detail_row.cantidad * detail_row.precio_unitario
    ) over (partition by order_row.id)
  from public.pedido as order_row
  inner join public.mesa as table_row
    on table_row.id = order_row.mesa_id
    and table_row.local_id = order_row.local_id
  inner join public.detalle_pedido as detail_row
    on detail_row.pedido_id = order_row.id
  inner join public.producto as product_row
    on product_row.id = detail_row.producto_id
    and product_row.local_id = order_row.local_id
  where order_row.local_id = v_local_id
    and order_row.estado = 'ENTREGADO'
    and table_row.estado = 'PENDIENTE_PAGO'
  order by order_row.creado_en, order_row.id, detail_row.id;
end;
$obtener_pedidos_pendientes_pago_caja$;

alter function public.obtener_pedidos_pendientes_pago_caja() owner to postgres;
revoke all on function public.obtener_pedidos_pendientes_pago_caja() from public;
revoke all on function public.obtener_pedidos_pendientes_pago_caja() from anon;
grant execute on function public.obtener_pedidos_pendientes_pago_caja() to authenticated;

notify pgrst, 'reload schema';

commit;
