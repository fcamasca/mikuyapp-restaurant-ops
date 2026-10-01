begin;
delete from public.historial_estado where pedido_id = -50291;
delete from public.detalle_pedido where pedido_id = -50291;
delete from public.pedido where id = -50291;
delete from public.mesa where id = '00000000-0000-0000-0000-00000000e291';
delete from public.producto where id = '00000000-0000-0000-0000-00000000e292';
delete from public.categoria where id = '00000000-0000-0000-0000-00000000e293';
-- E9 (homologación mínima): la jornada es inmutable y no se borra; se cierra con la transición permitida ABIERTA -> CERRADA.
update public.jornada_operativa set estado = 'CERRADA', cerrada_por = abierta_por, cerrada_en = greatest(now(), abierta_en)
where local_id in ('00000000-0000-0000-0000-00000000e295'::uuid) and estado = 'ABIERTA';
delete from public.perfil_usuario where (id = '00000000-0000-0000-0000-00000000e294') and id not in (select abierta_por from public.jornada_operativa union all select cerrada_por from public.jornada_operativa where cerrada_por is not null); -- E9 (homologación mínima): el perfil que abre/cierra una jornada no se borra
delete from auth.users where (id = '00000000-0000-0000-0000-00000000e294') and id not in (select id from public.perfil_usuario); -- E9 (homologación mínima): se conserva el usuario de un perfil conservado
delete from public.local where (id = '00000000-0000-0000-0000-00000000e295') and id not in (select local_id from public.jornada_operativa); -- E9 (homologación mínima): el local con jornadas (inmutables) se conserva

do $h5_t02_cleanup_verified$
begin
  if exists (select 1 from public.historial_estado where pedido_id = -50291)
    or exists (select 1 from public.detalle_pedido where pedido_id = -50291)
    or exists (select 1 from public.pedido where id = -50291)
    or exists (
      select 1 from auth.users
      where id = '00000000-0000-0000-0000-00000000e294' and id not in (select id from public.perfil_usuario)
    ) then
    raise exception 'H5-T02 no limpió el fixture concurrente';
  end if;
end;
$h5_t02_cleanup_verified$;
commit;
