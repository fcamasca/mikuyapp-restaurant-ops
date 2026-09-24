-- E7-T10 — Corrección detectada en integración: privilegios por defecto de Supabase.
-- Causa: en Supabase, ALTER DEFAULT PRIVILEGES concede ALL sobre tablas/secuencias y EXECUTE
-- sobre funciones nuevas de public a anon, authenticated y service_role. Las migraciones E7
-- revocaron anon/authenticated, pero no service_role, a diferencia de la convención E1
-- (tablas inmutables y funciones internas revocadas también a service_role). Con TRUNCATE,
-- service_role podría eludir los triggers de inmutabilidad del historial y de la comanda.
-- Esta migración nueva alinea E7 con la convención E1 sin cambiar reglas ni contratos.
begin;

revoke all on table public.historial_detalle_pedido from public, anon, authenticated, service_role;
revoke all on table public.comanda from public, anon, authenticated, service_role;
revoke all on sequence public.historial_detalle_pedido_id_seq from public, anon, authenticated, service_role;
revoke all on sequence public.comanda_id_seq from public, anon, authenticated, service_role;

revoke all on function public.tgf_historial_detalle_pedido_inmutable() from public, anon, authenticated, service_role;
revoke all on function public.tgf_comanda_contenido_inmutable() from public, anon, authenticated, service_role;
revoke all on function public.tgf_detalle_pedido_historial_estado() from public, anon, authenticated, service_role;

-- RPC E7: sólo authenticated (cada RPC revalida rol y local en servidor).
revoke all on function public.rpc_obtener_tablero_cocina() from public, anon, service_role;
revoke all on function public.rpc_recibir_pedido_cocina(bigint) from public, anon, service_role;
revoke all on function public.rpc_cancelar_detalle_pedido(bigint,text) from public, anon, service_role;
revoke all on function public.rpc_obtener_cancelaciones_pedido(bigint) from public, anon, service_role;
revoke all on function public.rpc_modificar_detalle_pedido(bigint,integer,text,integer,text) from public, anon, service_role;
revoke all on function public.rpc_retirar_detalle_pedido(bigint) from public, anon, service_role;
revoke all on function public.rpc_registrar_impresion_comanda(bigint,boolean) from public, anon, service_role;
grant execute on function public.rpc_obtener_tablero_cocina() to authenticated;
grant execute on function public.rpc_recibir_pedido_cocina(bigint) to authenticated;
grant execute on function public.rpc_cancelar_detalle_pedido(bigint,text) to authenticated;
grant execute on function public.rpc_obtener_cancelaciones_pedido(bigint) to authenticated;
grant execute on function public.rpc_modificar_detalle_pedido(bigint,integer,text,integer,text) to authenticated;
grant execute on function public.rpc_retirar_detalle_pedido(bigint) to authenticated;
grant execute on function public.rpc_registrar_impresion_comanda(bigint,boolean) to authenticated;

notify pgrst, 'reload schema';

commit;
