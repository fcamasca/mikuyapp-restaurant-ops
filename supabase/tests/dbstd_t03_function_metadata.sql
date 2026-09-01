begin;

do $dbstd_tp13_function_metadata$
declare
  v_expected record;
  v_function_oid oid;
begin
  for v_expected in
    select *
    from (values
      (
        'exportar_productos_local'::text,
        ''::text,
        'TABLE(codigo_categoria text, categoria text, codigo_producto text, producto text, precio numeric, activo boolean)'::text
      ),
      (
        'exportar_ventas_hoy'::text,
        ''::text,
        'TABLE(pedido_id bigint, mesa text, pagado_en timestamp with time zone, medio text, importe numeric)'::text
      ),
      (
        'obtener_resumen_ventas_hoy'::text,
        ''::text,
        'TABLE(medio text, pedidos_pagados bigint, importe numeric)'::text
      ),
      (
        'obtener_creadores_pedidos_vigentes'::text,
        'p_pedido_ids bigint[]'::text,
        'TABLE(pedido_id bigint, creador_nombre text)'::text
      )
    ) as expected_function(function_name, identity_arguments, result_type)
  loop
    select function_metadata.oid
    into strict v_function_oid
    from pg_catalog.pg_proc as function_metadata
    inner join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function_metadata.pronamespace
    where function_schema.nspname = 'public'
      and function_metadata.proname = v_expected.function_name
      and pg_catalog.pg_get_function_identity_arguments(function_metadata.oid)
        = v_expected.identity_arguments;

    if not exists (
      select 1
      from pg_catalog.pg_proc as function_metadata
      inner join pg_catalog.pg_roles as owner_metadata
        on owner_metadata.oid = function_metadata.proowner
      where function_metadata.oid = v_function_oid
        and function_metadata.provolatile = 's'
        and function_metadata.prosecdef = true
        and function_metadata.proconfig = array['search_path=pg_catalog']
        and owner_metadata.rolname = 'postgres'
        and pg_catalog.pg_get_function_result(function_metadata.oid) = v_expected.result_type
    ) then
      raise exception 'DBSTD-TP13 metadatos o retorno inesperados: public.%(%)',
        v_expected.function_name,
        v_expected.identity_arguments;
    end if;
  end loop;
end;
$dbstd_tp13_function_metadata$;

do $dbstd_tp14_function_grants$
declare
  v_signature text;
  v_privilege_fingerprint text;
begin
  foreach v_signature in array array[
    'public.exportar_productos_local()',
    'public.exportar_ventas_hoy()',
    'public.obtener_resumen_ventas_hoy()',
    'public.obtener_creadores_pedidos_vigentes(bigint[])'
  ] loop
    if pg_catalog.has_function_privilege(
        'anon',
        v_signature,
        'EXECUTE'
      )
      or not pg_catalog.has_function_privilege(
        'authenticated',
        v_signature,
        'EXECUTE'
      ) then
      raise exception 'DBSTD-TP14 grants inesperados: %', v_signature;
    end if;
  end loop;

  select pg_catalog.md5(pg_catalog.string_agg(grant_row.line, E'\n' order by grant_row.line))
  into v_privilege_fingerprint
  from (
    select pg_catalog.concat_ws(
      '|', 'TABLE', grantor, grantee, table_schema, table_name,
      privilege_type, is_grantable, with_hierarchy
    ) as line
    from information_schema.role_table_grants
    where table_schema = 'public'
    union all
    select pg_catalog.concat_ws(
      '|', 'COLUMN', grantor, grantee, table_schema, table_name,
      column_name, privilege_type, is_grantable
    ) as line
    from information_schema.role_column_grants
    where table_schema = 'public'
  ) as grant_row;

  if v_privilege_fingerprint is distinct from 'd64f59917898b2943d5119205d55e110' then
    raise exception 'DBSTD-TP14 grants de tablas o columnas cambiaron: %',
      v_privilege_fingerprint;
  end if;
end;
$dbstd_tp14_function_grants$;

do $dbstd_tp15_function_definitions$
declare
  v_function_name text;
  v_definition text;
begin
  foreach v_function_name in array array[
    'exportar_productos_local',
    'exportar_ventas_hoy',
    'obtener_resumen_ventas_hoy'
  ] loop
    select pg_catalog.pg_get_functiondef(function_metadata.oid)
    into strict v_definition
    from pg_catalog.pg_proc as function_metadata
    inner join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function_metadata.pronamespace
    where function_schema.nspname = 'public'
      and function_metadata.proname = v_function_name
      and pg_catalog.pg_get_function_identity_arguments(function_metadata.oid) = '';

    if pg_catalog.strpos(v_definition, 'public.obtener_contexto_autenticado()') = 0
      or pg_catalog.strpos(v_definition, 'public.perfil_usuario') > 0
      or pg_catalog.strpos(v_definition, 'public.rol') > 0 then
      raise exception 'DBSTD-TP15 definición de T02 alterada: %', v_function_name;
    end if;
  end loop;

  select pg_catalog.pg_get_functiondef(
    'public.obtener_creadores_pedidos_vigentes(bigint[])'::regprocedure
  )
  into strict v_definition;

  if pg_catalog.strpos(v_definition, 'public.obtener_contexto_autenticado()') = 0
    or pg_catalog.strpos(v_definition, 'return query') = 0
    or pg_catalog.strpos(v_definition, 'insert into') > 0
    or pg_catalog.strpos(v_definition, 'update public.') > 0
    or pg_catalog.strpos(v_definition, 'delete from') > 0 then
    raise exception 'DBSTD-TP15 definición de creadores no es read-only o cambió dependencias';
  end if;
end;
$dbstd_tp15_function_definitions$;

select 'DBSTD-TP13..TP15 OK' as resultado;

rollback;
