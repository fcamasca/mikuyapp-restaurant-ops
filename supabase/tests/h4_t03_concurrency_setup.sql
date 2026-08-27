begin;

delete from public.detalle_pedido where pedido_id = -40391;
delete from public.pedido where id = -40391;
delete from public.mesa where id = '00000000-0000-0000-0000-00000000d43c';
delete from public.producto where id = '00000000-0000-0000-0000-00000000d43d';
delete from public.categoria where id = '00000000-0000-0000-0000-00000000d43e';
delete from public.perfil_usuario where id = '00000000-0000-0000-0000-00000000d43f';
delete from auth.users where id = '00000000-0000-0000-0000-00000000d43f';
delete from public.local where id = '00000000-0000-0000-0000-00000000d440';

insert into auth.users (id, aud, role, email, encrypted_password)
values (
  '00000000-0000-0000-0000-00000000d43f',
  'authenticated', 'authenticated', 'h4-t03-concurrency@example.invalid', 'test'
);

insert into public.local (id, codigo, nombre)
values ('00000000-0000-0000-0000-00000000d440', 'H4-T03-C', 'Local concurrencia T03');

insert into public.perfil_usuario (id, local_id, rol_id, nombre)
select
  '00000000-0000-0000-0000-00000000d43f',
  '00000000-0000-0000-0000-00000000d440',
  role_row.id,
  'Cocina concurrencia T03'
from public.rol as role_row
where role_row.codigo = 'COCINA';

insert into public.mesa (id, local_id, codigo, nombre, estado)
values (
  '00000000-0000-0000-0000-00000000d43c',
  '00000000-0000-0000-0000-00000000d440',
  'T03-C', 'Mesa concurrencia T03', 'OCUPADA'
);

insert into public.categoria (id, local_id, codigo, nombre)
values (
  '00000000-0000-0000-0000-00000000d43e',
  '00000000-0000-0000-0000-00000000d440',
  'T03-C', 'Categoría concurrencia T03'
);

insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio)
values (
  '00000000-0000-0000-0000-00000000d43d',
  '00000000-0000-0000-0000-00000000d440',
  '00000000-0000-0000-0000-00000000d43e',
  'T03-C', 'Producto concurrencia T03', 1
);

insert into public.pedido (id, local_id, mesa_id, creado_por, estado, enviado_en)
overriding system value
values (
  -40391,
  '00000000-0000-0000-0000-00000000d440',
  '00000000-0000-0000-0000-00000000d43c',
  '00000000-0000-0000-0000-00000000d43f',
  'ENVIADO', pg_catalog.clock_timestamp()
);

insert into public.detalle_pedido (
  id, pedido_id, producto_id, cantidad, precio_unitario, estado, enviado_en
) overriding system value
values (
  -40391, -40391,
  '00000000-0000-0000-0000-00000000d43d',
  1, 1, 'ENVIADO', pg_catalog.clock_timestamp()
);

commit;
