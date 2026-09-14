begin;
create temporary table t04_checks(nombre text primary key);
create function pg_temp.t04_assert(p_ok boolean,p_nombre text) returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception 'T04: %',p_nombre; end if;
  insert into t04_checks values(p_nombre);
end $$;
-- Invocador, no SECURITY DEFINER: cada operación realmente se ejecuta con
-- SET ROLE authenticated. Los helpers son temporales y desaparecen al rollback.
create function pg_temp.t04_call(p_actor uuid,p_sql text) returns jsonb language plpgsql as $$
declare v_result jsonb;
begin
  perform set_config('request.jwt.claim.sub',coalesce(p_actor::text,''),true);
  set local role authenticated;
  execute p_sql into v_result;
  reset role;
  return v_result;
exception when others then reset role; raise;
end $$;
create function pg_temp.t04_reject(p_actor uuid,p_sql text,p_state text,p_nombre text)
returns void language plpgsql as $$
declare v_state text;
begin
  begin perform pg_temp.t04_call(p_actor,p_sql);
  exception when others then get stacked diagnostics v_state = returned_sqlstate; end;
  perform pg_temp.t04_assert(v_state = p_state,p_nombre);
end $$;

do $behaviour$
declare
  a uuid := 'e1040000-0000-0000-0000-000000000011';
  b uuid := 'e1040000-0000-0000-0000-000000000012';
  admin uuid := 'e1040000-0000-0000-0000-000000000013';
  caja uuid := 'e1040000-0000-0000-0000-000000000101';
  caja2 uuid := 'e1040000-0000-0000-0000-000000000102';
  otra uuid := 'e1040000-0000-0000-0000-000000000104';
  clave uuid := gen_random_uuid(); clave_b uuid := gen_random_uuid();
  original jsonb; recuperada jsonb; resultado jsonb; sesion uuid;
  actor uuid; monto text; comando text; llamada text;
