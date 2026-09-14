begin;
insert into auth.users(id,aud,role,email,encrypted_password) values
  ('e1055000-0000-0000-0000-000000000101','authenticated','authenticated','t05-race-a@example.invalid','x'),
  ('e1055000-0000-0000-0000-000000000102','authenticated','authenticated','t05-race-b@example.invalid','x'),
  ('e1055000-0000-0000-0000-000000000103','authenticated','authenticated','t05-race-w@example.invalid','x');
insert into public.local(id,codigo,nombre) values
  ('e1055000-0000-0000-0000-000000000201','T05-RACE','T05 Race');
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
  select 'e1055000-0000-0000-0000-000000000101'::uuid,'e1055000-0000-0000-0000-000000000201'::uuid,id,'Caja A' from public.rol where codigo='CAJA'
  union all
  select 'e1055000-0000-0000-0000-000000000102'::uuid,'e1055000-0000-0000-0000-000000000201'::uuid,id,'Caja B' from public.rol where codigo='CAJA'
  union all
  select 'e1055000-0000-0000-0000-000000000103'::uuid,'e1055000-0000-0000-0000-000000000201'::uuid,id,'Mozo' from public.rol where codigo='MOZO';
insert into public.caja(id,local_id,codigo,nombre) values
  ('e1055000-0000-0000-0000-000000000301','e1055000-0000-0000-0000-000000000201','RACE-CLOSE','Doble cierre'),
  ('e1055000-0000-0000-0000-000000000302','e1055000-0000-0000-0000-000000000201','RACE-MOVE','Cierre movimiento'),
  ('e1055000-0000-0000-0000-000000000303','e1055000-0000-0000-0000-000000000201','RACE-PAY','Cierre cobro');
insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values
  ('e1055000-0000-0000-0000-000000000401','e1055000-0000-0000-0000-000000000301','e1055000-0000-0000-0000-000000000201','e1055000-0000-0000-0000-000000000101',10,'e1055000-0000-0000-0000-000000000601'),
  ('e1055000-0000-0000-0000-000000000402','e1055000-0000-0000-0000-000000000302','e1055000-0000-0000-0000-000000000201','e1055000-0000-0000-0000-000000000101',20,'e1055000-0000-0000-0000-000000000602'),
  ('e1055000-0000-0000-0000-000000000403','e1055000-0000-0000-0000-000000000303','e1055000-0000-0000-0000-000000000201','e1055000-0000-0000-0000-000000000101',30,'e1055000-0000-0000-0000-000000000603');
insert into public.categoria(id,local_id,codigo,nombre) values
  ('e1055000-0000-0000-0000-000000000501','e1055000-0000-0000-0000-000000000201','T05-RACE','Categoría');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values
  ('e1055000-0000-0000-0000-000000000502','e1055000-0000-0000-0000-000000000201','e1055000-0000-0000-0000-000000000501','T05-RACE','Producto',15);
insert into public.mesa(id,local_id,codigo,nombre,estado) values
  ('e1055000-0000-0000-0000-000000000503','e1055000-0000-0000-0000-000000000201','T05-RACE','Mesa','PENDIENTE_PAGO');
insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values
  (-10559,'e1055000-0000-0000-0000-000000000201','e1055000-0000-0000-0000-000000000503','e1055000-0000-0000-0000-000000000103','ENTREGADO');
insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en)
  overriding system value values
  (-10559,-10559,'e1055000-0000-0000-0000-000000000502',2,15,'LISTO',now());
commit;
