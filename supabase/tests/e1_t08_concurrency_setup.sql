begin;
insert into auth.users(id,aud,role,email,encrypted_password) values
  ('e1080000-0000-0000-0000-000000000501','authenticated','authenticated','t08-race-c@example.invalid','x'),
  ('e1080000-0000-0000-0000-000000000502','authenticated','authenticated','t08-race-w@example.invalid','x');
insert into public.local(id,codigo,nombre) values('e1080000-0000-0000-0000-000000000503','T08-RACE','T08 Race');
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
  select 'e1080000-0000-0000-0000-000000000501'::uuid,'e1080000-0000-0000-0000-000000000503'::uuid,id,'Caja' from public.rol where codigo='CAJA'
  union all
  select 'e1080000-0000-0000-0000-000000000502'::uuid,'e1080000-0000-0000-0000-000000000503'::uuid,id,'Mozo' from public.rol where codigo='MOZO';
insert into public.caja(id,local_id,codigo,nombre) values
  ('e1080000-0000-0000-0000-000000000504','e1080000-0000-0000-0000-000000000503','T08-RACE','Caja');
insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values
  ('e1080000-0000-0000-0000-000000000505','e1080000-0000-0000-0000-000000000504',
   'e1080000-0000-0000-0000-000000000503','e1080000-0000-0000-0000-000000000501',0,
   'e1080000-0000-0000-0000-000000000506');
insert into public.categoria(id,local_id,codigo,nombre) values
  ('e1080000-0000-0000-0000-000000000507','e1080000-0000-0000-0000-000000000503','T08-RACE','Categoría');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values
  ('e1080000-0000-0000-0000-000000000508','e1080000-0000-0000-0000-000000000503',
   'e1080000-0000-0000-0000-000000000507','T08-RACE','Producto',20);
insert into public.mesa(id,local_id,codigo,nombre,estado) values
  ('e1080000-0000-0000-0000-000000000509','e1080000-0000-0000-0000-000000000503','T08-RACE','Mesa','PENDIENTE_PAGO');
insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values
  (-10809,'e1080000-0000-0000-0000-000000000503','e1080000-0000-0000-0000-000000000509',
   'e1080000-0000-0000-0000-000000000502','ENTREGADO');
insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en)
  overriding system value values
  (-10809,-10809,'e1080000-0000-0000-0000-000000000508',2,15,'LISTO',now());
commit;
