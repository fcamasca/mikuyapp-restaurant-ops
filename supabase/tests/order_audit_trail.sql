begin;

create function pg_temp.set_audit_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $set_audit_user$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$set_audit_user$;

do $verify_audit_trigger_definition$
begin
  if not exists (
    select 1
    from pg_catalog.pg_proc as function_metadata
    inner join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function_metadata.pronamespace
    where function_schema.nspname = 'public'
      and function_metadata.proname = 'registrar_auditoria_detalle_pedido'
      and pg_catalog.pg_get_function_identity_arguments(function_metadata.oid) = ''
      and pg_catalog.md5(function_metadata.prosrc)
        = 'e5995bb64d37ba0f5f3a255e84fa354f'
  ) then
    raise exception 'TP21 cambió el cuerpo de registrar_auditoria_detalle_pedido()';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger as trigger_metadata
    inner join pg_catalog.pg_class as table_metadata
      on table_metadata.oid = trigger_metadata.tgrelid
    inner join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = table_metadata.relnamespace
    inner join pg_catalog.pg_proc as function_metadata
      on function_metadata.oid = trigger_metadata.tgfoid
    inner join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function_metadata.pronamespace
    where table_schema.nspname = 'public'
      and table_metadata.relname = 'detalle_pedido'
      and trigger_metadata.tgname = 'detalle_pedido_registrar_auditoria'
      and function_schema.nspname = 'public'
      and function_metadata.proname = 'registrar_auditoria_detalle_pedido'
      and (trigger_metadata.tgtype & 1) <> 0
      and (trigger_metadata.tgtype & 2) <> 0
      and (trigger_metadata.tgtype & 4) <> 0
      and (trigger_metadata.tgtype & 8) <> 0
      and (trigger_metadata.tgtype & 16) <> 0
      and (trigger_metadata.tgtype & 32) = 0
      and not trigger_metadata.tgisinternal
  ) then
    raise exception 'TP21 cambió nombre, eventos, momento, nivel o vínculo del trigger';
  end if;
end;
$verify_audit_trigger_definition$;

do $prepare_audit_fixtures$
declare
  v_local_id uuid := '00000000-0000-0000-0000-00000000a201';
  v_waiter_one uuid := '00000000-0000-0000-0000-00000000a202';
  v_waiter_two uuid := '00000000-0000-0000-0000-00000000a203';
  v_category_id uuid := '00000000-0000-0000-0000-00000000a204';
  v_product_one uuid := '00000000-0000-0000-0000-00000000a205';
  v_product_two uuid := '00000000-0000-0000-0000-00000000a206';
  v_table_id uuid := '00000000-0000-0000-0000-00000000a207';
begin
  insert into auth.users (id, aud, role, email, encrypted_password) values
    (v_waiter_one, 'authenticated', 'authenticated', 'audit-one@example.invalid', 'test'),
    (v_waiter_two, 'authenticated', 'authenticated', 'audit-two@example.invalid', 'test');
  insert into public.local (id, codigo, nombre) values (v_local_id, 'AUDIT', 'Auditoría');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_waiter_one, v_local_id, role_row.id, 'Mozo creador'
  from public.rol as role_row where role_row.codigo = 'MOZO'
  union all
  select v_waiter_two, v_local_id, role_row.id, 'Mozo posterior'
  from public.rol as role_row where role_row.codigo = 'MOZO';
  insert into public.categoria (id, local_id, codigo, nombre)
  values (v_category_id, v_local_id, 'AUDIT', 'Auditoría');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio) values
    (v_product_one, v_local_id, v_category_id, 'AUDIT-1', 'Producto uno', 10),
    (v_product_two, v_local_id, v_category_id, 'AUDIT-2', 'Producto dos', 20);
  insert into public.mesa (id, local_id, codigo, nombre)
  values (v_table_id, v_local_id, 'AUDIT', 'Mesa auditoría');
end;
$prepare_audit_fixtures$;

select pg_temp.set_audit_user('00000000-0000-0000-0000-00000000a202');
select * from public.crear_o_recuperar_pedido_mesa('00000000-0000-0000-0000-00000000a207');

do $verify_initial_order_audit$
declare
  v_order public.pedido%rowtype;
begin
  select * into strict v_order
  from public.pedido
  where mesa_id = '00000000-0000-0000-0000-00000000a207';
  if v_order.creado_por <> '00000000-0000-0000-0000-00000000a202'
    or v_order.modificado_por <> v_order.creado_por
    or v_order.modificado_en <> v_order.creado_en then
    raise exception 'La creación inicial del pedido no igualó creación y modificación';
  end if;
end;
$verify_initial_order_audit$;

select pg_temp.set_audit_user(null);

