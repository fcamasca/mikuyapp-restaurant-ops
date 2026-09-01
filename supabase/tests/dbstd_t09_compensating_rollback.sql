\set ON_ERROR_STOP on

create temp table dbstd_t09_data_snapshot (
  table_name text primary key,
  row_count bigint not null,
  row_fingerprint text not null
);

do $snapshot_public_data$
declare
  v_table record;
  v_count bigint;
  v_fingerprint text;
begin
  for v_table in
    select table_metadata.relname
    from pg_catalog.pg_class as table_metadata
    inner join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public'
      and table_metadata.relkind = 'r'
    order by table_metadata.relname
  loop
    execute pg_catalog.format(
      'select pg_catalog.count(*), pg_catalog.md5(coalesce(pg_catalog.string_agg(pg_catalog.to_jsonb(source_row)::text, E''\n'' order by pg_catalog.to_jsonb(source_row)::text), '''')) from public.%I as source_row',
      v_table.relname
    ) into v_count, v_fingerprint;
    insert into dbstd_t09_data_snapshot values (v_table.relname, v_count, v_fingerprint);
  end loop;
end;
$snapshot_public_data$;

create temp table dbstd_t09_catalog_snapshot as
select
  (
    select pg_catalog.md5(pg_catalog.string_agg(
      pg_catalog.concat_ws('|', table_metadata.relname, attribute_metadata.attname,
        pg_catalog.format_type(attribute_metadata.atttypid, attribute_metadata.atttypmod),
        attribute_metadata.attnotnull::text, attribute_metadata.attidentity,
        attribute_metadata.attgenerated), E'\n'
      order by table_metadata.relname, attribute_metadata.attnum))
    from pg_catalog.pg_attribute as attribute_metadata
    inner join pg_catalog.pg_class as table_metadata on table_metadata.oid = attribute_metadata.attrelid
    inner join pg_catalog.pg_namespace as table_schema on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public' and table_metadata.relkind = 'r'
      and attribute_metadata.attnum > 0 and not attribute_metadata.attisdropped
  ) as table_fingerprint,
  (
    select pg_catalog.md5(pg_catalog.string_agg(pg_catalog.pg_get_constraintdef(constraint_metadata.oid), E'\n'
      order by constraint_metadata.conrelid::regclass::text, constraint_metadata.conname))
    from pg_catalog.pg_constraint as constraint_metadata
    inner join pg_catalog.pg_namespace as constraint_schema on constraint_schema.oid = constraint_metadata.connamespace
    where constraint_schema.nspname = 'public'
  ) as constraint_fingerprint,
  (
    select pg_catalog.md5(pg_catalog.string_agg(pg_catalog.pg_get_indexdef(index_metadata.indexrelid), E'\n'
      order by index_metadata.indexrelid::regclass::text))
    from pg_catalog.pg_index as index_metadata
    inner join pg_catalog.pg_class as table_metadata on table_metadata.oid = index_metadata.indrelid
    inner join pg_catalog.pg_namespace as table_schema on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public'
  ) as index_fingerprint,
  (
    select pg_catalog.md5(pg_catalog.string_agg(
      pg_catalog.concat_ws('|', table_metadata.relname, table_metadata.relrowsecurity::text,
        table_metadata.relforcerowsecurity::text), E'\n' order by table_metadata.relname))
    from pg_catalog.pg_class as table_metadata
    inner join pg_catalog.pg_namespace as table_schema on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public' and table_metadata.relkind = 'r'
  ) as rls_fingerprint,
  (
    select pg_catalog.md5(pg_catalog.string_agg(
      pg_catalog.concat_ws('|', table_metadata.relname, policy_metadata.polname,
        policy_metadata.polcmd, policy_metadata.polpermissive::text, policy_metadata.polroles::text,
        coalesce(pg_catalog.pg_get_expr(policy_metadata.polqual, policy_metadata.polrelid), ''),
        coalesce(pg_catalog.pg_get_expr(policy_metadata.polwithcheck, policy_metadata.polrelid), '')),
      E'\n' order by table_metadata.relname, policy_metadata.polname))
    from pg_catalog.pg_policy as policy_metadata
    inner join pg_catalog.pg_class as table_metadata on table_metadata.oid = policy_metadata.polrelid
    inner join pg_catalog.pg_namespace as table_schema on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public'
  ) as policy_fingerprint,
  (
    select pg_catalog.md5(pg_catalog.string_agg(pg_catalog.pg_get_triggerdef(trigger_metadata.oid), E'\n'
      order by table_metadata.relname, trigger_metadata.tgname))
    from pg_catalog.pg_trigger as trigger_metadata
    inner join pg_catalog.pg_class as table_metadata on table_metadata.oid = trigger_metadata.tgrelid
    inner join pg_catalog.pg_namespace as table_schema on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public' and not trigger_metadata.tgisinternal
  ) as trigger_fingerprint,
  pg_catalog.md5((select function_metadata.prosrc from pg_catalog.pg_proc as function_metadata
    where function_metadata.oid = 'public.registrar_auditoria_detalle_pedido()'::regprocedure)) as audit_function_fingerprint;

\ir ../rollbacks/20260831000100_dbstd_standardization.sql

do $dbstd_tp25_rollback_metadata$
declare
  v_function_name text;
  v_definition text;
  v_comment_count integer;
begin
  foreach v_function_name in array array[
    'exportar_productos_local', 'exportar_ventas_hoy',
    'obtener_resumen_ventas_hoy', 'obtener_creadores_pedidos_vigentes'
  ] loop
    if not exists (
      select 1
      from pg_catalog.pg_proc as function_metadata
      inner join pg_catalog.pg_namespace as function_schema on function_schema.oid = function_metadata.pronamespace
      inner join pg_catalog.pg_roles as owner_metadata on owner_metadata.oid = function_metadata.proowner
      where function_schema.nspname = 'public' and function_metadata.proname = v_function_name
        and function_metadata.provolatile = 'v' and function_metadata.prosecdef
        and function_metadata.proconfig = array['search_path=pg_catalog']
        and owner_metadata.rolname = 'postgres'
    ) then
      raise exception 'DBSTD-TP25 metadatos H6 no restaurados: %', v_function_name;
    end if;
  end loop;

  foreach v_function_name in array array[
    'exportar_productos_local', 'exportar_ventas_hoy', 'obtener_resumen_ventas_hoy'
  ] loop
    select pg_catalog.pg_get_functiondef(
      pg_catalog.to_regprocedure('public.' || v_function_name || '()')) into strict v_definition;
    if pg_catalog.strpos(v_definition, 'public.obtener_contexto_autenticado()') > 0
      or pg_catalog.strpos(v_definition, 'public.perfil_usuario') = 0
      or pg_catalog.strpos(v_definition, 'public.rol') = 0 then
      raise exception 'DBSTD-TP25 cuerpo H6 no restaurado: %', v_function_name;
    end if;
    if pg_catalog.has_function_privilege('anon', ('public.' || v_function_name || '()')::regprocedure, 'EXECUTE')
      or not pg_catalog.has_function_privilege('authenticated', ('public.' || v_function_name || '()')::regprocedure, 'EXECUTE') then
      raise exception 'DBSTD-TP25 grants H6 no restaurados: %', v_function_name;
    end if;
  end loop;

  if pg_catalog.has_function_privilege('anon', 'public.obtener_creadores_pedidos_vigentes(bigint[])', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.obtener_creadores_pedidos_vigentes(bigint[])', 'EXECUTE') then
    raise exception 'DBSTD-TP25 grants de creadores no restaurados';
  end if;

  select pg_catalog.count(*)::integer into v_comment_count
  from (
    select pg_catalog.col_description(attribute_metadata.attrelid, attribute_metadata.attnum) as description
    from pg_catalog.pg_attribute as attribute_metadata
    where (attribute_metadata.attrelid, attribute_metadata.attname) in (
      ('public.pedido'::regclass, 'estado'), ('public.pedido'::regclass, 'enviado_en'),
      ('public.pedido'::regclass, 'modificado_en'), ('public.pedido'::regclass, 'modificado_por'),
      ('public.detalle_pedido'::regclass, 'estado'), ('public.detalle_pedido'::regclass, 'precio_unitario'),
      ('public.detalle_pedido'::regclass, 'enviado_en'), ('public.pago'::regclass, 'importe'))
    union all
    select pg_catalog.obj_description(signature::regprocedure, 'pg_proc')
    from unnest(array[
      'public.obtener_contexto_autenticado()',
      'public.sincronizar_estado_operativo_pedido(bigint,uuid)',
      'public.registrar_auditoria_detalle_pedido()',
      'public.exportar_productos_local()', 'public.exportar_ventas_hoy()',
      'public.obtener_resumen_ventas_hoy()',
      'public.obtener_creadores_pedidos_vigentes(bigint[])']) as signature
    union all
    select pg_catalog.obj_description(trigger_metadata.oid, 'pg_trigger')
    from pg_catalog.pg_trigger as trigger_metadata
    where trigger_metadata.tgrelid = 'public.detalle_pedido'::regclass
      and trigger_metadata.tgname = 'detalle_pedido_registrar_auditoria'
  ) as approved_object where description is not null;
  if v_comment_count <> 0 then
    raise exception 'DBSTD-TP25 comentarios DBSTD no retirados: %', v_comment_count;
  end if;
end;
$dbstd_tp25_rollback_metadata$;

do $dbstd_tp25_invariants$
declare
  v_changed_table text;
  v_baseline_catalog dbstd_t09_catalog_snapshot%rowtype;
  v_current_catalog dbstd_t09_catalog_snapshot%rowtype;
begin
  for v_changed_table in select table_name from dbstd_t09_data_snapshot loop
    execute pg_catalog.format(
      'select case when snapshot.row_count <> current_rows.row_count or snapshot.row_fingerprint <> current_rows.row_fingerprint then %L end from dbstd_t09_data_snapshot snapshot cross join lateral (select pg_catalog.count(*) row_count, pg_catalog.md5(coalesce(pg_catalog.string_agg(pg_catalog.to_jsonb(source_row)::text, E''\n'' order by pg_catalog.to_jsonb(source_row)::text), '''')) row_fingerprint from public.%I source_row) current_rows where snapshot.table_name = %L',
      v_changed_table, v_changed_table, v_changed_table
    ) into v_changed_table;
    exit when v_changed_table is not null;
  end loop;
  if v_changed_table is not null then raise exception 'DBSTD-TP25 datos cambiaron en %', v_changed_table; end if;

  select * into strict v_baseline_catalog from dbstd_t09_catalog_snapshot;
  select
    (select pg_catalog.md5(pg_catalog.string_agg(
      pg_catalog.concat_ws('|', c.relname, a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod),
        a.attnotnull::text, a.attidentity, a.attgenerated), E'\n' order by c.relname, a.attnum))
     from pg_catalog.pg_attribute a join pg_catalog.pg_class c on c.oid=a.attrelid
     join pg_catalog.pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relkind='r' and a.attnum>0 and not a.attisdropped),
    (select pg_catalog.md5(pg_catalog.string_agg(pg_catalog.pg_get_constraintdef(co.oid), E'\n'
      order by co.conrelid::regclass::text, co.conname))
     from pg_catalog.pg_constraint co join pg_catalog.pg_namespace n on n.oid=co.connamespace where n.nspname='public'),
    (select pg_catalog.md5(pg_catalog.string_agg(pg_catalog.pg_get_indexdef(i.indexrelid), E'\n'
      order by i.indexrelid::regclass::text))
     from pg_catalog.pg_index i join pg_catalog.pg_class c on c.oid=i.indrelid
     join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public'),
    (select pg_catalog.md5(pg_catalog.string_agg(pg_catalog.concat_ws('|', c.relname,
      c.relrowsecurity::text, c.relforcerowsecurity::text), E'\n' order by c.relname))
     from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relkind='r'),
    (select pg_catalog.md5(pg_catalog.string_agg(pg_catalog.concat_ws('|', c.relname, p.polname,
      p.polcmd, p.polpermissive::text, p.polroles::text,
      coalesce(pg_catalog.pg_get_expr(p.polqual,p.polrelid),''),
      coalesce(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'')), E'\n' order by c.relname,p.polname))
     from pg_catalog.pg_policy p join pg_catalog.pg_class c on c.oid=p.polrelid
     join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public'),
    (select pg_catalog.md5(pg_catalog.string_agg(pg_catalog.pg_get_triggerdef(t.oid), E'\n'
      order by c.relname,t.tgname))
     from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid
     join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal),
    pg_catalog.md5((select p.prosrc from pg_catalog.pg_proc p
      where p.oid='public.registrar_auditoria_detalle_pedido()'::regprocedure))
  into v_current_catalog;

  if v_current_catalog is distinct from v_baseline_catalog then
    raise exception 'DBSTD-TP25 tablas, constraints, índices, RLS, policies, triggers o auditoría cambiaron';
  end if;
end;
$dbstd_tp25_invariants$;

select pg_catalog.set_config('request.jwt.claim.sub', '', false);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', false);

do $dbstd_tp26_legacy_missing_context$
begin
  if (select pg_catalog.count(*) from public.exportar_productos_local()) <> 0
    or (select pg_catalog.count(*) from public.exportar_ventas_hoy()) <> 0
    or (select pg_catalog.count(*) from public.obtener_resumen_ventas_hoy()) <> 0 then
    raise exception 'DBSTD-TP26 el contexto ausente no restauró el retorno vacío H6';
  end if;
end;
$dbstd_tp26_legacy_missing_context$;

\ir h6_t02_sales_exports.sql
\ir order_audit_trail.sql

select 'DBSTD-TP25 rollback compensatorio OK' as resultado;
select 'DBSTD-TP26 regresión H6 tras rollback OK; hardening 42501 retirado' as resultado;

\ir ../migrations/20260831000100_dbstd_t02_authenticated_context_hardening.sql
\ir dbstd_t02_authenticated_context_hardening.sql
\ir dbstd_t03_function_metadata.sql
\ir dbstd_t04_catalog_comments.sql
\ir order_audit_trail.sql

select 'DBSTD-T09 entorno local restaurado a DBSTD vigente' as resultado;
