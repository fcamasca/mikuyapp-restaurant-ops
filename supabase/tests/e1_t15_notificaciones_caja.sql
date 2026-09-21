begin;

create function pg_temp.t15_user(p uuid, p_role text default 'authenticated')
returns void language plpgsql set search_path=pg_catalog as $$
begin
  perform set_config('request.jwt.claim.sub',coalesce(p::text,''),true);
  perform set_config('request.jwt.claim.role',p_role,true);
end $$;

do $t$
declare
  cashier uuid := 'e1150000-0000-0000-0000-000000000101';
  cashier_other uuid := 'e1150000-0000-0000-0000-000000000102';
  admin_a uuid := 'e1150000-0000-0000-0000-000000000103';
  admin_b uuid := 'e1150000-0000-0000-0000-000000000104';
  admin_inactive uuid := 'e1150000-0000-0000-0000-000000000105';
  admin_other uuid := 'e1150000-0000-0000-0000-000000000106';
  waiter uuid := 'e1150000-0000-0000-0000-000000000107';
  kitchen uuid := 'e1150000-0000-0000-0000-000000000108';
  local_a uuid := 'e1150000-0000-0000-0000-000000000201';
  local_b uuid := 'e1150000-0000-0000-0000-000000000202';
  box_a uuid := 'e1150000-0000-0000-0000-000000000301';
  box_fail uuid := 'e1150000-0000-0000-0000-000000000302';
  box_b uuid := 'e1150000-0000-0000-0000-000000000303';
  session_a uuid;
  first_notification uuid;
  read_time timestamptz;
  snapshot jsonb;
  before_sessions bigint;
