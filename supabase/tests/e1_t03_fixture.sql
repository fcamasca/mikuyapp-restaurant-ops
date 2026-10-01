-- Exclusivamente para la base efímera creada por scripts/testE1T03.mjs.
begin;
insert into public.local (id, codigo, nombre, activo) values
  ('e1030000-0000-0000-0000-000000000001', 'E1-T03-A', 'Local A', true),
  ('e1030000-0000-0000-0000-000000000002', 'E1-T03-B', 'Local B', true),
  ('e1030000-0000-0000-0000-000000000003', 'E1-T03-INACTIVO', 'Local inactivo', false);
insert into auth.users (id, aud, role, email, encrypted_password) values
  ('e1030000-0000-0000-0000-000000000011', 'authenticated', 'authenticated', 'e1-t03-a@example.invalid', 'test'),
  ('e1030000-0000-0000-0000-000000000012', 'authenticated', 'authenticated', 'e1-t03-b@example.invalid', 'test');
insert into public.perfil_usuario (id, local_id, rol_id, nombre)
select 'e1030000-0000-0000-0000-000000000011'::uuid, 'e1030000-0000-0000-0000-000000000001'::uuid, id, 'Cajero A'
  from public.rol where codigo = 'CAJA'
union all
select 'e1030000-0000-0000-0000-000000000012', 'e1030000-0000-0000-0000-000000000001', id, 'Cajero B'
  from public.rol where codigo = 'CAJA';
-- E9 (homologación mínima): precondición global de E9 — jornada operativa ABIERTA válida para los locales del fixture.
insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
select l.id, (now() at time zone 'America/Lima')::date,
  1 + coalesce((select max(j.numero) from public.jornada_operativa j where j.local_id = l.id and j.fecha_operativa = (now() at time zone 'America/Lima')::date), 0),
  (select p.id from public.perfil_usuario p where p.local_id = l.id order by p.id limit 1), now(), gen_random_uuid()
from public.local l
where l.id in ('e1030000-0000-0000-0000-000000000001'::uuid, 'e1030000-0000-0000-0000-000000000002'::uuid, 'e1030000-0000-0000-0000-000000000003'::uuid)
  and exists (select 1 from public.perfil_usuario p where p.local_id = l.id)
  and not exists (select 1 from public.jornada_operativa j where j.local_id = l.id and j.estado = 'ABIERTA');
insert into public.mesa (id, local_id, codigo, nombre) values
  ('e1030000-0000-0000-0000-000000000021', 'e1030000-0000-0000-0000-000000000001', 'LEGACY', 'Legacy');
insert into public.pedido (id, local_id, mesa_id, creado_por, estado, creado_en)
  overriding system value values
  (-103, 'e1030000-0000-0000-0000-000000000001', 'e1030000-0000-0000-0000-000000000021',
   'e1030000-0000-0000-0000-000000000011', 'PAGADO', '2026-08-20T10:00:00Z');
insert into public.pago (pedido_id, importe, medio, usuario_id, pagado_en) values
  (-103, 42.35, 'TARJETA', 'e1030000-0000-0000-0000-000000000011', '2026-08-20T11:00:00Z');
commit;
