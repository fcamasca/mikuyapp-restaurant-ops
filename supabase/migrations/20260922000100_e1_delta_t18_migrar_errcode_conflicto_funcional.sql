begin;

-- E1-T18 (correctivo post-cierre, 22/09/2026): migra la convención interna de
-- SQLSTATE usada para conflictos funcionales de aplicación. `40001`
-- (serialization_failure) le indica a PostgREST 14 que el fallo es
-- transitorio y dispara reintento automático de la transacción; las 17
-- funciones/triggers de abajo lo usaban para condiciones permanentes
-- (sesión cerrada, descuento ya decidido, pedido ya anulado/pagado, etc.),
-- no para una condición nativa de serialización de PostgreSQL (el esquema
-- no usa aislamiento SERIALIZABLE). Esta migración reemplaza únicamente la
-- versión VIGENTE de cada función/trigger, cambiando el errcode de '40001'
-- a 'PT409' (PostgREST lo mapea directamente a HTTP 409, sin reintento).
-- Ninguna regla de negocio, mensaje, firma ni migración histórica cambia.
-- Ver specs/E1-CashOperation/design.md D17.

-- 1) h3_abrir_o_recuperar_pedido(uuid) -- legado H3, sin llamador vigente en src.
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
      errcode = 'PT409',
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

-- 2) crear_o_recuperar_pedido_mesa(uuid)
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
 if not found then raise exception using errcode='PT409',message='La mesa cambió durante la apertura del pedido'; end if;
 return query select v_pedido.id,v_pedido.estado,v_pedido.creado_en,v_pedido.enviado_en,true;
end;
$open$;

-- 3) agregar_detalle_pedido(bigint,uuid,integer,text)
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
  if v_pedido.estado='ENTREGADO' and v_mesa.estado <> 'PENDIENTE_PAGO' then raise exception using errcode='PT409',message='La mesa cambió antes de agregar el producto'; end if;

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

-- 4) actualizar_estado_detalle_cocina(bigint,text,text)
create or replace function public.actualizar_estado_detalle_cocina(
  p_detalle_id bigint,
  p_estado_esperado text,
  p_estado_nuevo text
)
returns table (detalle_id bigint, estado text, modificado_en timestamptz)
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
  if p_detalle_id is null or p_estado_esperado is null
    or p_estado_nuevo is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para actualizar el estado del detalle';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;
  if v_local_id is null or v_rol_codigo is distinct from 'COCINA' then
    raise exception using errcode = '42501', message = 'No autorizado para actualizar el estado del detalle';
  end if;

  select detail_row.pedido_id into v_pedido_id
  from public.detalle_pedido as detail_row where detail_row.id = p_detalle_id;
  if not found then
    raise exception using errcode = '42501', message = 'Detalle no disponible para cocina';
  end if;

  select order_row.* into v_pedido
  from public.pedido as order_row
  where order_row.id = v_pedido_id
    and order_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
    )
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Pedido no disponible para cocina';
  end if;

  select detail_row.* into v_detalle
  from public.detalle_pedido as detail_row
  where detail_row.id = p_detalle_id and detail_row.pedido_id = v_pedido.id
  for update;
  if not found then
    raise exception using errcode = 'PT409', message = 'El detalle cambió durante la operación';
  end if;
  if v_detalle.estado is distinct from p_estado_esperado then
    raise exception using errcode = 'PT409', message = 'El detalle fue actualizado por otra sesión';
  end if;
  if not (
    (p_estado_esperado = 'ENVIADO' and p_estado_nuevo = 'RECIBIDO_COCINA')
    or (p_estado_esperado = 'RECIBIDO_COCINA' and p_estado_nuevo = 'EN_PREPARACION')
    or (p_estado_esperado = 'EN_PREPARACION' and p_estado_nuevo = 'LISTO')
  ) then
    raise exception using errcode = '22023', message = 'Transición de cocina no permitida';
  end if;

  update public.detalle_pedido as detail_row
  set estado = p_estado_nuevo
  where detail_row.id = v_detalle.id
  returning detail_row.* into v_detalle;

  perform public.sincronizar_estado_operativo_pedido(v_pedido.id, v_usuario_id);

  return query select v_detalle.id, v_detalle.estado, v_detalle.modificado_en;
end;
$actualizar_estado_detalle_cocina$;

-- 5) liberar_mesa_pedido_vacio(bigint)
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
      errcode = 'PT409',
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
      errcode = 'PT409',
      message = 'La mesa cambió durante su liberación';
  end if;

  return query
  select v_pedido.id, v_pedido.mesa_id, 'ANULADO'::text, 'LIBRE'::text;
end;
$liberar_mesa_pedido_vacio$;

-- 6) entregar_pedido(bigint)
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
    raise exception using errcode = 'PT409', message = 'El pedido ya no está listo para entregar';
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
    raise exception using errcode = 'PT409', message = 'La mesa ya no está lista para entrega';
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
    raise exception using errcode = 'PT409', message = 'El pedido cambió durante la entrega';
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
    raise exception using errcode = 'PT409', message = 'La mesa cambió durante la entrega';
  end if;

  return query
  select v_pedido.id, 'ENTREGADO'::text, v_mesa.id, 'PENDIENTE_PAGO'::text;
end;
$entregar_pedido$;

-- 7) registrar_pago_pedido(bigint,text) -- compatibilidad UI H5; deriva sesión y delega.
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
  v_actor uuid := auth.uid();
  v_local uuid;
  v_rol text;
  v_sesion_id uuid;
  v_cantidad_sesiones bigint;
