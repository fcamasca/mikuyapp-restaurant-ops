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
-- E9 (homologación mínima): la jornada es inmutable y no se borra; se cierra con la transición permitida ABIERTA -> CERRADA.
update public.jornada_operativa set estado = 'CERRADA', cerrada_por = abierta_por, cerrada_en = greatest(now(), abierta_en)
where local_id in ('00000000-0000-0000-0000-0000000e7c10'::uuid) and estado = 'ABIERTA';
delete from public.perfil_usuario where (local_id = '00000000-0000-0000-0000-0000000e7c10') and id not in (select abierta_por from public.jornada_operativa union all select cerrada_por from public.jornada_operativa where cerrada_por is not null); -- E9 (homologación mínima): el perfil que abre/cierra una jornada no se borra
delete from public.local where (id = '00000000-0000-0000-0000-0000000e7c10') and id not in (select local_id from public.jornada_operativa); -- E9 (homologación mínima): el local con jornadas (inmutables) se conserva
delete from auth.users where (id::text like '00000000-0000-0000-0000-0000000e7c0%') and id not in (select id from public.perfil_usuario); -- E9 (homologación mínima): se conserva el usuario de un perfil conservado
commit;
