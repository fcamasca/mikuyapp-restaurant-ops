begin;

create function pg_temp.h3_t03_set_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $h3_t03_set_user$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$h3_t03_set_user$;

do $h3_t03_metadata$
declare
  function_definition text;
  argument_names text[];
begin
  select
    pg_catalog.pg_get_functiondef(function_metadata.oid),
    function_metadata.proargnames[1:4]
  into strict function_definition, argument_names
  from pg_catalog.pg_proc as function_metadata
  inner join pg_catalog.pg_namespace as function_schema
    on function_schema.oid = function_metadata.pronamespace
  where function_schema.nspname = 'public'
    and function_metadata.proname = 'agregar_detalle_pedido'
    and function_metadata.pronargs = 4
    and function_metadata.proargtypes = '20 2950 23 25'::pg_catalog.oidvector
    and function_metadata.prosecdef = true
    and function_metadata.proowner = (
      select role_metadata.oid
      from pg_catalog.pg_roles as role_metadata
      where role_metadata.rolname = 'postgres'
    )
    and function_metadata.proconfig = array['search_path=pg_catalog'];

  if argument_names <> array[
      'p_pedido_id', 'p_producto_id', 'p_cantidad', 'p_observacion'
    ]
    or function_definition !~* 'auth\.uid'
    or function_definition !~* 'obtener_contexto_autenticado'
    or function_definition !~* 'product_row\.precio'
    or function_definition !~* '''ABIERTO'''
    or function_definition ~* 'p_precio'
    or function_definition ~* 'p_estado' then
    raise exception 'H3-T03 contrato o definición de servidor inesperados';
  end if;

  if pg_catalog.has_function_privilege(
      'anon', 'public.agregar_detalle_pedido(bigint,uuid,integer,text)', 'EXECUTE'
    )
    or not pg_catalog.has_function_privilege(
      'authenticated', 'public.agregar_detalle_pedido(bigint,uuid,integer,text)', 'EXECUTE'
    )
    or pg_catalog.has_table_privilege(
      'authenticated', 'public.detalle_pedido', 'INSERT'
    ) then
    raise exception 'H3-T03 privilegios inesperados';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_attribute as column_metadata
    where column_metadata.attrelid = 'public.detalle_pedido'::pg_catalog.regclass
      and column_metadata.attnum > 0
      and not column_metadata.attisdropped
      and pg_catalog.has_column_privilege(
        'authenticated', 'public.detalle_pedido', column_metadata.attname, 'INSERT'
      )
  ) then
    raise exception 'H3-T03 concedió INSERT de columna directo';
  end if;
end;
$h3_t03_metadata$;

set local role authenticated;

do $h3_t03_direct_insert$
begin
  begin
    insert into public.detalle_pedido (
      pedido_id, producto_id, cantidad, precio_unitario, estado
    )
    values (
      -9301,
      '00000000-0000-0000-0000-00000000d3ff',
      1,
      0.01,
      'ABIERTO'
    );
    raise exception 'H3-T03 permitió falsear el precio mediante INSERT directo';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.detalle_pedido (
      pedido_id, producto_id, cantidad, precio_unitario, estado
    )
    values (
      -9302,
      '00000000-0000-0000-0000-00000000d3ff',
      1,
      1.00,
      'ENVIADO'
    );
    raise exception 'H3-T03 permitió crear directamente un detalle ENVIADO';
  exception when insufficient_privilege then null;
  end;
end;
$h3_t03_direct_insert$;

reset role;

