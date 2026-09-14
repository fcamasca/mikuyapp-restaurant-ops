-- Sólo la base aislada creada por testE1T04.mjs. Se ejecuta DESPUÉS de T03,
-- ANTES de T04 para probar que esta migración conserva datos preexistentes.
begin;
insert into public.local(id,codigo,nombre,activo) values
  ('e1040000-0000-0000-0000-000000000001','E1-T04-A','Local A',true),
  ('e1040000-0000-0000-0000-000000000002','E1-T04-B','Local B',true),
  ('e1040000-0000-0000-0000-000000000003','E1-T04-I','Local inactivo',false);
insert into auth.users(id,aud,role,email,encrypted_password)
select ('e1040000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  'authenticated','authenticated','e1-t04-' || n || '@example.invalid','test'
from generate_series(11,19) n;
insert into public.perfil_usuario(id,local_id,rol_id,nombre,activo)
select ('e1040000-0000-0000-0000-' || lpad(f.n::text,12,'0'))::uuid,
  ('e1040000-0000-0000-0000-' || lpad(f.local_n::text,12,'0'))::uuid,
  r.id,f.nombre,f.activo
from (values
  (11,1,'CAJA','Cajero A',true), (12,1,'CAJA','Cajero B',true),
  (13,1,'ADMINISTRADOR','Admin',true), (14,1,'MOZO','Mozo',true),
  (15,1,'COCINA','Cocina',true), (16,2,'CAJA','Caja otro local',true),
  (17,1,'CAJA','Perfil inactivo',false), (18,3,'CAJA','Local inactivo',true)
) f(n,local_n,rol,nombre,activo) join public.rol r on r.codigo = f.rol;
insert into public.caja(id,local_id,codigo,nombre,activo)
select ('e1040000-0000-0000-0000-' || lpad(f.n::text,12,'0'))::uuid,
  ('e1040000-0000-0000-0000-' || lpad(f.local_n::text,12,'0'))::uuid,
  f.codigo,f.codigo,f.activo
from (values (101,1,'CAJA-A',true),(102,1,'CAJA-A2',true),(103,1,'INACTIVA',false),
  (104,2,'CAJA-B',true),(105,1,'ROLLBACK',true),(106,1,'RACE-DIFF',true),
  (107,1,'RACE-SAME',true),(108,1,'RACE-23505',true)) f(n,local_n,codigo,activo);
-- Fixture cerrado administrativamente como postgres. NO implementa cierre T05.
insert into public.sesion_caja(id,caja_id,local_id,abierta_por,abierta_en,monto_inicial,idempotency_key,
  estado,cerrada_por,cerrada_en,efectivo_esperado,efectivo_contado,diferencia)
values ('e1040000-0000-0000-0000-000000000201','e1040000-0000-0000-0000-000000000101',
  'e1040000-0000-0000-0000-000000000001','e1040000-0000-0000-0000-000000000011',now()-interval '2 days',10,
  'e1040000-0000-0000-0000-000000000701','CERRADA','e1040000-0000-0000-0000-000000000012',now()-interval '1 day',10,10,0);
commit;
