begin;

create or replace function public.enviar_pedido_cocina(
  p_pedido_id bigint
)
returns table (
  pedido_id bigint,
  detalles_enviados integer,
  cabecera_actualizada boolean,
  pedido_estado text,
  enviado_en timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $enviar_pedido_cocina$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_pedido public.pedido%rowtype;
  v_detalles_enviados integer;
  v_primer_envio timestamptz;
begin
  if p_pedido_id is null or v_usuario_id is null then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para enviar pedidos';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para enviar pedidos';
  end if;

  select order_row.*
  into v_pedido
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
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Pedido no disponible para el usuario autenticado';
  end if;

  update public.detalle_pedido as detail_row
  set estado = 'ENVIADO'
  where detail_row.pedido_id = v_pedido.id
    and detail_row.estado = 'ABIERTO';

  get diagnostics v_detalles_enviados = row_count;

  if v_detalles_enviados = 0 then
    return query
    select
      v_pedido.id,
      0,
      false,
      v_pedido.estado,
      v_pedido.enviado_en;
    return;
  end if;

  if v_pedido.estado = 'ABIERTO' then
    v_primer_envio := pg_catalog.statement_timestamp();

    update public.pedido as order_row
    set
      estado = 'ENVIADO',
      enviado_en = v_primer_envio
    where order_row.id = v_pedido.id;

    insert into public.historial_estado (
      pedido_id,
      estado_anterior,
      estado_nuevo,
      usuario_id
    )
    values (
      v_pedido.id,
      'ABIERTO',
      'ENVIADO',
      v_usuario_id
    );

    v_pedido.estado := 'ENVIADO';
    v_pedido.enviado_en := v_primer_envio;

    return query
    select
      v_pedido.id,
      v_detalles_enviados,
      true,
      v_pedido.estado,
      v_pedido.enviado_en;
    return;
  end if;

  return query
  select
    v_pedido.id,
    v_detalles_enviados,
    false,
    v_pedido.estado,
    v_pedido.enviado_en;
end;
$enviar_pedido_cocina$;

alter function public.enviar_pedido_cocina(bigint) owner to postgres;

revoke all on function public.enviar_pedido_cocina(bigint) from public;
revoke all on function public.enviar_pedido_cocina(bigint) from anon;
grant execute on function public.enviar_pedido_cocina(bigint) to authenticated;

notify pgrst, 'reload schema';

commit;
