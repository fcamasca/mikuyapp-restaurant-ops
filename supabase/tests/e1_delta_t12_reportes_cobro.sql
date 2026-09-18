begin;
create function pg_temp.ok(v boolean,m text)returns void language plpgsql as $$begin if not coalesce(v,false) then raise exception '%',m;end if;end$$;
insert into auth.users(id,aud,role,email,encrypted_password) values
('e1129000-0000-0000-0000-000000000101','authenticated','authenticated','caja@dt12','x'),
('e1129000-0000-0000-0000-000000000102','authenticated','authenticated','mozo@dt12','x');
insert into public.local(id,codigo,nombre) values('e1129000-0000-0000-0000-000000000201','DT12','Delta T12');
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
select 'e1129000-0000-0000-0000-000000000101'::uuid,'e1129000-0000-0000-0000-000000000201'::uuid,id,'Caja' from public.rol where codigo='CAJA' union all
select 'e1129000-0000-0000-0000-000000000102','e1129000-0000-0000-0000-000000000201',id,'Mozo' from public.rol where codigo='MOZO';
insert into public.caja(id,local_id,codigo,nombre) values('e1129000-0000-0000-0000-000000000301','e1129000-0000-0000-0000-000000000201','C','Caja');
insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values('e1129000-0000-0000-0000-000000000401','e1129000-0000-0000-0000-000000000301','e1129000-0000-0000-0000-000000000201','e1129000-0000-0000-0000-000000000101',0,'e1129000-0000-0000-0000-000000000601');
insert into public.categoria(id,local_id,codigo,nombre) values('e1129000-0000-0000-0000-000000000501','e1129000-0000-0000-0000-000000000201','CAT','Cat');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values('e1129000-0000-0000-0000-000000000502','e1129000-0000-0000-0000-000000000201','e1129000-0000-0000-0000-000000000501','P','Producto',100);
insert into public.mesa(id,local_id,codigo,nombre,estado) values('e1129000-0000-0000-0000-000000000701','e1129000-0000-0000-0000-000000000201','M','Mesa','PENDIENTE_PAGO');
insert into public.pedido(id,local_id,mesa_id,creado_por,estado)overriding system value values(-11291,'e1129000-0000-0000-0000-000000000201','e1129000-0000-0000-0000-000000000701','e1129000-0000-0000-0000-000000000102','ENTREGADO');
insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en)overriding system value values(-11291,-11291,'e1129000-0000-0000-0000-000000000502',1,100,'LISTO',now());
set local role authenticated;select set_config('request.jwt.claim.sub','e1129000-0000-0000-0000-000000000101',true);
select * from public.rpc_registrar_cobro_pedido(-11291,'e1129000-0000-0000-0000-000000000401','TOTAL','[{"medio":"EFECTIVO","importe":40,"propina":4},{"medio":"YAPE","importe":60,"propina":6}]','e1129000-0000-0000-0000-000000000801');
create temporary table report as select * from public.rpc_obtener_reportes_sesion_caja('e1129000-0000-0000-0000-000000000401');
create temporary table daily as select * from public.rpc_obtener_resumen_diario_caja();
reset role;
select pg_temp.ok(exists(select 1 from report where venta_efectivo=40 and venta_yape=60 and propina_efectivo=4 and propina_yape=6 and cantidad_pagos=1 and pagos_parciales=0 and cantidad_pedidos_completados=1),'sesión suma líneas y cuenta un cobro/pedido');
select pg_temp.ok(exists(select 1 from daily where total_vendido=100 and venta_efectivo=40 and venta_yape=60 and total_propinas=10 and cantidad_pagos=1 and pagos_parciales=0 and cantidad_pedidos_completados=1),'diario sin duplicar venta ni pedido');
select 'PASS DELTA E1-T12 reportes por línea y conteos por cobro';
rollback;
