begin;

create function pg_temp.h3_t02_set_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $h3_t02_set_user$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$h3_t02_set_user$;

create function pg_temp.h3_t02_fail_history()
returns trigger
language plpgsql
as $h3_t02_fail_history$
begin
  raise exception using errcode = 'P0001', message = 'fallo inducido H3-T02';
end;
$h3_t02_fail_history$;

do $h3_t02_metadata$
declare
  function_definition text;
begin
  select pg_catalog.pg_get_functiondef(function_metadata.oid)
  into strict function_definition
  from pg_catalog.pg_proc as function_metadata
  inner join pg_catalog.pg_namespace as function_schema
    on function_schema.oid = function_metadata.pronamespace
  where function_schema.nspname = 'public'
    and function_metadata.proname = 'crear_o_recuperar_pedido_mesa'
    and function_metadata.pronargs = 1
    and function_metadata.proargtypes = '2950'::pg_catalog.oidvector
    and function_metadata.prosecdef = true;

  if function_definition !~* 'FOR UPDATE'
    or function_definition !~* 'obtener_contexto_autenticado'
    or function_definition !~* 'auth\.uid'
    or function_definition !~* 'historial_estado'
    or function_definition !~* 'OCUPADA' then
    raise exception 'H3-T02 definición transaccional incompleta';
  end if;

  if pg_catalog.has_function_privilege(
      'anon', 'public.crear_o_recuperar_pedido_mesa(uuid)', 'EXECUTE'
    )
    or not pg_catalog.has_function_privilege(
      'authenticated', 'public.crear_o_recuperar_pedido_mesa(uuid)', 'EXECUTE'
    ) then
    raise exception 'H3-T02 privilegios EXECUTE inesperados';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.pedido', 'INSERT')
    or pg_catalog.has_table_privilege('authenticated', 'public.pedido', 'UPDATE')
    or pg_catalog.has_table_privilege('authenticated', 'public.historial_estado', 'INSERT')
    or pg_catalog.has_column_privilege('authenticated', 'public.mesa', 'estado', 'UPDATE') then
    raise exception 'H3-T02 concedió escritura directa innecesaria';
  end if;
end;
$h3_t02_metadata$;

