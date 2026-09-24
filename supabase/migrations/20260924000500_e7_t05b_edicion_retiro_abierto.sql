-- E7-T05B — Edición y retiro de detalles ABIERTO vía RPC (HZ-01, DH-01).
-- Spec: E7-D14, E7-D15, E7-D16. Conserva exactamente las capacidades H3; sólo cambia el mecanismo.
begin;

create function public.rpc_modificar_detalle_pedido(
  p_detalle_id bigint,
  p_cantidad integer,
  p_observacion text,
  p_cantidad_esperada integer,
  p_observacion_esperada text
)
returns table (detalle_id bigint, cantidad integer, observacion text, estado text)
language plpgsql
security definer
set search_path = pg_catalog
as $rpc_modificar_detalle_pedido$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_pedido_id bigint;
  v_observacion text := nullif(pg_catalog.btrim(p_observacion), '');
  v_observacion_esperada text := nullif(pg_catalog.btrim(p_observacion_esperada), '');
  v_detalle public.detalle_pedido%rowtype;
  -- Semántica H3 de actualización parcial (equivalente al UPDATE directo sustituido):
  --   p_cantidad / p_observacion NULL          => el campo no cambia;
  --   p_observacion '' (o sólo espacios)       => se elimina la observación;
  --   p_*_esperada NULL                        => ese campo no se verifica;
  --   p_observacion_esperada ''                => se espera que no tenga observación.
begin
  if p_detalle_id is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para modificar productos';
  end if;
  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;
  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using errcode = '42501', message = 'No autorizado para modificar productos';
  end if;
  -- Validación H3: cantidad entera >= 1; observación vacía equivale a sin observación.
  if p_cantidad is not null and p_cantidad < 1 then
    raise exception using errcode = '22023', message = 'La cantidad debe ser un entero mayor o igual a 1';
  end if;

  select detail_row.pedido_id into v_pedido_id
  from public.detalle_pedido as detail_row where detail_row.id = p_detalle_id;
  if not found then
    raise exception using errcode = 'PT409', message = 'El producto cambió o ya no está disponible';
  end if;

  -- Orden de locks único: pedido -> detalle.
  perform 1 from public.pedido as order_row
  where order_row.id = v_pedido_id
    and order_row.local_id = v_local_id
    and order_row.estado in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO', 'ENTREGADO')
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Pedido no disponible para el usuario autenticado';
  end if;

  select detail_row.* into v_detalle
  from public.detalle_pedido as detail_row
  where detail_row.id = p_detalle_id and detail_row.pedido_id = v_pedido_id
  for update;
  if not found
    or v_detalle.estado <> 'ABIERTO'
    or (p_cantidad_esperada is not null and v_detalle.cantidad is distinct from p_cantidad_esperada)
    or (p_observacion_esperada is not null
        and nullif(pg_catalog.btrim(v_detalle.observacion), '') is distinct from v_observacion_esperada) then
    raise exception using errcode = 'PT409', message = 'El producto cambió o ya fue enviado';
  end if;

  if p_cantidad is null and p_observacion is null then
    return query select v_detalle.id, v_detalle.cantidad, v_detalle.observacion, v_detalle.estado;
    return;
  end if;

  update public.detalle_pedido as detail_row
  set cantidad = coalesce(p_cantidad, detail_row.cantidad),
      observacion = case when p_observacion is null then detail_row.observacion else v_observacion end
  where detail_row.id = v_detalle.id
  returning detail_row.* into strict v_detalle;

  return query select v_detalle.id, v_detalle.cantidad, v_detalle.observacion, v_detalle.estado;
end;
$rpc_modificar_detalle_pedido$;

create function public.rpc_retirar_detalle_pedido(p_detalle_id bigint)
returns table (detalle_id bigint, pedido_id bigint, pedido_estado text, mesa_estado text)
language plpgsql
security definer
set search_path = pg_catalog
as $rpc_retirar_detalle_pedido$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_pedido_id bigint;
  v_pedido public.pedido%rowtype;
  v_detalle public.detalle_pedido%rowtype;
  v_mesa public.mesa%rowtype;
  v_estado_pedido text;
  v_estado_mesa text;
begin
  if p_detalle_id is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para retirar productos';
  end if;
  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;
  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using errcode = '42501', message = 'No autorizado para retirar productos';
  end if;

  select detail_row.pedido_id into v_pedido_id
  from public.detalle_pedido as detail_row where detail_row.id = p_detalle_id;
  if not found then
    raise exception using errcode = 'PT409', message = 'El producto cambió o ya no está disponible';
  end if;

  -- Orden de locks único: pedido -> detalle -> mesa.
  select order_row.* into v_pedido
  from public.pedido as order_row
  where order_row.id = v_pedido_id
    and order_row.local_id = v_local_id
    and order_row.estado in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO', 'ENTREGADO')
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Pedido no disponible para el usuario autenticado';
  end if;

  select detail_row.* into v_detalle
  from public.detalle_pedido as detail_row
  where detail_row.id = p_detalle_id and detail_row.pedido_id = v_pedido.id
  for update;
  if not found or v_detalle.estado <> 'ABIERTO' then
    raise exception using errcode = 'PT409', message = 'El producto cambió o ya fue enviado';
  end if;

  delete from public.detalle_pedido as detail_row where detail_row.id = v_detalle.id;

  if exists (select 1 from public.detalle_pedido as detail_row where detail_row.pedido_id = v_pedido.id) then
    -- Corrección HZ-01: el retiro deriva cabecera y mesa en la misma transacción.
    select sync_result.pedido_estado, sync_result.mesa_estado
    into strict v_estado_pedido, v_estado_mesa
    from public.sincronizar_estado_operativo_pedido(v_pedido.id, v_usuario_id) as sync_result;
  else
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

  return query select v_detalle.id, v_pedido.id, v_estado_pedido, v_estado_mesa;
end;
$rpc_retirar_detalle_pedido$;

alter function public.rpc_modificar_detalle_pedido(bigint,integer,text,integer,text) owner to postgres;
alter function public.rpc_retirar_detalle_pedido(bigint) owner to postgres;
revoke all on function public.rpc_modificar_detalle_pedido(bigint,integer,text,integer,text) from public, anon;
revoke all on function public.rpc_retirar_detalle_pedido(bigint) from public, anon;
grant execute on function public.rpc_modificar_detalle_pedido(bigint,integer,text,integer,text) to authenticated;
grant execute on function public.rpc_retirar_detalle_pedido(bigint) to authenticated;

-- E7-D15: se sustituyen las mutaciones directas del cliente sobre detalle_pedido.
drop policy detalle_pedido_update_abierto_mozo on public.detalle_pedido;
drop policy detalle_pedido_delete_abierto_mozo on public.detalle_pedido;
revoke update (cantidad, observacion) on table public.detalle_pedido from authenticated;
revoke delete on table public.detalle_pedido from authenticated;

comment on function public.rpc_modificar_detalle_pedido(bigint,integer,text,integer,text) is
  'E7-D15: edición H3 parcial de cantidad/observación de un detalle ABIERTO (NULL = sin cambio/sin verificación; observación vacía = sin observación) con verificación optimista; locks pedido -> detalle.';
comment on function public.rpc_retirar_detalle_pedido(bigint) is
  'E7-D15: retiro H3 de un detalle ABIERTO con derivación de pedido/mesa (corrige HZ-01); locks pedido -> detalle -> mesa.';

notify pgrst, 'reload schema';

commit;
