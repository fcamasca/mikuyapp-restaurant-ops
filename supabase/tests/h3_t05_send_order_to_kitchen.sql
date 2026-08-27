begin;

create function pg_temp.h3_t05_set_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $h3_t05_set_user$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$h3_t05_set_user$;

create function pg_temp.h3_t05_fail_history()
returns trigger
language plpgsql
as $h3_t05_fail_history$
begin
  raise exception using errcode = 'P0001', message = 'fallo inducido H3-T05';
end;
$h3_t05_fail_history$;

do $h3_t05_metadata$
declare
  function_definition text;
begin
  select pg_catalog.pg_get_functiondef(function_metadata.oid)
  into strict function_definition
  from pg_catalog.pg_proc as function_metadata
  inner join pg_catalog.pg_namespace as function_schema
    on function_schema.oid = function_metadata.pronamespace
  where function_schema.nspname = 'public'
    and function_metadata.proname = 'enviar_pedido_cocina'
    and function_metadata.proargtypes = '20'::pg_catalog.oidvector
    and function_metadata.prosecdef = true
    and function_metadata.proowner = (
      select role_metadata.oid from pg_catalog.pg_roles as role_metadata
      where role_metadata.rolname = 'postgres'
    )
    and function_metadata.proconfig = array['search_path=pg_catalog'];

  if function_definition !~* 'auth\.uid'
    or function_definition !~* 'obtener_contexto_autenticado'
    or function_definition !~* 'FOR UPDATE'
    or function_definition !~* 'detail_row\.estado = ''ABIERTO'''
    or function_definition !~* 'set estado = ''ENVIADO'''
    or function_definition !~* 'sincronizar_estado_operativo_pedido' then
    raise exception 'H3-T05 definición transaccional incompleta';
  end if;

  if pg_catalog.has_function_privilege(
      'anon', 'public.enviar_pedido_cocina(bigint)', 'EXECUTE'
    )
    or not pg_catalog.has_function_privilege(
      'authenticated', 'public.enviar_pedido_cocina(bigint)', 'EXECUTE'
    )
    or pg_catalog.has_column_privilege(
      'authenticated', 'public.detalle_pedido', 'estado', 'UPDATE'
    )
    or pg_catalog.has_table_privilege(
      'authenticated', 'public.pedido', 'UPDATE'
    )
    or pg_catalog.has_table_privilege(
      'authenticated', 'public.historial_estado', 'INSERT'
    ) then
    raise exception 'H3-T05 privilegios directos inesperados';
  end if;
end;
$h3_t05_metadata$;

