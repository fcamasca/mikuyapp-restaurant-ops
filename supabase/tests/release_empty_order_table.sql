begin;

create function pg_temp.set_test_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $set_test_user$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$set_test_user$;

create function pg_temp.fail_release_history()
returns trigger
language plpgsql
as $fail_release_history$
begin
  if new.estado_nuevo = 'ANULADO' then
    raise exception using errcode = 'P0001', message = 'fallo inducido liberación';
  end if;
  return new;
end;
$fail_release_history$;

do $verify_release_empty_order_table$
declare
  v_local_id uuid := '00000000-0000-0000-0000-00000000e101';
  v_other_local_id uuid := '00000000-0000-0000-0000-00000000e102';
  v_waiter_id uuid := '00000000-0000-0000-0000-00000000e103';
  v_other_waiter_id uuid := '00000000-0000-0000-0000-00000000e104';
  v_admin_id uuid := '00000000-0000-0000-0000-00000000e105';
  v_category_id uuid := '00000000-0000-0000-0000-00000000e106';
  v_product_id uuid := '00000000-0000-0000-0000-00000000e107';
  v_table_empty uuid := '00000000-0000-0000-0000-00000000e108';
  v_table_open_detail uuid := '00000000-0000-0000-0000-00000000e109';
  v_table_sent_detail uuid := '00000000-0000-0000-0000-00000000e110';
  v_table_sent_order uuid := '00000000-0000-0000-0000-00000000e111';
  v_table_other uuid := '00000000-0000-0000-0000-00000000e112';
  v_table_rollback uuid := '00000000-0000-0000-0000-00000000e113';
  v_new_order_id bigint;
