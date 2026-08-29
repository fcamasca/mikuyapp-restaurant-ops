begin;

create function pg_temp.h5_t02_set_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $h5_t02_set_user$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$h5_t02_set_user$;

do $h5_t02_metadata$
declare
  v_delivery_function text;
  v_add_function text;
  v_send_function text;
  v_open_function text;
begin
  select pg_catalog.pg_get_functiondef(function_row.oid)
  into strict v_delivery_function
  from pg_catalog.pg_proc as function_row
  inner join pg_catalog.pg_namespace as function_schema
    on function_schema.oid = function_row.pronamespace
  where function_schema.nspname = 'public'
    and function_row.proname = 'entregar_pedido'
    and function_row.proargtypes = '20'::pg_catalog.oidvector
    and function_row.prosecdef
    and function_row.proowner = (
      select role_row.oid from pg_catalog.pg_roles as role_row
      where role_row.rolname = 'postgres'
    )
    and function_row.proconfig = array['search_path=pg_catalog'];

  if v_delivery_function !~* 'auth\.uid'
    or v_delivery_function !~* 'obtener_contexto_autenticado'
    or v_delivery_function !~* '''MOZO'''
    or v_delivery_function !~* 'for update'
    or v_delivery_function !~* 'count\(\*\).*LISTO'
    or v_delivery_function !~* 'set estado = ''ENTREGADO'''
    or v_delivery_function !~* 'set estado = ''PENDIENTE_PAGO'''
    or v_delivery_function !~* 'insert into public\.historial_estado'
    or v_delivery_function ~* 'update public\.detalle_pedido' then
    raise exception 'H5-T02 contrato de entregar_pedido inesperado';
  end if;

  if pg_catalog.has_function_privilege(
      'anon', 'public.entregar_pedido(bigint)', 'EXECUTE'
    ) or not pg_catalog.has_function_privilege(
      'authenticated', 'public.entregar_pedido(bigint)', 'EXECUTE'
    ) then
    raise exception 'H5-T02 privilegios de entregar_pedido inesperados';
  end if;

  select pg_catalog.pg_get_functiondef(function_row.oid)
  into strict v_add_function
  from pg_catalog.pg_proc as function_row
  inner join pg_catalog.pg_namespace as function_schema
    on function_schema.oid = function_row.pronamespace
  where function_schema.nspname = 'public'
    and function_row.proname = 'agregar_detalle_pedido'
    and function_row.proargtypes = '20 2950 23 25'::pg_catalog.oidvector;

  select pg_catalog.pg_get_functiondef(function_row.oid)
  into strict v_send_function
  from pg_catalog.pg_proc as function_row
  inner join pg_catalog.pg_namespace as function_schema
    on function_schema.oid = function_row.pronamespace
  where function_schema.nspname = 'public'
    and function_row.proname = 'enviar_pedido_cocina'
    and function_row.proargtypes = '20'::pg_catalog.oidvector;

  select pg_catalog.pg_get_functiondef(function_row.oid)
  into strict v_open_function
  from pg_catalog.pg_proc as function_row
  inner join pg_catalog.pg_namespace as function_schema
    on function_schema.oid = function_row.pronamespace
  where function_schema.nspname = 'public'
    and function_row.proname = 'crear_o_recuperar_pedido_mesa'
    and function_row.proargtypes = '2950'::pg_catalog.oidvector;

  if v_add_function ~* '''ENTREGADO'''
    or v_send_function ~* '''ENTREGADO'''
    or v_open_function ~* '''ENTREGADO''' then
    raise exception 'H5-T02 persiste ENTREGADO en una función incompatible';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policy as policy_row
    inner join pg_catalog.pg_class as table_row on table_row.oid = policy_row.polrelid
    inner join pg_catalog.pg_namespace as schema_row on schema_row.oid = table_row.relnamespace
    where schema_row.nspname = 'public'
      and table_row.relname = 'detalle_pedido'
      and policy_row.polname in (
        'detalle_pedido_update_abierto_mozo',
        'detalle_pedido_delete_abierto_mozo'
      )
      and (
        pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) ~* '''ENTREGADO'''
        or coalesce(
          pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid), ''
        ) ~* '''ENTREGADO'''
      )
  ) then
    raise exception 'H5-T02 persiste ENTREGADO en políticas de mutación';
  end if;
