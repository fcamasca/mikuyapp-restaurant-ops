begin;
create function pg_temp.ok(v boolean,m text)returns void language plpgsql as $$begin if not coalesce(v,false) then raise exception '%',m;end if;end$$;

insert into auth.users(id,aud,role,email,encrypted_password) values
('e1099000-0000-0000-0000-000000000101','authenticated','authenticated','delta-a@x','x'),
('e1099000-0000-0000-0000-000000000102','authenticated','authenticated','delta-b@x','x'),
('e1099000-0000-0000-0000-000000000103','authenticated','authenticated','delta-m@x','x'),
('e1099000-0000-0000-0000-000000000104','authenticated','authenticated','delta-o@x','x');
insert into public.local(id,codigo,nombre) values
('e1099000-0000-0000-0000-000000000201','D09','Delta T09'),
('e1099000-0000-0000-0000-000000000202','D09O','Delta otro');
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
select 'e1099000-0000-0000-0000-000000000101'::uuid,'e1099000-0000-0000-0000-000000000201'::uuid,id,'Caja A' from public.rol where codigo='CAJA' union all
select 'e1099000-0000-0000-0000-000000000102'::uuid,'e1099000-0000-0000-0000-000000000201'::uuid,id,'Caja B' from public.rol where codigo='CAJA' union all
select 'e1099000-0000-0000-0000-000000000103'::uuid,'e1099000-0000-0000-0000-000000000201'::uuid,id,'Mozo' from public.rol where codigo='MOZO' union all
select 'e1099000-0000-0000-0000-000000000104'::uuid,'e1099000-0000-0000-0000-000000000202'::uuid,id,'Caja otro' from public.rol where codigo='CAJA';
insert into public.caja(id,local_id,codigo,nombre) values
('e1099000-0000-0000-0000-000000000301','e1099000-0000-0000-0000-000000000201','D1','Delta 1'),
('e1099000-0000-0000-0000-000000000302','e1099000-0000-0000-0000-000000000201','D2','Delta 2'),
('e1099000-0000-0000-0000-000000000303','e1099000-0000-0000-0000-000000000202','DO','Delta otro');
insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values
('e1099000-0000-0000-0000-000000000401','e1099000-0000-0000-0000-000000000301','e1099000-0000-0000-0000-000000000201','e1099000-0000-0000-0000-000000000101',10,'e1099000-0000-0000-0000-000000000601'),
('e1099000-0000-0000-0000-000000000402','e1099000-0000-0000-0000-000000000302','e1099000-0000-0000-0000-000000000201','e1099000-0000-0000-0000-000000000101',0,'e1099000-0000-0000-0000-000000000602'),
('e1099000-0000-0000-0000-000000000403','e1099000-0000-0000-0000-000000000303','e1099000-0000-0000-0000-000000000202','e1099000-0000-0000-0000-000000000104',0,'e1099000-0000-0000-0000-000000000603');
update public.sesion_caja set estado='CERRADA',cerrada_en=now(),cerrada_por='e1099000-0000-0000-0000-000000000101',efectivo_esperado=0,efectivo_contado=0,diferencia=0 where id='e1099000-0000-0000-0000-000000000402';
insert into public.categoria(id,local_id,codigo,nombre) values('e1099000-0000-0000-0000-000000000501','e1099000-0000-0000-0000-000000000201','CAT','Cat');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values('e1099000-0000-0000-0000-000000000502','e1099000-0000-0000-0000-000000000201','e1099000-0000-0000-0000-000000000501','PROD','Producto',100);
do $$declare i int;mid uuid;begin for i in 1..8 loop mid:=('e1099000-0000-0000-0000-'||lpad((700+i)::text,12,'0'))::uuid;
 insert into public.mesa(id,local_id,codigo,nombre,estado)values(mid,'e1099000-0000-0000-0000-000000000201','M'||i,'Mesa '||i,'PENDIENTE_PAGO');
 insert into public.pedido(id,local_id,mesa_id,creado_por,estado)overriding system value values(-10990-i,'e1099000-0000-0000-0000-000000000201',mid,'e1099000-0000-0000-0000-000000000103','ENTREGADO');
 insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en)overriding system value values(-10990-i,-10990-i,'e1099000-0000-0000-0000-000000000502',1,100,'LISTO',now());end loop;end$$;

select pg_temp.ok(not exists(select 1 from public.pago where sesion_caja_id is null and cobro_id is not null),'TP31 legacy sin cabecera fabricada');
set local role authenticated;select set_config('request.jwt.claim.sub','e1099000-0000-0000-0000-000000000102',true);

-- TP32: total de un medio.
select * from public.rpc_registrar_cobro_pedido(-10991,'e1099000-0000-0000-0000-000000000401','TOTAL','[{"medio":"EFECTIVO","importe":100,"propina":2}]','e1099000-0000-0000-0000-000000000801');
-- TP33: un acto, dos medios distintos.
select * from public.rpc_registrar_cobro_pedido(-10992,'e1099000-0000-0000-0000-000000000401','TOTAL','[{"medio":"EFECTIVO","importe":40,"propina":1},{"medio":"YAPE","importe":60,"propina":3}]','e1099000-0000-0000-0000-000000000802');
-- TP34: medio repetido.
select * from public.rpc_registrar_cobro_pedido(-10993,'e1099000-0000-0000-0000-000000000401','TOTAL','[{"medio":"YAPE","importe":45,"propina":0},{"medio":"YAPE","importe":55,"propina":0}]','e1099000-0000-0000-0000-000000000803');
-- TP36: cuatro líneas, medio repetido.
select * from public.rpc_registrar_cobro_pedido(-10994,'e1099000-0000-0000-0000-000000000401','TOTAL','[{"medio":"EFECTIVO","importe":10,"propina":4},{"medio":"YAPE","importe":20,"propina":5},{"medio":"TARJETA","importe":30,"propina":6},{"medio":"TARJETA","importe":40,"propina":7}]','e1099000-0000-0000-0000-000000000804');