begin
  select contexto.local_id, contexto.rol_codigo
  into v_local, v_rol
  from public.obtener_contexto_autenticado() as contexto;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode = '42501', message = 'No autorizado para registrar pagos';
  end if;
  if p_medio is null or p_medio not in ('EFECTIVO', 'YAPE', 'PLIN', 'TARJETA') then
    raise exception using errcode = '22023', message = 'Medio de pago inválido';
  end if;
  if not exists (
    select 1 from public.pedido as pedido
    where pedido.id = p_pedido_id and pedido.local_id = v_local
  ) then
    raise exception using errcode = '42501', message = 'Pedido no disponible para el usuario autenticado';
  end if;

  select sesion.id
  into v_sesion_id
  from public.sesion_caja as sesion
  inner join public.caja as caja
    on caja.id = sesion.caja_id and caja.local_id = sesion.local_id
  where sesion.local_id = v_local and sesion.estado = 'ABIERTA' and caja.activo
  order by sesion.abierta_en, sesion.id
  limit 1;

  if v_sesion_id is null then
    raise exception using errcode = 'PT409', message = 'Debe abrir una sesión de caja antes de cobrar';
  end if;

  select pg_catalog.count(*)
  into v_cantidad_sesiones
  from public.sesion_caja as sesion
  inner join public.caja as caja
    on caja.id = sesion.caja_id and caja.local_id = sesion.local_id
  where sesion.local_id = v_local and sesion.estado = 'ABIERTA' and caja.activo;
  if v_cantidad_sesiones > 1 then
    raise exception using errcode = '22023', message = 'Seleccione explícitamente la sesión de caja para cobrar';
  end if;

  return query
  select resultado.pago_id, resultado.pedido_id, resultado.pedido_estado,
    resultado.mesa_id, resultado.mesa_estado, resultado.importe,
    resultado.medio, resultado.pagado_en
  from public.rpc_registrar_pago_total_pedido(
    p_pedido_id, v_sesion_id, p_medio, 0, gen_random_uuid()
  ) as resultado;
end;
$registrar_pago_pedido$;

