begin;
delete from public.pago where pedido_id=-50491;
delete from public.historial_estado where pedido_id=-50491;
delete from public.detalle_pedido where pedido_id=-50491;
delete from public.pedido where id=-50491;
delete from public.mesa where id='00000000-0000-0000-0000-00000000e491';
delete from public.producto where id='00000000-0000-0000-0000-00000000e492';
delete from public.categoria where id='00000000-0000-0000-0000-00000000e493';
-- E9 (homologación mínima): la jornada es inmutable y no se borra; se cierra con la transición permitida ABIERTA -> CERRADA.
update public.jornada_operativa set estado = 'CERRADA', cerrada_por = abierta_por, cerrada_en = greatest(now(), abierta_en)
where local_id in ('00000000-0000-0000-0000-00000000e495'::uuid) and estado = 'ABIERTA';
delete from public.perfil_usuario where (id='00000000-0000-0000-0000-00000000e494') and id not in (select abierta_por from public.jornada_operativa union all select cerrada_por from public.jornada_operativa where cerrada_por is not null); -- E9 (homologación mínima): el perfil que abre/cierra una jornada no se borra
delete from auth.users where (id='00000000-0000-0000-0000-00000000e494') and id not in (select id from public.perfil_usuario); -- E9 (homologación mínima): se conserva el usuario de un perfil conservado
delete from public.local where (id='00000000-0000-0000-0000-00000000e495') and id not in (select local_id from public.jornada_operativa); -- E9 (homologación mínima): el local con jornadas (inmutables) se conserva
insert into auth.users(id,aud,role,email,encrypted_password) values('00000000-0000-0000-0000-00000000e494','authenticated','authenticated','h5t04-concurrency@example.invalid','test')
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;
insert into public.local(id,codigo,nombre) values('00000000-0000-0000-0000-00000000e495','H5-T04-C','H5 T04 concurrencia')
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;
insert into public.perfil_usuario(id,local_id,rol_id,nombre) select '00000000-0000-0000-0000-00000000e494','00000000-0000-0000-0000-00000000e495',id,'Caja concurrencia' from public.rol where codigo='CAJA'
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;
-- E9 (homologación mínima): precondición global de E9 — jornada operativa ABIERTA válida para los locales del fixture.
insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
select l.id, (now() at time zone 'America/Lima')::date,
  1 + coalesce((select max(j.numero) from public.jornada_operativa j where j.local_id = l.id and j.fecha_operativa = (now() at time zone 'America/Lima')::date), 0),
  (select p.id from public.perfil_usuario p where p.local_id = l.id order by p.id limit 1), now(), gen_random_uuid()
from public.local l
where l.id in ('00000000-0000-0000-0000-00000000e495'::uuid)
  and exists (select 1 from public.perfil_usuario p where p.local_id = l.id)
  and not exists (select 1 from public.jornada_operativa j where j.local_id = l.id and j.estado = 'ABIERTA');
insert into public.mesa(id,local_id,codigo,nombre,estado) values('00000000-0000-0000-0000-00000000e491','00000000-0000-0000-0000-00000000e495','H5-T04-C','Mesa concurrencia','PENDIENTE_PAGO');
insert into public.categoria(id,local_id,codigo,nombre) values('00000000-0000-0000-0000-00000000e493','00000000-0000-0000-0000-00000000e495','H5-T04-C','Categoría');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values('00000000-0000-0000-0000-00000000e492','00000000-0000-0000-0000-00000000e495','00000000-0000-0000-0000-00000000e493','H5-T04-C','Producto',99);
insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values(-50491,'00000000-0000-0000-0000-00000000e495','00000000-0000-0000-0000-00000000e491','00000000-0000-0000-0000-00000000e494','ENTREGADO');
insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en) overriding system value values(-50491,-50491,'00000000-0000-0000-0000-00000000e492',4,8.25,'LISTO',now());
commit;
