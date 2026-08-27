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

do $verify_state_audit_scope$
declare
  v_order_id bigint;
  v_order_modified_at timestamptz;
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
end;
$verify_state_audit_scope$;

rollback;
