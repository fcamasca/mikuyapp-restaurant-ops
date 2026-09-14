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
insert into public.mesa (id, local_id, codigo, nombre) values
  ('e1030000-0000-0000-0000-000000000021', 'e1030000-0000-0000-0000-000000000001', 'LEGACY', 'Legacy');
insert into public.pedido (id, local_id, mesa_id, creado_por, estado, creado_en)
  overriding system value values
  (-103, 'e1030000-0000-0000-0000-000000000001', 'e1030000-0000-0000-0000-000000000021',
   'e1030000-0000-0000-0000-000000000011', 'PAGADO', '2026-08-20T10:00:00Z');
insert into public.pago (pedido_id, importe, medio, usuario_id, pagado_en) values
  (-103, 42.35, 'TARJETA', 'e1030000-0000-0000-0000-000000000011', '2026-08-20T11:00:00Z');
commit;