do $h3_t02_behaviour$
declare
  v_admin_id uuid := '00000000-0000-0000-0000-00000000c201';
  v_waiter_id uuid := '00000000-0000-0000-0000-00000000c202';
  v_other_waiter_id uuid := '00000000-0000-0000-0000-00000000c203';
  v_local_id uuid := '00000000-0000-0000-0000-00000000c204';
  v_other_local_id uuid := '00000000-0000-0000-0000-00000000c205';
  v_free_table_id uuid := '00000000-0000-0000-0000-00000000c206';
  v_inactive_table_id uuid := '00000000-0000-0000-0000-00000000c207';
  v_other_table_id uuid := '00000000-0000-0000-0000-00000000c208';
  v_rollback_table_id uuid := '00000000-0000-0000-0000-00000000c209';
  v_first_order_id bigint;
  v_second_order_id bigint;
  v_created boolean;
  v_error_state text;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values
    (v_admin_id, 'authenticated', 'authenticated', 'h3-t02-admin@example.invalid', 'test'),
    (v_waiter_id, 'authenticated', 'authenticated', 'h3-t02-waiter@example.invalid', 'test'),
    (v_other_waiter_id, 'authenticated', 'authenticated', 'h3-t02-other@example.invalid', 'test');

  insert into public.local (id, codigo, nombre)
  values
    (v_local_id, 'H3-T02-A', 'Local H3 T02 A'),
    (v_other_local_id, 'H3-T02-B', 'Local H3 T02 B');

  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_admin_id, v_local_id, role_row.id, 'Admin H3 T02'
  from public.rol as role_row where role_row.codigo = 'ADMINISTRADOR'
  union all
  select v_waiter_id, v_local_id, role_row.id, 'Mozo H3 T02'
  from public.rol as role_row where role_row.codigo = 'MOZO'
  union all
  select v_other_waiter_id, v_other_local_id, role_row.id, 'Otro mozo H3 T02'
  from public.rol as role_row where role_row.codigo = 'MOZO';

  insert into public.mesa (id, local_id, codigo, nombre, activo)
  values
    (v_free_table_id, v_local_id, 'H3-T02-M1', 'Mesa libre', true),
    (v_inactive_table_id, v_local_id, 'H3-T02-M2', 'Mesa inactiva', false),
    (v_other_table_id, v_other_local_id, 'H3-T02-M3', 'Mesa otro local', true),
    (v_rollback_table_id, v_local_id, 'H3-T02-M4', 'Mesa rollback', true);

  perform pg_temp.h3_t02_set_user(v_waiter_id);

  select result.pedido_id, result.fue_creado
  into strict v_first_order_id, v_created
  from public.crear_o_recuperar_pedido_mesa(v_free_table_id) as result;

  if not v_created
    or (select estado from public.pedido where id = v_first_order_id) <> 'ABIERTO'
    or (select creado_por from public.pedido where id = v_first_order_id) <> v_waiter_id
    or (select local_id from public.pedido where id = v_first_order_id) <> v_local_id
    or (select estado from public.mesa where id = v_free_table_id) <> 'OCUPADA' then
    raise exception 'H3-T02 creación inicial inconsistente';
  end if;

  if not exists (
    select 1
    from public.historial_estado
    where pedido_id = v_first_order_id
      and estado_anterior is null
      and estado_nuevo = 'ABIERTO'
      and usuario_id = v_waiter_id
  ) then
    raise exception 'H3-T02 historial inicial ausente o incorrecto';
  end if;

  select result.pedido_id, result.fue_creado
  into strict v_second_order_id, v_created
  from public.crear_o_recuperar_pedido_mesa(v_free_table_id) as result;

  if v_created
    or v_second_order_id <> v_first_order_id
    or (select count(*) from public.pedido where mesa_id = v_free_table_id) <> 1
    or (select count(*) from public.historial_estado where pedido_id = v_first_order_id) <> 1 then
    raise exception 'H3-T02 recuperación duplicó pedido o historial';
  end if;

  begin
    perform public.crear_o_recuperar_pedido_mesa(v_inactive_table_id);
    raise exception 'H3-T02 aceptó mesa inactiva';
  exception when sqlstate '42501' then null;
  end;

  begin
    perform public.crear_o_recuperar_pedido_mesa(v_other_table_id);
    raise exception 'H3-T02 aceptó mesa de otro local';
  exception when sqlstate '42501' then null;
  end;

  perform pg_temp.h3_t02_set_user(v_other_waiter_id);
  begin
    perform public.crear_o_recuperar_pedido_mesa(v_free_table_id);
    raise exception 'H3-T02 permitió recuperar pedido de otro local';
  exception when sqlstate '42501' then null;
  end;

  perform pg_temp.h3_t02_set_user(v_admin_id);
  begin
    perform public.crear_o_recuperar_pedido_mesa(v_rollback_table_id);
    raise exception 'H3-T02 aceptó un rol distinto de MOZO';
  exception when sqlstate '42501' then null;
  end;

  perform pg_temp.h3_t02_set_user(v_waiter_id);

  create trigger h3_t02_fail_history
  before insert on public.historial_estado
  for each row execute function pg_temp.h3_t02_fail_history();

  begin
    perform public.crear_o_recuperar_pedido_mesa(v_rollback_table_id);
    raise exception 'H3-T02 no propagó el fallo inducido';
  exception when sqlstate 'P0001' then
    get stacked diagnostics v_error_state = returned_sqlstate;
  end;

  if v_error_state <> 'P0001'
    or exists (select 1 from public.pedido where mesa_id = v_rollback_table_id)
    or (select estado from public.mesa where id = v_rollback_table_id) <> 'LIBRE' then
    raise exception 'H3-T02 rollback incompleto';
  end if;

  drop trigger h3_t02_fail_history on public.historial_estado;
end;
$h3_t02_behaviour$;

rollback;
