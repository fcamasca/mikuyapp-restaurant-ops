-- E7-T05 — Cancelación de detalles por el mozo y lectura de cancelaciones.
-- Spec: E7-D10, E7-D11, E7-D13, E7-D14 (DH-03, DH-04).
begin;

create function public.rpc_cancelar_detalle_pedido(p_detalle_id bigint, p_motivo text)
returns table (
  detalle_id bigint,
  pedido_id bigint,
  pedido_estado text,
  mesa_estado text,
  ya_cancelado boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $rpc_cancelar_detalle_pedido$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_motivo text := pg_catalog.btrim(p_motivo);
  v_pedido_id bigint;
  v_pedido public.pedido%rowtype;
  v_detalle public.detalle_pedido%rowtype;
  v_mesa public.mesa%rowtype;
  v_restantes bigint;
  v_estado_pedido text;
  v_estado_mesa text;
begin
  if p_detalle_id is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para cancelar productos';
  end if;
  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;
  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using errcode = '42501', message = 'No autorizado para cancelar productos';
  end if;
  if v_motivo is null or v_motivo = '' or pg_catalog.char_length(v_motivo) > 200 then
    raise exception using errcode = '22023', message = 'El motivo de cancelación es obligatorio (máximo 200 caracteres)';
  end if;

  select detail_row.pedido_id into v_pedido_id
  from public.detalle_pedido as detail_row where detail_row.id = p_detalle_id;

  if not found then
    -- Idempotencia E7-R16: una cancelación ya confirmada devuelve el mismo resultado.
    select history_row.pedido_id into v_pedido_id
    from public.historial_detalle_pedido as history_row
    where history_row.detalle_id = p_detalle_id
      and history_row.operacion = 'CANCELACION'
      and history_row.local_id = v_local_id;
    if not found then
      raise exception using errcode = '42501', message = 'Producto no disponible para el usuario autenticado';
    end if;
    return query
    select p_detalle_id, order_row.id, order_row.estado, table_row.estado, true
    from public.pedido as order_row
    inner join public.mesa as table_row on table_row.id = order_row.mesa_id
    where order_row.id = v_pedido_id;
    return;
  end if;

  -- Orden de locks único: pedido -> detalle -> mesa.
  select order_row.* into v_pedido
  from public.pedido as order_row
  where order_row.id = v_pedido_id
    and order_row.local_id = v_local_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Producto no disponible para el usuario autenticado';
  end if;
  if v_pedido.estado not in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO') then
    raise exception using errcode = 'PT409', message = 'El pedido ya no admite cancelaciones';
  end if;
  if exists (select 1 from public.pago as payment_row where payment_row.pedido_id = v_pedido.id) then
    raise exception using errcode = 'PT409', message = 'Un pedido con pagos no admite cancelaciones';
  end if;

  select detail_row.* into v_detalle
  from public.detalle_pedido as detail_row
  where detail_row.id = p_detalle_id and detail_row.pedido_id = v_pedido.id
  for update;
  if not found then
    -- Cancelado por otra sesión mientras esperaba el lock: resultado idempotente.
    if exists (select 1 from public.historial_detalle_pedido as history_row
               where history_row.detalle_id = p_detalle_id and history_row.operacion = 'CANCELACION'
                 and history_row.local_id = v_local_id) then
      return query
      select p_detalle_id, order_row.id, order_row.estado, table_row.estado, true
      from public.pedido as order_row
      inner join public.mesa as table_row on table_row.id = order_row.mesa_id
      where order_row.id = v_pedido.id;
      return;
    end if;
    raise exception using errcode = 'PT409', message = 'El producto cambió durante la operación';
  end if;

  if v_detalle.estado = 'ABIERTO' then
    raise exception using errcode = 'PT409', message = 'El producto aún no fue enviado; usa Retirar';
  end if;
  -- DH-03: un producto sin cocina enviado está LISTO y no se cancela.
  if not v_detalle.requiere_cocina or v_detalle.estado not in ('ENVIADO', 'RECIBIDO_COCINA') then
    raise exception using errcode = 'PT409', message = 'La preparación ya inició; el producto no puede cancelarse';
  end if;

  -- DH-04: siempre la línea completa. Snapshot inmutable antes de eliminar la línea activa.
  insert into public.historial_detalle_pedido (
    local_id, pedido_id, detalle_id, producto_id, operacion,
    estado_anterior, estado_nuevo, requiere_cocina, cantidad, precio_unitario,
    observacion, motivo, usuario_id
  ) values (
    v_local_id, v_pedido.id, v_detalle.id, v_detalle.producto_id, 'CANCELACION',
    v_detalle.estado, null, v_detalle.requiere_cocina, v_detalle.cantidad, v_detalle.precio_unitario,
    v_detalle.observacion, v_motivo, v_usuario_id
  );

  delete from public.detalle_pedido as detail_row where detail_row.id = v_detalle.id;

  select pg_catalog.count(*) into v_restantes
  from public.detalle_pedido as detail_row where detail_row.pedido_id = v_pedido.id;

  if v_restantes > 0 then
    select sync_result.pedido_estado, sync_result.mesa_estado
    into strict v_estado_pedido, v_estado_mesa
    from public.sincronizar_estado_operativo_pedido(v_pedido.id, v_usuario_id) as sync_result;
  else
    -- Sin detalles: pedido ABIERTO vacío y mesa OCUPADA (acciones H3 disponibles).
    select table_row.* into strict v_mesa
    from public.mesa as table_row
    where table_row.id = v_pedido.mesa_id and table_row.local_id = v_local_id
    for update;
    if v_pedido.estado <> 'ABIERTO' then
      update public.pedido as order_row set estado = 'ABIERTO' where order_row.id = v_pedido.id;
      insert into public.historial_estado (pedido_id, estado_anterior, estado_nuevo, usuario_id)
      values (v_pedido.id, v_pedido.estado, 'ABIERTO', v_usuario_id);
    end if;
    if v_mesa.estado <> 'OCUPADA' then
      update public.mesa as table_row set estado = 'OCUPADA' where table_row.id = v_mesa.id;
    end if;
    v_estado_pedido := 'ABIERTO';
    v_estado_mesa := 'OCUPADA';
  end if;

  return query select v_detalle.id, v_pedido.id, v_estado_pedido, v_estado_mesa, false;
end;
$rpc_cancelar_detalle_pedido$;

alter function public.rpc_cancelar_detalle_pedido(bigint,text) owner to postgres;
revoke all on function public.rpc_cancelar_detalle_pedido(bigint,text) from public, anon;
grant execute on function public.rpc_cancelar_detalle_pedido(bigint,text) to authenticated;

create function public.rpc_obtener_cancelaciones_pedido(p_pedido_id bigint)
returns table (
  detalle_id bigint,
  producto_id uuid,
  producto_nombre text,
  cantidad integer,
  precio_unitario numeric,
  observacion text,
  estado_anterior text,
  motivo text,
  cancelado_en timestamptz,
  cancelado_por_nombre text
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $rpc_obtener_cancelaciones_pedido$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
begin
  if p_pedido_id is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para consultar cancelaciones';
  end if;
  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;
  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using errcode = '42501', message = 'No autorizado para consultar cancelaciones';
  end if;

  return query
  select history_row.detalle_id, history_row.producto_id, product_row.nombre,
    history_row.cantidad, history_row.precio_unitario, history_row.observacion,
    history_row.estado_anterior, history_row.motivo, history_row.creado_en, profile_row.nombre
  from public.historial_detalle_pedido as history_row
  inner join public.pedido as order_row on order_row.id = history_row.pedido_id
  inner join public.producto as product_row on product_row.id = history_row.producto_id
  inner join public.perfil_usuario as profile_row on profile_row.id = history_row.usuario_id
  where history_row.pedido_id = p_pedido_id
    and history_row.local_id = v_local_id
    and order_row.local_id = v_local_id
    and order_row.estado in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO', 'ENTREGADO')
    and history_row.operacion = 'CANCELACION'
  order by history_row.creado_en, history_row.id;
end;
$rpc_obtener_cancelaciones_pedido$;

alter function public.rpc_obtener_cancelaciones_pedido(bigint) owner to postgres;
revoke all on function public.rpc_obtener_cancelaciones_pedido(bigint) from public, anon;
grant execute on function public.rpc_obtener_cancelaciones_pedido(bigint) to authenticated;

comment on function public.rpc_cancelar_detalle_pedido(bigint,text) is
  'E7-D10: MOZO cancela la línea completa ENVIADO/RECIBIDO_COCINA con motivo; locks pedido -> detalle -> mesa; snapshot en historial_detalle_pedido, eliminación de la línea activa y recálculo atómico; idempotente.';
comment on function public.rpc_obtener_cancelaciones_pedido(bigint) is
  'E7-D13: cancelaciones de un pedido vigente del local para el MOZO (sólo lectura).';

notify pgrst, 'reload schema';

commit;
