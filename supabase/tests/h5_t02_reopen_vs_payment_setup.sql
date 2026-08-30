select set_config('request.jwt.claim.role', 'service_role', false);

insert into auth.users(id,aud,role,email,encrypted_password) values
('00000000-0000-0000-0000-00000000f821','authenticated','authenticated','h5-race-w@example.invalid','test'),
('00000000-0000-0000-0000-00000000f822','authenticated','authenticated','h5-race-c@example.invalid','test');
insert into public.local(id,codigo,nombre) values('00000000-0000-0000-0000-00000000f823','H5-RACE','H5 Race');
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
select '00000000-0000-0000-0000-00000000f821'::uuid,'00000000-0000-0000-0000-00000000f823'::uuid,id,'Mozo' from public.rol where codigo='MOZO'
union all
select '00000000-0000-0000-0000-00000000f822'::uuid,'00000000-0000-0000-0000-00000000f823'::uuid,id,'Caja' from public.rol where codigo='CAJA';
insert into public.categoria(id,local_id,codigo,nombre) values('00000000-0000-0000-0000-00000000f824','00000000-0000-0000-0000-00000000f823','H5-RACE','Categoría');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values
('00000000-0000-0000-0000-00000000f825','00000000-0000-0000-0000-00000000f823','00000000-0000-0000-0000-00000000f824','OLD','Anterior',10),
('00000000-0000-0000-0000-00000000f826','00000000-0000-0000-0000-00000000f823','00000000-0000-0000-0000-00000000f824','NEW','Nuevo',8);
insert into public.mesa(id,local_id,codigo,nombre,estado) values('00000000-0000-0000-0000-00000000f827','00000000-0000-0000-0000-00000000f823','H5-RACE','Mesa','PENDIENTE_PAGO');
insert into public.pedido(id,local_id,mesa_id,creado_por,estado,enviado_en) overriding system value values
(-50821,'00000000-0000-0000-0000-00000000f823','00000000-0000-0000-0000-00000000f827','00000000-0000-0000-0000-00000000f821','ENTREGADO',now());
insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en) overriding system value values
(-50821,-50821,'00000000-0000-0000-0000-00000000f825',1,10,'LISTO',now());
