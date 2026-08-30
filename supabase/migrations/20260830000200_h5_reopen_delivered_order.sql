begin;

create or replace function public.sincronizar_estado_operativo_pedido(
  p_pedido_id bigint, p_usuario_id uuid
)
returns table (pedido_estado text, mesa_estado text, cabecera_actualizada boolean)
language plpgsql security definer set search_path = pg_catalog
as $sync$
declare
  v_pedido public.pedido%rowtype;
  v_mesa public.mesa%rowtype;
  v_estado_derivado text;
  v_estado_mesa text;
  v_actualizada boolean := false;
begin
  if p_pedido_id is null or p_usuario_id is null then
    raise exception using errcode = '22023', message = 'Pedido y actor son obligatorios';
  end if;

  select p.* into strict v_pedido from public.pedido p
  where p.id = p_pedido_id for update;
  select m.* into strict v_mesa from public.mesa m
  where m.id = v_pedido.mesa_id and m.local_id = v_pedido.local_id for update;

  if v_pedido.estado in ('PAGADO', 'ANULADO') then
    raise exception using errcode = '22000', message = 'Pedido terminal fuera del flujo operativo';
  end if;
  if v_pedido.estado not in (
    'ABIERTO','ENVIADO','RECIBIDO_COCINA','EN_PREPARACION','LISTO','ENTREGADO'
  ) then
    raise exception using errcode = '22000', message = 'Pedido fuera del flujo operativo de cocina';
  end if;

  select case
    when pg_catalog.bool_or(d.estado = 'ABIERTO') then 'ABIERTO'
    when pg_catalog.bool_or(d.estado = 'ENVIADO') then 'ENVIADO'
    when pg_catalog.bool_or(d.estado = 'RECIBIDO_COCINA') then 'RECIBIDO_COCINA'
    when pg_catalog.bool_or(d.estado = 'EN_PREPARACION') then 'EN_PREPARACION'
    when pg_catalog.bool_and(d.estado = 'LISTO') then 'LISTO'
    else null end
  into v_estado_derivado from public.detalle_pedido d
  where d.pedido_id = v_pedido.id;

  if v_estado_derivado is null then
    raise exception using errcode = '22000', message = 'No se puede derivar un pedido sin detalles';
  end if;

  -- Una entrega sin novedades conserva su snapshot. Solo un detalle nuevo/no LISTO
  -- vuelve a introducir el pedido en el flujo operativo.
  if v_pedido.estado = 'ENTREGADO' and v_estado_derivado = 'LISTO' then
    return query select v_pedido.estado, v_mesa.estado, false;
    return;
  end if;
  v_estado_mesa := case when v_estado_derivado = 'LISTO' then 'PEDIDO_LISTO' else 'OCUPADA' end;

  if v_mesa.estado not in ('OCUPADA','PEDIDO_LISTO','PENDIENTE_PAGO') then
    raise exception using errcode = '22000', message = 'Mesa fuera del flujo operativo de cocina';
  end if;
  if v_mesa.estado = 'PENDIENTE_PAGO' and v_pedido.estado <> 'ENTREGADO' then
    raise exception using errcode = '22000', message = 'Snapshot de pedido y mesa incoherente';
  end if;

  if v_pedido.estado is distinct from v_estado_derivado then
    update public.pedido set estado = v_estado_derivado where id = v_pedido.id;
    insert into public.historial_estado(pedido_id,estado_anterior,estado_nuevo,usuario_id)
    values(v_pedido.id,v_pedido.estado,v_estado_derivado,p_usuario_id);
    v_actualizada := true;
  end if;
  if v_mesa.estado is distinct from v_estado_mesa then
    update public.mesa set estado = v_estado_mesa where id = v_mesa.id;
  end if;
  return query select v_estado_derivado,v_estado_mesa,v_actualizada;
end;
$sync$;

alter function public.sincronizar_estado_operativo_pedido(bigint,uuid) owner to postgres;
revoke all on function public.sincronizar_estado_operativo_pedido(bigint,uuid) from public, anon, authenticated;

