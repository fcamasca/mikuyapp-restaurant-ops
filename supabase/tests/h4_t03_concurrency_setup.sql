begin;

delete from public.detalle_pedido where pedido_id = -40391;
delete from public.pedido where id = -40391;
delete from public.mesa where id = '00000000-0000-0000-0000-00000000d43c';
delete from public.producto where id = '00000000-0000-0000-0000-00000000d43d';
delete from public.categoria where id = '00000000-0000-0000-0000-00000000d43e';
-- E9 (homologación mínima): la jornada es inmutable y no se borra; se cierra con la transición permitida ABIERTA -> CERRADA.
update public.jornada_operativa set estado = 'CERRADA', cerrada_por = abierta_por, cerrada_en = greatest(now(), abierta_en)
where local_id in ('00000000-0000-0000-0000-00000000d440'::uuid) and estado = 'ABIERTA';
delete from public.perfil_usuario where (id = '00000000-0000-0000-0000-00000000d43f') and id not in (select abierta_por from public.jornada_operativa union all select cerrada_por from public.jornada_operativa where cerrada_por is not null); -- E9 (homologación mínima): el perfil que abre/cierra una jornada no se borra
delete from auth.users where (id = '00000000-0000-0000-0000-00000000d43f') and id not in (select id from public.perfil_usuario); -- E9 (homologación mínima): se conserva el usuario de un perfil conservado
delete from public.local where (id = '00000000-0000-0000-0000-00000000d440') and id not in (select local_id from public.jornada_operativa); -- E9 (homologación mínima): el local con jornadas (inmutables) se conserva

insert into auth.users (id, aud, role, email, encrypted_password)
values (
  '00000000-0000-0000-0000-00000000d43f',
  'authenticated', 'authenticated', 'h4-t03-concurrency@example.invalid', 'test'
)
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;

insert into public.local (id, codigo, nombre)
values ('00000000-0000-0000-0000-00000000d440', 'H4-T03-C', 'Local concurrencia T03')
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;

insert into public.perfil_usuario (id, local_id, rol_id, nombre)
select
  '00000000-0000-0000-0000-00000000d43f',
  '00000000-0000-0000-0000-00000000d440',
  role_row.id,
  'Cocina concurrencia T03'
from public.rol as role_row
where role_row.codigo = 'COCINA'
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;
-- E9 (homologación mínima): precondición global de E9 — jornada operativa ABIERTA válida para los locales del fixture.
insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
select l.id, (now() at time zone 'America/Lima')::date,
  1 + coalesce((select max(j.numero) from public.jornada_operativa j where j.local_id = l.id and j.fecha_operativa = (now() at time zone 'America/Lima')::date), 0),
  (select p.id from public.perfil_usuario p where p.local_id = l.id order by p.id limit 1), now(), gen_random_uuid()
from public.local l
where l.id in ('00000000-0000-0000-0000-00000000d440'::uuid)
  and exists (select 1 from public.perfil_usuario p where p.local_id = l.id)
  and not exists (select 1 from public.jornada_operativa j where j.local_id = l.id and j.estado = 'ABIERTA');

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
