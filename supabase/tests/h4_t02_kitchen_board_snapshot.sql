begin;

create function pg_temp.h4_t02_set_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $h4_t02_set_user$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$h4_t02_set_user$;

do $h4_t02_metadata$
declare
  v_function text;
  v_result text;
begin
  select pg_catalog.pg_get_functiondef(function_row.oid),
         pg_catalog.pg_get_function_result(function_row.oid)
  into strict v_function, v_result
  from pg_catalog.pg_proc as function_row
  inner join pg_catalog.pg_namespace as function_schema
    on function_schema.oid = function_row.pronamespace
  where function_schema.nspname = 'public'
    and function_row.proname = 'obtener_tablero_cocina'
    and function_row.pronargs = 0
    and function_row.prosecdef
    and function_row.provolatile = 's'
    and function_row.proowner = (
      select role_row.oid from pg_catalog.pg_roles as role_row
      where role_row.rolname = 'postgres'
    )
    and function_row.proconfig = array['search_path=pg_catalog'];

  if v_function !~* 'auth\.uid'
    or v_function !~* 'obtener_contexto_autenticado'
    or v_function !~* '''COCINA'''
    or v_function !~* 'detail_row\.estado in'
    or v_function ~* 'product_row\.activo'
    or v_result !~ 'pedido_id bigint'
    or v_result !~ 'mesa_codigo text'
    or v_result !~ 'producto_nombre text'
    or v_result !~ 'enviado_en timestamp with time zone'
    or v_result !~ 'modificado_en timestamp with time zone' then
    raise exception 'H4-T02 contrato o seguridad del snapshot inesperados';
  end if;

  if pg_catalog.has_function_privilege(
      'anon', 'public.obtener_tablero_cocina()', 'EXECUTE'
    ) or not pg_catalog.has_function_privilege(
      'authenticated', 'public.obtener_tablero_cocina()', 'EXECUTE'
    ) then
    raise exception 'H4-T02 privilegios de ejecución inesperados';
  end if;

  if pg_catalog.has_column_privilege(
      'authenticated', 'public.detalle_pedido', 'estado', 'UPDATE'
    ) or pg_catalog.has_column_privilege(
      'authenticated', 'public.pedido', 'estado', 'UPDATE'
    ) or pg_catalog.has_column_privilege(
      'authenticated', 'public.mesa', 'estado', 'UPDATE'
    ) then
    raise exception 'H4-T02 amplió escrituras directas';
  end if;
end;
$h4_t02_metadata$;

