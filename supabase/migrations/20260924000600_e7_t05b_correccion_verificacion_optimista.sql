-- E7-T05B (corrección) — Verificación optimista completa en rpc_modificar_detalle_pedido.
-- Spec: E7-D15 / E7-R33. Reemplaza la semántica parcial introducida en 20260924000500:
--   * el cliente envía siempre los valores finales de cantidad y observación;
--   * también envía siempre la cantidad y la observación que tenía como esperadas;
--   * ambos esperados se comparan siempre contra la fila persistida (NULL es un valor real);
--   * cualquier diferencia => PT409 sin modificar el detalle.
-- Observación vacía o sólo espacios se normaliza a sin observación (NULL), tanto final como esperada.
begin;

create or replace function public.rpc_modificar_detalle_pedido(
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
  -- Validación H3: cantidad final y esperada enteras >= 1.
  if p_cantidad is null or p_cantidad < 1 then
    raise exception using errcode = '22023', message = 'La cantidad debe ser un entero mayor o igual a 1';
  end if;
  if p_cantidad_esperada is null or p_cantidad_esperada < 1 then
    raise exception using errcode = '22023', message = 'La cantidad esperada es obligatoria';
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
  -- Verificación optimista completa: ambos esperados siempre, NULL comparado como valor real.
  if not found
    or v_detalle.estado <> 'ABIERTO'
    or v_detalle.cantidad is distinct from p_cantidad_esperada
    or nullif(pg_catalog.btrim(v_detalle.observacion), '') is distinct from v_observacion_esperada then
    raise exception using errcode = 'PT409', message = 'El producto cambió o ya fue enviado';
  end if;

  update public.detalle_pedido as detail_row
  set cantidad = p_cantidad,
      observacion = v_observacion
  where detail_row.id = v_detalle.id
  returning detail_row.* into strict v_detalle;

  return query select v_detalle.id, v_detalle.cantidad, v_detalle.observacion, v_detalle.estado;
end;
$rpc_modificar_detalle_pedido$;

alter function public.rpc_modificar_detalle_pedido(bigint,integer,text,integer,text) owner to postgres;
revoke all on function public.rpc_modificar_detalle_pedido(bigint,integer,text,integer,text) from public, anon;
grant execute on function public.rpc_modificar_detalle_pedido(bigint,integer,text,integer,text) to authenticated;

comment on function public.rpc_modificar_detalle_pedido(bigint,integer,text,integer,text) is
  'E7-D15: edición H3 de cantidad/observación de un detalle ABIERTO. Recibe siempre valores finales y esperados; ambos esperados se verifican contra la fila (NULL como valor real); cualquier diferencia => PT409. Observación vacía = sin observación. Locks pedido -> detalle.';

notify pgrst, 'reload schema';

commit;
