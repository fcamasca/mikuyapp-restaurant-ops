begin;

drop function public.rpc_obtener_pedidos_operacion_admin();

create function public.rpc_obtener_pedidos_operacion_admin()
returns table(
  pedido_id bigint,
  mesa_id uuid,
  mesa_codigo text,
  mesa_nombre text,
  pedido_estado text,
  mesa_estado text,
  creado_en timestamptz,
  ultima_actualizacion_en timestamptz,
  tiene_pagos boolean,
  cantidad_pagos bigint,
  subtotal numeric,
  descuento numeric,
  total_neto numeric,
  pagado_acumulado numeric,
  saldo numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_actor uuid := auth.uid();
  v_local uuid;
  v_rol text;
begin
  select contexto.local_id, contexto.rol_codigo
    into v_local, v_rol
  from public.obtener_contexto_autenticado() as contexto;

  if v_actor is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then
    raise exception using errcode = '42501', message = 'No autorizado para consultar operación administrativa';
  end if;

  return query
  select
    pedido.id,
    mesa.id,
    mesa.codigo,
    mesa.nombre,
    pedido.estado,
    mesa.estado,
    pedido.creado_en,
    greatest(
      pedido.creado_en,
      pedido.modificado_en,
      historial.ultima_transicion_en
    ) as ultima_actualizacion_en,
    coalesce(pagos.cantidad, 0) > 0,
    coalesce(pagos.cantidad, 0),
    totales.subtotal,
    totales.descuento,
    totales.total_neto,
    coalesce(pagos.pagado, 0),
    totales.total_neto - coalesce(pagos.pagado, 0)
  from public.pedido as pedido
  join public.mesa as mesa
    on mesa.id = pedido.mesa_id
    and mesa.local_id = pedido.local_id
  cross join lateral public.fn_resolver_total_pedido(pedido.id) as totales
  left join lateral (
    select count(*) as cantidad, sum(pago.importe) as pagado
    from public.pago as pago
    where pago.pedido_id = pedido.id
  ) as pagos on true
  left join lateral (
    select max(historial_estado.creado_en) as ultima_transicion_en
    from public.historial_estado
    where historial_estado.pedido_id = pedido.id
  ) as historial on true
  where pedido.local_id = v_local
    and pedido.estado in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO', 'ENTREGADO', 'PAGADO', 'ANULADO')
  order by ultima_actualizacion_en desc, pedido.id desc;
end;
$$;

alter function public.rpc_obtener_pedidos_operacion_admin() owner to postgres;
revoke all on function public.rpc_obtener_pedidos_operacion_admin() from public, anon, authenticated, service_role;
grant execute on function public.rpc_obtener_pedidos_operacion_admin() to authenticated;
comment on function public.rpc_obtener_pedidos_operacion_admin() is 'Lectura operacional ADMINISTRADOR del mismo local para descuento/anulación; incluye última actualización autoritativa y no concede cobro.';

notify pgrst, 'reload schema';

commit;