-- 8) rpc_abrir_sesion_caja(uuid,numeric,uuid)
create or replace function public.rpc_abrir_sesion_caja(
  p_caja_id uuid, p_monto_inicial numeric, p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare
  v_actor uuid := auth.uid();
  v_local uuid;
  v_rol text;
  v_sesion public.sesion_caja%rowtype;
  v_solicitud public.solicitud_apertura_caja%rowtype;
  v_creada boolean := false;
  v_constraint text;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  if p_idempotency_key is null or p_monto_inicial is null
    or p_monto_inicial < 0 or p_monto_inicial >= 1000000000000
    or p_monto_inicial <> pg_catalog.round(p_monto_inicial, 2) then
    -- NaN compara mayor que cualquier número; Infinity también se rechaza.
    raise exception using errcode = '22023', message = 'Monto inicial o clave de solicitud inválidos';
  end if;
  -- Orden caja -> sesión. Una segunda RPC espera y después lee el commit ganador.
  perform 1 from public.caja c
    where c.id = p_caja_id and c.local_id = v_local and c.activo for update;
  if not found then
    raise exception using errcode = '42501', message = 'Caja no disponible';
  end if;
  select r.* into v_solicitud from public.solicitud_apertura_caja r
    where r.caja_id = p_caja_id and r.actor_id = v_actor and r.idempotency_key = p_idempotency_key;
  if found then
    if v_solicitud.monto_solicitado <> p_monto_inicial then
      raise exception using errcode = '22023', message = 'Clave de solicitud reutilizada con otro monto';
    end if;
    select s.* into strict v_sesion from public.sesion_caja s where s.id = v_solicitud.sesion_caja_id;
    -- Si cerró después, informa CERRADA: no reabre ni crea otra sesión en un retry.
    return pg_catalog.to_jsonb(v_sesion) - 'idempotency_key';
  end if;

  -- Compatibilidad con una apertura persistida bajo el modelo T03 sin registro
  -- de solicitud T04. No fabrica auditoría retroactiva ni vuelve a abrirla.
  select s.* into v_sesion from public.sesion_caja s
    where s.caja_id = p_caja_id and s.abierta_por = v_actor and s.idempotency_key = p_idempotency_key;
  if found then
    if v_sesion.monto_inicial <> p_monto_inicial then
      raise exception using errcode = '22023', message = 'Clave de solicitud reutilizada con otro monto';
    end if;
    insert into public.solicitud_apertura_caja
      (caja_id, local_id, actor_id, idempotency_key, monto_solicitado, sesion_caja_id)
      values (p_caja_id, v_local, v_actor, p_idempotency_key, p_monto_inicial, v_sesion.id);
    return pg_catalog.to_jsonb(v_sesion) - 'idempotency_key';
  end if;

  select s.* into v_sesion from public.sesion_caja s
    where s.caja_id = p_caja_id and s.local_id = v_local and s.estado = 'ABIERTA' for update;
  if not found then
    begin
      insert into public.sesion_caja (caja_id, local_id, abierta_por, monto_inicial, idempotency_key)
        values (p_caja_id, v_local, v_actor, p_monto_inicial, p_idempotency_key)
        returning * into v_sesion;
      v_creada := true;
    exception when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint <> 'uq_sesion_caja_abierta' then raise; end if;
      -- Defensa ante otro escritor que alcanzó el índice sin el lock de caja.
      -- Nueva sentencia, snapshot fresco bajo READ COMMITTED; no filtra 23505 normal.
      select s.* into v_sesion from public.sesion_caja s
        where s.caja_id = p_caja_id and s.local_id = v_local and s.estado = 'ABIERTA' for update;
      if not found then
        raise exception using errcode = 'PT409', message = 'La sesión cambió; reintente la solicitud';
      end if;
    end;
  end if;

  if v_creada then
    insert into public.auditoria_caja (tipo, local_id, caja_id, sesion_caja_id,
      actor_id, creado_en, monto_inicial, estado_anterior, estado_nuevo)
    values ('APERTURA', v_local, p_caja_id, v_sesion.id, v_actor,
      v_sesion.abierta_en, v_sesion.monto_inicial, null, 'ABIERTA');
  end if;
  insert into public.solicitud_apertura_caja
    (caja_id, local_id, actor_id, idempotency_key, monto_solicitado, sesion_caja_id)
    values (p_caja_id, v_local, v_actor, p_idempotency_key, p_monto_inicial, v_sesion.id);
  return pg_catalog.to_jsonb(v_sesion) - 'idempotency_key';
end;
$$;

-- 9) rpc_obtener_sesion_caja_activa(uuid,uuid)
create or replace function public.rpc_obtener_sesion_caja_activa(p_caja_id uuid, p_sesion_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog as $$
declare v_local uuid; v_rol text; v_sesion public.sesion_caja%rowtype;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol from public.obtener_contexto_autenticado() c;
  if auth.uid() is null or v_local is null or v_rol is null or v_rol not in ('CAJA', 'ADMINISTRADOR') then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  perform 1 from public.caja c where c.id = p_caja_id and c.local_id = v_local and c.activo;
  if not found then raise exception using errcode = '42501', message = 'Caja no disponible'; end if;
  select s.* into v_sesion from public.sesion_caja s
    where s.caja_id = p_caja_id and s.local_id = v_local and s.estado = 'ABIERTA';
  if p_sesion_id is not null and (v_sesion.id is null or v_sesion.id <> p_sesion_id) then
    raise exception using errcode = 'PT409', message = 'Sesión activa no disponible para la caja seleccionada';
  end if;
  if v_sesion.id is null then return null; end if;
  return pg_catalog.to_jsonb(v_sesion) - 'idempotency_key';
end;
$$;

-- 10) rpc_registrar_movimiento_caja(uuid,text,numeric,text,uuid)
create or replace function public.rpc_registrar_movimiento_caja(
  p_sesion_caja_id uuid, p_tipo text, p_importe numeric,
  p_motivo text, p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare
  v_actor uuid := auth.uid(); v_local uuid; v_rol text; v_caja_id uuid;
  v_sesion public.sesion_caja%rowtype; v_movimiento public.movimiento_caja%rowtype;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode = '42501', message = 'No autorizado para registrar movimientos';
  end if;
  if p_sesion_caja_id is null or p_idempotency_key is null
    or p_tipo is null or p_tipo not in ('ENTRADA', 'SALIDA')
    or p_importe is null or p_importe <= 0 or p_importe >= 1000000000000
    or p_importe <> pg_catalog.round(p_importe, 2)
    or p_motivo is null or pg_catalog.btrim(p_motivo) = '' then
    raise exception using errcode = '22023', message = 'Movimiento inválido';
  end if;
  select s.caja_id into v_caja_id from public.sesion_caja s
    where s.id = p_sesion_caja_id and s.local_id = v_local;
  if v_caja_id is null then
    raise exception using errcode = '42501', message = 'Sesión no disponible';
  end if;
  perform 1 from public.caja c
    where c.id = v_caja_id and c.local_id = v_local and c.activo for update;
  if not found then raise exception using errcode = '42501', message = 'Caja no disponible'; end if;
  select s.* into strict v_sesion from public.sesion_caja s
    where s.id = p_sesion_caja_id and s.caja_id = v_caja_id and s.local_id = v_local for update;
  select m.* into v_movimiento from public.movimiento_caja m
    where m.sesion_caja_id = v_sesion.id and m.actor_id = v_actor
      and m.idempotency_key = p_idempotency_key;
  if found then
    if v_movimiento.tipo <> p_tipo or v_movimiento.importe <> p_importe
      or v_movimiento.motivo <> pg_catalog.btrim(p_motivo) then
      raise exception using errcode = '22023', message = 'Clave de solicitud reutilizada con otros datos';
    end if;
    return pg_catalog.to_jsonb(v_movimiento) - 'idempotency_key';
  end if;
  if v_sesion.estado is distinct from 'ABIERTA' then
    raise exception using errcode = 'PT409', message = 'La sesión de caja ya no está abierta';
  end if;
  insert into public.movimiento_caja
    (sesion_caja_id, caja_id, local_id, tipo, importe, motivo, actor_id, idempotency_key)
  values (v_sesion.id, v_sesion.caja_id, v_sesion.local_id, p_tipo, p_importe,
    pg_catalog.btrim(p_motivo), v_actor, p_idempotency_key)
  returning * into v_movimiento;
  insert into public.auditoria_caja
    (tipo, local_id, caja_id, sesion_caja_id, actor_id, creado_en,
      monto_inicial, estado_anterior, estado_nuevo, movimiento_caja_id,
      importe, tipo_movimiento, motivo)
  values (p_tipo, v_local, v_sesion.caja_id, v_sesion.id, v_actor,
    v_movimiento.creado_en, null, 'ABIERTA', 'ABIERTA', v_movimiento.id,
    v_movimiento.importe, v_movimiento.tipo, v_movimiento.motivo);
  return pg_catalog.to_jsonb(v_movimiento) - 'idempotency_key';
end;
$$;

-- 11) fn_cerrar_sesion_caja(uuid,numeric,text,uuid,boolean)
create or replace function public.fn_cerrar_sesion_caja(
  p_sesion_caja_id uuid, p_efectivo_contado numeric,
  p_motivo text, p_idempotency_key uuid, p_supervisor boolean
)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare
  v_actor uuid := auth.uid(); v_local uuid; v_rol text; v_caja_id uuid;
  v_sesion public.sesion_caja%rowtype; v_solicitud public.solicitud_cierre_caja%rowtype;
  v_totales record; v_esperado numeric(14,2); v_diferencia numeric(14,2);
  v_tipo text := case when p_supervisor then 'SUPERVISOR' else 'NORMAL' end;
  v_evento text := case when p_supervisor then 'CIERRE_SUPERVISOR' else 'CIERRE' end;
  v_motivo text := nullif(pg_catalog.btrim(p_motivo), ''); v_cerrada_en timestamptz;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null
    or (not p_supervisor and v_rol is distinct from 'CAJA')
    or (p_supervisor and v_rol is distinct from 'ADMINISTRADOR') then
    raise exception using errcode = '42501', message = 'No autorizado para cerrar la sesión';
  end if;
  if p_sesion_caja_id is null or p_idempotency_key is null
    or p_efectivo_contado is null or p_efectivo_contado < 0
    or p_efectivo_contado >= 1000000000000
    or p_efectivo_contado <> pg_catalog.round(p_efectivo_contado, 2)
    or (p_supervisor and v_motivo is null) then
    raise exception using errcode = '22023', message = 'Datos de cierre inválidos';
  end if;
  select s.caja_id into v_caja_id from public.sesion_caja s
    where s.id = p_sesion_caja_id and s.local_id = v_local;
  if v_caja_id is null then raise exception using errcode = '42501', message = 'Sesión no disponible'; end if;
  perform 1 from public.caja c
    where c.id = v_caja_id and c.local_id = v_local and c.activo for update;
  if not found then raise exception using errcode = '42501', message = 'Caja no disponible'; end if;
  select s.* into strict v_sesion from public.sesion_caja s
    where s.id = p_sesion_caja_id and s.caja_id = v_caja_id and s.local_id = v_local for update;
  select r.* into v_solicitud from public.solicitud_cierre_caja r
    where r.sesion_caja_id = v_sesion.id and r.actor_id = v_actor
      and r.idempotency_key = p_idempotency_key;
  if found then
    if v_solicitud.efectivo_contado <> p_efectivo_contado
      or v_solicitud.motivo is distinct from v_motivo or v_solicitud.tipo_cierre <> v_tipo then
      raise exception using errcode = '22023', message = 'Clave de cierre reutilizada con otros datos';
    end if;
    return (select pg_catalog.to_jsonb(r) from public.resumen_cierre_sesion_caja r
      where r.sesion_caja_id = v_sesion.id);
  end if;
  if v_sesion.estado is distinct from 'ABIERTA' then
    raise exception using errcode = 'PT409', message = 'La sesión de caja ya está cerrada';
  end if;
  select * into strict v_totales from public.fn_totales_sesion_caja(v_sesion.id);
  v_esperado := v_sesion.monto_inicial + v_totales.pago_efectivo
    + v_totales.propina_efectivo + v_totales.entradas - v_totales.salidas;
  v_diferencia := p_efectivo_contado - v_esperado;
  if v_diferencia <> 0 and v_motivo is null then
    raise exception using errcode = '22023', message = 'El motivo es obligatorio cuando existe diferencia';
  end if;
  v_cerrada_en := pg_catalog.clock_timestamp();
  insert into public.resumen_cierre_sesion_caja values (
    v_sesion.id, v_sesion.caja_id, v_local, v_actor, v_cerrada_en, v_tipo,
    v_totales.pago_efectivo, v_totales.propina_efectivo,
    v_totales.pago_yape, v_totales.propina_yape,
    v_totales.pago_plin, v_totales.propina_plin,
    v_totales.pago_tarjeta, v_totales.propina_tarjeta,
    v_totales.entradas, v_totales.salidas, v_esperado,
    p_efectivo_contado, v_diferencia, v_motivo
  );
  update public.sesion_caja s set estado = 'CERRADA', cerrada_por = v_actor,
    cerrada_en = v_cerrada_en, efectivo_esperado = v_esperado,
    efectivo_contado = p_efectivo_contado, diferencia = v_diferencia,
    motivo_diferencia = v_motivo where s.id = v_sesion.id;
  insert into public.auditoria_caja
    (tipo, local_id, caja_id, sesion_caja_id, actor_id, creado_en,
      monto_inicial, estado_anterior, estado_nuevo, efectivo_esperado,
      efectivo_contado, diferencia, motivo)
  values (v_evento, v_local, v_sesion.caja_id, v_sesion.id, v_actor,
    v_cerrada_en, null, 'ABIERTA', 'CERRADA', v_esperado,
    p_efectivo_contado, v_diferencia, v_motivo);
  insert into public.solicitud_cierre_caja
    (sesion_caja_id, actor_id, idempotency_key, efectivo_contado, motivo, tipo_cierre, creado_en)
  values (v_sesion.id, v_actor, p_idempotency_key, p_efectivo_contado,
    v_motivo, v_tipo, v_cerrada_en);
  return (select pg_catalog.to_jsonb(r) from public.resumen_cierre_sesion_caja r
    where r.sesion_caja_id = v_sesion.id);
