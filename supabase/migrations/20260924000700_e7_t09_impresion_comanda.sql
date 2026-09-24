-- E7-T09 — Registro de solicitudes de impresión de comandas.
-- Spec: E7-D12, E7-R25–E7-R28. Registra solicitudes, no certifica la salida física del papel.
-- No modifica detalle, pedido ni mesa.
begin;

create function public.rpc_registrar_impresion_comanda(p_comanda_id bigint, p_reimpresion boolean)
returns table (
  comanda_id bigint,
  pedido_id bigint,
  numero integer,
  impresiones integer,
  es_reimpresion boolean,
  primera_impresion_en timestamptz,
  ultima_impresion_en timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $rpc_registrar_impresion_comanda$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_comanda public.comanda%rowtype;
  v_estado_pedido text;
  v_ahora timestamptz := pg_catalog.clock_timestamp();
begin
  if p_comanda_id is null or p_reimpresion is null or v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para imprimir comandas';
  end if;
  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;
  if v_local_id is null or v_rol_codigo is distinct from 'COCINA' then
    raise exception using errcode = '42501', message = 'No autorizado para imprimir comandas';
  end if;

  -- Sólo se bloquea la comanda: imprimir no toma locks de pedido, detalle ni mesa.
  select command_row.* into v_comanda
  from public.comanda as command_row
  where command_row.id = p_comanda_id and command_row.local_id = v_local_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Comanda no disponible para el usuario autenticado';
  end if;

  select order_row.estado into strict v_estado_pedido
  from public.pedido as order_row where order_row.id = v_comanda.pedido_id;
  if v_estado_pedido not in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO') then
    raise exception using errcode = 'PT409', message = 'El pedido ya no está en cocina; la comanda no se imprime';
  end if;

  if not p_reimpresion and v_comanda.impresiones > 0 then
    raise exception using errcode = 'PT409', message = 'La comanda ya fue impresa; usa Reimprimir';
  end if;
  if p_reimpresion and v_comanda.impresiones = 0 then
    raise exception using errcode = 'PT409', message = 'La comanda aún no se imprimió; usa Imprimir';
  end if;

  update public.comanda as command_row
  set impresiones = command_row.impresiones + 1,
      primera_impresion_en = coalesce(command_row.primera_impresion_en, v_ahora),
      primera_impresion_por = coalesce(command_row.primera_impresion_por, v_usuario_id),
      ultima_impresion_en = v_ahora,
      ultima_impresion_por = v_usuario_id
  where command_row.id = v_comanda.id
  returning command_row.* into strict v_comanda;

  return query select v_comanda.id, v_comanda.pedido_id, v_comanda.numero, v_comanda.impresiones,
    v_comanda.impresiones > 1, v_comanda.primera_impresion_en, v_comanda.ultima_impresion_en;
end;
$rpc_registrar_impresion_comanda$;

alter function public.rpc_registrar_impresion_comanda(bigint,boolean) owner to postgres;
revoke all on function public.rpc_registrar_impresion_comanda(bigint,boolean) from public, anon;
grant execute on function public.rpc_registrar_impresion_comanda(bigint,boolean) to authenticated;

comment on function public.rpc_registrar_impresion_comanda(bigint,boolean) is
  'E7-D12: COCINA registra la primera solicitud de impresión (única; PT409 si ya existe) o una reimpresión explícita. Registra solicitudes, no salida física; no altera detalle, pedido ni mesa.';

notify pgrst, 'reload schema';

commit;
