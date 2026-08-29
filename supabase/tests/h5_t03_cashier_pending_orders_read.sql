begin;

create function pg_temp.h5_t03_set_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $h5_t03_set_user$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$h5_t03_set_user$;

do $h5_t03_metadata$
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
    and function_row.proname = 'obtener_pedidos_pendientes_pago_caja'
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
    or v_function !~* '''CAJA'''
    or v_function !~* 'order_row\.local_id = v_local_id'
    or v_function !~* 'order_row\.estado = ''ENTREGADO'''
    or v_function !~* 'table_row\.estado = ''PENDIENTE_PAGO'''
    or v_function !~* 'detail_row\.cantidad \* detail_row\.precio_unitario'
    or v_function ~* 'product_row\.precio'
    or v_function ~* 'product_row\.activo'
    or v_result !~ 'producto_nombre text'
    or v_result !~ 'precio_unitario numeric'
    or v_result !~ 'importe_linea numeric'
    or v_result !~ 'total_pedido numeric' then
    raise exception 'H5-T03 contrato o seguridad de lectura inesperados';
  end if;

  if pg_catalog.has_function_privilege(
      'anon', 'public.obtener_pedidos_pendientes_pago_caja()', 'EXECUTE'
    ) or not pg_catalog.has_function_privilege(
      'authenticated', 'public.obtener_pedidos_pendientes_pago_caja()', 'EXECUTE'
    ) then
    raise exception 'H5-T03 privilegios de ejecución inesperados';
  end if;
end;
$h5_t03_metadata$;

