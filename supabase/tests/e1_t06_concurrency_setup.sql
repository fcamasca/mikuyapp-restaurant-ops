begin;
insert into auth.users(id,aud,role,email,encrypted_password) values
 ('e1065000-0000-0000-0000-000000000101','authenticated','authenticated','t06-race-c@example.invalid','x'),
 ('e1065000-0000-0000-0000-000000000102','authenticated','authenticated','t06-race-a@example.invalid','x'),
 ('e1065000-0000-0000-0000-000000000103','authenticated','authenticated','t06-race-w@example.invalid','x');
insert into public.local(id,codigo,nombre) values('e1065000-0000-0000-0000-000000000201','T06-RACE','T06 Race');
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
 select 'e1065000-0000-0000-0000-000000000101'::uuid,'e1065000-0000-0000-0000-000000000201'::uuid,id,'Caja' from public.rol where codigo='CAJA' union all
 select 'e1065000-0000-0000-0000-000000000102'::uuid,'e1065000-0000-0000-0000-000000000201'::uuid,id,'Admin' from public.rol where codigo='ADMINISTRADOR' union all
 select 'e1065000-0000-0000-0000-000000000103'::uuid,'e1065000-0000-0000-0000-000000000201'::uuid,id,'Mozo' from public.rol where codigo='MOZO';
insert into public.caja(id,local_id,codigo,nombre) values('e1065000-0000-0000-0000-000000000301','e1065000-0000-0000-0000-000000000201','T06-RACE','Caja');
insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values
 ('e1065000-0000-0000-0000-000000000401','e1065000-0000-0000-0000-000000000301','e1065000-0000-0000-0000-000000000201','e1065000-0000-0000-0000-000000000101',0,'e1065000-0000-0000-0000-000000000601');
insert into public.categoria(id,local_id,codigo,nombre) values('e1065000-0000-0000-0000-000000000501','e1065000-0000-0000-0000-000000000201','T06-RACE','Categoría');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values
 ('e1065000-0000-0000-0000-000000000502','e1065000-0000-0000-0000-000000000201','e1065000-0000-0000-0000-000000000501','T06-RACE','Producto',50);
insert into public.mesa(id,local_id,codigo,nombre,estado) values
 ('e1065000-0000-0000-0000-000000000503','e1065000-0000-0000-0000-000000000201','T06-RACE','Mesa','PENDIENTE_PAGO');
insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values
 (-10659,'e1065000-0000-0000-0000-000000000201','e1065000-0000-0000-0000-000000000503','e1065000-0000-0000-0000-000000000103','ENTREGADO');
insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en) overriding system value values
 (-10659,-10659,'e1065000-0000-0000-0000-000000000502',2,50,'LISTO',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','e1065000-0000-0000-0000-000000000101',true);
select public.rpc_solicitar_descuento_pedido(-10659,20,null,'Carrera autorizada','e1065000-0000-0000-0000-000000000701');
commit;
