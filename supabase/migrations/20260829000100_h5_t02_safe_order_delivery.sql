begin;

create or replace function public.entregar_pedido(p_pedido_id bigint)
returns table (
  pedido_id bigint,
  pedido_estado text,
  mesa_id uuid,
  mesa_estado text
)
language plpgsql
security definer
set search_path = pg_catalog
as $entregar_pedido$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_pedido public.pedido%rowtype;
  v_mesa public.mesa%rowtype;
  v_total_detalles bigint;
  v_detalles_no_listos bigint;
begin
  if p_pedido_id is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para entregar pedidos';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using errcode = '42501', message = 'No autorizado para entregar pedidos';
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

  if v_pedido.estado is distinct from 'LISTO' then
    raise exception using errcode = '40001', message = 'El pedido ya no está listo para entregar';
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

  if v_mesa.estado is distinct from 'PEDIDO_LISTO' then
    raise exception using errcode = '40001', message = 'La mesa ya no está lista para entrega';
  end if;

  select
    pg_catalog.count(*),
    pg_catalog.count(*) filter (where detail_row.estado is distinct from 'LISTO')
  into v_total_detalles, v_detalles_no_listos
  from public.detalle_pedido as detail_row
  where detail_row.pedido_id = v_pedido.id;

  if v_total_detalles = 0 then
    raise exception using errcode = '55000', message = 'El pedido no contiene detalles para entregar';
  end if;

  if v_detalles_no_listos > 0 then
    raise exception using errcode = '55000', message = 'Todos los detalles deben estar listos para entregar';
  end if;

  update public.pedido as order_row
  set estado = 'ENTREGADO'
  where order_row.id = v_pedido.id
    and order_row.estado = 'LISTO';

  if not found then
    raise exception using errcode = '40001', message = 'El pedido cambió durante la entrega';
  end if;

  insert into public.historial_estado (
    pedido_id, estado_anterior, estado_nuevo, usuario_id
  ) values (
    v_pedido.id, 'LISTO', 'ENTREGADO', v_usuario_id
  );

  update public.mesa as table_row
  set estado = 'PENDIENTE_PAGO'
  where table_row.id = v_mesa.id
    and table_row.local_id = v_local_id
    and table_row.estado = 'PEDIDO_LISTO';

  if not found then
    raise exception using errcode = '40001', message = 'La mesa cambió durante la entrega';
  end if;

  return query
  select v_pedido.id, 'ENTREGADO'::text, v_mesa.id, 'PENDIENTE_PAGO'::text;
end;
$entregar_pedido$;

alter function public.entregar_pedido(bigint) owner to postgres;
revoke all on function public.entregar_pedido(bigint) from public;
revoke all on function public.entregar_pedido(bigint) from anon;
grant execute on function public.entregar_pedido(bigint) to authenticated;

create or replace function public.crear_o_recuperar_pedido_mesa(p_mesa_id uuid)
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
as $crear_o_recuperar_pedido_mesa$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_mesa_estado text;
  v_pedido public.pedido%rowtype;
begin
  if p_mesa_id is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para abrir pedidos';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using errcode = '42501', message = 'No autorizado para abrir pedidos';
  end if;

  select table_row.estado
  into v_mesa_estado
  from public.mesa as table_row
  where table_row.id = p_mesa_id
    and table_row.local_id = v_local_id
    and table_row.activo = true
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Mesa no disponible para el usuario autenticado';
  end if;

  select order_row.*
  into v_pedido
  from public.pedido as order_row
  where order_row.mesa_id = p_mesa_id
    and order_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
    );

  if found then
    return query
    select v_pedido.id, v_pedido.estado, v_pedido.creado_en,
      v_pedido.enviado_en, false;
    return;
  end if;

  if v_mesa_estado <> 'LIBRE' then
    raise exception using errcode = '55000', message = 'La mesa no está libre y no tiene un pedido vigente recuperable';
  end if;

  insert into public.pedido (local_id, mesa_id, creado_por, estado)
  values (v_local_id, p_mesa_id, v_usuario_id, 'ABIERTO')
  returning * into v_pedido;

  insert into public.historial_estado (
    pedido_id, estado_anterior, estado_nuevo, usuario_id
  ) values (v_pedido.id, null, 'ABIERTO', v_usuario_id);

  update public.mesa as table_row
  set estado = 'OCUPADA'
  where table_row.id = p_mesa_id
    and table_row.local_id = v_local_id
    and table_row.activo = true
    and table_row.estado = 'LIBRE';

  if not found then
    raise exception using errcode = '40001', message = 'La mesa cambió durante la apertura del pedido';
  end if;

  return query
  select v_pedido.id, v_pedido.estado, v_pedido.creado_en,
    v_pedido.enviado_en, true;
end;
$crear_o_recuperar_pedido_mesa$;

create or replace function public.agregar_detalle_pedido(
  p_pedido_id bigint,
  p_producto_id uuid,
  p_cantidad integer,
  p_observacion text default null
)
returns table (
  detalle_id bigint,
  pedido_id bigint,
  producto_id uuid,
  cantidad integer,
  precio_unitario numeric,
  observacion text,
  estado text
)
language plpgsql
security definer
set search_path = pg_catalog
as $agregar_detalle_pedido$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_precio public.producto.precio%type;
  v_detalle_id bigint;
  v_detalle public.detalle_pedido%rowtype;
