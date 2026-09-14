begin;

create function pg_temp.e1_t05_user(p_user uuid)
returns void language plpgsql set search_path=pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user::text,''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

do $metadata$
declare v_checks integer := 0; v_definition text;
begin
  if not exists (select 1 from pg_catalog.pg_class where oid='public.movimiento_caja'::regclass and relrowsecurity)
    or not exists (select 1 from pg_catalog.pg_class where oid='public.resumen_cierre_sesion_caja'::regclass and relrowsecurity)
    or not exists (select 1 from pg_catalog.pg_class where oid='public.solicitud_cierre_caja'::regclass and relrowsecurity) then
    raise exception 'T05 RLS ausente';
  end if; v_checks:=v_checks+1;
  if pg_catalog.has_table_privilege('anon','public.movimiento_caja','SELECT')
    or not pg_catalog.has_table_privilege('authenticated','public.movimiento_caja','SELECT')
    or pg_catalog.has_table_privilege('authenticated','public.movimiento_caja','INSERT,UPDATE,DELETE')
    or pg_catalog.has_table_privilege('authenticated','public.solicitud_cierre_caja','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'T05 privilegios de tablas inesperados';
  end if; v_checks:=v_checks+1;
  if pg_catalog.has_function_privilege('anon','public.rpc_registrar_movimiento_caja(uuid,text,numeric,text,uuid)','EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated','public.rpc_registrar_movimiento_caja(uuid,text,numeric,text,uuid)','EXECUTE')
    or pg_catalog.has_function_privilege('authenticated','public.fn_cerrar_sesion_caja(uuid,numeric,text,uuid,boolean)','EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated','public.rpc_cerrar_sesion_caja(uuid,numeric,text,uuid)','EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated','public.rpc_cerrar_sesion_caja_supervisor(uuid,numeric,text,uuid)','EXECUTE') then
    raise exception 'T05 grants RPC inesperados';
  end if; v_checks:=v_checks+1;
  select pg_catalog.pg_get_functiondef('public.fn_cerrar_sesion_caja(uuid,numeric,text,uuid,boolean)'::regprocedure) into v_definition;
  if v_definition !~* 'from public\.caja.*for update'
    or v_definition !~* 'from public\.sesion_caja.*for update'
    or v_definition !~* 'fn_totales_sesion_caja'
    or v_definition !~* 'pago_efectivo.*propina_efectivo.*entradas.*salidas' then
    raise exception 'T05 contrato/orden de cierre inesperado';
  end if; v_checks:=v_checks+1;
  raise notice 'E1-T05 metadata: % comprobaciones aprobadas',v_checks;
end $metadata$;

do $behaviour$
declare
  a uuid:='e1050000-0000-0000-0000-000000000101';
  b uuid:='e1050000-0000-0000-0000-000000000102';
  admin uuid:='e1050000-0000-0000-0000-000000000103';
  waiter uuid:='e1050000-0000-0000-0000-000000000104';
  kitchen uuid:='e1050000-0000-0000-0000-000000000105';
  other uuid:='e1050000-0000-0000-0000-000000000106';
  local_a uuid:='e1050000-0000-0000-0000-000000000201';
  local_b uuid:='e1050000-0000-0000-0000-000000000202';
  box_a uuid:='e1050000-0000-0000-0000-000000000301';
  box_b uuid:='e1050000-0000-0000-0000-000000000302';
  box_inactive uuid:='e1050000-0000-0000-0000-000000000303';
  s1 uuid:='e1050000-0000-0000-0000-000000000401';
  s2 uuid:='e1050000-0000-0000-0000-000000000402';
  s3 uuid:='e1050000-0000-0000-0000-000000000403';
  s_other uuid:='e1050000-0000-0000-0000-000000000404';
  s_inactive uuid:='e1050000-0000-0000-0000-000000000405';
  mesa_paid uuid:='e1050000-0000-0000-0000-000000000501';
  mesa_pending uuid:='e1050000-0000-0000-0000-000000000502';
  result jsonb; movement_id uuid; checks integer:=0;
begin
  insert into auth.users(id,aud,role,email,encrypted_password) values
    (a,'authenticated','authenticated','t05-a@example.invalid','x'),
    (b,'authenticated','authenticated','t05-b@example.invalid','x'),
    (admin,'authenticated','authenticated','t05-admin@example.invalid','x'),
    (waiter,'authenticated','authenticated','t05-w@example.invalid','x'),
    (kitchen,'authenticated','authenticated','t05-k@example.invalid','x'),
    (other,'authenticated','authenticated','t05-o@example.invalid','x');
  insert into public.local(id,codigo,nombre) values
    (local_a,'T05-A','T05 Local A'),(local_b,'T05-B','T05 Local B');
  insert into public.perfil_usuario(id,local_id,rol_id,nombre)
    select a,local_a,id,'Caja A' from public.rol where codigo='CAJA' union all
    select b,local_a,id,'Caja B' from public.rol where codigo='CAJA' union all
    select admin,local_a,id,'Admin' from public.rol where codigo='ADMINISTRADOR' union all
    select waiter,local_a,id,'Mozo' from public.rol where codigo='MOZO' union all
    select kitchen,local_a,id,'Cocina' from public.rol where codigo='COCINA' union all
    select other,local_b,id,'Caja Otro' from public.rol where codigo='CAJA';
  insert into public.caja(id,local_id,codigo,nombre,activo) values
    (box_a,local_a,'T05-A','Caja A',true),(box_b,local_b,'T05-B','Caja B',true),
    (box_inactive,local_a,'T05-I','Caja inactiva',false);
  insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values
    (s1,box_a,local_a,a,100,'e1050000-0000-0000-0000-000000000601'),
    (s_other,box_b,local_b,other,20,'e1050000-0000-0000-0000-000000000602'),
    (s_inactive,box_inactive,local_a,a,10,'e1050000-0000-0000-0000-000000000603');
  insert into public.mesa(id,local_id,codigo,nombre,estado) values
    (mesa_paid,local_a,'T05-P','Pagada','LIBRE'),
    (mesa_pending,local_a,'T05-E','Entregada','PENDIENTE_PAGO');
  insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values
    (-10501,local_a,mesa_paid,waiter,'PAGADO'),
    (-10502,local_a,mesa_pending,waiter,'ENTREGADO');
  insert into public.pago(pedido_id,importe,medio,usuario_id,sesion_caja_id,propina,idempotency_key) values
    (-10501,50,'EFECTIVO',a,s1,5,'e1050000-0000-0000-0000-000000000701'),
    (-10501,30,'YAPE',b,s1,3,'e1050000-0000-0000-0000-000000000702');

  perform pg_temp.e1_t05_user(b);
  result:=public.rpc_registrar_movimiento_caja(s1,'ENTRADA',20,'Cambio adicional','e1050000-0000-0000-0000-000000000801');
  movement_id:=(result->>'id')::uuid;
  if (result->>'actor_id')::uuid<>b or result->>'tipo'<>'ENTRADA'
    or (result->>'importe')::numeric<>20 or result->>'motivo'<>'Cambio adicional'
    or (result->>'creado_en') is null then raise exception 'TP13 entrada inválida'; end if;
  checks:=checks+1;
  result:=public.rpc_registrar_movimiento_caja(s1,'ENTRADA',20,'Cambio adicional','e1050000-0000-0000-0000-000000000801');
  if (result->>'id')::uuid<>movement_id or (select count(*) from public.movimiento_caja where id=movement_id)<>1
    or (select count(*) from public.auditoria_caja where movimiento_caja_id=movement_id)<>1 then
    raise exception 'TP16 reintento duplicó movimiento/auditoría'; end if;
  checks:=checks+1;

  perform pg_temp.e1_t05_user(a);
  result:=public.rpc_registrar_movimiento_caja(s1,'SALIDA',5,'Compra menor','e1050000-0000-0000-0000-000000000802');
  if result->>'tipo'<>'SALIDA' or (result->>'importe')::numeric<>5
    or (result->>'actor_id')::uuid<>a then raise exception 'TP14 salida inválida'; end if;
  checks:=checks+1;
  result:=public.rpc_obtener_resumen_sesion_caja(s1);
  if (result->>'monto_inicial')::numeric<>100 or (result->>'pago_efectivo')::numeric<>50
    or (result->>'propina_efectivo')::numeric<>5 or (result->>'pago_yape')::numeric<>30
    or (result->>'propina_yape')::numeric<>3 or (result->>'entradas')::numeric<>20
    or (result->>'salidas')::numeric<>5 or (result->>'efectivo_esperado')::numeric<>170 then
    raise exception 'TP17 fórmula autoritativa incorrecta: %',result; end if;
  checks:=checks+1;

  begin perform public.rpc_registrar_movimiento_caja(s1,'ENTRADA',0,'x',gen_random_uuid()); raise exception 'cero permitido'; exception when sqlstate '22023' then null; end;
  begin perform public.rpc_registrar_movimiento_caja(s1,'SALIDA',-1,'x',gen_random_uuid()); raise exception 'negativo permitido'; exception when sqlstate '22023' then null; end;
  begin perform public.rpc_registrar_movimiento_caja(s1,'SALIDA',1,' ',gen_random_uuid()); raise exception 'motivo vacío permitido'; exception when sqlstate '22023' then null; end;
  begin perform public.rpc_registrar_movimiento_caja(s_inactive,'ENTRADA',1,'x',gen_random_uuid()); raise exception 'caja inactiva permitida'; exception when sqlstate '42501' then null; end;
  begin perform public.rpc_registrar_movimiento_caja(s_other,'ENTRADA',1,'x',gen_random_uuid()); raise exception 'otro local permitido'; exception when sqlstate '42501' then null; end;
  if (select count(*) from public.movimiento_caja)<>2 then raise exception 'TP15 dejó residuos'; end if;
  checks:=checks+1;

  perform pg_temp.e1_t05_user(b);
  result:=public.rpc_cerrar_sesion_caja(s1,170,null,'e1050000-0000-0000-0000-000000000901');
  if (result->>'efectivo_esperado')::numeric<>170 or (result->>'efectivo_contado')::numeric<>170
    or (result->>'diferencia')::numeric<>0 or result->>'tipo_cierre'<>'NORMAL'
    or (select abierta_por from public.sesion_caja where id=s1)<>a
    or (select cerrada_por from public.sesion_caja where id=s1)<>b
    or (select estado from public.pedido where id=-10502)<>'ENTREGADO'
    or (select count(*) from public.auditoria_caja where sesion_caja_id=s1 and tipo='CIERRE' and actor_id=b)<>1 then
    raise exception 'TP10/TP17 cierre normal inválido: %',result; end if;
  checks:=checks+1;
  result:=public.rpc_cerrar_sesion_caja(s1,170,null,'e1050000-0000-0000-0000-000000000901');
  if (result->>'diferencia')::numeric<>0 or (select count(*) from public.resumen_cierre_sesion_caja where sesion_caja_id=s1)<>1 then
    raise exception 'TP18 reintento de cierre inválido'; end if;
  begin perform public.rpc_cerrar_sesion_caja(s1,170,null,gen_random_uuid()); raise exception 'doble cierre permitido'; exception when sqlstate '40001' then null; end;
  begin perform public.rpc_registrar_movimiento_caja(s1,'ENTRADA',1,'tardía',gen_random_uuid()); raise exception 'movimiento en cerrada permitido'; exception when sqlstate '40001' then null; end;
  checks:=checks+1;

  insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values
    (s2,box_a,local_a,a,10,'e1050000-0000-0000-0000-000000000604');
  begin perform public.rpc_cerrar_sesion_caja(s2,0,null,gen_random_uuid()); raise exception 'diferencia sin motivo permitida'; exception when sqlstate '22023' then null; end;
  result:=public.rpc_cerrar_sesion_caja(s2,0,'Faltante verificado','e1050000-0000-0000-0000-000000000902');
  if (result->>'diferencia')::numeric<>-10 or result->>'motivo'<>'Faltante verificado' then raise exception 'TP18 diferencia inválida'; end if;
  checks:=checks+1;

  insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values
    (s3,box_a,local_a,a,0,'e1050000-0000-0000-0000-000000000605');
  perform pg_temp.e1_t05_user(admin);
  begin perform public.rpc_cerrar_sesion_caja_supervisor(s3,0,' ',gen_random_uuid()); raise exception 'supervisor sin motivo permitido'; exception when sqlstate '22023' then null; end;
  result:=public.rpc_cerrar_sesion_caja_supervisor(s3,0,'Cierre administrativo','e1050000-0000-0000-0000-000000000903');
  if result->>'tipo_cierre'<>'SUPERVISOR' or (select cerrada_por from public.sesion_caja where id=s3)<>admin
    or (select count(*) from public.auditoria_caja where sesion_caja_id=s3 and tipo='CIERRE_SUPERVISOR' and actor_id=admin)<>1 then
    raise exception 'TP18 cierre supervisor inválido'; end if;
  checks:=checks+1;

  perform pg_temp.e1_t05_user(waiter);
  begin perform public.rpc_registrar_movimiento_caja(s1,'ENTRADA',1,'x',gen_random_uuid()); raise exception 'MOZO permitido'; exception when sqlstate '42501' then null; end;
  perform pg_temp.e1_t05_user(kitchen);
  begin perform public.rpc_cerrar_sesion_caja(s1,0,'x',gen_random_uuid()); raise exception 'COCINA permitido'; exception when sqlstate '42501' then null; end;
  checks:=checks+1;

  begin update public.movimiento_caja set motivo='editado' where id=movement_id; raise exception 'edición permitida'; exception when sqlstate '23514' then null; end;
  begin delete from public.movimiento_caja where id=movement_id; raise exception 'borrado permitido'; exception when sqlstate '23514' then null; end;
  begin update public.resumen_cierre_sesion_caja set motivo='editado' where sesion_caja_id=s1; raise exception 'snapshot editable'; exception when sqlstate '23514' then null; end;
  checks:=checks+1;
  raise notice 'E1-T05 comportamiento: % comprobaciones aprobadas',checks;
end $behaviour$;

select 'E1-T05 SQL: 15 comprobaciones agrupadas aprobadas';
rollback;
