begin;
create temporary table t08_checks(nombre text primary key);
create function pg_temp.t08_assert(p_ok boolean,p_nombre text) returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception 'T08: %',p_nombre; end if;
  insert into t08_checks values(p_nombre);
end $$;
create function pg_temp.t08_call(p_actor uuid,p_sql text) returns jsonb language plpgsql as $$
declare v_result jsonb;
begin
  perform set_config('request.jwt.claim.sub',coalesce(p_actor::text,''),true);
  set local role authenticated;
  execute p_sql into v_result;
  reset role;
  return v_result;
exception when others then reset role; raise;
end $$;
create function pg_temp.t08_reject(p_actor uuid,p_sql text,p_state text,p_nombre text)
returns void language plpgsql as $$
declare v_state text;
begin
  begin perform pg_temp.t08_call(p_actor,p_sql);
  exception when others then get stacked diagnostics v_state=returned_sqlstate; end;
  perform pg_temp.t08_assert(v_state=p_state,p_nombre);
end $$;

do $metadata$
declare c record; f record;
begin
  perform pg_temp.t08_assert(not exists(select 1 from pg_constraint
    where conrelid='public.pago'::regclass and conname='uq_pago_pedido_id'),'unicidad legacy retirada');
  perform pg_temp.t08_assert(to_regclass('public.idx_pago_pedido_id') is not null
    and to_regclass('public.uq_pago_sesion_actor_idempotencia') is not null,'indices pago nuevos');
  for c in select * from (values
    ('sesion_caja_id','uuid',false),('propina','numeric(10,2)',true),('idempotency_key','uuid',false)
  ) x(nombre,tipo,no_nulo) loop
    perform pg_temp.t08_assert(exists(select 1 from pg_attribute a where a.attrelid='public.pago'::regclass
      and a.attname=c.nombre and format_type(a.atttypid,a.atttypmod)=c.tipo and a.attnotnull=c.no_nulo),
      'columna '||c.nombre);
  end loop;
  perform pg_temp.t08_assert(exists(select 1 from pg_constraint where conrelid='public.pago'::regclass
    and conname='fk_pago_sesion_caja' and contype='f' and confdeltype='r'),'FK sesion restrict');
  perform pg_temp.t08_assert(exists(select 1 from pg_constraint where conrelid='public.pago'::regclass
    and conname='ck_pago_asociacion_e1' and contype='c'),'check legacy vs E1');
  select p.* into strict f from pg_proc p where p.oid=
    'public.rpc_registrar_pago_total_pedido(bigint,uuid,text,numeric,uuid)'::regprocedure;
  perform pg_temp.t08_assert(f.prosecdef and f.proconfig=array['search_path=pg_catalog']
    and pg_get_userbyid(f.proowner)='postgres' and f.provolatile='v','RPC endurecida');
  perform pg_temp.t08_assert(has_function_privilege('authenticated',f.oid,'EXECUTE')
    and not has_function_privilege('anon',f.oid,'EXECUTE'),'grants RPC');
  perform pg_temp.t08_assert(not has_table_privilege('authenticated','public.pago','INSERT')
    and not has_table_privilege('authenticated','public.pago','UPDATE')
    and not has_table_privilege('authenticated','public.pago','DELETE'),'sin DML pago cliente');
end $metadata$;

do $legacy$
begin
  perform pg_temp.t08_assert((select count(*)=1 from public.pago where pedido_id=-103
    and importe=42.35 and medio='TARJETA'
    and usuario_id='e1030000-0000-0000-0000-000000000011'
    and pagado_en='2026-08-20T11:00:00Z'::timestamptz
    and sesion_caja_id is null and idempotency_key is null and propina=0),
    'pago legacy intacto sin sesion fabricada');
  perform pg_temp.t08_assert(not exists(select 1 from public.sesion_caja where abierta_por='e1030000-0000-0000-0000-000000000011'),
    'sin sesion retroactiva legacy');
end $legacy$;

do $behaviour$
declare
  a uuid:='e1080000-0000-0000-0000-000000000011';
  b uuid:='e1080000-0000-0000-0000-000000000012';
  waiter uuid:='e1080000-0000-0000-0000-000000000013';
  other uuid:='e1080000-0000-0000-0000-000000000014';
  local_a uuid:='e1080000-0000-0000-0000-000000000001';
  local_b uuid:='e1080000-0000-0000-0000-000000000002';
  caja uuid:='e1080000-0000-0000-0000-000000000101';
  caja_b uuid:='e1080000-0000-0000-0000-000000000102';
  sesion uuid; sesion_b uuid; mesa uuid:='e1080000-0000-0000-0000-000000000201';
  categoria uuid:='e1080000-0000-0000-0000-000000000301';
  producto uuid:='e1080000-0000-0000-0000-000000000401';
  clave uuid:=gen_random_uuid(); resultado jsonb; retry jsonb;
