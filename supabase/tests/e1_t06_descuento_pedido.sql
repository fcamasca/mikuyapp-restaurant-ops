begin;
create function pg_temp.t06_user(p uuid) returns void language plpgsql set search_path=pg_catalog as $$
begin perform set_config('request.jwt.claim.sub',coalesce(p::text,''),true);perform set_config('request.jwt.claim.role','authenticated',true);end $$;

do $t$
declare
  caja_user uuid:='e1060000-0000-0000-0000-000000000101';admin_user uuid:='e1060000-0000-0000-0000-000000000102';
  waiter uuid:='e1060000-0000-0000-0000-000000000103';local_id uuid:='e1060000-0000-0000-0000-000000000201';
  box_id uuid:='e1060000-0000-0000-0000-000000000301';session_id uuid:='e1060000-0000-0000-0000-000000000401';
  category_id uuid:='e1060000-0000-0000-0000-000000000501';product_id uuid:='e1060000-0000-0000-0000-000000000502';
  r jsonb;did uuid;checks int:=0;subtotal numeric;discount numeric;net numeric;
begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='pedido'
    and column_name in ('subtotal_snapshot','descuento_snapshot','total_neto_snapshot')) then raise exception 'TP19 snapshots duplicados en pedido';end if;
  if pg_catalog.has_function_privilege('anon','public.rpc_solicitar_descuento_pedido(bigint,numeric,numeric,text,uuid)','EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated','public.rpc_decidir_descuento_pedido(bigint,text,text,uuid)','EXECUTE')
    or pg_catalog.has_function_privilege('authenticated','public.fn_resolver_total_pedido(bigint)','EXECUTE') then raise exception 'grants T06 inválidos';end if;
  checks:=checks+1;
  insert into auth.users(id,aud,role,email,encrypted_password) values
    (caja_user,'authenticated','authenticated','t06-c@example.invalid','x'),
    (admin_user,'authenticated','authenticated','t06-a@example.invalid','x'),
    (waiter,'authenticated','authenticated','t06-w@example.invalid','x');
  insert into public.local(id,codigo,nombre) values(local_id,'T06','Local T06');
  insert into public.perfil_usuario(id,local_id,rol_id,nombre)
    select caja_user,local_id,id,'Caja' from public.rol where codigo='CAJA' union all
    select admin_user,local_id,id,'Admin' from public.rol where codigo='ADMINISTRADOR' union all
    select waiter,local_id,id,'Mozo' from public.rol where codigo='MOZO';
  insert into public.caja(id,local_id,codigo,nombre) values(box_id,local_id,'T06','Caja T06');
  insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key)
    values(session_id,box_id,local_id,caja_user,0,'e1060000-0000-0000-0000-000000000601');
  insert into public.categoria(id,local_id,codigo,nombre) values(category_id,local_id,'T06','Categoría');
  insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values(product_id,local_id,category_id,'T06','Producto',50);
  insert into public.mesa(id,local_id,codigo,nombre,estado)
  select ('e1060000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,local_id,'T'||n,'Mesa','PENDIENTE_PAGO' from generate_series(701,707)n;
  insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value
  select -10600-n,local_id,('e1060000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,waiter,'ENTREGADO' from generate_series(701,707)n;
  insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en) overriding system value
  select -10600-n,-10600-n,product_id,case when n=702 then 3 else 2 end,
    case when n=702 then 33.33 else 50 end,'LISTO',now() from generate_series(701,707)n;

  perform pg_temp.t06_user(caja_user);
  r:=public.rpc_solicitar_descuento_pedido(-11301,20,null,'Cliente frecuente','e1060000-0000-0000-0000-000000000801');did:=(r->>'id')::uuid;
  if r->>'tipo'<>'IMPORTE' or r->>'estado'<>'PENDIENTE' or (r->>'solicitado_por')::uuid<>caja_user then raise exception 'TP19 solicitud importe';end if;
  r:=public.rpc_solicitar_descuento_pedido(-11301,20,null,'Cliente frecuente','e1060000-0000-0000-0000-000000000801');
  if (r->>'id')::uuid<>did or (select count(*) from public.auditoria_caja where descuento_pedido_id=did and tipo='SOLICITUD_DESCUENTO')<>1 then raise exception 'idempotencia solicitud';end if;
  checks:=checks+1;
  begin perform public.rpc_decidir_descuento_pedido(-11301,'AUTORIZAR',null,gen_random_uuid());raise exception 'CAJA autoautorizó';exception when sqlstate '42501' then null;end;
  perform pg_temp.t06_user(waiter);begin perform public.rpc_solicitar_descuento_pedido(-11303,10,null,'x',gen_random_uuid());raise exception 'MOZO solicitó';exception when sqlstate '42501' then null;end;
  checks:=checks+1;
  perform pg_temp.t06_user(admin_user);
  r:=public.rpc_decidir_descuento_pedido(-11301,'AUTORIZAR',null,'e1060000-0000-0000-0000-000000000901');
  if (r->>'subtotal_base')::numeric<>100 or (r->>'importe_aplicado')::numeric<>20 or (r->>'total_neto')::numeric<>80
    or (r->>'solicitado_por')::uuid<>caja_user or (r->>'decidido_por')::uuid<>admin_user then raise exception 'TP19 snapshot importe';end if;
  select * into subtotal,discount,net from public.fn_resolver_total_pedido(-11301);
  if subtotal<>100 or discount<>20 or net<>80 then raise exception 'TP19 DT01';end if;
  r:=public.rpc_decidir_descuento_pedido(-11301,'AUTORIZAR',null,'e1060000-0000-0000-0000-000000000901');
  if (r->>'id')::uuid<>did or (select count(*) from public.auditoria_caja where descuento_pedido_id=did and tipo='AUTORIZACION_DESCUENTO')<>1 then raise exception 'TP25 autorización duplicada';end if;
  checks:=checks+1;

  perform pg_temp.t06_user(caja_user);
  r:=public.rpc_solicitar_descuento_pedido(-11302,null,12.5,'Promoción','e1060000-0000-0000-0000-000000000802');
  perform pg_temp.t06_user(admin_user);r:=public.rpc_decidir_descuento_pedido(-11302,'AUTORIZAR',null,'e1060000-0000-0000-0000-000000000902');
  if (r->>'subtotal_base')::numeric<>99.99 or (r->>'importe_aplicado')::numeric<>12.50 or (r->>'total_neto')::numeric<>87.49 then raise exception 'TP20 redondeo porcentaje: %',r;end if;
  checks:=checks+1;

  perform pg_temp.t06_user(caja_user);
  begin perform public.rpc_solicitar_descuento_pedido(-11303,null,null,'x',gen_random_uuid());raise exception 'sin tipo';exception when sqlstate '22023' then null;end;
  begin perform public.rpc_solicitar_descuento_pedido(-11303,1,10,'x',gen_random_uuid());raise exception 'ambos tipos';exception when sqlstate '22023' then null;end;
  begin perform public.rpc_solicitar_descuento_pedido(-11303,0,null,'x',gen_random_uuid());raise exception 'cero';exception when sqlstate '22023' then null;end;
  begin perform public.rpc_solicitar_descuento_pedido(-11303,101,null,'x',gen_random_uuid());raise exception 'importe excesivo';exception when sqlstate '22023' then null;end;
  begin perform public.rpc_solicitar_descuento_pedido(-11303,null,100.01,'x',gen_random_uuid());raise exception 'porcentaje excesivo';exception when sqlstate '22023' then null;end;
  begin perform public.rpc_solicitar_descuento_pedido(-11303,10,null,' ',gen_random_uuid());raise exception 'motivo vacío';exception when sqlstate '22023' then null;end;
  if exists(select 1 from public.descuento_pedido where pedido_id=-11303) then raise exception 'TP22 dejó residuo';end if;
  checks:=checks+1;

  -- Pedido entregado con pago confirmado sintético: cualquier pago bloquea solicitud.
  insert into public.pago(pedido_id,importe,medio,usuario_id,sesion_caja_id,propina,idempotency_key)
    values(-11304,1,'YAPE',caja_user,session_id,0,'e1060000-0000-0000-0000-000000000803');
  begin perform public.rpc_solicitar_descuento_pedido(-11304,10,null,'tardío',gen_random_uuid());raise exception 'descuento tras pago';exception when sqlstate '40001' then null;end;
  checks:=checks+1;

  r:=public.rpc_solicitar_descuento_pedido(-11305,10,null,'A evaluar','e1060000-0000-0000-0000-000000000804');
  did:=(r->>'id')::uuid;perform pg_temp.t06_user(admin_user);
  r:=public.rpc_decidir_descuento_pedido(-11305,'RECHAZAR','No corresponde','e1060000-0000-0000-0000-000000000904');
  select * into subtotal,discount,net from public.fn_resolver_total_pedido(-11305);
  if r->>'estado'<>'RECHAZADO' or r->>'motivo_decision'<>'No corresponde' or discount<>0 or net<>subtotal then raise exception 'rechazo/total inválido';end if;
  checks:=checks+1;

  -- Cobro total provisional consume el snapshot DT-01 confirmado.
  perform pg_temp.t06_user(caja_user);
  perform public.rpc_registrar_pago_total_pedido(-11301,session_id,'EFECTIVO',0,'e1060000-0000-0000-0000-000000000805');
  if (select importe from public.pago where pedido_id=-11301)<>80 or (select estado from public.pedido where id=-11301)<>'PAGADO' then raise exception 'cobro no consumió descuento';end if;
  begin update public.descuento_pedido set total_neto=79 where pedido_id=-11301;raise exception 'snapshot modificable';exception when sqlstate '23514' then null;end;
  begin delete from public.descuento_pedido where pedido_id=-11301;raise exception 'snapshot eliminable';exception when sqlstate '23514' then null;end;
  checks:=checks+1;
  raise notice 'E1-T06 grupos aprobados: %',checks;
end $t$;
select 'E1-T06 SQL: 8 grupos de comprobación aprobados';
rollback;