create or replace function public.agregar_detalle_pedido(
  p_pedido_id bigint, p_producto_id uuid, p_cantidad integer, p_observacion text default null
)
returns table(detalle_id bigint,pedido_id bigint,producto_id uuid,cantidad integer,precio_unitario numeric,observacion text,estado text)
language plpgsql security definer set search_path = pg_catalog
as $add$
declare
  v_usuario_id uuid := auth.uid(); v_local_id uuid; v_rol_codigo text;
  v_pedido public.pedido%rowtype; v_mesa public.mesa%rowtype;
  v_precio public.producto.precio%type; v_detalle_id bigint;
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
  if v_pedido.estado='ENTREGADO' and v_mesa.estado <> 'PENDIENTE_PAGO' then raise exception using errcode='40001',message='La mesa cambió antes de agregar el producto'; end if;

  select pr.precio into v_precio from public.producto pr join public.categoria c
    on c.id=pr.categoria_id and c.local_id=pr.local_id
  where pr.id=p_producto_id and pr.local_id=v_local_id and pr.activo and c.activo;
  if not found then raise exception using errcode='42501',message='Producto no disponible para el pedido'; end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_pedido_id::text||':'||p_producto_id::text,0));
  select d.id into v_detalle_id from public.detalle_pedido d
  where d.pedido_id=p_pedido_id and d.producto_id=p_producto_id and d.estado='ABIERTO'
    and nullif(pg_catalog.btrim(d.observacion),'') is not distinct from nullif(pg_catalog.btrim(p_observacion),'')
  order by d.id limit 1 for update;
  if v_detalle_id is not null then
    update public.detalle_pedido d set cantidad=d.cantidad+p_cantidad
    where d.id=v_detalle_id and d.estado='ABIERTO' returning d.* into strict v_detalle;
  else
    insert into public.detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario,observacion,estado)
    values(p_pedido_id,p_producto_id,p_cantidad,v_precio,p_observacion,'ABIERTO') returning * into strict v_detalle;
  end if;
  perform public.sincronizar_estado_operativo_pedido(p_pedido_id,v_usuario_id);
  return query select v_detalle.id,v_detalle.pedido_id,v_detalle.producto_id,v_detalle.cantidad,v_detalle.precio_unitario,v_detalle.observacion,v_detalle.estado;
end;
$add$;

alter function public.agregar_detalle_pedido(bigint,uuid,integer,text) owner to postgres;
revoke all on function public.agregar_detalle_pedido(bigint,uuid,integer,text) from public, anon;
grant execute on function public.agregar_detalle_pedido(bigint,uuid,integer,text) to authenticated;

create or replace function public.crear_o_recuperar_pedido_mesa(p_mesa_id uuid)
returns table(pedido_id bigint,pedido_estado text,creado_en timestamptz,enviado_en timestamptz,fue_creado boolean)
language plpgsql security definer set search_path=pg_catalog
as $open$
declare
 v_usuario_id uuid:=auth.uid(); v_local_id uuid; v_rol_codigo text; v_mesa_estado text; v_pedido public.pedido%rowtype;
begin
 if p_mesa_id is null or v_usuario_id is null then raise exception using errcode='42501',message='No autorizado para abrir pedidos'; end if;
 select c.local_id,c.rol_codigo into v_local_id,v_rol_codigo from public.obtener_contexto_autenticado() c;
 if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then raise exception using errcode='42501',message='No autorizado para abrir pedidos'; end if;
 select m.estado into v_mesa_estado from public.mesa m where m.id=p_mesa_id and m.local_id=v_local_id and m.activo for update;
 if not found then raise exception using errcode='42501',message='Mesa no disponible para el usuario autenticado'; end if;
 select p.* into v_pedido from public.pedido p where p.mesa_id=p_mesa_id and p.local_id=v_local_id
  and p.estado in ('ABIERTO','ENVIADO','RECIBIDO_COCINA','EN_PREPARACION','LISTO','ENTREGADO');
 if found then return query select v_pedido.id,v_pedido.estado,v_pedido.creado_en,v_pedido.enviado_en,false; return; end if;
 if v_mesa_estado<>'LIBRE' then raise exception using errcode='55000',message='La mesa no está libre y no tiene un pedido vigente recuperable'; end if;
 insert into public.pedido(local_id,mesa_id,creado_por,estado) values(v_local_id,p_mesa_id,v_usuario_id,'ABIERTO') returning * into v_pedido;
 insert into public.historial_estado(pedido_id,estado_anterior,estado_nuevo,usuario_id) values(v_pedido.id,null,'ABIERTO',v_usuario_id);
 update public.mesa set estado='OCUPADA' where id=p_mesa_id and local_id=v_local_id and activo and estado='LIBRE';
 if not found then raise exception using errcode='40001',message='La mesa cambió durante la apertura del pedido'; end if;
 return query select v_pedido.id,v_pedido.estado,v_pedido.creado_en,v_pedido.enviado_en,true;
end;
$open$;

alter function public.crear_o_recuperar_pedido_mesa(uuid) owner to postgres;
revoke all on function public.crear_o_recuperar_pedido_mesa(uuid) from public, anon;
grant execute on function public.crear_o_recuperar_pedido_mesa(uuid) to authenticated;

notify pgrst,'reload schema';
commit;