do $h3_t05_behaviour$
declare
  v_admin_id uuid := '00000000-0000-0000-0000-00000000f501';
  v_waiter_id uuid := '00000000-0000-0000-0000-00000000f502';
  v_other_waiter_id uuid := '00000000-0000-0000-0000-00000000f503';
  v_local_id uuid := '00000000-0000-0000-0000-00000000f504';
  v_other_local_id uuid := '00000000-0000-0000-0000-00000000f505';
  v_table_id uuid := '00000000-0000-0000-0000-00000000f506';
  v_other_table_id uuid := '00000000-0000-0000-0000-00000000f507';
  v_category_id uuid := '00000000-0000-0000-0000-00000000f508';
  v_other_category_id uuid := '00000000-0000-0000-0000-00000000f509';
  v_product_id uuid := '00000000-0000-0000-0000-00000000f50a';
  v_other_product_id uuid := '00000000-0000-0000-0000-00000000f50b';
  v_advanced_table_ids uuid[] := array[
    '00000000-0000-0000-0000-00000000f510'::uuid,
    '00000000-0000-0000-0000-00000000f511'::uuid,
    '00000000-0000-0000-0000-00000000f512'::uuid,
    '00000000-0000-0000-0000-00000000f513'::uuid
  ];
  v_rollback_table_id uuid := '00000000-0000-0000-0000-00000000f514';
  v_sent integer;
  v_header_changed boolean;
  v_state text;
  v_sent_at timestamptz;
  v_original_sent_at timestamptz;
  v_order_id bigint;
  v_detail_id bigint;
  v_expected_state text;
  v_derived_state text;
  v_index integer := 0;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values
    (v_admin_id, 'authenticated', 'authenticated', 'h3-t05-admin@example.invalid', 'test'),
    (v_waiter_id, 'authenticated', 'authenticated', 'h3-t05-waiter@example.invalid', 'test'),
    (v_other_waiter_id, 'authenticated', 'authenticated', 'h3-t05-other@example.invalid', 'test');

  insert into public.local (id, codigo, nombre)
  values
    (v_local_id, 'H3-T05-A', 'Local H3 T05 A'),
    (v_other_local_id, 'H3-T05-B', 'Local H3 T05 B');

  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_admin_id, v_local_id, role_row.id, 'Admin H3 T05'
  from public.rol as role_row where role_row.codigo = 'ADMINISTRADOR'
  union all
  select v_waiter_id, v_local_id, role_row.id, 'Mozo H3 T05'
  from public.rol as role_row where role_row.codigo = 'MOZO'
  union all
  select v_other_waiter_id, v_other_local_id, role_row.id, 'Otro mozo H3 T05'
  from public.rol as role_row where role_row.codigo = 'MOZO';

  insert into public.mesa (id, local_id, codigo, nombre, estado)
  values
    (v_table_id, v_local_id, 'H3-T05-M1', 'Mesa H3 T05 A', 'OCUPADA'),
    (v_other_table_id, v_other_local_id, 'H3-T05-M2', 'Mesa H3 T05 B', 'OCUPADA'),
    (v_advanced_table_ids[1], v_local_id, 'H3-T05-M3', 'Mesa posterior 1', 'OCUPADA'),
    (v_advanced_table_ids[2], v_local_id, 'H3-T05-M4', 'Mesa posterior 2', 'OCUPADA'),
    (v_advanced_table_ids[3], v_local_id, 'H3-T05-M5', 'Mesa posterior 3', 'OCUPADA'),
    (v_advanced_table_ids[4], v_local_id, 'H3-T05-M6', 'Mesa posterior 4', 'OCUPADA'),
    (v_rollback_table_id, v_local_id, 'H3-T05-M7', 'Mesa rollback', 'OCUPADA');

  insert into public.categoria (id, local_id, codigo, nombre)
  values
    (v_category_id, v_local_id, 'H3-T05-C1', 'Categoría H3 T05 A'),
    (v_other_category_id, v_other_local_id, 'H3-T05-C2', 'Categoría H3 T05 B');

  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio)
  values
    (v_product_id, v_local_id, v_category_id, 'H3-T05-P1', 'Producto H3 T05 A', 10.00),
    (v_other_product_id, v_other_local_id, v_other_category_id, 'H3-T05-P2', 'Producto H3 T05 B', 11.00);

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado)
  overriding system value
  values
    (-9501, v_local_id, v_table_id, v_waiter_id, 'ABIERTO'),
    (-9502, v_other_local_id, v_other_table_id, v_other_waiter_id, 'ABIERTO'),
    (-9503, v_local_id, v_table_id, v_waiter_id, 'PAGADO'),
    (-9504, v_local_id, v_table_id, v_waiter_id, 'ANULADO');

  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, estado, enviado_en
  )
  overriding system value
  values
    (-9511, -9501, v_product_id, 1, 10.00, 'ABIERTO', null),
    (-9512, -9501, v_product_id, 2, 10.00, 'ABIERTO', null),
    (-9513, -9501, v_product_id, 1, 10.00, 'ENVIADO', '2026-08-25 11:58:00+00'),
    (-9514, -9501, v_product_id, 1, 10.00, 'RECIBIDO_COCINA', '2026-08-25 11:59:00+00'),
    (-9515, -9502, v_other_product_id, 1, 11.00, 'ABIERTO', null);

  perform pg_temp.h3_t05_set_user(v_waiter_id);

  select result.detalles_enviados, result.cabecera_actualizada,
         result.pedido_estado, result.enviado_en
  into strict v_sent, v_header_changed, v_state, v_sent_at
  from public.enviar_pedido_cocina(-9501) as result;

  if v_sent <> 2 or not v_header_changed or v_state <> 'ENVIADO'
    or v_sent_at is null
    or (select estado from public.pedido where id = -9501) <> 'ENVIADO'
    or (select enviado_en from public.pedido where id = -9501) is distinct from v_sent_at
    or (select count(*) from public.detalle_pedido
        where pedido_id = -9501 and estado = 'ENVIADO') <> 3
    or (select estado from public.detalle_pedido where id = -9514) <> 'RECIBIDO_COCINA'
    or (select count(*) from public.historial_estado
        where pedido_id = -9501 and estado_anterior = 'ABIERTO'
          and estado_nuevo = 'ENVIADO' and usuario_id = v_waiter_id) <> 1 then
    raise exception 'H3-T05 primer envío inconsistente';
  end if;

  v_original_sent_at := v_sent_at;

  select result.detalles_enviados, result.cabecera_actualizada
  into strict v_sent, v_header_changed
  from public.enviar_pedido_cocina(-9501) as result;

  if v_sent <> 0 or v_header_changed
    or (select count(*) from public.historial_estado where pedido_id = -9501) <> 1
    or (select enviado_en from public.pedido where id = -9501)
       is distinct from v_original_sent_at then
    raise exception 'H3-T05 segundo llamado no fue idempotente';
  end if;

  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, estado
  ) overriding system value
  values (-9516, -9501, v_product_id, 1, 10.00, 'ABIERTO');

  select result.detalles_enviados, result.cabecera_actualizada,
         result.pedido_estado, result.enviado_en
  into strict v_sent, v_header_changed, v_state, v_sent_at
  from public.enviar_pedido_cocina(-9501) as result;

  if v_sent <> 1 or v_header_changed or v_state <> 'ENVIADO'
    or v_sent_at is distinct from v_original_sent_at
    or (select count(*) from public.historial_estado where pedido_id = -9501) <> 1 then
    raise exception 'H3-T05 agregado posterior ENVIADO inconsistente';
  end if;

  foreach v_expected_state in array array[
    'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO', 'ENTREGADO'
  ] loop
    v_index := v_index + 1;
    v_order_id := -9520 - v_index;
    v_detail_id := -9530 - v_index;
    v_original_sent_at := '2026-08-25 12:00:00+00'::timestamptz
      + pg_catalog.make_interval(mins => v_index);

    insert into public.pedido (
      id, local_id, mesa_id, creado_por, estado, enviado_en
    ) overriding system value
    values (
      v_order_id, v_local_id, v_advanced_table_ids[v_index], v_waiter_id,
      v_expected_state, v_original_sent_at
    );

    insert into public.detalle_pedido (
      id, pedido_id, producto_id, cantidad, precio_unitario, estado, enviado_en
    ) overriding system value
    values
      (v_detail_id, v_order_id, v_product_id, 1, 10.00, 'ABIERTO', null),
      (v_detail_id - 10, v_order_id, v_product_id, 1, 10.00, 'ENVIADO', v_original_sent_at);

    select result.detalles_enviados, result.cabecera_actualizada,
           result.pedido_estado, result.enviado_en
    into strict v_sent, v_header_changed, v_state, v_sent_at
    from public.enviar_pedido_cocina(v_order_id) as result;

    v_derived_state := case
      when v_expected_state = 'ENTREGADO' then 'ENTREGADO'
      else 'ENVIADO'
    end;

    if v_sent <> 1
      or v_header_changed is distinct from (v_expected_state <> 'ENTREGADO')
      or v_state <> v_derived_state
      or v_sent_at is distinct from v_original_sent_at
      or (select estado from public.pedido where id = v_order_id) <> v_derived_state
      or (select estado from public.detalle_pedido where id = v_detail_id) <> 'ENVIADO'
      or (select estado from public.detalle_pedido where id = v_detail_id - 10) <> 'ENVIADO'
      or (
        v_expected_state = 'ENTREGADO'
        and exists (select 1 from public.historial_estado where pedido_id = v_order_id)
      )
      or (
        v_expected_state <> 'ENTREGADO'
        and not exists (
          select 1 from public.historial_estado
          where pedido_id = v_order_id
            and estado_anterior = v_expected_state
            and estado_nuevo = 'ENVIADO'
            and usuario_id = v_waiter_id
        )
      ) then
      raise exception 'H3-T05 envío posterior inconsistente para %', v_expected_state;
    end if;
  end loop;

  perform pg_temp.h3_t05_set_user(v_admin_id);
  begin
    perform public.enviar_pedido_cocina(-9501);
    raise exception 'H3-T05 aceptó rol distinto de MOZO';
  exception when sqlstate '42501' then null;
  end;

  perform pg_temp.h3_t05_set_user(v_other_waiter_id);
  begin
    perform public.enviar_pedido_cocina(-9501);
    raise exception 'H3-T05 aceptó pedido de otro local';
  exception when sqlstate '42501' then null;
  end;

  perform pg_temp.h3_t05_set_user(v_waiter_id);
  begin
    perform public.enviar_pedido_cocina(-9503);
    raise exception 'H3-T05 aceptó pedido PAGADO';
  exception when sqlstate '42501' then null;
  end;

  begin
    perform public.enviar_pedido_cocina(-9504);
    raise exception 'H3-T05 aceptó pedido ANULADO';
  exception when sqlstate '42501' then null;
  end;

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado)
  overriding system value
  values (-9590, v_local_id, v_rollback_table_id, v_waiter_id, 'ABIERTO');

  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, estado
  ) overriding system value
  values (-9591, -9590, v_product_id, 1, 10.00, 'ABIERTO');

  create trigger h3_t05_fail_history
  before insert on public.historial_estado
  for each row execute function pg_temp.h3_t05_fail_history();

  begin
    perform public.enviar_pedido_cocina(-9590);
    raise exception 'H3-T05 no propagó fallo inducido';
  exception when sqlstate 'P0001' then null;
  end;

  if (select estado from public.pedido where id = -9590) <> 'ABIERTO'
    or (select enviado_en from public.pedido where id = -9590) is not null
    or (select estado from public.detalle_pedido where id = -9591) <> 'ABIERTO'
    or (select enviado_en from public.detalle_pedido where id = -9591) is not null
    or exists (select 1 from public.historial_estado where pedido_id = -9590) then
    raise exception 'H3-T05 rollback incompleto';
  end if;

  drop trigger h3_t05_fail_history on public.historial_estado;
end;
$h3_t05_behaviour$;

rollback;