end;
$$;

-- 12) rpc_solicitar_descuento_pedido(bigint,numeric,numeric,text,uuid)
create or replace function public.rpc_solicitar_descuento_pedido(
  p_pedido_id bigint,p_importe numeric,p_porcentaje numeric,p_motivo text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare
  v_actor uuid:=auth.uid();v_local uuid;v_rol text;v_pedido public.pedido%rowtype;
  v_descuento public.descuento_pedido%rowtype;v_tipo text;v_valor numeric;v_subtotal numeric;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode='42501',message='No autorizado para solicitar descuentos';
  end if;
  if p_pedido_id is null or p_idempotency_key is null or p_motivo is null or btrim(p_motivo)=''
    or (p_importe is null)=(p_porcentaje is null) then
    raise exception using errcode='22023',message='Solicitud de descuento inválida';
  end if;
  v_tipo:=case when p_importe is not null then 'IMPORTE' else 'PORCENTAJE' end;
  v_valor:=coalesce(p_importe,p_porcentaje);
  if v_valor<=0 or v_valor='NaN'::numeric or v_valor>=1000000000000
    or (v_tipo='IMPORTE' and v_valor<>round(v_valor,2))
    or (v_tipo='PORCENTAJE' and (v_valor>100 or v_valor<>round(v_valor,4))) then
    raise exception using errcode='22023',message='Valor de descuento inválido';
  end if;
  select p.* into v_pedido from public.pedido p
    where p.id=p_pedido_id and p.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Pedido no disponible';end if;
  select d.* into v_descuento from public.descuento_pedido d where d.pedido_id=v_pedido.id for update;
  if found then
    if v_descuento.solicitado_por=v_actor and v_descuento.solicitud_idempotency_key=p_idempotency_key
      and v_descuento.tipo=v_tipo and v_descuento.valor_solicitado=v_valor
      and v_descuento.motivo=btrim(p_motivo) then
      return to_jsonb(v_descuento)-'solicitud_idempotency_key'-'decision_idempotency_key';
    end if;
    raise exception using errcode='PT409',message='El pedido ya tiene una solicitud de descuento';
  end if;
  if v_pedido.estado is distinct from 'ENTREGADO' or exists(select 1 from public.pago p where p.pedido_id=v_pedido.id) then
    raise exception using errcode='PT409',message='El pedido no admite descuento';
  end if;
  select r.subtotal into v_subtotal from public.fn_resolver_total_pedido(v_pedido.id) r;
  if v_subtotal<=0 or (v_tipo='IMPORTE' and v_valor>v_subtotal) then
    raise exception using errcode='22023',message='El descuento excede el subtotal';
  end if;
  insert into public.descuento_pedido(pedido_id,local_id,tipo,valor_solicitado,motivo,
    solicitado_por,solicitud_idempotency_key)
  values(v_pedido.id,v_local,v_tipo,v_valor,btrim(p_motivo),v_actor,p_idempotency_key)
  returning * into v_descuento;
  insert into public.auditoria_caja(tipo,local_id,caja_id,sesion_caja_id,actor_id,creado_en,
    monto_inicial,estado_anterior,estado_nuevo,pedido_id,descuento_pedido_id,solicitante_id,
    tipo_descuento,valor_solicitado,motivo)
  values('SOLICITUD_DESCUENTO',v_local,null,null,v_actor,v_descuento.solicitado_en,
    null,null,'PENDIENTE',v_pedido.id,v_descuento.id,v_actor,v_tipo,v_valor,v_descuento.motivo
  );
  return to_jsonb(v_descuento)-'solicitud_idempotency_key'-'decision_idempotency_key';
end $$;

-- 13) rpc_decidir_descuento_pedido(bigint,text,text,uuid)
create or replace function public.rpc_decidir_descuento_pedido(
  p_pedido_id bigint,p_decision text,p_motivo_decision text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare
  v_actor uuid:=auth.uid();v_local uuid;v_rol text;v_pedido public.pedido%rowtype;
  v_descuento public.descuento_pedido%rowtype;v_subtotal numeric;v_aplicado numeric;v_neto numeric;
  v_estado text;v_evento text;v_motivo text:=nullif(btrim(p_motivo_decision),'');
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then
    raise exception using errcode='42501',message='No autorizado para decidir descuentos';
  end if;
  if p_pedido_id is null or p_idempotency_key is null or p_decision not in ('AUTORIZAR','RECHAZAR')
    or (p_decision='RECHAZAR' and v_motivo is null) then
    raise exception using errcode='22023',message='Decisión de descuento inválida';
  end if;
  v_estado:=case when p_decision='AUTORIZAR' then 'AUTORIZADO' else 'RECHAZADO' end;
  v_evento:=case when p_decision='AUTORIZAR' then 'AUTORIZACION_DESCUENTO' else 'RECHAZO_DESCUENTO' end;
  select p.* into v_pedido from public.pedido p
    where p.id=p_pedido_id and p.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Pedido no disponible';end if;
  select d.* into v_descuento from public.descuento_pedido d
    where d.pedido_id=v_pedido.id and d.local_id=v_local for update;
  if not found then raise exception using errcode='PT409',message='No existe solicitud de descuento';end if;
  if v_descuento.estado<>'PENDIENTE' then
    if v_descuento.estado=v_estado and v_descuento.decidido_por=v_actor
      and v_descuento.decision_idempotency_key=p_idempotency_key
      and v_descuento.motivo_decision is not distinct from v_motivo then
      return to_jsonb(v_descuento)-'solicitud_idempotency_key'-'decision_idempotency_key';
    end if;
    raise exception using errcode='PT409',message='La solicitud ya fue decidida';
  end if;
  if v_pedido.estado is distinct from 'ENTREGADO' or exists(select 1 from public.pago p where p.pedido_id=v_pedido.id) then
    raise exception using errcode='PT409',message='El pedido ya no admite descuento';
  end if;
  if p_decision='AUTORIZAR' then
    select r.subtotal into v_subtotal from public.fn_resolver_total_pedido(v_pedido.id) r;
    v_aplicado:=case when v_descuento.tipo='IMPORTE' then v_descuento.valor_solicitado
      else round(v_subtotal*v_descuento.valor_solicitado/100,2) end;
    if v_subtotal<=0 or v_aplicado<=0 or v_aplicado>v_subtotal then
      raise exception using errcode='22023',message='El descuento excede el subtotal';
    end if;
    v_neto:=v_subtotal-v_aplicado;
  end if;
  update public.descuento_pedido d set estado=v_estado,decidido_por=v_actor,
    decidido_en=clock_timestamp(),decision_idempotency_key=p_idempotency_key,
    motivo_decision=v_motivo,subtotal_base=v_subtotal,importe_aplicado=v_aplicado,total_neto=v_neto
  where d.id=v_descuento.id returning * into v_descuento;
  insert into public.auditoria_caja(tipo,local_id,caja_id,sesion_caja_id,actor_id,creado_en,
    monto_inicial,estado_anterior,estado_nuevo,pedido_id,descuento_pedido_id,solicitante_id,
    autorizador_id,tipo_descuento,valor_solicitado,subtotal,descuento,total_neto,motivo)
  values(v_evento,v_local,null,null,v_actor,v_descuento.decidido_en,null,'PENDIENTE',v_estado,
    v_pedido.id,v_descuento.id,v_descuento.solicitado_por,v_actor,v_descuento.tipo,
    v_descuento.valor_solicitado,v_subtotal,v_aplicado,v_neto,
    case when p_decision='RECHAZAR' then v_motivo else null end
  );
  return to_jsonb(v_descuento)-'solicitud_idempotency_key'-'decision_idempotency_key';
end $$;

-- 14) anular_pedido_supervisado(bigint,text,uuid)
create or replace function public.anular_pedido_supervisado(
  p_pedido_id bigint,p_motivo text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare
  v_actor uuid:=auth.uid();v_local uuid;v_rol text;v_pedido public.pedido%rowtype;
  v_mesa public.mesa%rowtype;v_anulacion public.anulacion_pedido%rowtype;
  v_motivo text:=nullif(btrim(p_motivo),'');v_anulado_en timestamptz;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then
    raise exception using errcode='42501',message='No autorizado para anular pedidos';
  end if;
  if p_pedido_id is null or p_idempotency_key is null or v_motivo is null then
    raise exception using errcode='22023',message='Pedido, motivo y clave son obligatorios';
  end if;
  -- Orden T07: pedido -> mesa. No necesita ni bloquea sesión de caja.
  select p.* into v_pedido from public.pedido p
    where p.id=p_pedido_id and p.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Pedido no disponible';end if;
  select m.* into v_mesa from public.mesa m
    where m.id=v_pedido.mesa_id and m.local_id=v_local and m.activo for update;
  if not found then raise exception using errcode='42501',message='Mesa no disponible';end if;
  select a.* into v_anulacion from public.anulacion_pedido a where a.pedido_id=v_pedido.id;
  if found then
    if v_anulacion.actor_id=v_actor and v_anulacion.idempotency_key=p_idempotency_key
      and v_anulacion.motivo=v_motivo then return to_jsonb(v_anulacion)-'idempotency_key';end if;
    raise exception using errcode='PT409',message='El pedido ya fue anulado';
  end if;
  if exists(select 1 from public.pago p where p.pedido_id=v_pedido.id) then
    raise exception using errcode='PT409',message='Un pedido con pagos no puede anularse';
  end if;
  if v_pedido.estado not in ('ABIERTO','ENVIADO','RECIBIDO_COCINA','EN_PREPARACION','LISTO','ENTREGADO') then
    raise exception using errcode='PT409',message='El estado del pedido no admite anulación';
  end if;
  v_anulado_en:=clock_timestamp();
  update public.pedido p set estado='ANULADO' where p.id=v_pedido.id and p.estado=v_pedido.estado;
  if not found then raise exception using errcode='PT409',message='El pedido cambió durante la anulación';end if;
  update public.mesa m set estado='LIBRE' where m.id=v_mesa.id and m.local_id=v_local;
  if not found then raise exception using errcode='PT409',message='La mesa cambió durante la anulación';end if;
  insert into public.historial_estado(pedido_id,estado_anterior,estado_nuevo,usuario_id,creado_en)
  values(v_pedido.id,v_pedido.estado,'ANULADO',v_actor,v_anulado_en);
  insert into public.anulacion_pedido(pedido_id,local_id,mesa_id,actor_id,motivo,
    estado_anterior,estado_nuevo,mesa_estado_anterior,mesa_estado_nuevo,anulado_en,idempotency_key)
  values(v_pedido.id,v_local,v_mesa.id,v_actor,v_motivo,v_pedido.estado,'ANULADO',
    v_mesa.estado,'LIBRE',v_anulado_en,p_idempotency_key) returning * into v_anulacion;
  insert into public.auditoria_caja(tipo,local_id,caja_id,sesion_caja_id,actor_id,creado_en,
    monto_inicial,estado_anterior,estado_nuevo,pedido_id,anulacion_pedido_id,motivo,
    mesa_estado_anterior,mesa_estado_nuevo)
  values('ANULACION',v_local,null,null,v_actor,v_anulado_en,null,v_pedido.estado,'ANULADO',
    v_pedido.id,v_anulacion.id,v_motivo,v_mesa.estado,'LIBRE');
  return to_jsonb(v_anulacion)-'idempotency_key';
end $$;

-- 15) tgf_bloquear_detalle_pedido_con_pago() -- función de trigger
create or replace function public.tgf_bloquear_detalle_pedido_con_pago()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
declare v_pedido_id bigint:=coalesce(new.pedido_id,old.pedido_id);
begin
  if exists(select 1 from public.pago p where p.pedido_id=v_pedido_id) then
    raise exception using errcode='PT409',message='Un pedido con pagos no admite mutaciones';
  end if;
  return coalesce(new,old);
