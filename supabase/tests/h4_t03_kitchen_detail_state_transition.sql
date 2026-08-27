begin;

create function pg_temp.h4_t03_set_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $h4_t03_set_user$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$h4_t03_set_user$;

do $h4_t03_metadata$
declare
  v_function text;
begin
  select pg_catalog.pg_get_functiondef(function_row.oid)
  into strict v_function
  from pg_catalog.pg_proc as function_row
  inner join pg_catalog.pg_namespace as function_schema
    on function_schema.oid = function_row.pronamespace
  where function_schema.nspname = 'public'
    and function_row.proname = 'actualizar_estado_detalle_cocina'
    and function_row.proargtypes = '20 25 25'::pg_catalog.oidvector
    and function_row.prosecdef
    and function_row.proowner = (
      select role_row.oid from pg_catalog.pg_roles as role_row
      where role_row.rolname = 'postgres'
    )
    and function_row.proconfig = array['search_path=pg_catalog'];

  if v_function !~* 'auth\.uid'
    or v_function !~* 'obtener_contexto_autenticado'
    or v_function !~* '''COCINA'''
    or v_function !~* 'for update'
    or v_function !~* '40001'
    or v_function !~* 'set estado = p_estado_nuevo'
    or v_function ~* 'update public\.pedido'
    or v_function ~* 'update public\.mesa' then
    raise exception 'H4-T03 contrato, bloqueo o alcance inesperados';
  end if;

  if pg_catalog.has_function_privilege(
      'anon', 'public.actualizar_estado_detalle_cocina(bigint,text,text)', 'EXECUTE'
    ) or not pg_catalog.has_function_privilege(
      'authenticated',
      'public.actualizar_estado_detalle_cocina(bigint,text,text)',
      'EXECUTE'
    ) or pg_catalog.has_column_privilege(
      'authenticated', 'public.detalle_pedido', 'estado', 'UPDATE'
    ) then
    raise exception 'H4-T03 privilegios inesperados';
  end if;
end;
$h4_t03_metadata$;

