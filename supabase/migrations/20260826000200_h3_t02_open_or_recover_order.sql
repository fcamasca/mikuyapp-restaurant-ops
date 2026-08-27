begin;

create or replace function public.h3_abrir_o_recuperar_pedido(
  p_mesa_id uuid
)
returns table (
  pedido_id bigint,
  pedido_estado text,
  creado_en timestamptz,
  enviado_en timestamptz,
  fue_creado boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $h3_abrir_o_recuperar_pedido$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_mesa_estado text;
  v_pedido public.pedido%rowtype;
begin
  if p_mesa_id is null or v_usuario_id is null then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para abrir pedidos';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.h2_auth_context() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para abrir pedidos';
  end if;

  select table_row.estado
  into v_mesa_estado
  from public.mesa as table_row
  where table_row.id = p_mesa_id
    and table_row.local_id = v_local_id
    and table_row.activo = true
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Mesa no disponible para el usuario autenticado';
  end if;

  select order_row.*
  into v_pedido
  from public.pedido as order_row
  where order_row.mesa_id = p_mesa_id
    and order_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO',
      'ENVIADO',
      'RECIBIDO_COCINA',
      'EN_PREPARACION',
      'LISTO',
      'ENTREGADO'
    );

  if found then
    return query
    select
      v_pedido.id,
      v_pedido.estado,
      v_pedido.creado_en,
      v_pedido.enviado_en,
      false;
    return;
  end if;

  if v_mesa_estado <> 'LIBRE' then
    raise exception using
      errcode = '55000',
      message = 'La mesa no está libre y no tiene un pedido vigente recuperable';
  end if;

  insert into public.pedido (
    local_id,
    mesa_id,
    creado_por,
    estado
  )
  values (
    v_local_id,
    p_mesa_id,
    v_usuario_id,
    'ABIERTO'
  )
  returning * into v_pedido;

  insert into public.historial_estado (
    pedido_id,
    estado_anterior,
    estado_nuevo,
    usuario_id
  )
  values (
    v_pedido.id,
    null,
    'ABIERTO',
    v_usuario_id
  );

  update public.mesa as table_row
  set estado = 'OCUPADA'
  where table_row.id = p_mesa_id
    and table_row.local_id = v_local_id
    and table_row.activo = true
    and table_row.estado = 'LIBRE';

  if not found then
    raise exception using
      errcode = '40001',
      message = 'La mesa cambió durante la apertura del pedido';
  end if;

  return query
  select
    v_pedido.id,
    v_pedido.estado,
    v_pedido.creado_en,
    v_pedido.enviado_en,
    true;
end;
$h3_abrir_o_recuperar_pedido$;

alter function public.h3_abrir_o_recuperar_pedido(uuid) owner to postgres;

revoke all on function public.h3_abrir_o_recuperar_pedido(uuid) from public;
revoke all on function public.h3_abrir_o_recuperar_pedido(uuid) from anon;
grant execute on function public.h3_abrir_o_recuperar_pedido(uuid) to authenticated;

commit;
