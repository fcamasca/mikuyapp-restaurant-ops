begin;
insert into auth.users(id,aud,role,email,encrypted_password) values
('e1095000-0000-0000-0000-000000000101','authenticated','authenticated','t09-race-a@x','x'),
('e1095000-0000-0000-0000-000000000102','authenticated','authenticated','t09-race-b@x','x'),
('e1095000-0000-0000-0000-000000000103','authenticated','authenticated','t09-race-admin@x','x'),
('e1095000-0000-0000-0000-000000000104','authenticated','authenticated','t09-race-mozo@x','x');
insert into public.local(id,codigo,nombre)values('e1095000-0000-0000-0000-000000000201','T09-R','T09 Race');
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
select 'e1095000-0000-0000-0000-000000000101'::uuid,'e1095000-0000-0000-0000-000000000201'::uuid,id,'Caja A' from public.rol where codigo='CAJA' union all
select 'e1095000-0000-0000-0000-000000000102'::uuid,'e1095000-0000-0000-0000-000000000201'::uuid,id,'Caja B' from public.rol where codigo='CAJA' union all
select 'e1095000-0000-0000-0000-000000000103'::uuid,'e1095000-0000-0000-0000-000000000201'::uuid,id,'Admin' from public.rol where codigo='ADMINISTRADOR' union all
select 'e1095000-0000-0000-0000-000000000104'::uuid,'e1095000-0000-0000-0000-000000000201'::uuid,id,'Mozo' from public.rol where codigo='MOZO';
insert into public.caja(id,local_id,codigo,nombre)values
('e1095000-0000-0000-0000-000000000301','e1095000-0000-0000-0000-000000000201','R1','R1'),
('e1095000-0000-0000-0000-000000000302','e1095000-0000-0000-0000-000000000201','R2','R2'),
('e1095000-0000-0000-0000-000000000303','e1095000-0000-0000-0000-000000000201','R3','R3');
insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key)values
('e1095000-0000-0000-0000-000000000401','e1095000-0000-0000-0000-000000000301','e1095000-0000-0000-0000-000000000201','e1095000-0000-0000-0000-000000000101',0,'e1095000-0000-0000-0000-000000000601'),
('e1095000-0000-0000-0000-000000000402','e1095000-0000-0000-0000-000000000302','e1095000-0000-0000-0000-000000000201','e1095000-0000-0000-0000-000000000101',0,'e1095000-0000-0000-0000-000000000602'),
('e1095000-0000-0000-0000-000000000403','e1095000-0000-0000-0000-000000000303','e1095000-0000-0000-0000-000000000201','e1095000-0000-0000-0000-000000000101',0,'e1095000-0000-0000-0000-000000000603');
insert into public.categoria(id,local_id,codigo,nombre)values('e1095000-0000-0000-0000-000000000501','e1095000-0000-0000-0000-000000000201','CAT','Cat');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio)values('e1095000-0000-0000-0000-000000000502','e1095000-0000-0000-0000-000000000201','e1095000-0000-0000-0000-000000000501','P','P',100);
do $$declare i int;mid uuid;begin for i in 1..5 loop mid:=('e1095000-0000-0000-0000-'||lpad((700+i)::text,12,'0'))::uuid;
insert into public.mesa(id,local_id,codigo,nombre,estado)values(mid,'e1095000-0000-0000-0000-000000000201','R'||i,'R'||i,'PENDIENTE_PAGO');
insert into public.pedido(id,local_id,mesa_id,creado_por,estado)overriding system value values(-10950-i,'e1095000-0000-0000-0000-000000000201',mid,'e1095000-0000-0000-0000-000000000104','ENTREGADO');
insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en)overriding system value values(-10950-i,-10950-i,'e1095000-0000-0000-0000-000000000502',1,100,'LISTO',now());end loop;end$$;
commit;
