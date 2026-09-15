begin;
insert into auth.users(id,aud,role,email,encrypted_password) values
 ('e1075000-0000-0000-0000-000000000101','authenticated','authenticated','t07-race-a@example.invalid','x'),
 ('e1075000-0000-0000-0000-000000000102','authenticated','authenticated','t07-race-c@example.invalid','x'),
 ('e1075000-0000-0000-0000-000000000103','authenticated','authenticated','t07-race-w@example.invalid','x');
insert into public.local(id,codigo,nombre) values('e1075000-0000-0000-0000-000000000201','T07-RACE','T07 Race');
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
 select 'e1075000-0000-0000-0000-000000000101'::uuid,'e1075000-0000-0000-0000-000000000201'::uuid,id,'Admin' from public.rol where codigo='ADMINISTRADOR' union all
 select 'e1075000-0000-0000-0000-000000000102'::uuid,'e1075000-0000-0000-0000-000000000201'::uuid,id,'Caja' from public.rol where codigo='CAJA' union all
 select 'e1075000-0000-0000-0000-000000000103'::uuid,'e1075000-0000-0000-0000-000000000201'::uuid,id,'Mozo' from public.rol where codigo='MOZO';
insert into public.caja(id,local_id,codigo,nombre) values('e1075000-0000-0000-0000-000000000301','e1075000-0000-0000-0000-000000000201','T07-RACE','Caja');
insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values
 ('e1075000-0000-0000-0000-000000000401','e1075000-0000-0000-0000-000000000301','e1075000-0000-0000-0000-000000000201','e1075000-0000-0000-0000-000000000102',0,'e1075000-0000-0000-0000-000000000601');
insert into public.categoria(id,local_id,codigo,nombre) values('e1075000-0000-0000-0000-000000000501','e1075000-0000-0000-0000-000000000201','T07-RACE','Categoría');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values
 ('e1075000-0000-0000-0000-000000000502','e1075000-0000-0000-0000-000000000201','e1075000-0000-0000-0000-000000000501','T07-RACE','Producto',20);
insert into public.mesa(id,local_id,codigo,nombre,estado) values
 ('e1075000-0000-0000-0000-000000000503','e1075000-0000-0000-0000-000000000201','T07-RACE','Mesa','PENDIENTE_PAGO');
insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values
 (-10759,'e1075000-0000-0000-0000-000000000201','e1075000-0000-0000-0000-000000000503','e1075000-0000-0000-0000-000000000103','ENTREGADO');
insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en) overriding system value values
 (-10759,-10759,'e1075000-0000-0000-0000-000000000502',2,20,'LISTO',now());
commit;