end $$;

-- 16) rpc_registrar_cobro_pedido(bigint,uuid,text,jsonb,uuid)
create or replace function public.rpc_registrar_cobro_pedido(
  p_pedido_id bigint,p_sesion_caja_id uuid,p_tipo_cobro text,
  p_medios jsonb,p_idempotency_key uuid
)
returns table(
  cobro_id uuid,pedido_id bigint,pedido_estado text,mesa_id uuid,mesa_estado text,
  tipo_cobro text,total_aplicado numeric,propina_total numeric,sesion_caja_id uuid,
  cobrado_en timestamptz,subtotal numeric,descuento numeric,total_neto numeric,
  ya_pagado numeric,saldo_anterior numeric,saldo_posterior numeric,medios jsonb
)
language plpgsql security definer set search_path=pg_catalog as $$
declare
  v_actor uuid:=auth.uid();v_local uuid;v_rol text;v_sesion public.sesion_caja%rowtype;
  v_pedido public.pedido%rowtype;v_mesa public.mesa%rowtype;v_cobro public.cobro%rowtype;
  v_subtotal numeric;v_descuento numeric;v_neto numeric;v_pagado numeric;v_saldo numeric;
  v_total numeric:=0;v_propina_total numeric:=0;v_item jsonb;v_medio text;v_importe numeric;
  v_propina numeric;v_orden int:=0;v_medios_normalizados jsonb:='[]'::jsonb;
  v_medios_solicitados jsonb;v_primer_pago public.pago%rowtype;
  v_estado_pedido text;v_estado_mesa text;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode='42501',message='No autorizado para registrar cobros';
  end if;
  if p_pedido_id is null or p_sesion_caja_id is null or p_idempotency_key is null
    or p_tipo_cobro not in('TOTAL','PARCIAL') then
    raise exception using errcode='22023',message='Pedido, sesión, tipo y clave son obligatorios';
  end if;
  if p_medios is null or jsonb_typeof(p_medios)<>'array' or jsonb_array_length(p_medios)<1
    or jsonb_array_length(p_medios)>20 then
    raise exception using errcode='22023',message='La lista de medios es inválida';
  end if;

  -- Orden definitivo: sesión -> pedido -> mesa.
  select s.* into v_sesion from public.sesion_caja s
    where s.id=p_sesion_caja_id and s.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Sesión no disponible';end if;

  select c.* into v_cobro from public.cobro c
    where c.sesion_caja_id=v_sesion.id and c.actor_id=v_actor and c.idempotency_key=p_idempotency_key;
  if found then
    begin
      select jsonb_agg(jsonb_build_object('medio',x.value->>'medio','importe',(x.value->>'importe')::numeric,
        'propina',coalesce((x.value->>'propina')::numeric,0)) order by x.ord)
      into v_medios_solicitados from jsonb_array_elements(p_medios) with ordinality x(value,ord);
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception using errcode='22023',message='Clave reutilizada con otros datos';
    end;
    select coalesce(jsonb_agg(jsonb_build_object('pago_id',p.id,'orden',p.orden,'medio',p.medio,'importe',p.importe,'propina',p.propina) order by p.orden),'[]'::jsonb)
      into v_medios_normalizados from public.pago p where p.cobro_id=v_cobro.id;
    if v_cobro.pedido_id<>p_pedido_id or v_cobro.tipo<>p_tipo_cobro or v_medios_solicitados <>
      (select jsonb_agg(jsonb_build_object('medio',x->>'medio','importe',(x->>'importe')::numeric,
        'propina',(x->>'propina')::numeric) order by (x->>'orden')::int) from jsonb_array_elements(v_medios_normalizados)x) then
      raise exception using errcode='22023',message='Clave reutilizada con otros datos';
    end if;
    select p.* into strict v_pedido from public.pedido p where p.id=v_cobro.pedido_id;
    select m.* into strict v_mesa from public.mesa m where m.id=v_pedido.mesa_id;
    select r.subtotal,r.descuento,r.total_neto into v_subtotal,v_descuento,v_neto from public.fn_resolver_total_pedido(v_pedido.id)r;
    return query select v_cobro.id,v_cobro.pedido_id,v_pedido.estado,v_mesa.id,v_mesa.estado,v_cobro.tipo,
      v_cobro.total_aplicado,v_cobro.propina_total,v_cobro.sesion_caja_id,v_cobro.cobrado_en,
      v_subtotal,v_descuento,v_neto,v_neto-v_cobro.saldo_posterior,v_cobro.saldo_anterior,v_cobro.saldo_posterior,v_medios_normalizados;
    return;
  end if;

  if v_sesion.estado<>'ABIERTA' then raise exception using errcode='PT409',message='La sesión ya no está abierta';end if;
  if not exists(select 1 from public.caja c where c.id=v_sesion.caja_id and c.local_id=v_local and c.activo) then
    raise exception using errcode='42501',message='Caja no disponible';
  end if;
  select p.* into v_pedido from public.pedido p where p.id=p_pedido_id and p.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Pedido no disponible';end if;
  select m.* into v_mesa from public.mesa m where m.id=v_pedido.mesa_id and m.local_id=v_local and m.activo for update;
  if not found then raise exception using errcode='42501',message='Mesa no disponible';end if;
  if v_pedido.estado<>'ENTREGADO' or v_mesa.estado<>'PENDIENTE_PAGO'
    or exists(select 1 from public.anulacion_pedido a where a.pedido_id=v_pedido.id) then
    raise exception using errcode='PT409',message='Pedido no disponible para cobro';
  end if;
  select r.subtotal,r.descuento,r.total_neto into v_subtotal,v_descuento,v_neto from public.fn_resolver_total_pedido(v_pedido.id)r;
  select coalesce(sum(p.importe),0) into v_pagado from public.pago p where p.pedido_id=v_pedido.id;
  v_saldo:=v_neto-v_pagado;
  if v_saldo<=0 then raise exception using errcode='PT409',message='El pedido ya no tiene saldo';end if;

  for v_item in select value from jsonb_array_elements(p_medios) loop
    if jsonb_typeof(v_item)<>'object' or (v_item-'medio'-'importe'-'propina')<>'{}'::jsonb then
      raise exception using errcode='22023',message='Línea de medio inválida';
    end if;
    begin
      v_medio:=v_item->>'medio';v_importe:=(v_item->>'importe')::numeric;
      v_propina:=coalesce((v_item->>'propina')::numeric,0);
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception using errcode='22023',message='Importe o propina inválidos';
    end;
    if v_medio not in('EFECTIVO','YAPE','PLIN','TARJETA') or v_importe is null or v_importe<=0
      or v_importe='NaN'::numeric or v_importe>=1000000000000 or v_importe<>round(v_importe,2)
      or v_propina<0 or v_propina='NaN'::numeric or v_propina>=100000000 or v_propina<>round(v_propina,2) then
      raise exception using errcode='22023',message='Medio, importe o propina inválidos';
    end if;
    v_total:=v_total+v_importe;v_propina_total:=v_propina_total+v_propina;
    v_medios_normalizados:=v_medios_normalizados||jsonb_build_array(jsonb_build_object(
      'orden',v_orden+1,'medio',v_medio,'importe',v_importe,'propina',v_propina));
    v_orden:=v_orden+1;
  end loop;
  if (p_tipo_cobro='TOTAL' and v_total<>v_saldo)
    or (p_tipo_cobro='PARCIAL' and (v_total<=0 or v_total>=v_saldo)) then
    raise exception using errcode='22023',message='La suma de medios no coincide con el tipo y saldo del cobro';
  end if;

  insert into public.cobro(pedido_id,sesion_caja_id,local_id,actor_id,tipo,total_aplicado,propina_total,
    saldo_anterior,saldo_posterior,idempotency_key)
  values(v_pedido.id,v_sesion.id,v_local,v_actor,p_tipo_cobro,v_total,v_propina_total,v_saldo,v_saldo-v_total,p_idempotency_key)
  returning * into v_cobro;
  v_orden:=0;v_medios_normalizados:='[]'::jsonb;
  for v_item in select value from jsonb_array_elements(p_medios) loop
    v_orden:=v_orden+1;v_medio:=v_item->>'medio';v_importe:=(v_item->>'importe')::numeric;v_propina:=coalesce((v_item->>'propina')::numeric,0);
    insert into public.pago(pedido_id,importe,medio,usuario_id,sesion_caja_id,propina,idempotency_key,cobro_id,orden)
    values(v_pedido.id,v_importe,v_medio,v_actor,v_sesion.id,v_propina,
      md5(v_cobro.id::text||':'||v_orden::text)::uuid,v_cobro.id,v_orden)
    returning * into v_primer_pago;
    v_medios_normalizados:=v_medios_normalizados||jsonb_build_array(jsonb_build_object(
      'pago_id',v_primer_pago.id,'orden',v_orden,'medio',v_medio,'importe',v_importe,'propina',v_propina));
  end loop;
  v_estado_pedido:='ENTREGADO';v_estado_mesa:='PENDIENTE_PAGO';
  if v_cobro.saldo_posterior=0 then
    update public.pedido set estado='PAGADO' where id=v_pedido.id;
    insert into public.historial_estado(pedido_id,estado_anterior,estado_nuevo,usuario_id)
      values(v_pedido.id,'ENTREGADO','PAGADO',v_actor);
    update public.mesa set estado='LIBRE' where id=v_mesa.id;
    v_estado_pedido:='PAGADO';v_estado_mesa:='LIBRE';
  end if;
  select p.* into v_primer_pago from public.pago p where p.cobro_id=v_cobro.id order by p.orden limit 1;
  insert into public.auditoria_caja(tipo,local_id,caja_id,sesion_caja_id,actor_id,creado_en,monto_inicial,
    pedido_id,pago_id,importe,propina,medio_pago,subtotal,descuento,total_neto,saldo_anterior,saldo_nuevo,
    estado_anterior,estado_nuevo,cobro_id,medios)
  values('PAGO',v_local,v_sesion.caja_id,v_sesion.id,v_actor,v_cobro.cobrado_en,null,v_pedido.id,
    v_primer_pago.id,v_total,v_propina_total,v_primer_pago.medio,v_subtotal,v_descuento,v_neto,v_saldo,
    v_cobro.saldo_posterior,'ENTREGADO',v_estado_pedido,v_cobro.id,v_medios_normalizados);
  return query select v_cobro.id,v_pedido.id,v_estado_pedido,v_mesa.id,v_estado_mesa,v_cobro.tipo,
    v_total,v_propina_total,v_sesion.id,v_cobro.cobrado_en,v_subtotal,v_descuento,v_neto,
    v_pagado+v_total,v_saldo,v_cobro.saldo_posterior,v_medios_normalizados;