begin
  if v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para agregar productos al pedido';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using errcode = '42501', message = 'No autorizado para agregar productos al pedido';
  end if;
  if p_pedido_id is null or p_producto_id is null then
    raise exception using errcode = '22023', message = 'Pedido y producto son obligatorios';
  end if;
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception using errcode = '22023', message = 'La cantidad debe ser un entero positivo';
  end if;
  if p_observacion is not null and pg_catalog.btrim(p_observacion) = '' then
    raise exception using errcode = '22023', message = 'La observación no puede estar vacía';
  end if;

  perform 1
  from public.pedido as order_row
  where order_row.id = p_pedido_id
    and order_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
    )
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Pedido no disponible para el usuario autenticado';
  end if;

  select product_row.precio
  into v_precio
  from public.producto as product_row
  inner join public.categoria as category_row
    on category_row.id = product_row.categoria_id
    and category_row.local_id = product_row.local_id
  where product_row.id = p_producto_id
    and product_row.local_id = v_local_id
    and product_row.activo = true
    and category_row.activo = true;
  if not found then
    raise exception using errcode = '42501', message = 'Producto no disponible para el pedido';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_pedido_id::text || ':' || p_producto_id::text, 0)
  );

  select detail_row.id
  into v_detalle_id
  from public.detalle_pedido as detail_row
  where detail_row.pedido_id = p_pedido_id
    and detail_row.producto_id = p_producto_id
    and detail_row.estado = 'ABIERTO'
    and nullif(pg_catalog.btrim(detail_row.observacion), '')
      is not distinct from nullif(pg_catalog.btrim(p_observacion), '')
  order by detail_row.id
  limit 1
  for update;

  if v_detalle_id is not null then
    update public.detalle_pedido as detail_row
    set cantidad = detail_row.cantidad + p_cantidad
    where detail_row.id = v_detalle_id
      and detail_row.estado = 'ABIERTO'
    returning detail_row.* into strict v_detalle;
  else
    insert into public.detalle_pedido as detail_row (
      pedido_id, producto_id, cantidad, precio_unitario, observacion, estado
    ) values (
      p_pedido_id, p_producto_id, p_cantidad, v_precio, p_observacion, 'ABIERTO'
    )
    returning detail_row.* into strict v_detalle;
  end if;

  perform public.sincronizar_estado_operativo_pedido(p_pedido_id, v_usuario_id);

  return query
  select v_detalle.id, v_detalle.pedido_id, v_detalle.producto_id,
    v_detalle.cantidad, v_detalle.precio_unitario, v_detalle.observacion,
    v_detalle.estado;
end;
$agregar_detalle_pedido$;

create or replace function public.enviar_pedido_cocina(p_pedido_id bigint)
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
  v_envio_detalles timestamptz;
  v_estado_derivado text;
  v_cabecera_actualizada boolean;
  v_pedido_enviado_en timestamptz;
begin
  if p_pedido_id is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para enviar pedidos';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using errcode = '42501', message = 'No autorizado para enviar pedidos';
  end if;

  select order_row.*
  into v_pedido
  from public.pedido as order_row
  where order_row.id = p_pedido_id
    and order_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
    )
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Pedido no disponible para el usuario autenticado';
  end if;

  v_envio_detalles := pg_catalog.clock_timestamp();
  update public.detalle_pedido as detail_row
  set estado = 'ENVIADO', enviado_en = v_envio_detalles
  where detail_row.pedido_id = v_pedido.id
    and detail_row.estado = 'ABIERTO';
  get diagnostics v_detalles_enviados = row_count;

  if v_detalles_enviados = 0 then
    return query select v_pedido.id, 0, false, v_pedido.estado, v_pedido.enviado_en;
    return;
  end if;

  v_pedido_enviado_en := case
    when v_pedido.enviado_en is null then v_envio_detalles
    else v_pedido.enviado_en
  end;

  if v_pedido.enviado_en is null then
    update public.pedido as order_row
    set enviado_en = v_pedido_enviado_en
    where order_row.id = v_pedido.id;
  end if;

  select sync_result.pedido_estado, sync_result.cabecera_actualizada
  into strict v_estado_derivado, v_cabecera_actualizada
  from public.sincronizar_estado_operativo_pedido(
    v_pedido.id, v_usuario_id
  ) as sync_result;

  return query
  select v_pedido.id, v_detalles_enviados, v_cabecera_actualizada,
    v_estado_derivado, v_pedido_enviado_en;
end;
$enviar_pedido_cocina$;

alter policy detalle_pedido_update_abierto_mozo
on public.detalle_pedido
using (
  detalle_pedido.estado = 'ABIERTO'
  and exists (
    select 1
    from public.pedido as order_row
    cross join public.obtener_contexto_autenticado() as auth_context
    where order_row.id = detalle_pedido.pedido_id
      and order_row.local_id = auth_context.local_id
      and auth_context.rol_codigo = 'MOZO'
      and order_row.estado in (
        'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
      )
  )
)
with check (
  detalle_pedido.estado = 'ABIERTO'
  and exists (
    select 1
    from public.pedido as order_row
    cross join public.obtener_contexto_autenticado() as auth_context
    where order_row.id = detalle_pedido.pedido_id
      and order_row.local_id = auth_context.local_id
      and auth_context.rol_codigo = 'MOZO'
      and order_row.estado in (
        'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
      )
  )
);

alter policy detalle_pedido_delete_abierto_mozo
on public.detalle_pedido
using (
  detalle_pedido.estado = 'ABIERTO'
  and exists (
    select 1
    from public.pedido as order_row
    cross join public.obtener_contexto_autenticado() as auth_context
    where order_row.id = detalle_pedido.pedido_id
      and order_row.local_id = auth_context.local_id
      and auth_context.rol_codigo = 'MOZO'
      and order_row.estado in (
        'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
      )
  )
);

notify pgrst, 'reload schema';

commit;
