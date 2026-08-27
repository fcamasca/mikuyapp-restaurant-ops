begin;

create or replace function public.obtener_tablero_cocina()
returns table (
  pedido_id bigint,
  pedido_estado text,
  mesa_id uuid,
  mesa_codigo text,
  mesa_nombre text,
  mesa_estado text,
  detalle_id bigint,
  producto_id uuid,
  producto_codigo text,
  producto_nombre text,
  cantidad integer,
  observacion text,
  estado text,
  enviado_en timestamptz,
  modificado_en timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $obtener_tablero_cocina$
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
  order by detail_row.enviado_en, order_row.id, detail_row.id;
end;
$obtener_tablero_cocina$;

alter function public.obtener_tablero_cocina() owner to postgres;
revoke all on function public.obtener_tablero_cocina() from public;
revoke all on function public.obtener_tablero_cocina() from anon;
grant execute on function public.obtener_tablero_cocina() to authenticated;

notify pgrst, 'reload schema';

commit;
