-- E7 — Fixture comprometida para carreras reales (T04 TP10, T05 TP18, T05B TP13).
-- Ejecutar sólo en una base local aislada; limpiar con e7_concurrency_cleanup.sql.
begin;
insert into auth.users (id, aud, role, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000e7c01', 'authenticated', 'authenticated', 'e7c-mozo@example.invalid', 't'),
  ('00000000-0000-0000-0000-0000000e7c02', 'authenticated', 'authenticated', 'e7c-cocina1@example.invalid', 't'),
  ('00000000-0000-0000-0000-0000000e7c03', 'authenticated', 'authenticated', 'e7c-cocina2@example.invalid', 't'),
  ('00000000-0000-0000-0000-0000000e7c04', 'authenticated', 'authenticated', 'e7c-admin@example.invalid', 't')
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;
insert into public.local (id, codigo, nombre) values ('00000000-0000-0000-0000-0000000e7c10', 'E7-CONC', 'Local E7 concurrencia')
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;
insert into public.perfil_usuario (id, local_id, rol_id, nombre)
select '00000000-0000-0000-0000-0000000e7c01'::uuid, '00000000-0000-0000-0000-0000000e7c10'::uuid, id, 'Mozo C' from public.rol where codigo = 'MOZO'
union all select '00000000-0000-0000-0000-0000000e7c02', '00000000-0000-0000-0000-0000000e7c10', id, 'Cocina C1' from public.rol where codigo = 'COCINA'
union all select '00000000-0000-0000-0000-0000000e7c03', '00000000-0000-0000-0000-0000000e7c10', id, 'Cocina C2' from public.rol where codigo = 'COCINA'
union all select '00000000-0000-0000-0000-0000000e7c04', '00000000-0000-0000-0000-0000000e7c10', id, 'Admin C' from public.rol where codigo = 'ADMINISTRADOR'
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;
-- E9 (homologación mínima): precondición global de E9 — jornada operativa ABIERTA válida para los locales del fixture.
insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
select l.id, (now() at time zone 'America/Lima')::date,
  1 + coalesce((select max(j.numero) from public.jornada_operativa j where j.local_id = l.id and j.fecha_operativa = (now() at time zone 'America/Lima')::date), 0),
  (select p.id from public.perfil_usuario p where p.local_id = l.id order by p.id limit 1), now(), gen_random_uuid()
from public.local l
where l.id in ('00000000-0000-0000-0000-0000000e7c10'::uuid)
  and exists (select 1 from public.perfil_usuario p where p.local_id = l.id)
  and not exists (select 1 from public.jornada_operativa j where j.local_id = l.id and j.estado = 'ABIERTA');
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