insert into public.detalle_pedido (
  pedido_id,
  producto_id,
  cantidad,
  precio_unitario
)
values (
  (select id from public.pedido
   where mesa_id = '00000000-0000-0000-0000-00000000a207'),
  '00000000-0000-0000-0000-00000000a205',
  1,
  10
);

do $verify_internal_insert_without_jwt$
begin
  if not exists (
    select 1
    from public.detalle_pedido
    where pedido_id = (
        select id from public.pedido
        where mesa_id = '00000000-0000-0000-0000-00000000a207'
      )
      and producto_id = '00000000-0000-0000-0000-00000000a205'
      and creado_por = '00000000-0000-0000-0000-00000000a202'
      and modificado_por = '00000000-0000-0000-0000-00000000a202'
      and creado_en = modificado_en
  ) then
    raise exception 'TP18 ejecución interna sin JWT no resolvió al creador del pedido';
  end if;
end;
$verify_internal_insert_without_jwt$;

delete from public.detalle_pedido
where pedido_id = (
    select id from public.pedido
    where mesa_id = '00000000-0000-0000-0000-00000000a207'
  )
  and producto_id = '00000000-0000-0000-0000-00000000a205';

select pg_temp.set_audit_user('00000000-0000-0000-0000-00000000a202');

select * from public.agregar_detalle_pedido(
  (select id from public.pedido where mesa_id = '00000000-0000-0000-0000-00000000a207'),
  '00000000-0000-0000-0000-00000000a205', 1, null
);

select pg_temp.set_audit_user('00000000-0000-0000-0000-00000000a203');
select * from public.agregar_detalle_pedido(
  (select id from public.pedido where mesa_id = '00000000-0000-0000-0000-00000000a207'),
  '00000000-0000-0000-0000-00000000a206', 1, 'Sin ají'
);

set local role authenticated;
update public.detalle_pedido
set cantidad = 2
where pedido_id = (
    select id from public.pedido
    where mesa_id = '00000000-0000-0000-0000-00000000a207'
  )
  and producto_id = '00000000-0000-0000-0000-00000000a205';

do $reject_audit_spoofing$
begin
  begin
    update public.detalle_pedido
    set modificado_por = '00000000-0000-0000-0000-00000000a202'
    where producto_id = '00000000-0000-0000-0000-00000000a205';
    raise exception 'authenticated pudo suplantar modificado_por';
  exception when insufficient_privilege then
    null;
  end;

  if (select count(*) from public.obtener_creadores_pedidos_vigentes(array[
      (select id from public.pedido where mesa_id = '00000000-0000-0000-0000-00000000a207')
    ])) <> 1
    or (select creador_nombre from public.obtener_creadores_pedidos_vigentes(array[
      (select id from public.pedido where mesa_id = '00000000-0000-0000-0000-00000000a207')
    ])) <> 'Mozo creador' then
    raise exception 'Nombre del creador vigente inválido';
  end if;
end;
$reject_audit_spoofing$;
reset role;

do $verify_order_audit$
declare
  v_order public.pedido%rowtype;
  v_first public.detalle_pedido%rowtype;
  v_second public.detalle_pedido%rowtype;
begin
  select * into strict v_order
  from public.pedido
  where mesa_id = '00000000-0000-0000-0000-00000000a207';
  select * into strict v_first
  from public.detalle_pedido
  where pedido_id = v_order.id
    and producto_id = '00000000-0000-0000-0000-00000000a205';
  select * into strict v_second
  from public.detalle_pedido
  where pedido_id = v_order.id
    and producto_id = '00000000-0000-0000-0000-00000000a206';

  if v_order.creado_por <> '00000000-0000-0000-0000-00000000a202'
    or v_order.modificado_por <> '00000000-0000-0000-0000-00000000a203'
    or v_order.modificado_en < v_order.creado_en then
    raise exception 'Auditoría comercial del pedido inválida';
  end if;
  if v_first.creado_por <> '00000000-0000-0000-0000-00000000a202'
    or v_first.modificado_por <> '00000000-0000-0000-0000-00000000a203'
    or v_first.modificado_en < v_first.creado_en then
    raise exception 'Auditoría del primer detalle inválida';
  end if;
  if v_second.creado_por <> '00000000-0000-0000-0000-00000000a203'
    or v_second.modificado_por <> v_second.creado_por
    or v_second.modificado_en <> v_second.creado_en then
    raise exception 'Auditoría inicial del detalle posterior inválida';
  end if;
  if v_first.cantidad <> 2 then
    raise exception 'La modificación comercial no se persistió';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_constraint
    where conname in (
      'fk_pedido_modificado_por',
      'fk_detalle_pedido_creado_por',
      'fk_detalle_pedido_modificado_por'
    )
      and confdeltype = 'r'
  ) <> 3 then
    raise exception 'FK de auditoría no conservan ON DELETE RESTRICT';
  end if;

  if pg_catalog.has_column_privilege('authenticated', 'public.pedido', 'modificado_por', 'UPDATE')
    or pg_catalog.has_column_privilege('authenticated', 'public.detalle_pedido', 'creado_por', 'UPDATE')
    or pg_catalog.has_column_privilege('authenticated', 'public.detalle_pedido', 'modificado_por', 'UPDATE') then
    raise exception 'authenticated recibió privilegios directos de auditoría';
  end if;
