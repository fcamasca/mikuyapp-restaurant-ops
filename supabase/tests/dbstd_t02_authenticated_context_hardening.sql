begin;

create function pg_temp.dbstd_set_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $dbstd_set_user$
begin
  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    coalesce(p_user_id::text, ''),
    true
  );
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$dbstd_set_user$;

create function pg_temp.dbstd_assert_three_rpcs_reject(p_case text)
returns void
language plpgsql
set search_path = pg_catalog
as $dbstd_assert_three_rpcs_reject$
declare
  v_function_name text;
begin
  foreach v_function_name in array array[
    'obtener_resumen_ventas_hoy',
    'exportar_ventas_hoy',
    'exportar_productos_local'
  ] loop
    begin
      execute pg_catalog.format('select * from public.%I()', v_function_name);
      raise exception '% no rechazó %', v_function_name, p_case;
    exception
      when sqlstate '42501' then
        if sqlerrm <> 'No autorizado' then
          raise exception '% devolvió mensaje inesperado para %: %',
            v_function_name,
            p_case,
            sqlerrm;
        end if;
    end;
  end loop;
end;
$dbstd_assert_three_rpcs_reject$;

do $verify_scope_and_contract$
declare
  v_function_name text;
  v_definition text;
begin
  foreach v_function_name in array array[
    'obtener_resumen_ventas_hoy',
    'exportar_ventas_hoy',
    'exportar_productos_local'
  ] loop
    select pg_catalog.pg_get_functiondef(function_metadata.oid)
    into strict v_definition
    from pg_catalog.pg_proc as function_metadata
    inner join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function_metadata.pronamespace
    where function_schema.nspname = 'public'
      and function_metadata.proname = v_function_name
      and pg_catalog.pg_get_function_identity_arguments(function_metadata.oid) = ''
      and function_metadata.prosecdef = true
      and function_metadata.provolatile = 's'
      and function_metadata.proowner = (
        select role_metadata.oid
        from pg_catalog.pg_roles as role_metadata
        where role_metadata.rolname = 'postgres'
      )
      and function_metadata.proconfig = array['search_path=pg_catalog'];

    if pg_catalog.strpos(v_definition, 'public.obtener_contexto_autenticado()') = 0
      or pg_catalog.strpos(v_definition, 'public.perfil_usuario') > 0
      or pg_catalog.strpos(v_definition, 'public.rol') > 0 then
      raise exception '% no usa exclusivamente el helper de contexto', v_function_name;
    end if;

    if pg_catalog.has_function_privilege(
        'anon',
        ('public.' || v_function_name || '()')::regprocedure,
        'EXECUTE'
      )
      or not pg_catalog.has_function_privilege(
        'authenticated',
        ('public.' || v_function_name || '()')::regprocedure,
        'EXECUTE'
      ) then
      raise exception '% cambió owner, seguridad, volatilidad o grants', v_function_name;
    end if;
  end loop;
end;
$verify_scope_and_contract$;

do $prepare_invalid_context_fixtures$
declare
  v_local_active uuid := '00000000-0000-0000-0000-00000000d201';
  v_local_inactive uuid := '00000000-0000-0000-0000-00000000d202';
  v_missing_profile uuid := '00000000-0000-0000-0000-00000000d211';
  v_inactive_profile uuid := '00000000-0000-0000-0000-00000000d212';
  v_inactive_role_profile uuid := '00000000-0000-0000-0000-00000000d213';
  v_inactive_local_profile uuid := '00000000-0000-0000-0000-00000000d214';
begin
  insert into auth.users (id, aud, role, email, encrypted_password) values
    (v_missing_profile, 'authenticated', 'authenticated', 'dbstd-missing-profile@example.invalid', 'test'),
    (v_inactive_profile, 'authenticated', 'authenticated', 'dbstd-inactive-profile@example.invalid', 'test'),
    (v_inactive_role_profile, 'authenticated', 'authenticated', 'dbstd-inactive-role@example.invalid', 'test'),
    (v_inactive_local_profile, 'authenticated', 'authenticated', 'dbstd-inactive-local@example.invalid', 'test');

  insert into public.local (id, codigo, nombre, activo) values
    (v_local_active, 'DBSTD-ACT', 'DBSTD activo', true),
    (v_local_inactive, 'DBSTD-INA', 'DBSTD inactivo', false);

  insert into public.perfil_usuario (id, local_id, rol_id, nombre, activo)
  select v_inactive_profile, v_local_active, role_row.id, 'Perfil inactivo', false
  from public.rol as role_row
  where role_row.codigo = 'ADMINISTRADOR'
  union all
  select v_inactive_role_profile, v_local_active, role_row.id, 'Rol inactivo', true
  from public.rol as role_row
  where role_row.codigo = 'ADMINISTRADOR'
  union all
  select v_inactive_local_profile, v_local_inactive, role_row.id, 'Local inactivo', true
  from public.rol as role_row
  where role_row.codigo = 'ADMINISTRADOR';
end;
$prepare_invalid_context_fixtures$;

select pg_temp.dbstd_set_user('00000000-0000-0000-0000-00000000d211');
select pg_temp.dbstd_assert_three_rpcs_reject('perfil inexistente');

select pg_temp.dbstd_set_user('00000000-0000-0000-0000-00000000d212');
select pg_temp.dbstd_assert_three_rpcs_reject('perfil inactivo');

update public.rol
set activo = false
where codigo = 'ADMINISTRADOR';
select pg_temp.dbstd_set_user('00000000-0000-0000-0000-00000000d213');
select pg_temp.dbstd_assert_three_rpcs_reject('rol inactivo');
update public.rol
set activo = true
where codigo = 'ADMINISTRADOR';

select pg_temp.dbstd_set_user('00000000-0000-0000-0000-00000000d214');
select pg_temp.dbstd_assert_three_rpcs_reject('local inactivo');

select pg_temp.dbstd_set_user(null);
select pg_temp.dbstd_assert_three_rpcs_reject('auth.uid() nulo');

select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-00000000d299',
  true
);
select pg_temp.dbstd_assert_three_rpcs_reject('contexto no resoluble');

select 'DBSTD-TP08..TP12 OK' as resultado;

rollback;