do $h4_t03_behaviour$
declare
  v_kitchen_a uuid := '00000000-0000-0000-0000-00000000d431';
  v_kitchen_b uuid := '00000000-0000-0000-0000-00000000d432';
  v_waiter_a uuid := '00000000-0000-0000-0000-00000000d433';
  v_local_a uuid := '00000000-0000-0000-0000-00000000d434';
  v_local_b uuid := '00000000-0000-0000-0000-00000000d435';
  v_table_a uuid := '00000000-0000-0000-0000-00000000d436';
  v_table_b uuid := '00000000-0000-0000-0000-00000000d437';
  v_category_a uuid := '00000000-0000-0000-0000-00000000d438';
  v_category_b uuid := '00000000-0000-0000-0000-00000000d439';
  v_product_a uuid := '00000000-0000-0000-0000-00000000d43a';
  v_product_b uuid := '00000000-0000-0000-0000-00000000d43b';
  v_sent_at timestamptz := '2026-08-27 11:00:00-05';
  v_order_modified timestamptz;
  v_detail_modified timestamptz;
  v_detail_sent timestamptz;
  v_detail_creator uuid;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values
    (v_kitchen_a, 'authenticated', 'authenticated', 'h4-t03-kitchen-a@example.invalid', 'test'),
    (v_kitchen_b, 'authenticated', 'authenticated', 'h4-t03-kitchen-b@example.invalid', 'test'),
    (v_waiter_a, 'authenticated', 'authenticated', 'h4-t03-waiter@example.invalid', 'test');

  insert into public.local (id, codigo, nombre)
  values
    (v_local_a, 'H4-T03-A', 'Local H4 T03 A'),
    (v_local_b, 'H4-T03-B', 'Local H4 T03 B');

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
    (v_table_a, v_local_a, 'T03-A', 'Mesa A', 'OCUPADA'),
    (v_table_b, v_local_b, 'T03-B', 'Mesa B', 'OCUPADA');

  insert into public.categoria (id, local_id, codigo, nombre)
  values
    (v_category_a, v_local_a, 'T03-A', 'Categoría A'),
    (v_category_b, v_local_b, 'T03-B', 'Categoría B');

  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio)
  values
    (v_product_a, v_local_a, v_category_a, 'T03-A', 'Producto A', 10),
    (v_product_b, v_local_b, v_category_b, 'T03-B', 'Producto B', 12);

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado, enviado_en)
  overriding system value
  values
    (-40301, v_local_a, v_table_a, v_waiter_a, 'ENVIADO', v_sent_at),
    (-40302, v_local_a, v_table_a, v_waiter_a, 'PAGADO', v_sent_at),
    (-40303, v_local_b, v_table_b, v_kitchen_b, 'ENVIADO', v_sent_at);

  perform pg_temp.h4_t03_set_user(v_waiter_a);
  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, estado, enviado_en
  ) overriding system value
  values
    (-40311, -40301, v_product_a, 1, 10, 'ENVIADO', v_sent_at),
    (-40312, -40301, v_product_a, 1, 10, 'ABIERTO', null),
    (-40313, -40301, v_product_a, 1, 10, 'LISTO', v_sent_at),
    (-40314, -40302, v_product_a, 1, 10, 'ENVIADO', v_sent_at),
    (-40315, -40303, v_product_b, 1, 12, 'ENVIADO', v_sent_at);

  select modificado_en into strict v_order_modified
  from public.pedido where id = -40301;
  select modificado_en, enviado_en, creado_por
  into strict v_detail_modified, v_detail_sent, v_detail_creator
  from public.detalle_pedido where id = -40311;

  perform pg_temp.h4_t03_set_user(v_kitchen_a);
  perform public.actualizar_estado_detalle_cocina(
    -40311, 'ENVIADO', 'RECIBIDO_COCINA'
  );

  if not exists (
    select 1 from public.detalle_pedido
    where id = -40311
      and estado = 'RECIBIDO_COCINA'
      and enviado_en = v_detail_sent
      and creado_por = v_detail_creator
      and modificado_por = v_kitchen_a
      and modificado_en > v_detail_modified
  ) or (select modificado_en from public.pedido where id = -40301)
      is distinct from v_order_modified then
    raise exception 'H4-T03 primera transición o auditoría incorrectas';
  end if;

  perform public.actualizar_estado_detalle_cocina(
    -40311, 'RECIBIDO_COCINA', 'EN_PREPARACION'
  );
  perform public.actualizar_estado_detalle_cocina(
    -40311, 'EN_PREPARACION', 'LISTO'
  );

  if (select estado from public.detalle_pedido where id = -40311) <> 'LISTO'
    or (select enviado_en from public.detalle_pedido where id = -40311)
      is distinct from v_detail_sent
    or (select modificado_en from public.pedido where id = -40301)
      is distinct from v_order_modified then
    raise exception 'H4-T03 secuencia completa alteró datos no autorizados';
  end if;

  begin
    perform public.actualizar_estado_detalle_cocina(-40311, 'LISTO', 'EN_PREPARACION');
    raise exception 'H4-T03 permitió retroceso desde LISTO';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform public.actualizar_estado_detalle_cocina(-40312, 'ABIERTO', 'ENVIADO');
    raise exception 'H4-T03 permitió transición desde ABIERTO';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform public.actualizar_estado_detalle_cocina(-40313, 'LISTO', 'LISTO');
    raise exception 'H4-T03 permitió transición desde LISTO';
  exception when sqlstate '22023' then null;
  end;

  update public.detalle_pedido set estado = 'ENVIADO' where id = -40313;
  begin
    perform public.actualizar_estado_detalle_cocina(-40313, 'ENVIADO', 'LISTO');
    raise exception 'H4-T03 permitió salto de estado';
  exception when sqlstate '22023' then null;
  end;
  if (select estado from public.detalle_pedido where id = -40313) <> 'ENVIADO' then
    raise exception 'H4-T03 no revirtió el salto rechazado';
  end if;

  begin
    perform public.actualizar_estado_detalle_cocina(
      -40313, 'RECIBIDO_COCINA', 'EN_PREPARACION'
    );
    raise exception 'H4-T03 no detectó estado esperado obsoleto';
  exception when sqlstate '40001' then null;
  end;

  begin
    perform public.actualizar_estado_detalle_cocina(
      -40314, 'ENVIADO', 'RECIBIDO_COCINA'
    );
    raise exception 'H4-T03 permitió pedido terminal';
  exception when sqlstate '42501' then null;
  end;

  begin
    perform public.actualizar_estado_detalle_cocina(
      -40315, 'ENVIADO', 'RECIBIDO_COCINA'
    );
    raise exception 'H4-T03 permitió detalle de otro local';
  exception when sqlstate '42501' then null;
  end;

  perform pg_temp.h4_t03_set_user(v_waiter_a);
  begin
    perform public.actualizar_estado_detalle_cocina(
      -40313, 'ENVIADO', 'RECIBIDO_COCINA'
    );
    raise exception 'H4-T03 permitió rol distinto de COCINA';
  exception when sqlstate '42501' then null;
  end;

  if (select estado from public.detalle_pedido where id = -40313) <> 'ENVIADO'
    or (select estado from public.detalle_pedido where id = -40314) <> 'ENVIADO'
    or (select estado from public.detalle_pedido where id = -40315) <> 'ENVIADO' then
    raise exception 'H4-T03 dejó mutaciones parciales después de errores';
  end if;
end;
$h4_t03_behaviour$;

rollback;