begin
  insert into auth.users(id,aud,role,email,encrypted_password) values
    (cashier,'authenticated','authenticated','t15-caja@example.invalid','x'),
    (cashier_other,'authenticated','authenticated','t15-caja-other@example.invalid','x'),
    (admin_a,'authenticated','authenticated','t15-admin-a@example.invalid','x'),
    (admin_b,'authenticated','authenticated','t15-admin-b@example.invalid','x'),
    (admin_inactive,'authenticated','authenticated','t15-admin-off@example.invalid','x'),
    (admin_other,'authenticated','authenticated','t15-admin-other@example.invalid','x'),
    (waiter,'authenticated','authenticated','t15-mozo@example.invalid','x'),
    (kitchen,'authenticated','authenticated','t15-cocina@example.invalid','x');
  insert into public.local(id,codigo,nombre) values
    (local_a,'T15-A','Local T15 A'),(local_b,'T15-B','Local T15 B');
  insert into public.perfil_usuario(id,local_id,rol_id,nombre,activo)
    select cashier,local_a,id,'Caja Apertura',true from public.rol where codigo='CAJA' union all
    select cashier_other,local_b,id,'Caja Otro',true from public.rol where codigo='CAJA' union all
    select admin_a,local_a,id,'Admin Uno',true from public.rol where codigo='ADMINISTRADOR' union all
    select admin_b,local_a,id,'Admin Dos',true from public.rol where codigo='ADMINISTRADOR' union all
    select admin_inactive,local_a,id,'Admin Inactivo',false from public.rol where codigo='ADMINISTRADOR' union all
    select admin_other,local_b,id,'Admin Otro Local',true from public.rol where codigo='ADMINISTRADOR' union all
    select waiter,local_a,id,'Mozo T15',true from public.rol where codigo='MOZO' union all
    select kitchen,local_a,id,'Cocina T15',true from public.rol where codigo='COCINA';
  insert into public.caja(id,local_id,codigo,nombre) values
    (box_a,local_a,'T15-A','Caja principal'),
    (box_fail,local_a,'T15-F','Caja fallo'),
    (box_b,local_b,'T15-B','Caja otro local');

  -- TP02/TP06: una apertura real, dos destinatarios activos locales y cero duplicados.
  perform pg_temp.t15_user(cashier);
  perform public.rpc_abrir_sesion_caja(box_a,100,'e1150000-0000-0000-0000-000000000401');
  select id into session_a from public.sesion_caja where caja_id=box_a and estado='ABIERTA';
  perform public.rpc_abrir_sesion_caja(box_a,100,'e1150000-0000-0000-0000-000000000401');
  if (select count(*) from public.notificacion_caja where sesion_caja_id=session_a and tipo='APERTURA')<>1
    or (select count(*) from public.notificacion_caja_destinatario d join public.notificacion_caja n on n.id=d.notificacion_caja_id where n.sesion_caja_id=session_a and n.tipo='APERTURA')<>2
    or exists(select 1 from public.notificacion_caja_destinatario d join public.notificacion_caja n on n.id=d.notificacion_caja_id where n.sesion_caja_id=session_a and d.administrador_id in(admin_inactive,admin_other)) then
    raise exception 'TP02/TP06 distribución de apertura inválida';
  end if;

  -- Lectura autorizada resuelve actor legible y contador sin SELECT cliente a perfiles.
  perform pg_temp.t15_user(admin_a);
  snapshot := public.rpc_obtener_notificaciones_caja();
  if (snapshot->>'no_leidas')::integer<>1
    or snapshot#>>'{notificaciones,0,tipo}'<>'APERTURA'
    or snapshot#>>'{notificaciones,0,actor_nombre}'<>'Caja Apertura'
    or (snapshot#>>'{notificaciones,0,monto_inicial}')::numeric<>100 then
    raise exception 'TP59 lectura de apertura inválida: %',snapshot;
  end if;
  first_notification := (snapshot#>>'{notificaciones,0,id}')::uuid;

  -- TP60: lectura individual, idempotente y persistente al reconstruir contexto.
  read_time := (public.rpc_marcar_notificacion_caja_leida(first_notification)->>'leida_en')::timestamptz;
  if (public.rpc_marcar_notificacion_caja_leida(first_notification)->>'leida_en')::timestamptz<>read_time then
    raise exception 'TP60 marcado no idempotente';
  end if;
  perform pg_temp.t15_user(admin_a);
  if (public.rpc_obtener_notificaciones_caja()->>'no_leidas')::integer<>0 then
    raise exception 'TP60 lectura no persistió';
  end if;
  perform pg_temp.t15_user(admin_b);
  if (public.rpc_obtener_notificaciones_caja()->>'no_leidas')::integer<>1 then
    raise exception 'TP60 lectura afectó a otro destinatario';
  end if;

  -- TP17: cierre sin diferencia informativo e idempotente.
  perform pg_temp.t15_user(cashier);
  perform public.rpc_cerrar_sesion_caja(session_a,100,null,'e1150000-0000-0000-0000-000000000402');
  perform public.rpc_cerrar_sesion_caja(session_a,100,null,'e1150000-0000-0000-0000-000000000402');
  if (select count(*) from public.notificacion_caja where sesion_caja_id=session_a and tipo='CIERRE')<>1
    or (select prioridad from public.notificacion_caja where sesion_caja_id=session_a and tipo='CIERRE')<>'INFORMATIVA' then
    raise exception 'TP17 cierre normal inválido';
  end if;

  -- Nueva sesión y TP18: diferencia genera ALERTA con motivo, nunca aprobación.
  perform public.rpc_abrir_sesion_caja(box_a,50,'e1150000-0000-0000-0000-000000000403');
  select id into session_a from public.sesion_caja where caja_id=box_a and estado='ABIERTA';
  perform public.rpc_cerrar_sesion_caja(session_a,40,'Faltante de arqueo','e1150000-0000-0000-0000-000000000404');
  perform pg_temp.t15_user(admin_a);
  snapshot := public.rpc_obtener_notificaciones_caja();
  if snapshot#>>'{notificaciones,0,prioridad}'<>'ALERTA'
    or (snapshot#>>'{notificaciones,0,diferencia}')::numeric<>-10
    or snapshot#>>'{notificaciones,0,motivo}'<>'Faltante de arqueo'
    or (snapshot#>>'{notificaciones,0,efectivo_esperado}')::numeric<>50
    or (snapshot#>>'{notificaciones,0,efectivo_contado}')::numeric<>40 then
    raise exception 'TP18 alerta inválida: %',snapshot;
  end if;

  -- TP51/TP52/TP55: tablas cerradas, roles/local aislados y funciones endurecidas.
  perform pg_temp.t15_user(waiter); execute 'set local role authenticated';
  begin perform public.rpc_obtener_notificaciones_caja(); raise exception 'MOZO autorizado'; exception when insufficient_privilege then null; end;
  begin insert into public.notificacion_caja(auditoria_caja_id,local_id,sesion_caja_id,tipo,prioridad,creado_en) values(gen_random_uuid(),local_a,session_a,'APERTURA','INFORMATIVA',now()); raise exception 'INSERT directo permitido'; exception when insufficient_privilege then null; end;
  begin update public.notificacion_caja_destinatario set leida_en=now(); raise exception 'UPDATE directo permitido'; exception when insufficient_privilege then null; end;
  reset role;
  perform pg_temp.t15_user(admin_a); execute 'set local role authenticated';
  if exists(select 1 from public.perfil_usuario where id=cashier) then
    raise exception 'TP55 amplió SELECT directo de perfil_usuario para resolver actor';
  end if;
  reset role;
  perform pg_temp.t15_user(kitchen); begin perform public.rpc_obtener_notificaciones_caja(); raise exception 'COCINA autorizada'; exception when insufficient_privilege then null; end;
  perform pg_temp.t15_user(cashier); begin perform public.rpc_obtener_notificaciones_caja(); raise exception 'CAJA autorizada'; exception when insufficient_privilege then null; end;
  perform pg_temp.t15_user(admin_other);
  if (public.rpc_obtener_notificaciones_caja()->>'no_leidas')::integer<>0 then raise exception 'filtración entre locales'; end if;
  begin perform public.rpc_marcar_notificacion_caja_leida(first_notification); raise exception 'otro local marcó lectura'; exception when insufficient_privilege then null; end;
  perform pg_temp.t15_user(null,'anon'); execute 'set local role anon';
  begin perform public.rpc_obtener_notificaciones_caja(); raise exception 'anon autorizado'; exception when insufficient_privilege then null; end;
  reset role;
  if has_table_privilege('authenticated','public.notificacion_caja','SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated','public.notificacion_caja_destinatario','SELECT,INSERT,UPDATE,DELETE')
    or has_function_privilege('anon','public.rpc_obtener_notificaciones_caja()','EXECUTE')
    or not has_function_privilege('authenticated','public.rpc_obtener_notificaciones_caja()','EXECUTE')
    or (select rolname from pg_proc p join pg_roles r on r.oid=p.proowner where p.oid='public.rpc_obtener_notificaciones_caja()'::regprocedure)<>'postgres'
    or pg_get_functiondef('public.rpc_obtener_notificaciones_caja()'::regprocedure)!~* 'security definer'
    or pg_get_functiondef('public.rpc_obtener_notificaciones_caja()'::regprocedure)!~* 'set search_path to ''pg_catalog''' then
    raise exception 'TP55 endurecimiento inválido';
  end if;

  -- TP54: fallo de un destinatario revierte sesión, auditoría y notificación.
  create function pg_temp.fail_t15_recipient() returns trigger language plpgsql as $$begin raise exception 'fallo destinatario inducido';end$$;
  create trigger t15_fail before insert on public.notificacion_caja_destinatario for each statement execute function pg_temp.fail_t15_recipient();
  select count(*) into before_sessions from public.sesion_caja;
  perform pg_temp.t15_user(cashier);
  begin perform public.rpc_abrir_sesion_caja(box_fail,10,'e1150000-0000-0000-0000-000000000405'); raise exception 'apertura no falló'; exception when others then if sqlerrm<>'fallo destinatario inducido' then raise; end if; end;
  drop trigger t15_fail on public.notificacion_caja_destinatario;
  if (select count(*) from public.sesion_caja)<>before_sessions
    or exists(select 1 from public.auditoria_caja where caja_id=box_fail)
    or exists(select 1 from public.notificacion_caja where local_id=local_a and sesion_caja_id in(select id from public.sesion_caja where caja_id=box_fail)) then
    raise exception 'TP54 dejó efectos huérfanos';
  end if;

  raise notice 'E1-T15: TP02, TP06, TP10, TP17, TP18, TP51, TP52, TP54, TP55, TP59 y TP60 aprobados';
end $t$;

select 'E1-T15 SQL aprobado';
rollback;