do $h5_t03_behaviour$
declare
  v_cashier_a uuid := '00000000-0000-0000-0000-00000000e301';
  v_cashier_b uuid := '00000000-0000-0000-0000-00000000e302';
  v_waiter_a uuid := '00000000-0000-0000-0000-00000000e303';
  v_kitchen_a uuid := '00000000-0000-0000-0000-00000000e304';
  v_admin_a uuid := '00000000-0000-0000-0000-00000000e305';
  v_local_a uuid := '00000000-0000-0000-0000-00000000e306';
  v_local_b uuid := '00000000-0000-0000-0000-00000000e307';
  v_category_a uuid := '00000000-0000-0000-0000-00000000e308';
  v_category_b uuid := '00000000-0000-0000-0000-00000000e309';
  v_product_changed uuid := '00000000-0000-0000-0000-00000000e30a';
  v_product_second uuid := '00000000-0000-0000-0000-00000000e30b';
  v_product_b uuid := '00000000-0000-0000-0000-00000000e30c';
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values
    (v_cashier_a, 'authenticated', 'authenticated', 'h5-t03-cashier-a@example.invalid', 'test'),
    (v_cashier_b, 'authenticated', 'authenticated', 'h5-t03-cashier-b@example.invalid', 'test'),
    (v_waiter_a, 'authenticated', 'authenticated', 'h5-t03-waiter@example.invalid', 'test'),
    (v_kitchen_a, 'authenticated', 'authenticated', 'h5-t03-kitchen@example.invalid', 'test'),
    (v_admin_a, 'authenticated', 'authenticated', 'h5-t03-admin@example.invalid', 'test');

  insert into public.local (id, codigo, nombre)
  values (v_local_a, 'H5-T03-A', 'Local H5 T03 A'),
    (v_local_b, 'H5-T03-B', 'Local H5 T03 B');

  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_cashier_a, v_local_a, role_row.id, 'Caja A'
  from public.rol as role_row where role_row.codigo = 'CAJA'
  union all
  select v_cashier_b, v_local_b, role_row.id, 'Caja B'
  from public.rol as role_row where role_row.codigo = 'CAJA'
  union all
  select v_waiter_a, v_local_a, role_row.id, 'Mozo A'
  from public.rol as role_row where role_row.codigo = 'MOZO'
  union all
  select v_kitchen_a, v_local_a, role_row.id, 'Cocina A'
  from public.rol as role_row where role_row.codigo = 'COCINA'
  union all
  select v_admin_a, v_local_a, role_row.id, 'Administrador A'
  from public.rol as role_row where role_row.codigo = 'ADMINISTRADOR';

  insert into public.mesa (id, local_id, codigo, nombre, estado)
  values
    ('00000000-0000-0000-0000-00000000e311', v_local_a, 'T03-A1', 'Mesa Caja A', 'PENDIENTE_PAGO'),
    ('00000000-0000-0000-0000-00000000e312', v_local_a, 'T03-A2', 'Mesa no entregada', 'PEDIDO_LISTO'),
    ('00000000-0000-0000-0000-00000000e313', v_local_b, 'T03-B1', 'Mesa Caja B', 'PENDIENTE_PAGO');

  insert into public.categoria (id, local_id, codigo, nombre)
  values (v_category_a, v_local_a, 'H5-T03-A', 'Categoría A'),
    (v_category_b, v_local_b, 'H5-T03-B', 'Categoría B');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, activo)
  values
    (v_product_changed, v_local_a, v_category_a, 'H5-T03-A1', 'Nombre original', 10, true),
    (v_product_second, v_local_a, v_category_a, 'H5-T03-A2', 'Segundo producto', 5, true),
    (v_product_b, v_local_b, v_category_b, 'H5-T03-B1', 'Producto B', 20, true);

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado, enviado_en)
  overriding system value
  values
    (-50301, v_local_a, '00000000-0000-0000-0000-00000000e311', v_waiter_a, 'ENTREGADO', now()),
    (-50302, v_local_a, '00000000-0000-0000-0000-00000000e312', v_waiter_a, 'LISTO', now()),
    (-50303, v_local_b, '00000000-0000-0000-0000-00000000e313', v_cashier_b, 'ENTREGADO', now());

  perform pg_temp.h5_t03_set_user(v_waiter_a);
  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, estado, enviado_en
  ) overriding system value
  values
    (-50311, -50301, v_product_changed, 3, 10, 'LISTO', now()),
    (-50312, -50301, v_product_second, 2, 5, 'LISTO', now()),
    (-50313, -50302, v_product_second, 1, 5, 'LISTO', now()),
    (-50314, -50303, v_product_b, 4, 20, 'LISTO', now());

  update public.producto
  set nombre = 'Nombre vigente modificado', precio = 99, activo = false
  where id = v_product_changed;

  perform pg_temp.h5_t03_set_user(v_cashier_a);
  if (select count(*) from public.obtener_pedidos_pendientes_pago_caja()) <> 2
    or exists (
      select 1 from public.obtener_pedidos_pendientes_pago_caja()
      where pedido_id <> -50301
        or pedido_estado <> 'ENTREGADO'
        or mesa_estado <> 'PENDIENTE_PAGO'
    ) then
    raise exception 'H5-T03 lectura válida o aislamiento del local A incorrectos';
  end if;

  if not exists (
    select 1 from public.obtener_pedidos_pendientes_pago_caja()
    where detalle_id = -50311
      and producto_nombre = 'Nombre vigente modificado'
      and cantidad = 3
      and precio_unitario = 10
      and importe_linea = 30
      and total_pedido = 40
  ) or not exists (
    select 1 from public.obtener_pedidos_pendientes_pago_caja()
    where detalle_id = -50312
      and cantidad = 2
      and precio_unitario = 5
      and importe_linea = 10
      and total_pedido = 40
  ) then
    raise exception 'H5-T03 nombre vigente, precio histórico o totales incorrectos';
  end if;

  perform pg_temp.h5_t03_set_user(v_cashier_b);
  if (select count(*) from public.obtener_pedidos_pendientes_pago_caja()) <> 1
    or not exists (
      select 1 from public.obtener_pedidos_pendientes_pago_caja()
      where pedido_id = -50303 and total_pedido = 80
    ) then
    raise exception 'H5-T03 aislamiento del local B incorrecto';
  end if;

  perform pg_temp.h5_t03_set_user(v_waiter_a);
  begin
    perform public.obtener_pedidos_pendientes_pago_caja();
    raise exception 'H5-T03 permitió lectura a MOZO';
  exception when sqlstate '42501' then null;
  end;
  perform pg_temp.h5_t03_set_user(v_kitchen_a);
  begin
    perform public.obtener_pedidos_pendientes_pago_caja();
    raise exception 'H5-T03 permitió lectura a COCINA';
  exception when sqlstate '42501' then null;
  end;
  perform pg_temp.h5_t03_set_user(v_admin_a);
  begin
    perform public.obtener_pedidos_pendientes_pago_caja();
    raise exception 'H5-T03 permitió lectura a ADMINISTRADOR';
  exception when sqlstate '42501' then null;
  end;
  perform pg_temp.h5_t03_set_user(null);
  begin
    perform public.obtener_pedidos_pendientes_pago_caja();
    raise exception 'H5-T03 permitió lectura sin autenticación';
  exception when sqlstate '42501' then null;
  end;
end;
$h5_t03_behaviour$;

rollback;
