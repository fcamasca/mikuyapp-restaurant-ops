begin;
create temporary table e1_checks (nombre text primary key);
create function pg_temp.e1_assert(p_ok boolean, p_nombre text)
returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception 'E1-T03: %', p_nombre; end if;
  insert into e1_checks values (p_nombre);
end $$;
create function pg_temp.e1_reject(p_sql text, p_estado text, p_nombre text)
returns void language plpgsql as $$
declare v_estado text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate;
  end;
  perform pg_temp.e1_assert(v_estado = p_estado, p_nombre);
end $$;

select pg_temp.e1_assert(not exists (select 1 from public.sesion_caja), 'no sesiones retroactivas');
select pg_temp.e1_assert(
  (select count(*) from public.caja) = (select count(*) from public.local where activo)
  and not exists (select 1 from public.local l where l.activo and not exists
    (select 1 from public.caja c where c.local_id = l.id and c.codigo = 'CAJA-01')),
  'una caja minima por local activo');
select pg_temp.e1_assert(not exists (
  select 1 from public.caja where local_id = 'e1030000-0000-0000-0000-000000000003'
), 'sin provisionar local inactivo');
select pg_temp.e1_assert((select count(*) from pg_class where oid in
  ('public.caja'::regclass, 'public.sesion_caja'::regclass) and relrowsecurity) = 2, 'RLS habilitado');
select pg_temp.e1_assert(not exists (select 1 from pg_policy where polrelid in
  ('public.caja'::regclass, 'public.sesion_caja'::regclass)), 'denegacion por defecto hasta T04');
select pg_temp.e1_assert(not exists (select 1 from pg_constraint where conrelid in
  ('public.caja'::regclass, 'public.sesion_caja'::regclass) and contype = 'f' and confdeltype <> 'r'), 'FK restrict');
select pg_temp.e1_assert(not exists (select 1 from pg_publication_tables where schemaname = 'public'
  and tablename in ('caja', 'sesion_caja')), 'sin payload financiero realtime');

do $$
declare v_role text; v_table text; v_priv text;
begin
  foreach v_role in array array['anon', 'authenticated'] loop
    foreach v_table in array array['public.caja', 'public.sesion_caja'] loop
      foreach v_priv in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
        perform pg_temp.e1_assert(not has_table_privilege(v_role, v_table, v_priv), v_role || ' ' || v_table || ' ' || v_priv);
      end loop;
    end loop;
    perform pg_temp.e1_assert(not has_function_privilege(v_role,
      'public.tgf_sesion_caja_conservar_historia()', 'EXECUTE'), 'trigger no invocable ' || v_role);
  end loop;
end $$;

do $$
declare
  v_caja uuid;
  v_otra uuid;
  v_sesion uuid;
  v_sql text;
  v_columna text;
