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

insert into auth.users (id, aud, role, email, encrypted_password)
values (
  '00000000-0000-0000-0000-00000000e294',
  'authenticated', 'authenticated', 'h5-t02-concurrency@example.invalid', 'test'
);
insert into public.local (id, codigo, nombre)
values ('00000000-0000-0000-0000-00000000e295', 'H5-T02-C', 'Local concurrencia H5 T02');
insert into public.perfil_usuario (id, local_id, rol_id, nombre)
select '00000000-0000-0000-0000-00000000e294',
  '00000000-0000-0000-0000-00000000e295', role_row.id, 'Mozo concurrencia H5 T02'
from public.rol as role_row where role_row.codigo = 'MOZO';
insert into public.mesa (id, local_id, codigo, nombre, estado)
values ('00000000-0000-0000-0000-00000000e291',
  '00000000-0000-0000-0000-00000000e295', 'H5-T02-C', 'Mesa concurrencia', 'PEDIDO_LISTO');
insert into public.categoria (id, local_id, codigo, nombre)
values ('00000000-0000-0000-0000-00000000e293',
  '00000000-0000-0000-0000-00000000e295', 'H5-T02-C', 'Categoría concurrencia');
insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio)
values ('00000000-0000-0000-0000-00000000e292',
  '00000000-0000-0000-0000-00000000e295',
  '00000000-0000-0000-0000-00000000e293', 'H5-T02-C', 'Producto concurrencia', 1);
insert into public.pedido (id, local_id, mesa_id, creado_por, estado, enviado_en)
overriding system value
values (-50291, '00000000-0000-0000-0000-00000000e295',
  '00000000-0000-0000-0000-00000000e291',
  '00000000-0000-0000-0000-00000000e294', 'LISTO', pg_catalog.clock_timestamp());
select pg_catalog.set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e294', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
insert into public.detalle_pedido (
  id, pedido_id, producto_id, cantidad, precio_unitario, estado, enviado_en
) overriding system value
values (-50291, -50291, '00000000-0000-0000-0000-00000000e292',
  1, 1, 'LISTO', pg_catalog.clock_timestamp());

commit;
