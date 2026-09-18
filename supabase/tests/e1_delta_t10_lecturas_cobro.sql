begin;
create function pg_temp.ok(v boolean,m text)returns void language plpgsql as $$begin if not coalesce(v,false) then raise exception '%',m;end if;end$$;

insert into auth.users(id,aud,role,email,encrypted_password) values
('e1100000-0000-0000-0000-000000000101','authenticated','authenticated','caja@t10','x'),
('e1100000-0000-0000-0000-000000000102','authenticated','authenticated','otro@t10','x'),
('e1100000-0000-0000-0000-000000000103','authenticated','authenticated','mozo@t10','x');
insert into public.local(id,codigo,nombre) values
('e1100000-0000-0000-0000-000000000201','T10A','T10 A'),
('e1100000-0000-0000-0000-000000000202','T10B','T10 B');
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
select 'e1100000-0000-0000-0000-000000000101'::uuid,'e1100000-0000-0000-0000-000000000201'::uuid,id,'Caja legible' from public.rol where codigo='CAJA' union all
select 'e1100000-0000-0000-0000-000000000102','e1100000-0000-0000-0000-000000000202',id,'Caja otro' from public.rol where codigo='CAJA' union all
select 'e1100000-0000-0000-0000-000000000103','e1100000-0000-0000-0000-000000000201',id,'Mozo' from public.rol where codigo='MOZO';
insert into public.caja(id,local_id,codigo,nombre) values('e1100000-0000-0000-0000-000000000301','e1100000-0000-0000-0000-000000000201','C1','Caja');
insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values('e1100000-0000-0000-0000-000000000401','e1100000-0000-0000-0000-000000000301','e1100000-0000-0000-0000-000000000201','e1100000-0000-0000-0000-000000000101',0,'e1100000-0000-0000-0000-000000000601');
insert into public.categoria(id,local_id,codigo,nombre) values('e1100000-0000-0000-0000-000000000501','e1100000-0000-0000-0000-000000000201','CAT','Cat');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values('e1100000-0000-0000-0000-000000000502','e1100000-0000-0000-0000-000000000201','e1100000-0000-0000-0000-000000000501','P','Producto',100);
insert into public.mesa(id,local_id,codigo,nombre,estado) values('e1100000-0000-0000-0000-000000000701','e1100000-0000-0000-0000-000000000201','M1','Mesa','PENDIENTE_PAGO');
insert into public.pedido(id,local_id,mesa_id,creado_por,estado)overriding system value values(-11001,'e1100000-0000-0000-0000-000000000201','e1100000-0000-0000-0000-000000000701','e1100000-0000-0000-0000-000000000103','ENTREGADO');
insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en)overriding system value values(-11001,-11001,'e1100000-0000-0000-0000-000000000502',1,100,'LISTO',now());

set local role authenticated;select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000101',true);
select * from public.rpc_registrar_cobro_pedido(-11001,'e1100000-0000-0000-0000-000000000401','PARCIAL','[{"medio":"EFECTIVO","importe":20,"propina":2},{"medio":"TARJETA","importe":30,"propina":1}]','e1100000-0000-0000-0000-000000000801');
create temporary table got as select * from public.rpc_obtener_cobros_pedido_caja(-11001);
reset role;
select pg_temp.ok((select count(*)=1 from got) and exists(select 1 from got where total_aplicado=50 and propina_total=3 and saldo_anterior=100 and saldo_posterior=50 and actor_nombre='Caja legible' and jsonb_array_length(medios)=2),'lectura agrupa acto y N medios');
select pg_temp.ok((select medios->0->>'medio'='EFECTIVO' and medios->1->>'medio'='TARJETA' from got),'orden, medios y propinas preservados');

set local role authenticated;select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000102',true);
do $$begin begin perform public.rpc_obtener_cobros_pedido_caja(-11001);raise exception 'cruce';exception when sqlstate '42501' then null;end;end$$;
select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000103',true);
do $$begin begin perform public.rpc_obtener_cobros_pedido_caja(-11001);raise exception 'rol';exception when sqlstate '42501' then null;end;end$$;
reset role;
select 'PASS DELTA E1-T10 lectura agrupada, actor y aislamiento';
rollback;
