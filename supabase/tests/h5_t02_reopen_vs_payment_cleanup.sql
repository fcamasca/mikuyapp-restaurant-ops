delete from public.pago where pedido_id=-50821;
delete from public.historial_estado where pedido_id=-50821;
delete from public.detalle_pedido where pedido_id=-50821;
delete from public.pedido where id=-50821;
delete from public.mesa where id='00000000-0000-0000-0000-00000000f827';
delete from public.producto where id in ('00000000-0000-0000-0000-00000000f825','00000000-0000-0000-0000-00000000f826');
delete from public.categoria where id='00000000-0000-0000-0000-00000000f824';
delete from public.perfil_usuario where id in (
  '00000000-0000-0000-0000-00000000f821',
  '00000000-0000-0000-0000-00000000f822'
);
delete from auth.users where id in (
  '00000000-0000-0000-0000-00000000f821',
  '00000000-0000-0000-0000-00000000f822'
);
delete from public.local where id='00000000-0000-0000-0000-00000000f823';

select
  (select count(*) from auth.users where id in ('00000000-0000-0000-0000-00000000f821','00000000-0000-0000-0000-00000000f822'))
  + (select count(*) from public.local where id='00000000-0000-0000-0000-00000000f823')
  + (select count(*) from public.pedido where id=-50821)
  + (select count(*) from public.detalle_pedido where pedido_id=-50821)
  + (select count(*) from public.pago where pedido_id=-50821)
  + (select count(*) from public.historial_estado where pedido_id=-50821)
  as fixtures_residuales;