do $h4_t02_behaviour$
declare
  v_kitchen_a uuid := '00000000-0000-0000-0000-00000000d421';
  v_kitchen_b uuid := '00000000-0000-0000-0000-00000000d422';
  v_waiter_a uuid := '00000000-0000-0000-0000-00000000d423';
  v_local_a uuid := '00000000-0000-0000-0000-00000000d424';
  v_local_b uuid := '00000000-0000-0000-0000-00000000d425';
  v_table_a uuid := '00000000-0000-0000-0000-00000000d426';
  v_table_b uuid := '00000000-0000-0000-0000-00000000d427';
  v_category_a uuid := '00000000-0000-0000-0000-00000000d428';
  v_category_b uuid := '00000000-0000-0000-0000-00000000d429';
  v_product_active uuid := '00000000-0000-0000-0000-00000000d42a';
  v_product_historic uuid := '00000000-0000-0000-0000-00000000d42b';
  v_product_b uuid := '00000000-0000-0000-0000-00000000d42c';
  v_sent_at timestamptz := '2026-08-27 10:00:00-05';
  v_count integer;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values
    (v_kitchen_a, 'authenticated', 'authenticated', 'h4-t02-kitchen-a@example.invalid', 'test'),
    (v_kitchen_b, 'authenticated', 'authenticated', 'h4-t02-kitchen-b@example.invalid', 'test'),
    (v_waiter_a, 'authenticated', 'authenticated', 'h4-t02-waiter@example.invalid', 'test');

  insert into public.local (id, codigo, nombre)
  values
    (v_local_a, 'H4-T02-A', 'Local H4 T02 A'),
    (v_local_b, 'H4-T02-B', 'Local H4 T02 B');

  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_kitchen_a, v_local_a, role_row.id, 'Cocina A'
  from public.rol as role_row where role_row.codigo = 'COCINA'
  union all
  select v_kitchen_b, v_local_b, role_row.id, 'Cocina B'
  from public.rol as role_row where role_row.codigo = 'COCINA'
  union all
  select v_waiter_a, v_local_a, role_row.id, 'Mozo A'
  from public.rol as role_row where role_row.codigo = 'MOZO';

  insert into public.mesa (id, local_id, codigo, nombre, estado)
  values
    (v_table_a, v_local_a, 'M-A', 'Mesa A', 'OCUPADA'),
    (v_table_b, v_local_b, 'M-B', 'Mesa B', 'OCUPADA');

  insert into public.categoria (id, local_id, codigo, nombre, activo)
  values
    (v_category_a, v_local_a, 'C-A', 'Categoría histórica', false),
    (v_category_b, v_local_b, 'C-B', 'Categoría B', true);

  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, activo)
  values
    (v_product_active, v_local_a, v_category_a, 'P-A1', 'Producto activo', 10, true),
    (v_product_historic, v_local_a, v_category_a, 'P-A2', 'Producto histórico inactivo', 12, false),
    (v_product_b, v_local_b, v_category_b, 'P-B1', 'Producto B', 8, true);

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado, enviado_en)
  overriding system value
  values
    (-40201, v_local_a, v_table_a, v_waiter_a, 'ENVIADO', v_sent_at),
    (-40202, v_local_a, v_table_a, v_waiter_a, 'PAGADO', v_sent_at),
    (-40203, v_local_a, v_table_a, v_waiter_a, 'ANULADO', null),
    (-40204, v_local_b, v_table_b, v_kitchen_b, 'ENVIADO', v_sent_at);

  perform pg_temp.h4_t02_set_user(v_waiter_a);

  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, observacion, estado, enviado_en
  ) overriding system value
  values
    (-40211, -40201, v_product_active, 1, 10, null, 'ABIERTO', null),
    (-40212, -40201, v_product_active, 1, 10, 'Nuevo', 'ENVIADO', v_sent_at),
    (-40213, -40201, v_product_historic, 2, 12, 'Histórico', 'RECIBIDO_COCINA', v_sent_at),
    (-40214, -40201, v_product_active, 1, 10, null, 'EN_PREPARACION', v_sent_at),
    (-40215, -40201, v_product_active, 3, 10, null, 'LISTO', v_sent_at),
    (-40216, -40202, v_product_active, 1, 10, null, 'LISTO', v_sent_at),
    (-40217, -40203, v_product_active, 1, 10, null, 'ENVIADO', v_sent_at),
    (-40218, -40204, v_product_b, 1, 8, null, 'ENVIADO', v_sent_at);

  perform pg_temp.h4_t02_set_user(v_kitchen_a);

  select count(*) into v_count from public.obtener_tablero_cocina();
  if v_count <> 4 then
    raise exception 'H4-T02 esperaba 4 filas del local A y obtuvo %', v_count;
  end if;

  if exists (
    select 1 from public.obtener_tablero_cocina()
    where estado = 'ABIERTO'
      or pedido_estado in ('ENTREGADO', 'PAGADO', 'ANULADO')
      or pedido_id in (-40202, -40203, -40204)
  ) then
    raise exception 'H4-T02 incluyó detalle abierto, pedido terminal u otro local';
  end if;

  if not exists (
    select 1 from public.obtener_tablero_cocina()
    where detalle_id = -40213
      and producto_nombre = 'Producto histórico inactivo'
      and cantidad = 2
      and observacion = 'Histórico'
      and estado = 'RECIBIDO_COCINA'
      and enviado_en = v_sent_at
      and modificado_en is not null
      and mesa_codigo = 'M-A'
  ) then
    raise exception 'H4-T02 no conservó el producto histórico o el contrato esperado';
  end if;

  perform pg_temp.h4_t02_set_user(v_kitchen_b);
  if (select count(*) from public.obtener_tablero_cocina()) <> 1
    or not exists (
      select 1 from public.obtener_tablero_cocina() where detalle_id = -40218
    ) then
    raise exception 'H4-T02 no aisló correctamente el local B';
  end if;

  perform pg_temp.h4_t02_set_user(v_waiter_a);
  begin
    perform public.obtener_tablero_cocina();
    raise exception 'H4-T02 permitió snapshot a un rol distinto de COCINA';
  exception when sqlstate '42501' then
    null;
  end;

  perform pg_temp.h4_t02_set_user(null);
  begin
    perform public.obtener_tablero_cocina();
    raise exception 'H4-T02 permitió snapshot sin autenticación';
  exception when sqlstate '42501' then
    null;
  end;
end;
$h4_t02_behaviour$;

rollback;
