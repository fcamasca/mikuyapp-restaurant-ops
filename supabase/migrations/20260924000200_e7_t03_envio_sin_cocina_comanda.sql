-- E7-T03 — Alta con snapshot de cocina, envío de productos sin cocina y generación de comanda.
-- Spec: E7-D04, E7-D05, E7-D06, E7-D12. Firmas y retornos existentes se conservan.
begin;

-- Ajuste mínimo requerido por E7-D05: el trigger de auditoría H4 sólo permitía fijar
-- enviado_en en ABIERTO -> ENVIADO; se admite también ABIERTO -> LISTO para detalles sin cocina.
CREATE OR REPLACE FUNCTION public.registrar_auditoria_detalle_pedido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $registrar_auditoria_detalle_pedido$
declare
  v_usuario_id uuid := auth.uid();
  v_pedido_id bigint;
  v_actualiza_contenido boolean := false;
begin
  v_pedido_id := case when tg_op = 'DELETE' then old.pedido_id else new.pedido_id end;

  if v_usuario_id is null then
    select order_row.creado_por
    into v_usuario_id
    from public.pedido as order_row
    where order_row.id = v_pedido_id;
  end if;

  if v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No se pudo determinar el autor de la modificación';
  end if;

  if tg_op = 'INSERT' then
    new.creado_por := v_usuario_id;
    new.modificado_por := v_usuario_id;
    new.modificado_en := new.creado_en;
    v_actualiza_contenido := true;
  elsif tg_op = 'UPDATE' then
    if old.enviado_en is not null
      and new.enviado_en is distinct from old.enviado_en then
      raise exception using
        errcode = '22000',
        message = 'El timestamp de envío del detalle es inmutable';
    end if;

    if old.enviado_en is null
      and new.enviado_en is not null
      and not (
        old.estado = 'ABIERTO'
        and (
          new.estado = 'ENVIADO'
          -- E7-D05: un detalle sin cocina pasa ABIERTO -> LISTO al enviarse.
          or (new.estado = 'LISTO' and not new.requiere_cocina)
        )
      ) then
      raise exception using
        errcode = '22000',
        message = 'El timestamp de envío solo puede fijarse al enviar un detalle abierto';
    end if;

    new.creado_por := old.creado_por;
    new.creado_en := old.creado_en;
    if new.cantidad is distinct from old.cantidad
      or new.observacion is distinct from old.observacion
      or new.estado is distinct from old.estado
      or new.pedido_id is distinct from old.pedido_id
      or new.producto_id is distinct from old.producto_id then
      new.modificado_por := v_usuario_id;
      new.modificado_en := pg_catalog.clock_timestamp();
    end if;
    v_actualiza_contenido := new.cantidad is distinct from old.cantidad
      or new.observacion is distinct from old.observacion
      or new.pedido_id is distinct from old.pedido_id
      or new.producto_id is distinct from old.producto_id;
  else
    v_actualiza_contenido := true;
  end if;

  if v_actualiza_contenido then
    update public.pedido as order_row
    set modificado_por = v_usuario_id,
        modificado_en = pg_catalog.clock_timestamp()
    where order_row.id = v_pedido_id;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$registrar_auditoria_detalle_pedido$;

comment on function public.registrar_auditoria_detalle_pedido() is
  'Mantiene la auditoría de detalle_pedido, protege sus campos de creación, valida la asignación e inmutabilidad de enviado_en (ABIERTO -> ENVIADO, o ABIERTO -> LISTO sin cocina según E7-D05) y propaga a pedido únicamente las modificaciones de contenido.';

create or replace function public.agregar_detalle_pedido(
  p_pedido_id bigint, p_producto_id uuid, p_cantidad integer, p_observacion text default null
)
returns table(detalle_id bigint,pedido_id bigint,producto_id uuid,cantidad integer,precio_unitario numeric,observacion text,estado text)
language plpgsql security definer set search_path = pg_catalog
as $add$
declare
  v_usuario_id uuid := auth.uid(); v_local_id uuid; v_rol_codigo text;
  v_pedido public.pedido%rowtype; v_mesa public.mesa%rowtype;
  v_precio public.producto.precio%type; v_requiere_cocina boolean; v_detalle_id bigint;
  v_detalle public.detalle_pedido%rowtype;