end;
$verify_order_audit$;

do $verify_content_update_and_delete$
declare
  v_order_id bigint;
  v_modified_before timestamptz;
  v_modified_after timestamptz;
begin
  select id, modificado_en
  into strict v_order_id, v_modified_before
  from public.pedido
  where mesa_id = '00000000-0000-0000-0000-00000000a207';

  update public.detalle_pedido
  set observacion = 'Con limón'
  where pedido_id = v_order_id
    and producto_id = '00000000-0000-0000-0000-00000000a205';

  select modificado_en
  into strict v_modified_after
  from public.pedido
  where id = v_order_id;

  if v_modified_after <= v_modified_before
    or (select modificado_por from public.pedido where id = v_order_id)
      <> '00000000-0000-0000-0000-00000000a203'
    or (select observacion from public.detalle_pedido
        where pedido_id = v_order_id
          and producto_id = '00000000-0000-0000-0000-00000000a205')
      <> 'Con limón' then
    raise exception 'TP19 modificación de observación no propagó la auditoría actual';
  end if;

  v_modified_before := v_modified_after;

  delete from public.detalle_pedido
  where pedido_id = v_order_id
    and producto_id = '00000000-0000-0000-0000-00000000a206';

  select modificado_en
  into strict v_modified_after
  from public.pedido
  where id = v_order_id;

  if v_modified_after <= v_modified_before
    or (select modificado_por from public.pedido where id = v_order_id)
      <> '00000000-0000-0000-0000-00000000a203'
    or exists (
      select 1
      from public.detalle_pedido
      where pedido_id = v_order_id
        and producto_id = '00000000-0000-0000-0000-00000000a206'
    ) then
    raise exception 'TP19 DELETE no propagó la auditoría actual';
  end if;
end;
$verify_content_update_and_delete$;

do $verify_state_audit_scope$
declare
  v_order_id bigint;
  v_order_modified_at timestamptz;
  v_content_modified_at timestamptz;
begin
  select id, modificado_en
  into strict v_order_id, v_order_modified_at
  from public.pedido
  where mesa_id = '00000000-0000-0000-0000-00000000a207';

  perform public.enviar_pedido_cocina(v_order_id);

  if (select modificado_en from public.pedido where id = v_order_id) <> v_order_modified_at then
    raise exception 'El envío alteró la fecha de modificación comercial del pedido';
  end if;
  if exists (
    select 1
    from public.detalle_pedido
    where pedido_id = v_order_id
      and (estado <> 'ENVIADO'
        or modificado_por <> '00000000-0000-0000-0000-00000000a203')
  ) then
    raise exception 'El cambio de estado no actualizó la auditoría individual del detalle';
  end if;

  begin
    update public.detalle_pedido
    set enviado_en = pg_catalog.clock_timestamp()
    where pedido_id = v_order_id
      and producto_id = '00000000-0000-0000-0000-00000000a205';
    raise exception 'TP21 permitió reemplazar enviado_en después del primer envío';
  exception
    when sqlstate '22000' then
      null;
  end;

  perform public.agregar_detalle_pedido(
    v_order_id,
    '00000000-0000-0000-0000-00000000a206',
    1,
    'Reposición'
  );

  begin
    update public.detalle_pedido
    set enviado_en = pg_catalog.clock_timestamp()
    where pedido_id = v_order_id
      and producto_id = '00000000-0000-0000-0000-00000000a206';
    raise exception 'TP21 permitió fijar enviado_en sin transición ABIERTO a ENVIADO';
  exception
    when sqlstate '22000' then
      null;
  end;

  select modificado_en
  into strict v_content_modified_at
  from public.pedido
  where id = v_order_id;

  update public.detalle_pedido
  set estado = 'ENVIADO',
      enviado_en = pg_catalog.clock_timestamp()
  where pedido_id = v_order_id
    and producto_id = '00000000-0000-0000-0000-00000000a206'
    and estado = 'ABIERTO';

  if not found
    or (select enviado_en from public.detalle_pedido
        where pedido_id = v_order_id
          and producto_id = '00000000-0000-0000-0000-00000000a206') is null
    or (select modificado_en from public.pedido where id = v_order_id)
      <> v_content_modified_at then
    raise exception 'TP20 transición ABIERTO a ENVIADO alteró la semántica actual';
  end if;
end;
$verify_state_audit_scope$;

select 'DBSTD-TP18..TP21 OK' as resultado;

rollback;
