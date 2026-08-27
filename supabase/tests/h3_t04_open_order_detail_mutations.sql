begin;

do $h3_t04_metadata$
declare
  actual_update_columns text[];
  actual_policies text[];
begin
  select pg_catalog.array_agg(column_metadata.attname order by column_metadata.attname)
  into actual_update_columns
  from pg_catalog.pg_attribute as column_metadata
  where column_metadata.attrelid = 'public.detalle_pedido'::pg_catalog.regclass
    and column_metadata.attnum > 0
    and not column_metadata.attisdropped
    and pg_catalog.has_column_privilege(
      'authenticated',
      'public.detalle_pedido',
      column_metadata.attname,
      'UPDATE'
    );

  if actual_update_columns <> array['cantidad', 'observacion']
    or pg_catalog.has_table_privilege(
      'authenticated', 'public.detalle_pedido', 'UPDATE'
    )
    or pg_catalog.has_table_privilege(
      'authenticated', 'public.detalle_pedido', 'INSERT'
    )
    or not pg_catalog.has_table_privilege(
      'authenticated', 'public.detalle_pedido', 'SELECT'
    )
    or not pg_catalog.has_table_privilege(
      'authenticated', 'public.detalle_pedido', 'DELETE'
    ) then
    raise exception 'H3-T04 matriz de privilegios inesperada: %', actual_update_columns;
  end if;

  select pg_catalog.array_agg(policy_metadata.polname order by policy_metadata.polname)
  into actual_policies
  from pg_catalog.pg_policy as policy_metadata
  where policy_metadata.polrelid = 'public.detalle_pedido'::pg_catalog.regclass
    and policy_metadata.polroles = array[
      (select role_metadata.oid
       from pg_catalog.pg_roles as role_metadata
       where role_metadata.rolname = 'authenticated')
    ];

  if actual_policies <> array[
      'detalle_pedido_delete_abierto_mozo',
      'detalle_pedido_select_mozo_local',
      'detalle_pedido_update_abierto_mozo'
    ] then
    raise exception 'H3-T04 policies inesperadas: %', actual_policies;
  end if;

  if not pg_catalog.has_table_privilege(
      'authenticated', 'public.pedido', 'SELECT'
    )
    or not exists (
      select 1
      from pg_catalog.pg_policy as policy_metadata
      where policy_metadata.polrelid = 'public.pedido'::pg_catalog.regclass
        and policy_metadata.polname = 'pedido_select_vigente_mozo_local'
        and policy_metadata.polroles = array[
          (select role_metadata.oid
           from pg_catalog.pg_roles as role_metadata
           where role_metadata.rolname = 'authenticated')
        ]
    ) then
    raise exception 'H3-T04 lectura RLS de pedido necesaria para autorización ausente';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policy as policy_metadata
    where policy_metadata.polrelid = 'public.detalle_pedido'::pg_catalog.regclass
      and policy_metadata.polname in (
        'detalle_pedido_update_abierto_mozo',
        'detalle_pedido_delete_abierto_mozo'
      )
      and (
        pg_catalog.pg_get_expr(
          policy_metadata.polqual,
          policy_metadata.polrelid
        ) !~ 'estado = ''ABIERTO'''
        or pg_catalog.pg_get_expr(
          policy_metadata.polqual,
          policy_metadata.polrelid
        ) !~ 'obtener_contexto_autenticado'
      )
  ) then
    raise exception 'H3-T04 USING no protege estado, contexto y local';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policy as policy_metadata
    where policy_metadata.polrelid = 'public.detalle_pedido'::pg_catalog.regclass
      and policy_metadata.polname = 'detalle_pedido_update_abierto_mozo'
      and (
        policy_metadata.polwithcheck is null
        or pg_catalog.pg_get_expr(
          policy_metadata.polwithcheck,
          policy_metadata.polrelid
        ) !~ 'estado = ''ABIERTO'''
        or pg_catalog.pg_get_expr(
          policy_metadata.polwithcheck,
          policy_metadata.polrelid
        ) !~ 'obtener_contexto_autenticado'
      )
  ) then
    raise exception 'H3-T04 WITH CHECK incompleto';
  end if;
end;
$h3_t04_metadata$;

