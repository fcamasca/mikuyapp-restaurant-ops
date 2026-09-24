-- E7 — Limpieza de la fixture de concurrencia (base local aislada). Tablas inmutables se
-- limpian desactivando sus triggers de protección sólo dentro de esta transacción de limpieza.
begin;
set local session_replication_role = replica;
delete from public.historial_detalle_pedido where local_id = '00000000-0000-0000-0000-0000000e7c10';
delete from public.comanda where local_id = '00000000-0000-0000-0000-0000000e7c10';
delete from public.historial_estado where pedido_id in (select id from public.pedido where local_id = '00000000-0000-0000-0000-0000000e7c10');
delete from public.detalle_pedido where pedido_id in (select id from public.pedido where local_id = '00000000-0000-0000-0000-0000000e7c10');
delete from public.pedido where local_id = '00000000-0000-0000-0000-0000000e7c10';
delete from public.producto where local_id = '00000000-0000-0000-0000-0000000e7c10';
delete from public.categoria where local_id = '00000000-0000-0000-0000-0000000e7c10';
delete from public.mesa where local_id = '00000000-0000-0000-0000-0000000e7c10';
delete from public.perfil_usuario where local_id = '00000000-0000-0000-0000-0000000e7c10';
delete from public.local where id = '00000000-0000-0000-0000-0000000e7c10';
delete from auth.users where id::text like '00000000-0000-0000-0000-0000000e7c0%';
commit;
