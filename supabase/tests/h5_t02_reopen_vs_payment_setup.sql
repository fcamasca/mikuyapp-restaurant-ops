select set_config('request.jwt.claim.role', 'service_role', false);

insert into auth.users(id,aud,role,email,encrypted_password) values
('00000000-0000-0000-0000-00000000f821','authenticated','authenticated','h5-race-w@example.invalid','test'),
('00000000-0000-0000-0000-00000000f822','authenticated','authenticated','h5-race-c@example.invalid','test')
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;
insert into public.local(id,codigo,nombre) values('00000000-0000-0000-0000-00000000f823','H5-RACE','H5 Race')
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
select '00000000-0000-0000-0000-00000000f821'::uuid,'00000000-0000-0000-0000-00000000f823'::uuid,id,'Mozo' from public.rol where codigo='MOZO'
union all
select '00000000-0000-0000-0000-00000000f822'::uuid,'00000000-0000-0000-0000-00000000f823'::uuid,id,'Caja' from public.rol where codigo='CAJA'
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;
-- E9 (homologación mínima): precondición global de E9 — jornada operativa ABIERTA válida para los locales del fixture.
insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
select l.id, (now() at time zone 'America/Lima')::date,
  1 + coalesce((select max(j.numero) from public.jornada_operativa j where j.local_id = l.id and j.fecha_operativa = (now() at time zone 'America/Lima')::date), 0),
  (select p.id from public.perfil_usuario p where p.local_id = l.id order by p.id limit 1), now(), gen_random_uuid()
from public.local l
where l.id in ('00000000-0000-0000-0000-00000000f823'::uuid)
  and exists (select 1 from public.perfil_usuario p where p.local_id = l.id)
  and not exists (select 1 from public.jornada_operativa j where j.local_id = l.id and j.estado = 'ABIERTA');
insert into public.categoria(id,local_id,codigo,nombre) values('00000000-0000-0000-0000-00000000f824','00000000-0000-0000-0000-00000000f823','H5-RACE','Categoría');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values
('00000000-0000-0000-0000-00000000f825','00000000-0000-0000-0000-00000000f823','00000000-0000-0000-0000-00000000f824','OLD','Anterior',10),
('00000000-0000-0000-0000-00000000f826','00000000-0000-0000-0000-00000000f823','00000000-0000-0000-0000-00000000f824','NEW','Nuevo',8);
insert into public.mesa(id,local_id,codigo,nombre,estado) values('00000000-0000-0000-0000-00000000f827','00000000-0000-0000-0000-00000000f823','H5-RACE','Mesa','PENDIENTE_PAGO');
insert into public.pedido(id,local_id,mesa_id,creado_por,estado,enviado_en) overriding system value values
(-50821,'00000000-0000-0000-0000-00000000f823','00000000-0000-0000-0000-00000000f827','00000000-0000-0000-0000-00000000f821','ENTREGADO',now());
insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en) overriding system value values
(-50821,-50821,'00000000-0000-0000-0000-00000000f825',1,10,'LISTO',now());