do $h3_t03_behaviour$
declare
  v_admin_id uuid := '00000000-0000-0000-0000-00000000d301';
  v_waiter_id uuid := '00000000-0000-0000-0000-00000000d302';
  v_other_waiter_id uuid := '00000000-0000-0000-0000-00000000d303';
  v_local_id uuid := '00000000-0000-0000-0000-00000000d304';
  v_other_local_id uuid := '00000000-0000-0000-0000-00000000d305';
  v_table_id uuid := '00000000-0000-0000-0000-00000000d306';
  v_other_table_id uuid := '00000000-0000-0000-0000-00000000d307';
  v_category_id uuid := '00000000-0000-0000-0000-00000000d308';
  v_inactive_category_id uuid := '00000000-0000-0000-0000-00000000d309';
  v_other_category_id uuid := '00000000-0000-0000-0000-00000000d30a';
  v_product_id uuid := '00000000-0000-0000-0000-00000000d30b';
  v_inactive_product_id uuid := '00000000-0000-0000-0000-00000000d30c';
  v_inactive_category_product_id uuid := '00000000-0000-0000-0000-00000000d30d';
  v_other_product_id uuid := '00000000-0000-0000-0000-00000000d30e';
  v_order_id bigint;
  v_other_order_id bigint;
  v_detail_id bigint;
  v_initial_count bigint;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values
    (v_admin_id, 'authenticated', 'authenticated', 'h3-t03-admin@example.invalid', 'test'),
    (v_waiter_id, 'authenticated', 'authenticated', 'h3-t03-waiter@example.invalid', 'test'),
    (v_other_waiter_id, 'authenticated', 'authenticated', 'h3-t03-other@example.invalid', 'test');

  insert into public.local (id, codigo, nombre)
  values
    (v_local_id, 'H3-T03-A', 'Local H3 T03 A'),
    (v_other_local_id, 'H3-T03-B', 'Local H3 T03 B');

  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_admin_id, v_local_id, role_row.id, 'Admin H3 T03'
  from public.rol as role_row where role_row.codigo = 'ADMINISTRADOR'
  union all
  select v_waiter_id, v_local_id, role_row.id, 'Mozo H3 T03'
  from public.rol as role_row where role_row.codigo = 'MOZO'
  union all
  select v_other_waiter_id, v_other_local_id, role_row.id, 'Otro mozo H3 T03'
  from public.rol as role_row where role_row.codigo = 'MOZO';

  insert into public.mesa (id, local_id, codigo, nombre, estado)
  values
    (v_table_id, v_local_id, 'H3-T03-M1', 'Mesa H3 T03 A', 'OCUPADA'),
    (v_other_table_id, v_other_local_id, 'H3-T03-M2', 'Mesa H3 T03 B', 'OCUPADA');

  insert into public.categoria (id, local_id, codigo, nombre, activo)
  values
    (v_category_id, v_local_id, 'H3-T03-C1', 'Categoría activa', true),
    (v_inactive_category_id, v_local_id, 'H3-T03-C2', 'Categoría inactiva', false),
    (v_other_category_id, v_other_local_id, 'H3-T03-C3', 'Categoría otro local', true);

  insert into public.producto (
    id, local_id, categoria_id, codigo, nombre, precio, activo
  )
  values
    (v_product_id, v_local_id, v_category_id, 'H3-T03-P1', 'Producto válido', 17.40, true),
    (v_inactive_product_id, v_local_id, v_category_id, 'H3-T03-P2', 'Producto inactivo', 9.10, false),
    (v_inactive_category_product_id, v_local_id, v_inactive_category_id, 'H3-T03-P3', 'Categoría inactiva', 8.20, true),
    (v_other_product_id, v_other_local_id, v_other_category_id, 'H3-T03-P4', 'Producto otro local', 7.30, true);

  insert into public.pedido (local_id, mesa_id, creado_por, estado)
  values (v_local_id, v_table_id, v_waiter_id, 'ABIERTO')
  returning id into v_order_id;

  insert into public.pedido (local_id, mesa_id, creado_por, estado)
  values (v_other_local_id, v_other_table_id, v_other_waiter_id, 'ABIERTO')
  returning id into v_other_order_id;

  perform pg_temp.h3_t03_set_user(v_waiter_id);

  select result.detalle_id
  into strict v_detail_id
  from public.agregar_detalle_pedido(
    v_order_id, v_product_id, 2, 'Sin cebolla'
  ) as result;

  if not exists (
    select 1
    from public.detalle_pedido as detail_row
    where detail_row.id = v_detail_id
      and detail_row.pedido_id = v_order_id
      and detail_row.producto_id = v_product_id
      and detail_row.cantidad = 2
      and detail_row.precio_unitario = 17.40
      and detail_row.observacion = 'Sin cebolla'
      and detail_row.estado = 'ABIERTO'
  ) then
    raise exception 'H3-T03 detalle, precio de servidor o estado inicial incorrectos';
  end if;

  perform public.agregar_detalle_pedido(v_order_id, v_product_id, 1, 'Sin cebolla');
  if (select count(*) from public.detalle_pedido where pedido_id = v_order_id and producto_id = v_product_id and observacion = 'Sin cebolla') <> 1
    or (select cantidad from public.detalle_pedido where id = v_detail_id) <> 3 then
    raise exception 'H3-T07 no consolidó producto ABIERTO con observación equivalente';
  end if;

  perform public.agregar_detalle_pedido(v_order_id, v_product_id, 1, 'Poco picante');
  if not exists (
    select 1 from public.detalle_pedido
    where pedido_id = v_order_id and producto_id = v_product_id
      and observacion = 'Poco picante' and cantidad = 1 and estado = 'ABIERTO'
  ) then
    raise exception 'H3-T07 fusionó observaciones diferentes';
  end if;

  perform public.agregar_detalle_pedido(v_order_id, v_product_id, 1, null);
  perform public.agregar_detalle_pedido(v_order_id, v_product_id, 1, null);
  if (select count(*) from public.detalle_pedido where pedido_id = v_order_id and producto_id = v_product_id and observacion is null and estado = 'ABIERTO') <> 1
    or (select cantidad from public.detalle_pedido where pedido_id = v_order_id and producto_id = v_product_id and observacion is null and estado = 'ABIERTO') <> 2 then
    raise exception 'H3-T07 no consolidó producto ABIERTO sin observación';
  end if;

  update public.detalle_pedido
  set estado = 'ENVIADO', enviado_en = pg_catalog.clock_timestamp()
  where id = v_detail_id;
  perform public.agregar_detalle_pedido(v_order_id, v_product_id, 1, 'Sin cebolla');
  if (select cantidad from public.detalle_pedido where id = v_detail_id) <> 3
    or (select estado from public.detalle_pedido where id = v_detail_id) <> 'ENVIADO'
    or not exists (
      select 1 from public.detalle_pedido
      where pedido_id = v_order_id and producto_id = v_product_id
        and observacion = 'Sin cebolla' and cantidad = 1 and estado = 'ABIERTO'
    ) then
    raise exception 'H3-T07 modificó un enviado o no creó el nuevo ABIERTO';
  end if;

  v_initial_count := (select count(*) from public.detalle_pedido);

  begin
    perform public.agregar_detalle_pedido(v_order_id, v_inactive_product_id, 1, null);
    raise exception 'H3-T03 aceptó producto inactivo';
  exception when sqlstate '42501' then null;
  end;

  begin
    perform public.agregar_detalle_pedido(v_order_id, v_inactive_category_product_id, 1, null);
    raise exception 'H3-T03 aceptó categoría inactiva';
  exception when sqlstate '42501' then null;
  end;

  begin
    perform public.agregar_detalle_pedido(v_order_id, v_other_product_id, 1, null);
    raise exception 'H3-T03 aceptó producto de otro local';
  exception when sqlstate '42501' then null;
  end;

  begin
    perform public.agregar_detalle_pedido(v_other_order_id, v_product_id, 1, null);
    raise exception 'H3-T03 aceptó pedido de otro local';
  exception when sqlstate '42501' then null;
  end;

  begin
    perform public.agregar_detalle_pedido(v_order_id, v_product_id, 0, null);
    raise exception 'H3-T03 aceptó cantidad cero';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform public.agregar_detalle_pedido(v_order_id, v_product_id, -1, null);
    raise exception 'H3-T03 aceptó cantidad negativa';
  exception when sqlstate '22023' then null;
  end;

  perform pg_temp.h3_t03_set_user(v_admin_id);
  begin
    perform public.agregar_detalle_pedido(v_order_id, v_product_id, 1, null);
    raise exception 'H3-T03 aceptó un rol distinto de MOZO';
  exception when sqlstate '42501' then null;
  end;

  perform pg_temp.h3_t03_set_user(v_other_waiter_id);
  begin
    perform public.agregar_detalle_pedido(v_order_id, v_product_id, 1, null);
    raise exception 'H3-T03 aceptó un pedido no autorizado';
  exception when sqlstate '42501' then null;
  end;

  if (select count(*) from public.detalle_pedido) <> v_initial_count then
    raise exception 'H3-T03 produjo una inserción parcial después de un error';
  end if;
end;
$h3_t03_behaviour$;

rollback;
