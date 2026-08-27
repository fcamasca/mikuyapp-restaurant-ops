begin;

create or replace function public.liberar_mesa_pedido_vacio(
  p_pedido_id bigint
)
returns table (
  pedido_id bigint,
  mesa_id uuid,
  pedido_estado text,
  mesa_estado text
)
language plpgsql
security definer
set search_path = pg_catalog
as $liberar_mesa_pedido_vacio$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_pedido public.pedido%rowtype;
  v_mesa_estado text;
begin
  if p_pedido_id is null or v_usuario_id is null then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para liberar mesas';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para liberar mesas';
  end if;

  select order_row.*
  into v_pedido
  from public.pedido as order_row
  where order_row.id = p_pedido_id
    and order_row.local_id = v_local_id
    and order_row.estado = 'ABIERTO'
  for update;

  if not found then
    raise exception using
      errcode = '55000',
      message = 'El pedido ya no puede liberar la mesa';
  end if;

  select table_row.estado
  into v_mesa_estado
  from public.mesa as table_row
  where table_row.id = v_pedido.mesa_id
    and table_row.local_id = v_local_id
    and table_row.activo = true
  for update;

  if not found or v_mesa_estado <> 'OCUPADA' then
    raise exception using
      errcode = '55000',
      message = 'La mesa ya no está ocupada por este pedido';
  end if;

  if exists (
    select 1
    from public.detalle_pedido as detail_row
    where detail_row.pedido_id = v_pedido.id
  ) then
    raise exception using
      errcode = '55000',
      message = 'El pedido contiene productos y no puede liberar la mesa';
  end if;

  update public.pedido as order_row
  set estado = 'ANULADO'
  where order_row.id = v_pedido.id
    and order_row.estado = 'ABIERTO';

  if not found then
    raise exception using
      errcode = '40001',
      message = 'El pedido cambió durante la liberación de la mesa';
  end if;

  insert into public.historial_estado (
    pedido_id,
    estado_anterior,
    estado_nuevo,
    usuario_id
  )
  values (
    v_pedido.id,
    'ABIERTO',
    'ANULADO',
    v_usuario_id
  );

  update public.mesa as table_row
  set estado = 'LIBRE'
  where table_row.id = v_pedido.mesa_id
    and table_row.local_id = v_local_id
    and table_row.estado = 'OCUPADA';

  if not found then
    raise exception using
      errcode = '40001',
      message = 'La mesa cambió durante su liberación';
  end if;

  return query
  select v_pedido.id, v_pedido.mesa_id, 'ANULADO'::text, 'LIBRE'::text;
end;
$liberar_mesa_pedido_vacio$;

alter function public.liberar_mesa_pedido_vacio(bigint) owner to postgres;

revoke all on function public.liberar_mesa_pedido_vacio(bigint) from public;
revoke all on function public.liberar_mesa_pedido_vacio(bigint) from anon;
grant execute on function public.liberar_mesa_pedido_vacio(bigint) to authenticated;

notify pgrst, 'reload schema';

commit;
