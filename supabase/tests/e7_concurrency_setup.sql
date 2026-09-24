-- E7 — Fixture comprometida para carreras reales (T04 TP10, T05 TP18, T05B TP13).
-- Ejecutar sólo en una base local aislada; limpiar con e7_concurrency_cleanup.sql.
begin;
insert into auth.users (id, aud, role, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000e7c01', 'authenticated', 'authenticated', 'e7c-mozo@example.invalid', 't'),
  ('00000000-0000-0000-0000-0000000e7c02', 'authenticated', 'authenticated', 'e7c-cocina1@example.invalid', 't'),
  ('00000000-0000-0000-0000-0000000e7c03', 'authenticated', 'authenticated', 'e7c-cocina2@example.invalid', 't'),
  ('00000000-0000-0000-0000-0000000e7c04', 'authenticated', 'authenticated', 'e7c-admin@example.invalid', 't');
insert into public.local (id, codigo, nombre) values ('00000000-0000-0000-0000-0000000e7c10', 'E7-CONC', 'Local E7 concurrencia');
insert into public.perfil_usuario (id, local_id, rol_id, nombre)
select '00000000-0000-0000-0000-0000000e7c01'::uuid, '00000000-0000-0000-0000-0000000e7c10'::uuid, id, 'Mozo C' from public.rol where codigo = 'MOZO'
union all select '00000000-0000-0000-0000-0000000e7c02', '00000000-0000-0000-0000-0000000e7c10', id, 'Cocina C1' from public.rol where codigo = 'COCINA'
union all select '00000000-0000-0000-0000-0000000e7c03', '00000000-0000-0000-0000-0000000e7c10', id, 'Cocina C2' from public.rol where codigo = 'COCINA'
union all select '00000000-0000-0000-0000-0000000e7c04', '00000000-0000-0000-0000-0000000e7c10', id, 'Admin C' from public.rol where codigo = 'ADMINISTRADOR';
insert into public.mesa (id, local_id, codigo, nombre)
select ('00000000-0000-0000-0000-0000000e7d' || lpad(g::text, 2, '0'))::uuid,
       '00000000-0000-0000-0000-0000000e7c10', 'EC-' || g, 'Mesa C' || g
from generate_series(1, 12) g;
insert into public.categoria (id, local_id, codigo, nombre)
values ('00000000-0000-0000-0000-0000000e7c20', '00000000-0000-0000-0000-0000000e7c10', 'EC', 'Cat C');
insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
  ('00000000-0000-0000-0000-0000000e7c21', '00000000-0000-0000-0000-0000000e7c10', '00000000-0000-0000-0000-0000000e7c20', 'EC-CEV', 'Ceviche C', 30, true),
  ('00000000-0000-0000-0000-0000000e7c22', '00000000-0000-0000-0000-0000000e7c10', '00000000-0000-0000-0000-0000000e7c20', 'EC-CHI', 'Chicha C', 8, false);
commit;