-- TP37: faltante, exceso y línea intermedia inválida revierten todo.
do $$begin
 begin perform public.rpc_registrar_cobro_pedido(-10995,'e1099000-0000-0000-0000-000000000401','TOTAL','[{"medio":"YAPE","importe":99,"propina":0}]',gen_random_uuid());raise exception 'faltante';exception when sqlstate '22023' then null;end;
 begin perform public.rpc_registrar_cobro_pedido(-10995,'e1099000-0000-0000-0000-000000000401','TOTAL','[{"medio":"YAPE","importe":101,"propina":0}]',gen_random_uuid());raise exception 'exceso';exception when sqlstate '22023' then null;end;
 begin perform public.rpc_registrar_cobro_pedido(-10995,'e1099000-0000-0000-0000-000000000401','TOTAL','[{"medio":"EFECTIVO","importe":50,"propina":0},{"medio":"INVALIDO","importe":50,"propina":0}]',gen_random_uuid());raise exception 'linea';exception when sqlstate '22023' then null;end;
end$$;

-- TP40 y TP48: parcial multi-medio, retry y acto final separado.
select * from public.rpc_registrar_cobro_pedido(-10995,'e1099000-0000-0000-0000-000000000401','PARCIAL','[{"medio":"EFECTIVO","importe":15,"propina":2},{"medio":"PLIN","importe":25,"propina":3}]','e1099000-0000-0000-0000-000000000805');
select * from public.rpc_registrar_cobro_pedido(-10995,'e1099000-0000-0000-0000-000000000401','PARCIAL','[{"medio":"EFECTIVO","importe":15,"propina":2},{"medio":"PLIN","importe":25,"propina":3}]','e1099000-0000-0000-0000-000000000805');
select * from public.rpc_registrar_cobro_pedido(-10995,'e1099000-0000-0000-0000-000000000401','TOTAL','[{"medio":"TARJETA","importe":60,"propina":0}]','e1099000-0000-0000-0000-000000000806');

-- TP43: sesión cerrada y otro local.
do $$begin
 begin perform public.rpc_registrar_cobro_pedido(-10996,'e1099000-0000-0000-0000-000000000402','PARCIAL','[{"medio":"YAPE","importe":10,"propina":0}]',gen_random_uuid());raise exception 'cerrada';exception when sqlstate '40001' then null;end;
 begin perform public.rpc_registrar_cobro_pedido(-10996,'e1099000-0000-0000-0000-000000000403','PARCIAL','[{"medio":"YAPE","importe":10,"propina":0}]',gen_random_uuid());raise exception 'local';exception when sqlstate '42501' then null;end;
end$$;
reset role;

select pg_temp.ok((select count(*)=1 from public.cobro where pedido_id=-10991) and (select count(*)=1 from public.pago where pedido_id=-10991),'TP32 cabecera y línea');
select pg_temp.ok((select count(*)=1 from public.cobro where pedido_id=-10992) and (select count(*)=2 from public.pago where pedido_id=-10992) and (select count(*)=1 from public.auditoria_caja where pedido_id=-10992 and tipo='PAGO'),'TP33 acto atómico');
select pg_temp.ok((select count(*)=1 from public.cobro where pedido_id=-10993) and (select count(*)=2 and count(distinct medio)=1 from public.pago where pedido_id=-10993),'TP34 repetido');
select pg_temp.ok((select count(*)=1 from public.cobro where pedido_id=-10994) and (select count(*)=4 and sum(importe)=100 and sum(propina)=22 from public.pago where pedido_id=-10994),'TP36 cuatro líneas');
select pg_temp.ok((select count(*)=0 from public.cobro where pedido_id=-10996) and (select count(*)=0 from public.pago where pedido_id=-10996),'TP37/43 sin residuos');
select pg_temp.ok((select count(*)=2 from public.cobro where pedido_id=-10995) and (select count(*)=3 from public.pago where pedido_id=-10995) and (select count(*)=2 from public.auditoria_caja where pedido_id=-10995 and tipo='PAGO'),'TP40/48 retry y documentos lógicos');
select pg_temp.ok((select count(*)=5 from public.historial_estado where pedido_id between -10995 and -10991 and estado_nuevo='PAGADO'),'una transición por pedido completado');
select pg_temp.ok(not exists(select 1 from public.pago p left join public.cobro c on c.id=p.cobro_id where p.cobro_id is not null and c.id is null),'cero líneas huérfanas');
select pg_temp.ok(not exists(select 1 from public.auditoria_caja a left join public.cobro c on c.id=a.cobro_id where a.tipo='PAGO' and c.id is null),'cero auditorías huérfanas');
select pg_temp.ok((select pago_efectivo=165 and propina_efectivo=9 and propina_yape=8 and propina_plin=3 and propina_tarjeta=13 from public.fn_totales_sesion_caja('e1099000-0000-0000-0000-000000000401')),'TP45-47 propina y efectivo');
select 'PASS DELTA E1-T09 SQL TP31-TP37,TP40,TP43,TP45-TP48';
rollback;
