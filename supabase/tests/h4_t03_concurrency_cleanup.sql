begin;

delete from public.detalle_pedido where pedido_id = -40391;
delete from public.pedido where id = -40391;
delete from public.mesa where id = '00000000-0000-0000-0000-00000000d43c';
delete from public.producto where id = '00000000-0000-0000-0000-00000000d43d';
delete from public.categoria where id = '00000000-0000-0000-0000-00000000d43e';
delete from public.perfil_usuario where id = '00000000-0000-0000-0000-00000000d43f';
delete from auth.users where id = '00000000-0000-0000-0000-00000000d43f';
delete from public.local where id = '00000000-0000-0000-0000-00000000d440';

do $cleanup_verified$
begin
  if exists (select 1 from public.detalle_pedido where id = -40391)
    or exists (select 1 from public.pedido where id = -40391)
    or exists (
      select 1 from auth.users
      where id = '00000000-0000-0000-0000-00000000d43f'
    ) then
    raise exception 'H4-T03 no limpió el fixture concurrente';
  end if;
end;
$cleanup_verified$;

commit;
