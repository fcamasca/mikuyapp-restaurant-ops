begin;
create function pg_temp.ok(v boolean,m text)returns void language plpgsql as $$begin if not coalesce(v,false) then raise exception '%',m;end if;end$$;
insert into auth.users(id,aud,role,email,encrypted_password) values
('e1090000-0000-0000-0000-000000000101','authenticated','authenticated','t09-a@x','x'),
('e1090000-0000-0000-0000-000000000102','authenticated','authenticated','t09-b@x','x'),
('e1090000-0000-0000-0000-000000000103','authenticated','authenticated','t09-m@x','x'),
('e1090000-0000-0000-0000-000000000104','authenticated','authenticated','t09-o@x','x');
insert into public.local(id,codigo,nombre) values
('e1090000-0000-0000-0000-000000000201','T09','T09'),('e1090000-0000-0000-0000-000000000202','T09-O','Otro');
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
select 'e1090000-0000-0000-0000-000000000101'::uuid,'e1090000-0000-0000-0000-000000000201'::uuid,id,'Caja A' from public.rol where codigo='CAJA' union all
select 'e1090000-0000-0000-0000-000000000102'::uuid,'e1090000-0000-0000-0000-000000000201'::uuid,id,'Caja B' from public.rol where codigo='CAJA' union all
select 'e1090000-0000-0000-0000-000000000103'::uuid,'e1090000-0000-0000-0000-000000000201'::uuid,id,'Mozo' from public.rol where codigo='MOZO' union all
select 'e1090000-0000-0000-0000-000000000104'::uuid,'e1090000-0000-0000-0000-000000000202'::uuid,id,'Otro' from public.rol where codigo='CAJA';
insert into public.caja(id,local_id,codigo,nombre) values
('e1090000-0000-0000-0000-000000000301','e1090000-0000-0000-0000-000000000201','C1','Caja 1'),
('e1090000-0000-0000-0000-000000000302','e1090000-0000-0000-0000-000000000201','C2','Caja 2'),
('e1090000-0000-0000-0000-000000000303','e1090000-0000-0000-0000-000000000202','CO','Caja O');
insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values
('e1090000-0000-0000-0000-000000000401','e1090000-0000-0000-0000-000000000301','e1090000-0000-0000-0000-000000000201','e1090000-0000-0000-0000-000000000101',0,'e1090000-0000-0000-0000-000000000601'),
('e1090000-0000-0000-0000-000000000402','e1090000-0000-0000-0000-000000000302','e1090000-0000-0000-0000-000000000201','e1090000-0000-0000-0000-000000000101',0,'e1090000-0000-0000-0000-000000000602'),
('e1090000-0000-0000-0000-000000000403','e1090000-0000-0000-0000-000000000303','e1090000-0000-0000-0000-000000000202','e1090000-0000-0000-0000-000000000104',0,'e1090000-0000-0000-0000-000000000603');
update public.sesion_caja set estado='CERRADA',cerrada_en=now(),cerrada_por='e1090000-0000-0000-0000-000000000101',efectivo_esperado=0,efectivo_contado=0,diferencia=0 where id='e1090000-0000-0000-0000-000000000402';
insert into public.categoria(id,local_id,codigo,nombre) values('e1090000-0000-0000-0000-000000000501','e1090000-0000-0000-0000-000000000201','CAT','Cat');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values('e1090000-0000-0000-0000-000000000502','e1090000-0000-0000-0000-000000000201','e1090000-0000-0000-0000-000000000501','PROD','Producto',100);
do $$declare i int;mid uuid;begin for i in 1..9 loop mid:=('e1090000-0000-0000-0000-'||lpad((700+i)::text,12,'0'))::uuid;
 insert into public.mesa(id,local_id,codigo,nombre,estado)values(mid,'e1090000-0000-0000-0000-000000000201','M'||i,'Mesa '||i,'PENDIENTE_PAGO');
 insert into public.pedido(id,local_id,mesa_id,creado_por,estado)overriding system value values(-10900-i,'e1090000-0000-0000-0000-000000000201',mid,'e1090000-0000-0000-0000-000000000103','ENTREGADO');
 insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en)overriding system value values(-10900-i,-10900-i,'e1090000-0000-0000-0000-000000000502',1,100,'LISTO',now());end loop;end$$;