begin
  if v_usuario_id is null then raise exception using errcode='42501',message='No autorizado para agregar productos al pedido'; end if;
  select c.local_id,c.rol_codigo into v_local_id,v_rol_codigo from public.obtener_contexto_autenticado() c;
  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then raise exception using errcode='42501',message='No autorizado para agregar productos al pedido'; end if;
  if p_pedido_id is null or p_producto_id is null or p_cantidad is null or p_cantidad <= 0 then raise exception using errcode='22023',message='Pedido, producto y cantidad positiva son obligatorios'; end if;
  if p_observacion is not null and pg_catalog.btrim(p_observacion)='' then raise exception using errcode='22023',message='La observación no puede estar vacía'; end if;

  select p.* into v_pedido from public.pedido p
  where p.id=p_pedido_id and p.local_id=v_local_id
    and p.estado in ('ABIERTO','ENVIADO','RECIBIDO_COCINA','EN_PREPARACION','LISTO','ENTREGADO')
  for update;
  if not found then raise exception using errcode='42501',message='Pedido no disponible para el usuario autenticado'; end if;
  select m.* into strict v_mesa from public.mesa m
  where m.id=v_pedido.mesa_id and m.local_id=v_local_id and m.activo for update;
  if v_pedido.estado='ENTREGADO' and v_mesa.estado <> 'PENDIENTE_PAGO' then raise exception using errcode='PT409',message='La mesa cambió antes de agregar el producto'; end if;

  -- E7-D03/D04: snapshot de la condición de cocina junto con el precio vigente.
  select product_row.precio, product_row.requiere_cocina into v_precio, v_requiere_cocina
  from public.producto product_row join public.categoria c
    on c.id=product_row.categoria_id and c.local_id=product_row.local_id
  where product_row.id=p_producto_id and product_row.local_id=v_local_id and product_row.activo and c.activo;
  if not found then raise exception using errcode='42501',message='Producto no disponible para el pedido'; end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_pedido_id::text||':'||p_producto_id::text,0));
  select d.id into v_detalle_id from public.detalle_pedido d
  where d.pedido_id=p_pedido_id and d.producto_id=p_producto_id and d.estado='ABIERTO'
    and d.requiere_cocina = v_requiere_cocina
    and nullif(pg_catalog.btrim(d.observacion),'') is not distinct from nullif(pg_catalog.btrim(p_observacion),'')
  order by d.id limit 1 for update;
  if v_detalle_id is not null then
    update public.detalle_pedido d set cantidad=d.cantidad+p_cantidad
    where d.id=v_detalle_id and d.estado='ABIERTO' returning d.* into strict v_detalle;
  else
    insert into public.detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario,observacion,estado,requiere_cocina)
    values(p_pedido_id,p_producto_id,p_cantidad,v_precio,p_observacion,'ABIERTO',v_requiere_cocina) returning * into strict v_detalle;
  end if;
  perform public.sincronizar_estado_operativo_pedido(p_pedido_id,v_usuario_id);
  return query select v_detalle.id,v_detalle.pedido_id,v_detalle.producto_id,v_detalle.cantidad,v_detalle.precio_unitario,v_detalle.observacion,v_detalle.estado;
end;
$add$;

alter function public.agregar_detalle_pedido(bigint,uuid,integer,text) owner to postgres;
revoke all on function public.agregar_detalle_pedido(bigint,uuid,integer,text) from public, anon;
grant execute on function public.agregar_detalle_pedido(bigint,uuid,integer,text) to authenticated;

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
  v_lineas_cocina jsonb;
  v_numero_comanda integer;
  v_detalles_cocina integer;
  v_detalles_sin_cocina integer;
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

  -- E7-D05/D06: con cocina ABIERTO -> ENVIADO; sin cocina ABIERTO -> LISTO; mismo instante de envío.
  with enviados as (
    update public.detalle_pedido as detail_row
    set estado = 'ENVIADO', enviado_en = v_envio_detalles
    where detail_row.pedido_id = v_pedido.id
      and detail_row.estado = 'ABIERTO'
      and detail_row.requiere_cocina
    returning detail_row.id, detail_row.producto_id, detail_row.cantidad, detail_row.observacion
  )
  select
    pg_catalog.count(*)::integer,
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'detalle_id', enviados.id,
        'producto_codigo', product_row.codigo,
        'producto_nombre', product_row.nombre,
        'cantidad', enviados.cantidad,
        'observacion', enviados.observacion
      ) order by enviados.id
    )
  into v_detalles_cocina, v_lineas_cocina
  from enviados
  inner join public.producto as product_row on product_row.id = enviados.producto_id;

  update public.detalle_pedido as detail_row
  set estado = 'LISTO', enviado_en = v_envio_detalles
  where detail_row.pedido_id = v_pedido.id
    and detail_row.estado = 'ABIERTO'
    and not detail_row.requiere_cocina;
  get diagnostics v_detalles_sin_cocina = row_count;

  v_detalles_enviados := v_detalles_cocina + v_detalles_sin_cocina;

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

  -- E7-D12: una comanda por envío con al menos una línea de cocina, numerada bajo el lock del pedido.
  if v_detalles_cocina > 0 then
    select coalesce(pg_catalog.max(command_row.numero), 0) + 1
    into v_numero_comanda
    from public.comanda as command_row
    where command_row.pedido_id = v_pedido.id;

    insert into public.comanda (local_id, pedido_id, numero, enviado_en, lineas, creado_por)
    values (v_local_id, v_pedido.id, v_numero_comanda, v_envio_detalles, v_lineas_cocina, v_usuario_id);
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

alter function public.enviar_pedido_cocina(bigint) owner to postgres;
revoke all on function public.enviar_pedido_cocina(bigint) from public, anon;
grant execute on function public.enviar_pedido_cocina(bigint) to authenticated;

comment on function public.agregar_detalle_pedido(bigint,uuid,integer,text) is
  'H3/H5 alta de detalle ABIERTO con precio vigente; E7-D04 copia requiere_cocina como snapshot y consolida sólo líneas con la misma condición.';
comment on function public.enviar_pedido_cocina(bigint) is
  'H3/H4 envío atómico de detalles ABIERTO; E7-D05/D06: sin cocina pasan a LISTO, con cocina a ENVIADO, y se genera una comanda por envío con líneas de cocina.';

notify pgrst, 'reload schema';

commit;