begin
  if not exists (
    select 1 from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'liberar_mesa_pedido_vacio'
      and p.prosecdef and p.proowner = (select oid from pg_catalog.pg_roles where rolname = 'postgres')
      and p.proconfig = array['search_path=pg_catalog']
  ) then raise exception 'Configuración SECURITY DEFINER inválida'; end if;

  if pg_catalog.has_function_privilege('anon', 'public.liberar_mesa_pedido_vacio(bigint)', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.liberar_mesa_pedido_vacio(bigint)', 'EXECUTE')
    or pg_catalog.has_column_privilege('authenticated', 'public.pedido', 'estado', 'UPDATE')
    or pg_catalog.has_column_privilege('authenticated', 'public.mesa', 'estado', 'UPDATE') then
    raise exception 'Privilegios de liberación inválidos';
  end if;

  insert into auth.users (id, aud, role, email, encrypted_password) values
    (v_waiter_id, 'authenticated', 'authenticated', 'release-waiter@example.invalid', 'test'),
    (v_other_waiter_id, 'authenticated', 'authenticated', 'release-other@example.invalid', 'test'),
    (v_admin_id, 'authenticated', 'authenticated', 'release-admin@example.invalid', 'test');
  insert into public.local (id, codigo, nombre) values
    (v_local_id, 'RELEASE-A', 'Release A'), (v_other_local_id, 'RELEASE-B', 'Release B');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_waiter_id, v_local_id, id, 'Mozo liberar' from public.rol where codigo = 'MOZO'
  union all select v_other_waiter_id, v_other_local_id, id, 'Otro mozo' from public.rol where codigo = 'MOZO'
  union all select v_admin_id, v_local_id, id, 'Admin liberar' from public.rol where codigo = 'ADMINISTRADOR';
  insert into public.categoria (id, local_id, codigo, nombre) values (v_category_id, v_local_id, 'RELEASE-C', 'Categoría');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio) values (v_product_id, v_local_id, v_category_id, 'RELEASE-P', 'Producto', 10);
  insert into public.mesa (id, local_id, codigo, nombre, estado) values
    (v_table_empty, v_local_id, 'R01', 'Vacía', 'OCUPADA'),
    (v_table_open_detail, v_local_id, 'R02', 'Con abierto', 'OCUPADA'),
    (v_table_sent_detail, v_local_id, 'R03', 'Con enviado', 'OCUPADA'),
    (v_table_sent_order, v_local_id, 'R04', 'Pedido enviado', 'OCUPADA'),
    (v_table_other, v_other_local_id, 'R05', 'Otro local', 'OCUPADA'),
    (v_table_rollback, v_local_id, 'R06', 'Rollback', 'OCUPADA');
  insert into public.pedido (id, local_id, mesa_id, creado_por, estado) overriding system value values
    (-98101, v_local_id, v_table_empty, v_waiter_id, 'ABIERTO'),
    (-98102, v_local_id, v_table_open_detail, v_waiter_id, 'ABIERTO'),
    (-98103, v_local_id, v_table_sent_detail, v_waiter_id, 'ABIERTO'),
    (-98104, v_local_id, v_table_sent_order, v_waiter_id, 'ENVIADO'),
    (-98105, v_other_local_id, v_table_other, v_other_waiter_id, 'ABIERTO'),
    (-98106, v_local_id, v_table_rollback, v_waiter_id, 'ABIERTO');
  insert into public.detalle_pedido (id, pedido_id, producto_id, cantidad, precio_unitario, estado) overriding system value values
    (-98102, -98102, v_product_id, 1, 10, 'ABIERTO'),
    (-98103, -98103, v_product_id, 1, 10, 'ENVIADO');

  perform pg_temp.set_test_user(v_waiter_id);
  perform public.liberar_mesa_pedido_vacio(-98101);
  if (select estado from public.pedido where id = -98101) <> 'ANULADO'
    or (select estado from public.mesa where id = v_table_empty) <> 'LIBRE'
    or (select count(*) from public.historial_estado where pedido_id = -98101 and estado_anterior = 'ABIERTO' and estado_nuevo = 'ANULADO' and usuario_id = v_waiter_id) <> 1 then
    raise exception 'Transición completa inválida';
  end if;
  if exists (select 1 from public.pedido where mesa_id = v_table_empty and estado in ('ABIERTO','ENVIADO','RECIBIDO_COCINA','EN_PREPARACION','LISTO','ENTREGADO')) then
    raise exception 'Pedido anulado continúa vigente';
  end if;
  select result.pedido_id into strict v_new_order_id from public.crear_o_recuperar_pedido_mesa(v_table_empty) as result;
  if v_new_order_id = -98101 or (select estado from public.pedido where id = v_new_order_id) <> 'ABIERTO' then raise exception 'No inició nuevo ciclo'; end if;

  begin perform public.liberar_mesa_pedido_vacio(-98102); raise exception 'Aceptó detalle ABIERTO'; exception when sqlstate '55000' then null; end;
  begin perform public.liberar_mesa_pedido_vacio(-98103); raise exception 'Aceptó detalle ENVIADO'; exception when sqlstate '55000' then null; end;
  begin perform public.liberar_mesa_pedido_vacio(-98104); raise exception 'Aceptó pedido ENVIADO'; exception when sqlstate '55000' then null; end;
  begin perform public.liberar_mesa_pedido_vacio(-98101); raise exception 'Aceptó doble llamada'; exception when sqlstate '55000' then null; end;

  perform pg_temp.set_test_user(v_other_waiter_id);
  begin perform public.liberar_mesa_pedido_vacio(-98106); raise exception 'Aceptó otro local'; exception when sqlstate '55000' then null; end;
  perform pg_temp.set_test_user(v_admin_id);
  begin perform public.liberar_mesa_pedido_vacio(-98106); raise exception 'Aceptó ADMINISTRADOR'; exception when sqlstate '42501' then null; end;

  perform pg_temp.set_test_user(v_waiter_id);
  create trigger fail_release_history before insert on public.historial_estado for each row execute function pg_temp.fail_release_history();
  begin perform public.liberar_mesa_pedido_vacio(-98106); raise exception 'No propagó fallo inducido'; exception when sqlstate 'P0001' then null; end;
  if (select estado from public.pedido where id = -98106) <> 'ABIERTO'
    or (select estado from public.mesa where id = v_table_rollback) <> 'OCUPADA'
    or exists (select 1 from public.historial_estado where pedido_id = -98106 and estado_nuevo = 'ANULADO') then
    raise exception 'Rollback incompleto';
  end if;
  drop trigger fail_release_history on public.historial_estado;
end;
$verify_release_empty_order_table$;

rollback;