set local role authenticated;select set_config('request.jwt.claim.sub','e1090000-0000-0000-0000-000000000102',true);
-- TP32 total y actor B sobre sesión abierta por A.
select * from public.rpc_registrar_pago_pedido_v2(-10901,'e1090000-0000-0000-0000-000000000401',100,'EFECTIVO',0,'e1090000-0000-0000-0000-000000000801');
reset role;
select pg_temp.ok((select estado='PAGADO' from public.pedido where id=-10901) and (select estado='LIBRE' from public.mesa where id='e1090000-0000-0000-0000-000000000701'),'TP32');
set local role authenticated;select set_config('request.jwt.claim.sub','e1090000-0000-0000-0000-000000000102',true);
-- TP33, TP34 y TP36.
select * from public.rpc_registrar_pago_pedido_v2(-10902,'e1090000-0000-0000-0000-000000000401',40,'EFECTIVO',1,'e1090000-0000-0000-0000-000000000802');
select * from public.rpc_registrar_pago_pedido_v2(-10902,'e1090000-0000-0000-0000-000000000401',60,'YAPE',2,'e1090000-0000-0000-0000-000000000803');
select * from public.rpc_registrar_pago_pedido_v2(-10903,'e1090000-0000-0000-0000-000000000401',50,'TARJETA',0,'e1090000-0000-0000-0000-000000000804');
select * from public.rpc_registrar_pago_pedido_v2(-10903,'e1090000-0000-0000-0000-000000000401',50,'TARJETA',0,'e1090000-0000-0000-0000-000000000805');
select * from public.rpc_registrar_pago_pedido_v2(-10904,'e1090000-0000-0000-0000-000000000401',10,'EFECTIVO',3,'e1090000-0000-0000-0000-000000000806');
select * from public.rpc_registrar_pago_pedido_v2(-10904,'e1090000-0000-0000-0000-000000000401',20,'YAPE',4,'e1090000-0000-0000-0000-000000000807');
select * from public.rpc_registrar_pago_pedido_v2(-10904,'e1090000-0000-0000-0000-000000000401',30,'TARJETA',5,'e1090000-0000-0000-0000-000000000808');
select * from public.rpc_registrar_pago_pedido_v2(-10904,'e1090000-0000-0000-0000-000000000401',40,'TARJETA',6,'e1090000-0000-0000-0000-000000000809');
reset role;
select pg_temp.ok((select count(*)=4 and sum(importe)=100 and sum(propina)=18 from public.pago where pedido_id=-10904),'TP36');
set local role authenticated;select set_config('request.jwt.claim.sub','e1090000-0000-0000-0000-000000000102',true);
-- TP37 inválidos.
do $$begin begin perform public.rpc_registrar_pago_pedido_v2(-10905,'e1090000-0000-0000-0000-000000000401',0,'EFECTIVO',0,gen_random_uuid());raise exception 'cero';exception when sqlstate '22023' then null;end;
begin perform public.rpc_registrar_pago_pedido_v2(-10905,'e1090000-0000-0000-0000-000000000401',-1,'EFECTIVO',0,gen_random_uuid());raise exception 'neg';exception when sqlstate '22023' then null;end;
begin perform public.rpc_registrar_pago_pedido_v2(-10905,'e1090000-0000-0000-0000-000000000401',101,'EFECTIVO',0,gen_random_uuid());raise exception 'over';exception when sqlstate '22023' then null;end;end$$;
-- TP40 idempotencia.
select * from public.rpc_registrar_pago_pedido_v2(-10905,'e1090000-0000-0000-0000-000000000401',20,'YAPE',0,'e1090000-0000-0000-0000-000000000810');
select * from public.rpc_registrar_pago_pedido_v2(-10905,'e1090000-0000-0000-0000-000000000401',20,'YAPE',0,'e1090000-0000-0000-0000-000000000810');
reset role;
select pg_temp.ok((select count(*)=1 from public.pago where pedido_id=-10905) and (select count(*)=1 from public.auditoria_caja where pedido_id=-10905 and tipo='PAGO'),'TP40');
set local role authenticated;select set_config('request.jwt.claim.sub','e1090000-0000-0000-0000-000000000102',true);
-- TP42 mutación después de parcial.
select set_config('request.jwt.claim.sub','e1090000-0000-0000-0000-000000000103',true);
do $$begin begin perform public.agregar_detalle_pedido(-10905,'e1090000-0000-0000-0000-000000000502',1,null);raise exception 'mutó';exception when sqlstate '40001' then null;end;end$$;
select set_config('request.jwt.claim.sub','e1090000-0000-0000-0000-000000000102',true);
-- TP43 sesión cerrada y otro local.
do $$begin begin perform public.rpc_registrar_pago_pedido_v2(-10906,'e1090000-0000-0000-0000-000000000402',10,'YAPE',0,gen_random_uuid());raise exception 'cerrada';exception when sqlstate '40001' then null;end;
begin perform public.rpc_registrar_pago_pedido_v2(-10906,'e1090000-0000-0000-0000-000000000403',10,'YAPE',0,gen_random_uuid());raise exception 'otro local';exception when sqlstate '42501' then null;end;end$$;
-- TP41: antes de todo pago H5 conserva reapertura mediante nuevo detalle.
select set_config('request.jwt.claim.sub','e1090000-0000-0000-0000-000000000103',true);
select * from public.agregar_detalle_pedido(-10909,'e1090000-0000-0000-0000-000000000502',1,null);
reset role;
select pg_temp.ok((select estado='ABIERTO' from public.pedido where id=-10909) and not exists(select 1 from public.pago where pedido_id=-10909),'TP41');
set local role authenticated;select set_config('request.jwt.claim.sub','e1090000-0000-0000-0000-000000000102',true);
-- TP45-47: propina separada y efectivo esperado sólo efectivo.
reset role;
select pg_temp.ok((select pago_efectivo=150 and propina_efectivo=4 and propina_yape=6 and propina_tarjeta=11 from public.fn_totales_sesion_caja('e1090000-0000-0000-0000-000000000401')),'TP45-47');
set local role authenticated;select set_config('request.jwt.claim.sub','e1090000-0000-0000-0000-000000000102',true);
do $$begin begin perform public.rpc_registrar_pago_pedido_v2(-10906,'e1090000-0000-0000-0000-000000000401',10,'YAPE',-1,gen_random_uuid());raise exception 'propina';exception when sqlstate '22023' then null;end;end$$;
reset role;
select pg_temp.ok((select count(*)=10 from public.auditoria_caja where tipo='PAGO') and not exists(select 1 from public.auditoria_caja a left join public.pago p on p.id=a.pago_id where a.tipo='PAGO' and p.id is null),'auditoría pago');
select 'PASS E1-T09 SQL: TP32-TP37,TP40,TP42-TP43,TP45-TP47';
rollback;