begin
  insert into auth.users(id,aud,role,email,encrypted_password) values
    (a,'authenticated','authenticated','t08-a@example.invalid','x'),
    (b,'authenticated','authenticated','t08-b@example.invalid','x'),
    (waiter,'authenticated','authenticated','t08-w@example.invalid','x'),
    (other,'authenticated','authenticated','t08-o@example.invalid','x');
  insert into public.local(id,codigo,nombre) values(local_a,'T08-A','T08 A'),(local_b,'T08-B','T08 B');
  insert into public.perfil_usuario(id,local_id,rol_id,nombre)
    select a,local_a,id,'Caja A' from public.rol where codigo='CAJA' union all
    select b,local_a,id,'Caja B' from public.rol where codigo='CAJA' union all
    select waiter,local_a,id,'Mozo' from public.rol where codigo='MOZO' union all
    select other,local_b,id,'Caja otro local' from public.rol where codigo='CAJA';
  insert into public.caja(id,local_id,codigo,nombre) values(caja,local_a,'T08-A','Caja A'),(caja_b,local_b,'T08-B','Caja B');
  insert into public.sesion_caja(caja_id,local_id,abierta_por,monto_inicial,idempotency_key)
    values(caja,local_a,a,0,gen_random_uuid()) returning id into sesion;
  insert into public.sesion_caja(caja_id,local_id,abierta_por,monto_inicial,idempotency_key)
    values(caja_b,local_b,other,0,gen_random_uuid()) returning id into sesion_b;
  insert into public.categoria(id,local_id,codigo,nombre) values(categoria,local_a,'T08','T08');
  insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values(producto,local_a,categoria,'T08','T08',99);
  insert into public.mesa(id,local_id,codigo,nombre,estado) values(mesa,local_a,'T08','T08','PENDIENTE_PAGO');
  insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value
    values(-10801,local_a,mesa,waiter,'ENTREGADO');
  insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en)
    overriding system value values(-10801,-10801,producto,2,12.50,'LISTO',now());

  resultado:=pg_temp.t08_call(b,format(
    'select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10801,%L,''EFECTIVO'',3.25,%L) r',sesion,clave));
  perform pg_temp.t08_assert((resultado->>'importe')::numeric=25 and (resultado->>'propina')::numeric=3.25
    and resultado->>'sesion_caja_id'=sesion::text and resultado->>'pedido_estado'='PAGADO'
    and resultado->>'mesa_estado'='LIBRE','pago total asociado y propina separada');
  perform pg_temp.t08_assert((select count(*)=1 from public.pago where pedido_id=-10801 and sesion_caja_id=sesion
    and usuario_id=b and importe=25 and propina=3.25 and medio='EFECTIVO' and idempotency_key=clave),
    'fila pago actor sesion propina clave');
  retry:=pg_temp.t08_call(b,format(
    'select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10801,%L,''EFECTIVO'',3.25,%L) r',sesion,clave));
  perform pg_temp.t08_assert(retry=resultado and (select count(*)=1 from public.pago where pedido_id=-10801),
    'retry mismo resultado una fila');
  perform pg_temp.t08_reject(b,format(
    'select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10801,%L,''YAPE'',3.25,%L) r',sesion,clave),
    '22023','clave reutilizada otro medio');
  perform pg_temp.t08_reject(b,format(
    'select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10801,%L,''EFECTIVO'',3.26,%L) r',sesion,clave),
    '22023','clave reutilizada otra propina');
  perform pg_temp.t08_reject(b,format(
    'select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10801,%L,''EFECTIVO'',0,%L) r',sesion,gen_random_uuid()),
    '40001','segundo pago operativo aun no habilitado');
  perform pg_temp.t08_reject(other,format(
    'select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10801,%L,''EFECTIVO'',0,%L) r',sesion,gen_random_uuid()),
    '42501','otro local no usa sesion');
  perform pg_temp.t08_reject(b,format(
    'select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10801,%L,''EFECTIVO'',0,%L) r',sesion_b,gen_random_uuid()),
    '42501','sesion otro local no disponible');
  perform pg_temp.t08_reject(waiter,format(
    'select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10801,%L,''EFECTIVO'',0,%L) r',sesion,gen_random_uuid()),
    '42501','MOZO no cobra');
  perform pg_temp.t08_reject(b,format(
    'select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10801,%L,''EFECTIVO'',-1,%L) r',sesion,gen_random_uuid()),
    '22023','propina negativa');
  perform pg_temp.t08_reject(b,format(
    'select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10801,%L,''EFECTIVO'',1.001,%L) r',sesion,gen_random_uuid()),
    '22023','propina precision invalida');

  -- Prueba estructural, como postgres y dentro del rollback: dos filas para el
  -- mismo pedido son posibles, pero la RPC total no habilita esta operación.
  insert into public.pago(pedido_id,importe,medio,usuario_id,sesion_caja_id,propina,idempotency_key)
    values(-10801,1,'YAPE',a,sesion,0,gen_random_uuid());
  perform pg_temp.t08_assert((select count(*)=2 from public.pago where pedido_id=-10801),
    'estructura admite multiples filas por pedido');
  begin
    insert into public.pago(pedido_id,importe,medio,usuario_id,sesion_caja_id,propina,idempotency_key)
      values(-10801,1,'YAPE',b,sesion,0,clave);
    raise exception 'duplico idempotencia';
  exception when unique_violation then null; end;
  perform pg_temp.t08_assert(true,'indice idempotencia impide duplicado');
  begin
    insert into public.pago(pedido_id,importe,medio,usuario_id,sesion_caja_id,propina,idempotency_key)
      values(-10801,1,'YAPE',a,null,1,null);
    raise exception 'nuevo sin sesion aceptado';
  exception when check_violation then null; end;
  perform pg_temp.t08_assert(true,'NULL sesion sólo patrón legacy propina cero');
end $behaviour$;

set local role anon;
do $$ begin
  begin perform public.rpc_registrar_pago_total_pedido(null,null,null,null,null); raise exception 'anon cobra';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select pg_temp.t08_assert(true,'anon sin execute');
select 'E1-T08 SQL: '||count(*)||' comprobaciones aprobadas' from t08_checks;
rollback;