do $h3_t04_fixtures$
declare
  v_admin_id uuid := '00000000-0000-0000-0000-00000000e401';
  v_waiter_id uuid := '00000000-0000-0000-0000-00000000e402';
  v_other_waiter_id uuid := '00000000-0000-0000-0000-00000000e403';
  v_local_id uuid := '00000000-0000-0000-0000-00000000e404';
  v_other_local_id uuid := '00000000-0000-0000-0000-00000000e405';
  v_table_id uuid := '00000000-0000-0000-0000-00000000e406';
  v_other_table_id uuid := '00000000-0000-0000-0000-00000000e407';
  v_category_id uuid := '00000000-0000-0000-0000-00000000e408';
  v_other_category_id uuid := '00000000-0000-0000-0000-00000000e409';
  v_product_id uuid := '00000000-0000-0000-0000-00000000e40a';
  v_other_product_id uuid := '00000000-0000-0000-0000-00000000e40b';
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values
    (v_admin_id, 'authenticated', 'authenticated', 'h3-t04-admin@example.invalid', 'test'),
    (v_waiter_id, 'authenticated', 'authenticated', 'h3-t04-waiter@example.invalid', 'test'),
    (v_other_waiter_id, 'authenticated', 'authenticated', 'h3-t04-other@example.invalid', 'test');

  insert into public.local (id, codigo, nombre)
  values
    (v_local_id, 'H3-T04-A', 'Local H3 T04 A'),
    (v_other_local_id, 'H3-T04-B', 'Local H3 T04 B');

  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_admin_id, v_local_id, role_row.id, 'Admin H3 T04'
  from public.rol as role_row where role_row.codigo = 'ADMINISTRADOR'
  union all
  select v_waiter_id, v_local_id, role_row.id, 'Mozo H3 T04'
  from public.rol as role_row where role_row.codigo = 'MOZO'
  union all
  select v_other_waiter_id, v_other_local_id, role_row.id, 'Otro mozo H3 T04'
  from public.rol as role_row where role_row.codigo = 'MOZO';

  insert into public.mesa (id, local_id, codigo, nombre, estado)
  values
    (v_table_id, v_local_id, 'H3-T04-M1', 'Mesa H3 T04 A', 'OCUPADA'),
    (v_other_table_id, v_other_local_id, 'H3-T04-M2', 'Mesa H3 T04 B', 'OCUPADA');

  insert into public.categoria (id, local_id, codigo, nombre)
  values
    (v_category_id, v_local_id, 'H3-T04-C1', 'Categoría H3 T04 A'),
    (v_other_category_id, v_other_local_id, 'H3-T04-C2', 'Categoría H3 T04 B');

  insert into public.producto (
    id, local_id, categoria_id, codigo, nombre, precio
  )
  values
    (v_product_id, v_local_id, v_category_id, 'H3-T04-P1', 'Producto H3 T04 A', 10.00),
    (v_other_product_id, v_other_local_id, v_other_category_id, 'H3-T04-P2', 'Producto H3 T04 B', 11.00);

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado)
  overriding system value
  values
    (-9401, v_local_id, v_table_id, v_waiter_id, 'ABIERTO'),
    (-9402, v_other_local_id, v_other_table_id, v_other_waiter_id, 'ABIERTO');

  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, observacion, estado, enviado_en
  )
  overriding system value
  values
    (-9411, -9401, v_product_id, 2, 10.00, null, 'ABIERTO', null),
    (-9412, -9401, v_product_id, 1, 5.00, null, 'ABIERTO', null),
    (-9413, -9401, v_product_id, 1, 7.00, null, 'ENVIADO', '2026-08-26 10:00:00+00'),
    (-9414, -9401, v_product_id, 1, 8.00, null, 'RECIBIDO_COCINA', '2026-08-26 10:01:00+00'),
    (-9415, -9401, v_product_id, 1, 9.00, null, 'EN_PREPARACION', '2026-08-26 10:02:00+00'),
    (-9416, -9401, v_product_id, 1, 10.00, null, 'LISTO', '2026-08-26 10:03:00+00'),
    (-9417, -9402, v_other_product_id, 1, 11.00, null, 'ABIERTO', null);

  perform pg_catalog.set_config('request.jwt.claim.sub', v_waiter_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$h3_t04_fixtures$;

set local role authenticated;

do $h3_t04_waiter_behaviour$
declare
  affected_rows bigint;
  detail_id bigint;
begin
  update public.detalle_pedido
  set cantidad = 3
  where id = -9411;
  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise exception 'H3-T04 no actualizó cantidad de detalle ABIERTO';
  end if;

  update public.detalle_pedido
  set observacion = 'Sin cebolla'
  where id = -9411;
  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise exception 'H3-T04 no persistió observación de detalle ABIERTO';
  end if;

  if (select pg_catalog.sum(cantidad * precio_unitario)
      from public.detalle_pedido where pedido_id = -9401) <> 69.00 then
    raise exception 'H3-T04 total incorrecto después de cambiar cantidad';
  end if;

  begin
    update public.detalle_pedido set cantidad = 0 where id = -9411;
    raise exception 'H3-T04 aceptó cantidad cero';
  exception when check_violation then null;
  end;

  begin
    update public.detalle_pedido set cantidad = -1 where id = -9411;
    raise exception 'H3-T04 aceptó cantidad negativa';
  exception when check_violation then null;
  end;

  begin
    update public.detalle_pedido set observacion = '   ' where id = -9411;
    raise exception 'H3-T04 aceptó observación inválida';
  exception when check_violation then null;
  end;

  foreach detail_id in array array[-9413, -9414, -9415, -9416]::bigint[] loop
    update public.detalle_pedido set cantidad = 2 where id = detail_id;
    get diagnostics affected_rows = row_count;
    if affected_rows <> 0 then
      raise exception 'H3-T04 modificó detalle enviado o posterior: %', detail_id;
    end if;

    delete from public.detalle_pedido where id = detail_id;
    get diagnostics affected_rows = row_count;
    if affected_rows <> 0 then
      raise exception 'H3-T04 eliminó detalle enviado o posterior: %', detail_id;
    end if;
  end loop;

  begin
    update public.detalle_pedido
    set cantidad = 4, precio_unitario = 0.01
    where id = -9411;
    raise exception 'H3-T04 permitió cambiar precio_unitario';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.detalle_pedido set estado = 'ENVIADO' where id = -9411;
    raise exception 'H3-T04 permitió cambiar estado';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.detalle_pedido set pedido_id = -9402 where id = -9411;
    raise exception 'H3-T04 permitió cambiar pedido_id';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.detalle_pedido
    set producto_id = '00000000-0000-0000-0000-00000000e40b'
    where id = -9411;
    raise exception 'H3-T04 permitió cambiar producto_id';
  exception when insufficient_privilege then null;
  end;

  update public.detalle_pedido set cantidad = 2 where id = -9417;
  get diagnostics affected_rows = row_count;
  if affected_rows <> 0 then
    raise exception 'H3-T04 modificó detalle de otro local';
  end if;

  delete from public.detalle_pedido where id = -9417;
  get diagnostics affected_rows = row_count;
  if affected_rows <> 0 then
    raise exception 'H3-T04 eliminó detalle de otro local';
  end if;

  delete from public.detalle_pedido where id = -9412;
  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise exception 'H3-T04 no retiró detalle ABIERTO';
  end if;

  if (select pg_catalog.sum(cantidad * precio_unitario)
      from public.detalle_pedido where pedido_id = -9401) <> 64.00 then
    raise exception 'H3-T04 total incorrecto después del retiro';
  end if;

  if (select cantidad from public.detalle_pedido where id = -9411) <> 3
    or (select precio_unitario from public.detalle_pedido where id = -9411) <> 10.00
    or (select observacion from public.detalle_pedido where id = -9411) <> 'Sin cebolla' then
    raise exception 'H3-T04 una operación rechazada produjo cambios parciales';
  end if;
end;
$h3_t04_waiter_behaviour$;

reset role;

do $h3_t04_set_admin$
begin
  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-00000000e401',
    true
  );
end;
$h3_t04_set_admin$;

set local role authenticated;

do $h3_t04_non_waiter$
declare
  affected_rows bigint;
begin
  update public.detalle_pedido set cantidad = 4 where id = -9411;
  get diagnostics affected_rows = row_count;
  if affected_rows <> 0 then
    raise exception 'H3-T04 permitió UPDATE a rol distinto de MOZO';
  end if;

  delete from public.detalle_pedido where id = -9411;
  get diagnostics affected_rows = row_count;
  if affected_rows <> 0 then
    raise exception 'H3-T04 permitió DELETE a rol distinto de MOZO';
  end if;
end;
$h3_t04_non_waiter$;

reset role;

do $h3_t04_final_state$
begin
  if (select cantidad from public.detalle_pedido where id = -9411) <> 3
    or not exists (select 1 from public.detalle_pedido where id = -9413)
    or not exists (select 1 from public.detalle_pedido where id = -9414)
    or not exists (select 1 from public.detalle_pedido where id = -9415)
    or not exists (select 1 from public.detalle_pedido where id = -9416)
    or not exists (select 1 from public.detalle_pedido where id = -9417) then
    raise exception 'H3-T04 estado final inconsistente';
  end if;
end;
$h3_t04_final_state$;

rollback;
