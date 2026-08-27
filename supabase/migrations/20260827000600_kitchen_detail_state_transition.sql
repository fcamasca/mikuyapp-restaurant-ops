begin;

create or replace function public.actualizar_estado_detalle_cocina(
  p_detalle_id bigint,
  p_estado_esperado text,
  p_estado_nuevo text
)
returns table (
  detalle_id bigint,
  estado text,
  modificado_en timestamptz
)
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
  if p_detalle_id is null
    or p_estado_esperado is null
    or p_estado_nuevo is null
    or v_usuario_id is null then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para actualizar el estado del detalle';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'COCINA' then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para actualizar el estado del detalle';
  end if;

  select detail_row.pedido_id
  into v_pedido_id
  from public.detalle_pedido as detail_row
  where detail_row.id = p_detalle_id;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Detalle no disponible para cocina';
  end if;

  select order_row.*
  into v_pedido
  from public.pedido as order_row
  where order_row.id = v_pedido_id
    and order_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO',
      'ENVIADO',
      'RECIBIDO_COCINA',
      'EN_PREPARACION',
      'LISTO'
    )
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Pedido no disponible para cocina';
  end if;

  select detail_row.*
  into v_detalle
  from public.detalle_pedido as detail_row
  where detail_row.id = p_detalle_id
    and detail_row.pedido_id = v_pedido.id
  for update;

  if not found then
    raise exception using
      errcode = '40001',
      message = 'El detalle cambió durante la operación';
  end if;

  if v_detalle.estado is distinct from p_estado_esperado then
    raise exception using
      errcode = '40001',
      message = 'El detalle fue actualizado por otra sesión';
  end if;

  if not (
    (p_estado_esperado = 'ENVIADO' and p_estado_nuevo = 'RECIBIDO_COCINA')
    or (
      p_estado_esperado = 'RECIBIDO_COCINA'
      and p_estado_nuevo = 'EN_PREPARACION'
    )
    or (p_estado_esperado = 'EN_PREPARACION' and p_estado_nuevo = 'LISTO')
  ) then
    raise exception using
      errcode = '22023',
      message = 'Transición de cocina no permitida';
  end if;

  update public.detalle_pedido as detail_row
  set estado = p_estado_nuevo
  where detail_row.id = v_detalle.id
  returning detail_row.* into v_detalle;

  return query
  select v_detalle.id, v_detalle.estado, v_detalle.modificado_en;
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
