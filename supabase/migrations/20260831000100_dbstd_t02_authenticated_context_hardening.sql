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

comment on column public.pedido.estado is
  'Estado actual de la cabecera del pedido. Durante el flujo operativo se sincroniza a partir de los estados de sus detalles; un pedido ENTREGADO sin nuevos detalles conserva su estado. PAGADO y ANULADO son estados terminales.';

comment on column public.pedido.enviado_en is
  'Instante del primer envío del pedido a cocina. Los envíos posteriores de nuevos detalles no reemplazan este valor.';

comment on column public.pedido.modificado_en is
  'Comportamiento actual: se inicializa con creado_en y se actualiza al insertar o eliminar detalles, o al modificar cantidad, observacion, pedido_id o producto_id de un detalle. No cambia por una transición aislada de estado del detalle. Su semántica definitiva permanece pendiente de decisión.';

comment on column public.pedido.modificado_por is
  'Comportamiento actual: se inicializa con creado_por y se actualiza con el actor que inserta o elimina detalles, o modifica cantidad, observacion, pedido_id o producto_id de un detalle. No cambia por una transición aislada de estado del detalle. Su semántica definitiva permanece pendiente de decisión.';

comment on column public.detalle_pedido.estado is
  'Estado operativo individual del detalle. El conjunto de estados de los detalles se utiliza para derivar los estados operativos del pedido y de la mesa.';

comment on column public.detalle_pedido.precio_unitario is
  'Snapshot del precio unitario aplicado al crear el detalle; no depende de cambios posteriores en producto.precio.';

comment on column public.detalle_pedido.enviado_en is
  'Instante del primer envío individual del detalle a cocina. Solo puede establecerse en la transición ABIERTO a ENVIADO y, una vez fijado, es inmutable.';

comment on column public.pago.importe is
  'Snapshot del importe registrado al cobrar el pedido; constituye el valor persistido utilizado por los reportes de ventas.';

comment on function public.obtener_contexto_autenticado() is
  'Devuelve el local y rol del usuario autenticado únicamente cuando perfil, rol y local están activos y el rol pertenece al conjunto autorizado; en otro caso no devuelve filas.';

comment on function public.sincronizar_estado_operativo_pedido(bigint, uuid) is
  'Deriva y sincroniza los estados operativos del pedido y de su mesa a partir de los estados de sus detalles, y registra en historial_estado los cambios de estado de la cabecera.';

comment on function public.registrar_auditoria_detalle_pedido() is
  'Mantiene la auditoría de detalle_pedido, protege sus campos de creación, valida la asignación e inmutabilidad de enviado_en y propaga a pedido únicamente las modificaciones de contenido definidas por el comportamiento actual.';

comment on function public.exportar_productos_local() is
  'Devuelve al ADMINISTRADOR los productos de su local autenticado, incluidos activos e inactivos, ordenados por categoría y producto; rechaza contextos inexistentes o inválidos.';

comment on function public.exportar_ventas_hoy() is
  'Devuelve al ADMINISTRADOR las ventas PAGADO de su local correspondientes al día en America/Lima, ordenadas por fecha de pago; rechaza contextos inexistentes o inválidos.';

comment on function public.obtener_resumen_ventas_hoy() is
  'Agrupa por medio de pago las ventas PAGADO del día en America/Lima para ADMINISTRADOR y CAJA de su local autenticado; rechaza contextos inexistentes o inválidos.';

comment on function public.obtener_creadores_pedidos_vigentes(bigint[]) is
  'Devuelve al MOZO los nombres de los creadores de los pedidos solicitados que permanecen vigentes y pertenecen a su local autenticado.';

comment on trigger detalle_pedido_registrar_auditoria on public.detalle_pedido is
  'Trigger BEFORE INSERT, UPDATE o DELETE que ejecuta registrar_auditoria_detalle_pedido() para mantener auditoría, validar enviado_en y propagar al pedido las modificaciones de contenido definidas por el comportamiento actual.';

notify pgrst, 'reload schema';

commit;
