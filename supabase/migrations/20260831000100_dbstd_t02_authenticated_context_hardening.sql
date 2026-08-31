begin;

create or replace function public.obtener_resumen_ventas_hoy()
returns table (
  medio text,
  pedidos_pagados bigint,
  importe numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $obtener_resumen_ventas_hoy$
declare
  v_local_id uuid;
  v_rol_codigo text;
begin
  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null
    or v_rol_codigo is null
    or v_rol_codigo not in ('ADMINISTRADOR', 'CAJA') then
    raise exception using
      errcode = '42501',
      message = 'No autorizado';
  end if;

  return query
  select
    payment_row.medio,
    pg_catalog.count(*)::bigint,
    coalesce(pg_catalog.sum(payment_row.importe), 0)::numeric
  from public.pago as payment_row
  inner join public.pedido as order_row
    on order_row.id = payment_row.pedido_id
  where order_row.local_id = v_local_id
    and order_row.estado = 'PAGADO'
    and (payment_row.pagado_en at time zone 'America/Lima')::date
      = (pg_catalog.now() at time zone 'America/Lima')::date
  group by payment_row.medio;
end;
$obtener_resumen_ventas_hoy$;

alter function public.obtener_resumen_ventas_hoy() owner to postgres;
revoke all on function public.obtener_resumen_ventas_hoy() from public;
revoke all on function public.obtener_resumen_ventas_hoy() from anon;
grant execute on function public.obtener_resumen_ventas_hoy() to authenticated;

create or replace function public.exportar_ventas_hoy()
returns table (
  pedido_id bigint,
  mesa text,
  pagado_en timestamptz,
  medio text,
  importe numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $exportar_ventas_hoy$
declare
  v_local_id uuid;
  v_rol_codigo text;
begin
  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null
    or v_rol_codigo is distinct from 'ADMINISTRADOR' then
    raise exception using
      errcode = '42501',
      message = 'No autorizado';
  end if;

  return query
  select
    order_row.id,
    table_row.codigo,
    payment_row.pagado_en,
    payment_row.medio,
    payment_row.importe
  from public.pago as payment_row
  inner join public.pedido as order_row
    on order_row.id = payment_row.pedido_id
  inner join public.mesa as table_row
    on table_row.id = order_row.mesa_id
  where order_row.local_id = v_local_id
    and order_row.estado = 'PAGADO'
    and (payment_row.pagado_en at time zone 'America/Lima')::date
      = (pg_catalog.now() at time zone 'America/Lima')::date
  order by payment_row.pagado_en;
end;
$exportar_ventas_hoy$;

alter function public.exportar_ventas_hoy() owner to postgres;
revoke all on function public.exportar_ventas_hoy() from public;
revoke all on function public.exportar_ventas_hoy() from anon;
grant execute on function public.exportar_ventas_hoy() to authenticated;

create or replace function public.exportar_productos_local()
returns table (
  codigo_categoria text,
  categoria text,
  codigo_producto text,
  producto text,
  precio numeric,
  activo boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $exportar_productos_local$
declare
  v_local_id uuid;
  v_rol_codigo text;
begin
  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null
    or v_rol_codigo is distinct from 'ADMINISTRADOR' then
    raise exception using
      errcode = '42501',
      message = 'No autorizado';
  end if;

  return query
  select
    category_row.codigo,
    category_row.nombre,
    product_row.codigo,
    product_row.nombre,
    product_row.precio,
    product_row.activo
  from public.producto as product_row
  inner join public.categoria as category_row
    on category_row.id = product_row.categoria_id
    and category_row.local_id = product_row.local_id
  where product_row.local_id = v_local_id
  order by category_row.orden, category_row.nombre, product_row.nombre;
end;
$exportar_productos_local$;

alter function public.exportar_productos_local() owner to postgres;
revoke all on function public.exportar_productos_local() from public;
revoke all on function public.exportar_productos_local() from anon;
grant execute on function public.exportar_productos_local() to authenticated;

alter function public.obtener_creadores_pedidos_vigentes(bigint[]) stable;
alter function public.obtener_creadores_pedidos_vigentes(bigint[]) owner to postgres;
revoke all on function public.obtener_creadores_pedidos_vigentes(bigint[]) from public;
revoke all on function public.obtener_creadores_pedidos_vigentes(bigint[]) from anon;
grant execute on function public.obtener_creadores_pedidos_vigentes(bigint[]) to authenticated;

notify pgrst, 'reload schema';

commit;