begin
  perform pg_temp.t04_assert(not exists(select 1 from public.auditoria_caja), 'sin auditoria retroactiva');
  perform pg_temp.t04_assert(pg_temp.t04_call(a,format('select public.rpc_obtener_sesion_caja_activa(%L)',caja)) is null,'sin sesion activa devuelve null');
  original := pg_temp.t04_call(a,format('select public.rpc_abrir_sesion_caja(%L,12.35,%L)',caja,clave));
  sesion := (original->>'id')::uuid;
  perform pg_temp.t04_assert(original->>'estado' = 'ABIERTA' and original->>'abierta_por' = a::text
    and (original->>'monto_inicial')::numeric = 12.35 and original->>'local_id' = 'e1040000-0000-0000-0000-000000000001'
    and (original->>'abierta_en')::timestamptz = now(),'TP02 snapshot servidor');
  perform pg_temp.t04_assert(not original ? 'idempotency_key','snapshot no publica clave interna');
  recuperada := pg_temp.t04_call(a,format('select public.rpc_abrir_sesion_caja(%L,999,%L)',caja,gen_random_uuid()));
  perform pg_temp.t04_assert(recuperada = original,'TP03 segunda apertura snapshot identico aun monto diferente');
  recuperada := pg_temp.t04_call(b,format('select public.rpc_abrir_sesion_caja(%L,50,%L)',caja,clave_b));
  perform pg_temp.t04_assert(recuperada = original,'TP05 Cajero B recupera sin alterar apertura A');
  perform pg_temp.t04_assert(pg_temp.t04_call(b,format('select public.rpc_obtener_sesion_caja_activa(%L,%L)',caja,sesion)) = original,'TP05 lectura activa compartida B');
  perform pg_temp.t04_assert(pg_temp.t04_call(a,format('select public.rpc_abrir_sesion_caja(%L,12.35,%L)',caja,clave)) = original,'TP06 retry creador');
  perform pg_temp.t04_assert(pg_temp.t04_call(b,format('select public.rpc_abrir_sesion_caja(%L,50,%L)',caja,clave_b)) = original,'TP06 retry recuperador');
  perform pg_temp.t04_assert((select count(*) = 1 from public.sesion_caja where caja_id=caja and estado='ABIERTA'),'TP03 una fila abierta');
  perform pg_temp.t04_assert((select count(*) = 1 from public.auditoria_caja where sesion_caja_id=sesion and actor_id=a
    and monto_inicial=12.35 and estado_anterior is null and estado_nuevo='ABIERTA' and creado_en=now()),'TP02 un evento apertura con actor hora monto');
  perform pg_temp.t04_assert((select count(*)=3 from public.solicitud_apertura_caja where sesion_caja_id=sesion),'idempotencia todas las solicitudes sin duplicacion');
  perform pg_temp.t04_reject(b,format('select public.rpc_abrir_sesion_caja(%L,51,%L)',caja,clave_b),'22023','misma clave otro payload rechazada');
  foreach monto in array array['null','-1','''NaN''::numeric','''Infinity''::numeric','''-Infinity''::numeric','1.001','1000000000000'] loop
    perform pg_temp.t04_reject(a,format('select public.rpc_abrir_sesion_caja(%L,%s,%L)',caja2,monto,gen_random_uuid()),'22023','TP07 monto '||monto);
  end loop;
  perform pg_temp.t04_reject(a,format('select public.rpc_abrir_sesion_caja(%L,0,null)',caja2),'22023','clave null rechazada');
  resultado := pg_temp.t04_call(b,format('select public.rpc_abrir_sesion_caja(%L,0,%L)',caja2,gen_random_uuid()));
  perform pg_temp.t04_assert(resultado->>'id' <> sesion::text and resultado->>'abierta_por' = b::text,'otra caja del local independiente y monto cero');
  perform pg_temp.t04_reject(b,format('select public.rpc_obtener_sesion_caja_activa(%L,%L)',caja2,sesion),'40001','TP08 sesion de otra caja rechazada');
  perform pg_temp.t04_reject(a,format('select public.rpc_obtener_sesion_caja_activa(%L,%L)',caja,'e1040000-0000-0000-0000-000000000201'),'40001','TP08 sesion cerrada no operativa');
  foreach comando in array array[
    'select public.rpc_abrir_sesion_caja(%L,0,'||quote_literal(gen_random_uuid())||')',
    'select public.rpc_obtener_sesion_caja_activa(%L)',
    'select count(*)::text::jsonb from public.rpc_obtener_historial_sesiones_caja(%L)'
  ] loop
    perform pg_temp.t04_reject(a,format(comando,otra),'42501','otro local '||comando);
    perform pg_temp.t04_reject(a,format(comando,gen_random_uuid()),'42501','caja inexistente '||comando);
  end loop;
  perform pg_temp.t04_reject(a,'select public.rpc_abrir_sesion_caja(''e1040000-0000-0000-0000-000000000103'',0,gen_random_uuid())','42501','caja inactiva apertura');
  perform pg_temp.t04_reject(a,'select public.rpc_obtener_sesion_caja_activa(''e1040000-0000-0000-0000-000000000103'')','42501','caja inactiva lectura operativa');
  perform pg_temp.t04_reject(admin,format('select public.rpc_abrir_sesion_caja(%L,0,%L)',caja,gen_random_uuid()),'42501','ADMIN no hereda apertura CAJA');
  perform pg_temp.t04_assert(pg_temp.t04_call(admin,format('select public.rpc_obtener_sesion_caja_activa(%L)',caja)) = original,'ADMIN lectura activa autorizada');
  foreach actor in array array[a,b,admin] loop
    resultado := pg_temp.t04_call(actor,format('select jsonb_agg(x) from public.rpc_obtener_historial_sesiones_caja(%L) x',caja));
    perform pg_temp.t04_assert(jsonb_array_length(resultado)=2,'TP11 historico propio actor '||actor);
    perform pg_temp.t04_assert(exists(select 1 from jsonb_array_elements(resultado) x where x->>'estado'='CERRADA'
      and x->>'abierta_por'=a::text and x->>'cerrada_por'=b::text),'TP10 lectura historia A B '||actor);
    perform pg_temp.t04_assert(pg_temp.t04_call(actor,'select count(*)::text::jsonb from public.sesion_caja where local_id <> ''e1040000-0000-0000-0000-000000000001''')='0'::jsonb,'RLS sesiones local '||actor);
    perform pg_temp.t04_assert(pg_temp.t04_call(actor,format('select count(*)::text::jsonb from public.caja where id=%L',otra))='0'::jsonb,'RLS caja otro local '||actor);
  end loop;
  perform pg_temp.t04_assert(pg_temp.t04_call(b,format('select count(*)::text::jsonb from public.rpc_obtener_historial_sesiones_caja(%L,1,1)',caja))='1'::jsonb,'historico paginado');
  perform pg_temp.t04_reject(a,'select count(*)::text::jsonb from public.rpc_obtener_historial_sesiones_caja(null,201,0)','22023','limite maximo');
  perform pg_temp.t04_reject(a,'select count(*)::text::jsonb from public.rpc_obtener_historial_sesiones_caja(null,10,-1)','22023','offset negativo');

  -- Cada rol/perfil inválido prueba todas las RPC y SELECT RLS reales.
  foreach actor in array array['e1040000-0000-0000-0000-000000000014'::uuid,
    'e1040000-0000-0000-0000-000000000015'::uuid,'e1040000-0000-0000-0000-000000000017'::uuid,
    'e1040000-0000-0000-0000-000000000018'::uuid,'e1040000-0000-0000-0000-000000000019'::uuid,null::uuid] loop
    foreach llamada in array array[format('select public.rpc_abrir_sesion_caja(%L,0,%L)',caja,gen_random_uuid()),
      format('select public.rpc_obtener_sesion_caja_activa(%L)',caja),
      'select count(*)::text::jsonb from public.rpc_obtener_historial_sesiones_caja()'] loop
      perform pg_temp.t04_reject(actor,llamada,'42501','TP12 '||coalesce(actor::text,'sin uid')||' '||llamada);
    end loop;
    perform pg_temp.t04_assert(pg_temp.t04_call(actor,'select count(*)::text::jsonb from public.sesion_caja')='0'::jsonb,'TP12 RLS sesion '||coalesce(actor::text,'sin uid'));
    perform pg_temp.t04_assert(pg_temp.t04_call(actor,'select count(*)::text::jsonb from public.caja')='0'::jsonb,'TP12 RLS caja '||coalesce(actor::text,'sin uid'));
  end loop;
  update public.rol set activo=false where codigo='CAJA';
  perform pg_temp.t04_reject(a,format('select public.rpc_abrir_sesion_caja(%L,12.35,%L)',caja,clave),'42501','TP12 rol inactivo incluso retry');
  perform pg_temp.t04_reject(a,format('select public.rpc_obtener_sesion_caja_activa(%L)',caja),'42501','TP12 lectura rol inactivo');
  perform pg_temp.t04_assert(pg_temp.t04_call(a,'select count(*)::text::jsonb from public.sesion_caja')='0'::jsonb,'TP12 RLS rol inactivo');
  update public.rol set activo=true where codigo='CAJA';

  -- Fixture de cierre, no implementación de T05: un retry de B conserva su resultado
  -- original aunque A abra después otra sesión con nueva clave.
  update public.sesion_caja set estado='CERRADA',cerrada_por=b,cerrada_en=now(),
    efectivo_esperado=12.35,efectivo_contado=12.35,diferencia=0 where id=sesion;
  resultado := pg_temp.t04_call(b,format('select public.rpc_abrir_sesion_caja(%L,50,%L)',caja,clave_b));
  perform pg_temp.t04_assert(resultado->>'id'=sesion::text and resultado->>'estado'='CERRADA','retry recuperador tras cierre no abre');
  recuperada := pg_temp.t04_call(a,format('select public.rpc_abrir_sesion_caja(%L,2,%L)',caja,gen_random_uuid()));
  perform pg_temp.t04_assert(recuperada->>'id'<>sesion::text and recuperada->>'estado'='ABIERTA','clave nueva tras cierre crea nueva');
  perform pg_temp.t04_assert(pg_temp.t04_call(b,format('select public.rpc_abrir_sesion_caja(%L,50,%L)',caja,clave_b))=resultado,'retry recuperador no confunde siguiente sesion');
  resultado := pg_temp.t04_call(a,format('select public.rpc_abrir_sesion_caja(%L,10,''e1040000-0000-0000-0000-000000000701'')',caja));
  perform pg_temp.t04_assert(resultado->>'id'='e1040000-0000-0000-0000-000000000201' and resultado->>'estado'='CERRADA','compatibilidad clave T03 sin alterar historia');
end $behaviour$;

do $security$
declare actor uuid := 'e1040000-0000-0000-0000-000000000011'; f record; t text; p text;
begin
  foreach t in array array['caja','sesion_caja','solicitud_apertura_caja','auditoria_caja'] loop
    foreach p in array array['INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER','REFERENCES'] loop
      perform pg_temp.t04_assert(not has_table_privilege('authenticated','public.'||t,p),'sin DML cliente '||t||' '||p);
    end loop;
    perform pg_temp.t04_assert(not has_table_privilege('anon','public.'||t,'SELECT'),'sin lectura anon '||t);
  end loop;
  foreach t in array array['auditoria_caja','solicitud_apertura_caja'] loop
    perform pg_temp.t04_reject(actor,'select to_jsonb(x) from public.'||t||' x limit 1','42501','tabla interna sin lectura '||t);
    perform pg_temp.t04_reject(actor,'delete from public.'||t,'42501','delete real denegado '||t);
  end loop;
  perform pg_temp.t04_reject(actor,'select idempotency_key::text::jsonb from public.sesion_caja limit 1','42501','clave sesion privada');
  perform pg_temp.t04_reject(actor,'insert into public.sesion_caja (caja_id) values (gen_random_uuid()) returning to_jsonb(sesion_caja)','42501','INSERT sesion directo denegado');
  for f in select oid,proname,prosecdef,provolatile,proconfig,proowner from pg_proc where pronamespace='public'::regnamespace
    and proname in ('rpc_abrir_sesion_caja','rpc_obtener_sesion_caja_activa','rpc_obtener_historial_sesiones_caja') loop
    perform pg_temp.t04_assert(f.prosecdef and f.proconfig=array['search_path=pg_catalog']
      and pg_get_userbyid(f.proowner)='postgres' and f.provolatile=case when f.proname='rpc_abrir_sesion_caja' then 'v' else 's' end,
      'metadatos endurecidos '||f.proname);
    perform pg_temp.t04_assert(not has_function_privilege('anon',f.oid,'EXECUTE') and has_function_privilege('authenticated',f.oid,'EXECUTE'),
      'grants RPC '||f.proname);
  end loop;
  perform pg_temp.t04_assert(not exists(select 1 from pg_publication_tables where schemaname='public'
    and tablename in ('caja','sesion_caja','auditoria_caja','solicitud_apertura_caja')),'no exposicion realtime');
  begin update public.auditoria_caja set monto_inicial=0; raise exception 'audit editable'; exception when check_violation then null; end;
  perform pg_temp.t04_assert(true,'audit inmutable incluso postgres');
  begin delete from public.solicitud_apertura_caja; raise exception 'solicitud eliminable'; exception when check_violation then null; end;
  perform pg_temp.t04_assert(true,'solicitud inmutable incluso postgres');
end $security$;

-- Rollback atómico inducido después de crear la sesión pero antes de completar auditoría.
create function pg_temp.t04_fail_audit() returns trigger language plpgsql as $$
begin raise exception 'fallo audit inducido'; end $$;
create trigger t04_fail_audit before insert on public.auditoria_caja for each row
  when (new.caja_id='e1040000-0000-0000-0000-000000000105') execute function pg_temp.t04_fail_audit();
select pg_temp.t04_reject('e1040000-0000-0000-0000-000000000011',
  'select public.rpc_abrir_sesion_caja(''e1040000-0000-0000-0000-000000000105'',0,gen_random_uuid())','P0001','error audit retorna error');
select pg_temp.t04_assert(not exists(select 1 from public.sesion_caja where caja_id='e1040000-0000-0000-0000-000000000105')
  and not exists(select 1 from public.solicitud_apertura_caja where caja_id='e1040000-0000-0000-0000-000000000105')
  and not exists(select 1 from public.auditoria_caja where caja_id='e1040000-0000-0000-0000-000000000105'),'rollback sin session solicitud ni audit huerfanos');

set local role anon;
do $$ begin
  begin perform public.rpc_abrir_sesion_caja(null,0,null); raise exception 'anon abre'; exception when insufficient_privilege then null; end;
  begin perform public.rpc_obtener_sesion_caja_activa(null); raise exception 'anon lee'; exception when insufficient_privilege then null; end;
  begin perform public.rpc_obtener_historial_sesiones_caja(); raise exception 'anon historial'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select pg_temp.t04_assert(true,'TP12 RPC anon reales denegadas');
select 'E1-T04 SQL: '||count(*)||' comprobaciones aprobadas' from t04_checks;
rollback;
