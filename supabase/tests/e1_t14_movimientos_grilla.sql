begin;

create function pg_temp.e1_t14_user(p_user uuid)
returns void language plpgsql set search_path=pg_catalog as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user::text,''), true);
  perform set_config('request.jwt.claim.role', case when p_user is null then 'anon' else 'authenticated' end, true);
end $$;

do $metadata$
begin
  if has_table_privilege('authenticated','public.lote_movimiento_caja','SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('anon','public.lote_movimiento_caja','SELECT') then
    raise exception 'lote interno expuesto';
  end if;
  if not has_function_privilege('authenticated','public.rpc_obtener_movimientos_sesion_caja(uuid)','EXECUTE')
    or not has_function_privilege('authenticated','public.registrar_movimientos_caja(uuid,jsonb,uuid)','EXECUTE')
    or has_function_privilege('anon','public.rpc_obtener_movimientos_sesion_caja(uuid)','EXECUTE')
    or has_function_privilege('anon','public.registrar_movimientos_caja(uuid,jsonb,uuid)','EXECUTE') then
    raise exception 'grants inesperados';
  end if;
  if has_function_privilege('authenticated','public.rpc_registrar_movimiento_caja(uuid,text,numeric,text,uuid)','EXECUTE') is not true then
    raise exception 'RPC individual dejó de ser compatible';
  end if;
end $metadata$;

do $behaviour$
declare
  caja_a uuid := 'e1140000-0000-0000-0000-000000000001';
  admin_a uuid := 'e1140000-0000-0000-0000-000000000002';
  mozo_a uuid := 'e1140000-0000-0000-0000-000000000003';
  cocina_a uuid := 'e1140000-0000-0000-0000-000000000004';
  caja_b uuid := 'e1140000-0000-0000-0000-000000000005';
  local_a uuid := 'e1140000-0000-0000-0000-000000000011';
  local_b uuid := 'e1140000-0000-0000-0000-000000000012';
  box_a uuid := 'e1140000-0000-0000-0000-000000000021';
  box_b uuid := 'e1140000-0000-0000-0000-000000000022';
  session_a uuid := 'e1140000-0000-0000-0000-000000000031';
  session_b uuid := 'e1140000-0000-0000-0000-000000000032';
  batch_key uuid := 'e1140000-0000-0000-0000-000000000041';
  one_key uuid := 'e1140000-0000-0000-0000-000000000042';
  result jsonb; before_count integer; before_audit integer;
begin
  insert into auth.users(id,aud,role,email,encrypted_password) values
    (caja_a,'authenticated','authenticated','e114-caja@example.invalid','x'),
    (admin_a,'authenticated','authenticated','e114-admin@example.invalid','x'),
    (mozo_a,'authenticated','authenticated','e114-mozo@example.invalid','x'),
    (cocina_a,'authenticated','authenticated','e114-cocina@example.invalid','x'),
    (caja_b,'authenticated','authenticated','e114-otro@example.invalid','x');
  insert into public.local(id,codigo,nombre) values (local_a,'E114-A','Local A'),(local_b,'E114-B','Local B');
  insert into public.perfil_usuario(id,local_id,rol_id,nombre)
    select caja_a,local_a,id,'Cajero A' from public.rol where codigo='CAJA' union all
    select admin_a,local_a,id,'Admin A' from public.rol where codigo='ADMINISTRADOR' union all
    select mozo_a,local_a,id,'Mozo A' from public.rol where codigo='MOZO' union all
    select cocina_a,local_a,id,'Cocina A' from public.rol where codigo='COCINA' union all
    select caja_b,local_b,id,'Cajero B' from public.rol where codigo='CAJA';
  insert into public.caja(id,local_id,codigo,nombre) values (box_a,local_a,'E114-A','Caja A'),(box_b,local_b,'E114-B','Caja B');
  insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values
    (session_a,box_a,local_a,caja_a,100,'e1140000-0000-0000-0000-000000000051'),
    (session_b,box_b,local_b,caja_b,50,'e1140000-0000-0000-0000-000000000052');

  perform pg_temp.e1_t14_user(caja_a);
  result := public.registrar_movimientos_caja(session_a,
    '[{"tipo":"ENTRADA","importe":20,"motivo":"Cambio"},{"tipo":"SALIDA","importe":5,"motivo":"Compra"}]', batch_key);
  if jsonb_array_length(result) <> 2
    or (select count(*) from public.movimiento_caja where sesion_caja_id=session_a) <> 2
    or (select count(*) from public.auditoria_caja where sesion_caja_id=session_a and movimiento_caja_id is not null) <> 2 then
    raise exception 'lote mixto o auditoría inválidos';
  end if;
  if (public.rpc_obtener_resumen_sesion_caja(session_a)->>'efectivo_esperado')::numeric <> 115 then
    raise exception 'esperado no se actualizó con fórmula vigente';
  end if;
  result := public.registrar_movimientos_caja(session_a,
    '[{"tipo":"ENTRADA","importe":20,"motivo":"Cambio"},{"tipo":"SALIDA","importe":5,"motivo":"Compra"}]', batch_key);
  if jsonb_array_length(result) <> 2 or (select count(*) from public.movimiento_caja where sesion_caja_id=session_a) <> 2 then
    raise exception 'reintento duplicó lote';
  end if;
  begin
    perform public.registrar_movimientos_caja(session_a,'[{"tipo":"ENTRADA","importe":1,"motivo":"Otro"}]',batch_key);
    raise exception 'clave reutilizada aceptada';
  exception when sqlstate '22023' then null; end;

  result := public.registrar_movimientos_caja(session_a,'[{"tipo":"ENTRADA","importe":2,"motivo":"Uno"}]',one_key);
  if jsonb_array_length(result) <> 1 then raise exception 'lote de una fila inválido'; end if;
  before_count := (select count(*) from public.movimiento_caja where sesion_caja_id=session_a);
  before_audit := (select count(*) from public.auditoria_caja where sesion_caja_id=session_a and movimiento_caja_id is not null);
  begin
    perform public.registrar_movimientos_caja(session_a,
      '[{"tipo":"ENTRADA","importe":3,"motivo":"Válido"},{"tipo":"SALIDA","importe":0,"motivo":"Inválido"}]',gen_random_uuid());
    raise exception 'lote inválido aceptado';
  exception when sqlstate '22023' then null; end;
  if (select count(*) from public.movimiento_caja where sesion_caja_id=session_a) <> before_count
    or (select count(*) from public.auditoria_caja where sesion_caja_id=session_a and movimiento_caja_id is not null) <> before_audit then
    raise exception 'fallo intermedio dejó residuos';
  end if;
  if (select count(*) from public.rpc_obtener_movimientos_sesion_caja(session_a)) <> 3
    or (select actor_nombre from public.rpc_obtener_movimientos_sesion_caja(session_a) limit 1) <> 'Cajero A' then
    raise exception 'lectura CAJA/actor_nombre inválida';
  end if;
  perform pg_temp.e1_t14_user(admin_a);
  if (select count(*) from public.rpc_obtener_movimientos_sesion_caja(session_a)) <> 3 then raise exception 'lectura ADMIN denegada'; end if;
  perform pg_temp.e1_t14_user(mozo_a);
  begin perform public.rpc_obtener_movimientos_sesion_caja(session_a); raise exception 'MOZO permitido'; exception when sqlstate '42501' then null; end;
  perform pg_temp.e1_t14_user(cocina_a);
  begin perform public.rpc_obtener_movimientos_sesion_caja(session_a); raise exception 'COCINA permitido'; exception when sqlstate '42501' then null; end;
  perform pg_temp.e1_t14_user(caja_b);
  begin perform public.rpc_obtener_movimientos_sesion_caja(session_a); raise exception 'otro local permitido'; exception when sqlstate '42501' then null; end;
  perform pg_temp.e1_t14_user(null);
  begin perform public.rpc_obtener_movimientos_sesion_caja(session_a); raise exception 'anon permitido'; exception when sqlstate '42501' then null; end;
end $behaviour$;

select 'E1-T14 movimientos: lectura, batch, atomicidad, auditoría, idempotencia y aislamiento aprobados';
rollback;