end;
$h5_t02_metadata$;

do $h5_t02_behaviour$
declare
  v_waiter_a uuid := '00000000-0000-0000-0000-00000000e201';
  v_waiter_b uuid := '00000000-0000-0000-0000-00000000e202';
  v_kitchen_a uuid := '00000000-0000-0000-0000-00000000e203';
  v_local_a uuid := '00000000-0000-0000-0000-00000000e204';
  v_local_b uuid := '00000000-0000-0000-0000-00000000e205';
  v_category_a uuid := '00000000-0000-0000-0000-00000000e206';
  v_category_b uuid := '00000000-0000-0000-0000-00000000e207';
  v_product_a uuid := '00000000-0000-0000-0000-00000000e208';
  v_product_b uuid := '00000000-0000-0000-0000-00000000e209';
  v_sent_at timestamptz := '2026-08-29 12:00:00-05';
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values
    (v_waiter_a, 'authenticated', 'authenticated', 'h5-t02-waiter-a@example.invalid', 'test'),
    (v_waiter_b, 'authenticated', 'authenticated', 'h5-t02-waiter-b@example.invalid', 'test'),
    (v_kitchen_a, 'authenticated', 'authenticated', 'h5-t02-kitchen@example.invalid', 'test');

  insert into public.local (id, codigo, nombre)
  values (v_local_a, 'H5-T02-A', 'Local H5 T02 A'),
    (v_local_b, 'H5-T02-B', 'Local H5 T02 B');

  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_waiter_a, v_local_a, role_row.id, 'Mozo A'
  from public.rol as role_row where role_row.codigo = 'MOZO'
  union all
  select v_waiter_b, v_local_b, role_row.id, 'Mozo B'
  from public.rol as role_row where role_row.codigo = 'MOZO'
  union all
  select v_kitchen_a, v_local_a, role_row.id, 'Cocina A'
  from public.rol as role_row where role_row.codigo = 'COCINA';

  insert into public.categoria (id, local_id, codigo, nombre)
  values (v_category_a, v_local_a, 'H5-T02-A', 'Categoría A'),
    (v_category_b, v_local_b, 'H5-T02-B', 'Categoría B');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio)
  values (v_product_a, v_local_a, v_category_a, 'H5-T02-A', 'Producto A', 10),
    (v_product_b, v_local_b, v_category_b, 'H5-T02-B', 'Producto B', 12);

  insert into public.mesa (id, local_id, codigo, nombre, estado)
  values
    ('00000000-0000-0000-0000-00000000e211', v_local_a, 'H5-211', 'Mesa válida', 'PEDIDO_LISTO'),
    ('00000000-0000-0000-0000-00000000e212', v_local_a, 'H5-212', 'Mesa vacía', 'PEDIDO_LISTO'),
    ('00000000-0000-0000-0000-00000000e213', v_local_a, 'H5-213', 'Mesa mixta', 'PEDIDO_LISTO'),
    ('00000000-0000-0000-0000-00000000e214', v_local_b, 'H5-214', 'Mesa otro local', 'PEDIDO_LISTO'),
    ('00000000-0000-0000-0000-00000000e215', v_local_a, 'H5-215', 'Mesa entregada', 'PENDIENTE_PAGO');

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado, enviado_en)
  overriding system value
  values
    (-50201, v_local_a, '00000000-0000-0000-0000-00000000e211', v_waiter_a, 'LISTO', v_sent_at),
    (-50202, v_local_a, '00000000-0000-0000-0000-00000000e212', v_waiter_a, 'LISTO', v_sent_at),
    (-50203, v_local_a, '00000000-0000-0000-0000-00000000e213', v_waiter_a, 'LISTO', v_sent_at),
    (-50204, v_local_b, '00000000-0000-0000-0000-00000000e214', v_waiter_b, 'LISTO', v_sent_at),
    (-50205, v_local_a, '00000000-0000-0000-0000-00000000e215', v_waiter_a, 'ENTREGADO', v_sent_at);

  perform pg_temp.h5_t02_set_user(v_waiter_a);
  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, estado, enviado_en
  ) overriding system value
  values
    (-50211, -50201, v_product_a, 1, 10, 'LISTO', v_sent_at),
    (-50212, -50201, v_product_a, 2, 10, 'LISTO', v_sent_at),
    (-50213, -50203, v_product_a, 1, 10, 'LISTO', v_sent_at),
    (-50214, -50203, v_product_a, 1, 10, 'EN_PREPARACION', v_sent_at),
    (-50215, -50204, v_product_b, 1, 12, 'LISTO', v_sent_at),
    (-50216, -50205, v_product_a, 1, 10, 'ABIERTO', null);

  perform public.entregar_pedido(-50201);

  if (select estado from public.pedido where id = -50201) <> 'ENTREGADO'
    or (select estado from public.mesa where id = '00000000-0000-0000-0000-00000000e211')
      <> 'PENDIENTE_PAGO'
    or exists (
      select 1 from public.detalle_pedido
      where pedido_id = -50201 and estado <> 'LISTO'
    )
    or (select count(*) from public.historial_estado
      where pedido_id = -50201
        and estado_anterior = 'LISTO'
        and estado_nuevo = 'ENTREGADO'
        and usuario_id = v_waiter_a) <> 1 then
    raise exception 'H5-T02 entrega válida incorrecta';
  end if;

  begin
    perform public.entregar_pedido(-50201);
    raise exception 'H5-T02 permitió doble entrega';
  exception when sqlstate '40001' then null;
  end;

  begin
    perform public.entregar_pedido(-50202);
    raise exception 'H5-T02 permitió pedido sin detalles';
  exception when sqlstate '55000' then null;
  end;

  begin
    perform public.entregar_pedido(-50203);
    raise exception 'H5-T02 permitió detalle no LISTO';
  exception when sqlstate '55000' then null;
  end;

  perform pg_temp.h5_t02_set_user(v_waiter_b);
  begin
    perform public.entregar_pedido(-50203);
    raise exception 'H5-T02 permitió entrega de otro local';
  exception when sqlstate '42501' then null;
  end;

  perform pg_temp.h5_t02_set_user(v_kitchen_a);
  begin
    perform public.entregar_pedido(-50203);
    raise exception 'H5-T02 permitió rol distinto de MOZO';
  exception when sqlstate '42501' then null;
  end;

  perform pg_temp.h5_t02_set_user(v_waiter_a);
  begin
    perform public.agregar_detalle_pedido(-50205, v_product_a, 1, null);
    raise exception 'H5-T02 permitió alta después de ENTREGADO';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.enviar_pedido_cocina(-50205);
    raise exception 'H5-T02 permitió envío después de ENTREGADO';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.crear_o_recuperar_pedido_mesa(
      '00000000-0000-0000-0000-00000000e215'
    );
    raise exception 'H5-T02 recuperó pedido ENTREGADO';
  exception when sqlstate '55000' then null;
  end;

  if (select count(*) from public.historial_estado
      where pedido_id = -50201
        and estado_anterior = 'LISTO'
        and estado_nuevo = 'ENTREGADO') <> 1
    or (select estado from public.pedido where id = -50202) <> 'LISTO'
    or (select estado from public.pedido where id = -50203) <> 'LISTO' then
    raise exception 'H5-T02 errores dejaron cambios parciales';
  end if;
end;
$h5_t02_behaviour$;

select pg_temp.h5_t02_set_user('00000000-0000-0000-0000-00000000e201');
set local role authenticated;

do $h5_t02_rls_mutations$
declare
  v_rows bigint;
begin
  update public.detalle_pedido
  set cantidad = 2
  where id = -50216;
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'H5-T02 RLS permitió modificar detalle de ENTREGADO';
  end if;

  delete from public.detalle_pedido where id = -50216;
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'H5-T02 RLS permitió retirar detalle de ENTREGADO';
  end if;
end;
$h5_t02_rls_mutations$;

reset role;
rollback;
