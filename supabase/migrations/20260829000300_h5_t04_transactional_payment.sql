begin;

create or replace function public.registrar_pago_pedido(
  p_pedido_id bigint,
  p_medio text
)
returns table (
  pago_id bigint,
  pedido_id bigint,
  pedido_estado text,
  mesa_id uuid,
  mesa_estado text,
  importe numeric,
  medio text,
  pagado_en timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $registrar_pago_pedido$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_pedido public.pedido%rowtype;
  v_mesa public.mesa%rowtype;
  v_importe public.pago.importe%type;
  v_pago public.pago%rowtype;
begin
  if p_pedido_id is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para registrar pagos';
  end if;

  if p_medio is null or p_medio not in ('EFECTIVO', 'YAPE', 'PLIN', 'TARJETA') then
    raise exception using errcode = '22023', message = 'Medio de pago inválido';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'CAJA' then
    raise exception using errcode = '42501', message = 'No autorizado para registrar pagos';
  end if;

  select order_row.*
  into v_pedido
  from public.pedido as order_row
  where order_row.id = p_pedido_id
    and order_row.local_id = v_local_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Pedido no disponible para el usuario autenticado';
  end if;

  if v_pedido.estado is distinct from 'ENTREGADO' then
    raise exception using errcode = '40001', message = 'El pedido ya no está disponible para cobro';
  end if;

  select table_row.*
  into v_mesa
  from public.mesa as table_row
  where table_row.id = v_pedido.mesa_id
    and table_row.local_id = v_local_id
    and table_row.activo = true
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Mesa no disponible para el usuario autenticado';
  end if;

  if v_mesa.estado is distinct from 'PENDIENTE_PAGO' then
    raise exception using errcode = '40001', message = 'La mesa ya no está pendiente de pago';
  end if;

  select pg_catalog.sum(detail_row.cantidad * detail_row.precio_unitario)
  into v_importe
  from public.detalle_pedido as detail_row
  where detail_row.pedido_id = v_pedido.id;

  if v_importe is null or v_importe <= 0 then
    raise exception using errcode = '55000', message = 'El pedido no tiene un importe positivo para cobrar';
  end if;

  insert into public.pago (pedido_id, importe, medio, usuario_id)
  values (v_pedido.id, v_importe, p_medio, v_usuario_id)
  returning * into strict v_pago;

  update public.pedido as order_row
  set estado = 'PAGADO'
  where order_row.id = v_pedido.id
    and order_row.estado = 'ENTREGADO';

  if not found then
    raise exception using errcode = '40001', message = 'El pedido cambió durante el cobro';
  end if;

  insert into public.historial_estado (
    pedido_id, estado_anterior, estado_nuevo, usuario_id
  ) values (
    v_pedido.id, 'ENTREGADO', 'PAGADO', v_usuario_id
  );

  update public.mesa as table_row
  set estado = 'LIBRE'
  where table_row.id = v_mesa.id
    and table_row.local_id = v_local_id
    and table_row.estado = 'PENDIENTE_PAGO';

  if not found then
    raise exception using errcode = '40001', message = 'La mesa cambió durante el cobro';
  end if;

  return query
  select v_pago.id, v_pedido.id, 'PAGADO'::text, v_mesa.id,
    'LIBRE'::text, v_pago.importe, v_pago.medio, v_pago.pagado_en;
end;
$registrar_pago_pedido$;

alter function public.registrar_pago_pedido(bigint, text) owner to postgres;
revoke all on function public.registrar_pago_pedido(bigint, text) from public;
revoke all on function public.registrar_pago_pedido(bigint, text) from anon;
grant execute on function public.registrar_pago_pedido(bigint, text) to authenticated;

notify pgrst, 'reload schema';

commit;