begin
  select id into strict v_caja from public.caja where local_id = 'e1030000-0000-0000-0000-000000000001';
  select id into strict v_otra from public.caja where local_id = 'e1030000-0000-0000-0000-000000000002';
  perform set_config('request.jwt.claim.sub', 'e1030000-0000-0000-0000-000000000011', true);
  insert into public.sesion_caja (caja_id, local_id, monto_inicial, idempotency_key)
  values (v_caja, 'e1030000-0000-0000-0000-000000000001', 0, gen_random_uuid()) returning id into v_sesion;
  perform pg_temp.e1_assert((select abierta_por = auth.uid() and abierta_en = now() and estado = 'ABIERTA'
    from public.sesion_caja where id = v_sesion), 'defaults actor hora estado');
  v_sql := format('insert into public.sesion_caja (caja_id, local_id, monto_inicial, idempotency_key) values (%L, %L, %%s, gen_random_uuid())',
    v_otra, 'e1030000-0000-0000-0000-000000000002');
  perform pg_temp.e1_reject(format(v_sql, '-1'), '23514', 'monto negativo');
  perform pg_temp.e1_reject(format(v_sql, 'null'), '23502', 'monto null');
  perform pg_temp.e1_reject(format(v_sql, '''NaN''::numeric'), '23514', 'monto NaN');
  perform pg_temp.e1_reject(format(v_sql, '''Infinity''::numeric'), '22003', 'monto infinito');
  perform pg_temp.e1_reject(format('insert into public.sesion_caja (caja_id, local_id, monto_inicial, idempotency_key)
    values (%L, %L, 1, gen_random_uuid())', v_otra, 'e1030000-0000-0000-0000-000000000001'), '23503', 'FK caja local cruzado');
  perform pg_temp.e1_reject(format('insert into public.sesion_caja (caja_id, local_id, monto_inicial, idempotency_key)
    values (%L, %L, 1, gen_random_uuid())', v_caja, 'e1030000-0000-0000-0000-000000000001'), '23505', 'segunda abierta');
  perform pg_temp.e1_reject(format('update public.sesion_caja set abierta_por = %L where id = %L',
    'e1030000-0000-0000-0000-000000000012', v_sesion), '23514', 'abierta_por inmutable');
  perform pg_temp.e1_reject(format('update public.sesion_caja set monto_inicial = 10 where id = %L', v_sesion), '23514', 'monto inicial inmutable');
  perform pg_temp.e1_reject(format('update public.sesion_caja set abierta_en = now() - interval ''1 day'' where id = %L', v_sesion), '23514', 'hora apertura inmutable');
  foreach v_columna in array array['id', 'caja_id', 'local_id', 'idempotency_key'] loop
    perform pg_temp.e1_reject(format('update public.sesion_caja set %I = gen_random_uuid() where id = %L', v_columna, v_sesion),
      '23514', v_columna || ' inmutable');
  end loop;
  perform pg_temp.e1_reject(format('delete from public.sesion_caja where id = %L', v_sesion), '23514', 'no borrar historia');
  perform pg_temp.e1_reject(format('update public.sesion_caja set estado = ''CERRADA'' where id = %L', v_sesion), '23514', 'cierre incompleto');
  perform pg_temp.e1_reject(format('delete from public.caja where id = %L', v_caja), '23503', 'no borrar caja referenciada');
  perform pg_temp.e1_reject('delete from public.perfil_usuario where id = ''e1030000-0000-0000-0000-000000000011''', '23503', 'no borrar actor referenciado');

  -- Escritura de fixture como postgres, no es una RPC de cierre ni prueba de autorización.
  update public.sesion_caja set estado = 'CERRADA', cerrada_por = 'e1030000-0000-0000-0000-000000000012',
    cerrada_en = now(), efectivo_esperado = 0, efectivo_contado = 0, diferencia = 0 where id = v_sesion;
  perform pg_temp.e1_assert((select abierta_por <> cerrada_por from public.sesion_caja where id = v_sesion), 'modelo admite cierre B apertura A');
  perform pg_temp.e1_reject('delete from public.perfil_usuario where id = ''e1030000-0000-0000-0000-000000000012''', '23503', 'no borrar actor de cierre');
  perform pg_temp.e1_reject(format('update public.sesion_caja set estado = ''ABIERTA'' where id = %L', v_sesion), '23514', 'sin reabrir cerrada');
  perform pg_temp.e1_reject(format('update public.sesion_caja set motivo_diferencia = ''editar'' where id = %L', v_sesion), '23514', 'snapshot cierre inmutable');
  perform pg_temp.e1_reject(format('insert into public.sesion_caja (caja_id, local_id, monto_inicial, idempotency_key)
    select caja_id, local_id, monto_inicial, idempotency_key from public.sesion_caja where id = %L', v_sesion), '23505', 'idempotencia apertura persiste tras cierre');
  insert into public.sesion_caja (caja_id, local_id, monto_inicial, idempotency_key)
    values (v_caja, 'e1030000-0000-0000-0000-000000000001', 12.35, gen_random_uuid()) returning id into v_sesion;
  perform pg_temp.e1_assert((select count(*) from public.sesion_caja where caja_id = v_caja) = 2,
    'varias sesiones historicas misma caja');
  perform pg_temp.e1_assert((select count(*) from public.sesion_caja where caja_id = v_caja and estado = 'ABIERTA') = 1,
    'una sola abierta entre historicas');
  v_sql := format('update public.sesion_caja set estado = ''CERRADA'', cerrada_por = abierta_por, cerrada_en = now(),
    efectivo_esperado = 12.35, efectivo_contado = 10, diferencia = -2.35, motivo_diferencia = %%s where id = %L', v_sesion);
  perform pg_temp.e1_reject(format(v_sql, 'null'), '23514', 'diferencia sin motivo');
  perform pg_temp.e1_reject(format(v_sql, '''  '''), '23514', 'diferencia motivo vacio');
  execute format(v_sql, '''Faltante contado''');
  perform pg_temp.e1_assert((select diferencia = -2.35 and estado = 'CERRADA' from public.sesion_caja where id = v_sesion),
    'modelo admite diferencia con motivo');
end $$;

-- Acceso real con rol PostgreSQL cliente, no sólo inspección del ACL.
set local role authenticated;
do $$
begin
  begin perform 1 from public.sesion_caja; raise exception 'SELECT permitido'; exception when insufficient_privilege then null; end;
  begin insert into public.caja (local_id, codigo, nombre) values (gen_random_uuid(), 'X', 'X');
    raise exception 'INSERT permitido'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select pg_temp.e1_assert(true, 'SELECT INSERT reales authenticated denegados');
set local role anon;
do $$
begin
  begin perform 1 from public.caja; raise exception 'SELECT anon permitido'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select pg_temp.e1_assert(true, 'SELECT real anon denegado');
select 'E1-T03 SQL: ' || count(*) || ' comprobaciones aprobadas' from e1_checks;
rollback;