end $$;

-- 17) registrar_movimientos_caja(uuid,jsonb,uuid)
create or replace function public.registrar_movimientos_caja(
  p_sesion_caja_id uuid, p_movimientos jsonb, p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare
  v_actor uuid := auth.uid(); v_local uuid; v_rol text; v_actor_nombre text; v_caja_id uuid;
  v_sesion public.sesion_caja%rowtype; v_lote public.lote_movimiento_caja%rowtype;
  v_movimiento public.movimiento_caja%rowtype; v_item jsonb; v_tipo text; v_motivo text;
  v_importe numeric; v_resultado jsonb := '[]'::jsonb;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol
  from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode = '42501', message = 'No autorizado para registrar movimientos';
  end if;
  select p.nombre into v_actor_nombre from public.perfil_usuario p where p.id = v_actor and p.local_id = v_local;
  if p_sesion_caja_id is null or p_idempotency_key is null or p_movimientos is null
    or jsonb_typeof(p_movimientos) <> 'array' or jsonb_array_length(p_movimientos) < 1
    or jsonb_array_length(p_movimientos) > 50 then
    raise exception using errcode = '22023', message = 'Lote de movimientos inválido';
  end if;
  select s.caja_id into v_caja_id from public.sesion_caja s
    where s.id = p_sesion_caja_id and s.local_id = v_local;
  if v_caja_id is null then
    raise exception using errcode = '42501', message = 'Sesión no disponible';
  end if;
  perform 1 from public.caja c
    where c.id = v_caja_id and c.local_id = v_local and c.activo for update;
  if not found then raise exception using errcode = '42501', message = 'Caja no disponible'; end if;
  select s.* into strict v_sesion from public.sesion_caja s
    where s.id = p_sesion_caja_id and s.caja_id = v_caja_id and s.local_id = v_local for update;
  select l.* into v_lote from public.lote_movimiento_caja l
    where l.sesion_caja_id = v_sesion.id and l.actor_id = v_actor and l.idempotency_key = p_idempotency_key;
  if found then
    if v_lote.movimientos <> p_movimientos then
      raise exception using errcode = '22023', message = 'Clave de lote reutilizada con otros datos';
    end if;
    return v_lote.resultado;
  end if;
  if v_sesion.estado is distinct from 'ABIERTA' then
    raise exception using errcode = 'PT409', message = 'La sesión de caja ya no está abierta';
  end if;
  insert into public.lote_movimiento_caja
    (sesion_caja_id, caja_id, local_id, actor_id, idempotency_key, movimientos)
  values (v_sesion.id, v_sesion.caja_id, v_sesion.local_id, v_actor, p_idempotency_key, p_movimientos)
  returning * into v_lote;

  for v_item in select value from jsonb_array_elements(p_movimientos) loop
    if jsonb_typeof(v_item) <> 'object' or not (v_item ? 'tipo') or not (v_item ? 'importe') or not (v_item ? 'motivo')
      or v_item->>'tipo' not in ('ENTRADA', 'SALIDA')
      or coalesce(v_item->>'importe', '') !~ '^[0-9]+([.][0-9]{1,2})?$' then
      raise exception using errcode = '22023', message = 'Movimiento inválido en lote';
    end if;
    v_tipo := v_item->>'tipo'; v_importe := (v_item->>'importe')::numeric;
    v_motivo := nullif(btrim(v_item->>'motivo'), '');
    if v_importe <= 0 or v_importe >= 1000000000000 or v_importe <> round(v_importe, 2) or v_motivo is null then
      raise exception using errcode = '22023', message = 'Movimiento inválido en lote';
    end if;
    insert into public.movimiento_caja
      (sesion_caja_id, caja_id, local_id, tipo, importe, motivo, actor_id, idempotency_key)
    values (v_sesion.id, v_sesion.caja_id, v_sesion.local_id, v_tipo, v_importe,
      v_motivo, v_actor, gen_random_uuid()) returning * into v_movimiento;
    insert into public.auditoria_caja
      (tipo, local_id, caja_id, sesion_caja_id, actor_id, creado_en,
       monto_inicial, estado_anterior, estado_nuevo, movimiento_caja_id,
       importe, tipo_movimiento, motivo)
    values (v_tipo, v_local, v_sesion.caja_id, v_sesion.id, v_actor,
      v_movimiento.creado_en, null, 'ABIERTA', 'ABIERTA', v_movimiento.id,
      v_movimiento.importe, v_movimiento.tipo, v_movimiento.motivo);
    v_resultado := v_resultado || jsonb_build_array(jsonb_build_object(
      'id', v_movimiento.id, 'sesion_caja_id', v_movimiento.sesion_caja_id,
      'tipo', v_movimiento.tipo, 'importe', v_movimiento.importe,
      'motivo', v_movimiento.motivo, 'actor_id', v_actor,
      'actor_nombre', v_actor_nombre, 'creado_en', v_movimiento.creado_en));
  end loop;
  update public.lote_movimiento_caja set resultado = v_resultado where id = v_lote.id;
  return v_resultado;
end;
$$;

notify pgrst, 'reload schema';

commit;
