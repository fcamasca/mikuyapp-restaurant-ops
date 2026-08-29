begin;
delete from public.historial_estado where pedido_id = -50291;
delete from public.detalle_pedido where pedido_id = -50291;
delete from public.pedido where id = -50291;
delete from public.mesa where id = '00000000-0000-0000-0000-00000000e291';
delete from public.producto where id = '00000000-0000-0000-0000-00000000e292';
delete from public.categoria where id = '00000000-0000-0000-0000-00000000e293';
delete from public.perfil_usuario where id = '00000000-0000-0000-0000-00000000e294';
delete from auth.users where id = '00000000-0000-0000-0000-00000000e294';
delete from public.local where id = '00000000-0000-0000-0000-00000000e295';

do $h5_t02_cleanup_verified$
begin
  if exists (select 1 from public.historial_estado where pedido_id = -50291)
    or exists (select 1 from public.detalle_pedido where pedido_id = -50291)
    or exists (select 1 from public.pedido where id = -50291)
    or exists (
      select 1 from auth.users
      where id = '00000000-0000-0000-0000-00000000e294'
    ) then
    raise exception 'H5-T02 no limpió el fixture concurrente';
  end if;
end;
$h5_t02_cleanup_verified$;
commit;
