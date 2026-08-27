begin;

create function pg_temp.h4_t04_set_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $h4_t04_set_user$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$h4_t04_set_user$;

do $h4_t04_metadata$
declare
  v_helper text;
  v_add text;
  v_send text;
  v_transition text;
begin
  select pg_catalog.pg_get_functiondef(function_row.oid)
  into strict v_helper
  from pg_catalog.pg_proc as function_row
  where function_row.oid =
    'public.sincronizar_estado_operativo_pedido(bigint,uuid)'::pg_catalog.regprocedure;

  select pg_catalog.pg_get_functiondef(
    'public.agregar_detalle_pedido(bigint,uuid,integer,text)'::pg_catalog.regprocedure
  ) into v_add;
  select pg_catalog.pg_get_functiondef(
    'public.enviar_pedido_cocina(bigint)'::pg_catalog.regprocedure
  ) into v_send;
  select pg_catalog.pg_get_functiondef(
    'public.actualizar_estado_detalle_cocina(bigint,text,text)'::pg_catalog.regprocedure
  ) into v_transition;

  if v_helper !~* 'bool_or.*ABIERTO'
    or v_helper !~* 'bool_or.*ENVIADO'
    or v_helper !~* 'bool_or.*RECIBIDO_COCINA'
    or v_helper !~* 'bool_or.*EN_PREPARACION'
    or v_helper !~* 'bool_and.*LISTO'
    or v_helper !~* 'historial_estado'
    or v_helper !~* 'PEDIDO_LISTO'
    or v_helper !~* 'OCUPADA'
    or v_add !~* 'sincronizar_estado_operativo_pedido'
    or v_send !~* 'sincronizar_estado_operativo_pedido'
    or v_transition !~* 'sincronizar_estado_operativo_pedido' then
    raise exception 'H4-T04 derivación o integración incompletas';
  end if;

  if pg_catalog.has_function_privilege(
    'authenticated',
    'public.sincronizar_estado_operativo_pedido(bigint,uuid)',
    'EXECUTE'
  ) then
    raise exception 'H4-T04 expuso directamente la operación interna';
  end if;
end;
$h4_t04_metadata$;

create function pg_temp.h4_t04_fail_history()
returns trigger
language plpgsql
set search_path = pg_catalog
as $h4_t04_fail_history$
begin
  if new.pedido_id = -40402 then
    raise exception using errcode = 'P0001', message = 'Error inducido H4-T04';
  end if;
  return new;
end;
$h4_t04_fail_history$;

do $h4_t04_behaviour$
declare
  v_waiter uuid := '00000000-0000-0000-0000-00000000d441';
  v_kitchen uuid := '00000000-0000-0000-0000-00000000d442';
  v_local uuid := '00000000-0000-0000-0000-00000000d443';
  v_table_main uuid := '00000000-0000-0000-0000-00000000d444';
  v_table_rollback uuid := '00000000-0000-0000-0000-00000000d445';
  v_category uuid := '00000000-0000-0000-0000-00000000d446';
  v_product uuid := '00000000-0000-0000-0000-00000000d447';
  v_sent_at timestamptz := '2026-08-27 12:00:00-05';
  v_order_modified timestamptz;
  v_history_count bigint;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values
    (v_waiter, 'authenticated', 'authenticated', 'h4-t04-waiter@example.invalid', 'test'),
    (v_kitchen, 'authenticated', 'authenticated', 'h4-t04-kitchen@example.invalid', 'test');

  insert into public.local (id, codigo, nombre)
  values (v_local, 'H4-T04', 'Local H4 T04');

  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_waiter, v_local, role_row.id, 'Mozo T04'
  from public.rol as role_row where role_row.codigo = 'MOZO'
  union all
  select v_kitchen, v_local, role_row.id, 'Cocina T04'
  from public.rol as role_row where role_row.codigo = 'COCINA';

  insert into public.mesa (id, local_id, codigo, nombre, estado)
  values
    (v_table_main, v_local, 'T04-1', 'Mesa principal', 'OCUPADA'),
    (v_table_rollback, v_local, 'T04-2', 'Mesa rollback', 'OCUPADA');

  insert into public.categoria (id, local_id, codigo, nombre)
  values (v_category, v_local, 'T04', 'Categoría T04');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio)
  values (v_product, v_local, v_category, 'T04', 'Producto T04', 10);

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado, enviado_en)
  overriding system value
  values
    (-40401, v_local, v_table_main, v_waiter, 'ENVIADO', v_sent_at),
    (-40402, v_local, v_table_rollback, v_waiter, 'ENVIADO', v_sent_at);

  perform pg_temp.h4_t04_set_user(v_waiter);
  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, estado, enviado_en
  ) overriding system value
  values
    (-40411, -40401, v_product, 1, 10, 'ENVIADO', v_sent_at),
    (-40412, -40401, v_product, 2, 10, 'ENVIADO', v_sent_at),
    (-40421, -40402, v_product, 1, 10, 'ENVIADO', v_sent_at);

  select modificado_en into strict v_order_modified
  from public.pedido where id = -40401;
  select count(*) into v_history_count
  from public.historial_estado where pedido_id = -40401;

  perform pg_temp.h4_t04_set_user(v_kitchen);
  perform public.actualizar_estado_detalle_cocina(
    -40411, 'ENVIADO', 'RECIBIDO_COCINA'
  );
  if (select estado from public.pedido where id = -40401) <> 'ENVIADO'
    or (select count(*) from public.historial_estado where pedido_id = -40401)
      <> v_history_count then
    raise exception 'H4-T04 ENVIADO + RECIBIDO no conservó mínimo o duplicó historial';
  end if;

  perform public.actualizar_estado_detalle_cocina(
    -40412, 'ENVIADO', 'RECIBIDO_COCINA'
  );
  if (select estado from public.pedido where id = -40401) <> 'RECIBIDO_COCINA'
    or not exists (
      select 1 from public.historial_estado
      where pedido_id = -40401 and estado_anterior = 'ENVIADO'
        and estado_nuevo = 'RECIBIDO_COCINA' and usuario_id = v_kitchen
    ) then
    raise exception 'H4-T04 no derivó RECIBIDO_COCINA o no registró historial';
  end if;

  perform public.actualizar_estado_detalle_cocina(
    -40411, 'RECIBIDO_COCINA', 'EN_PREPARACION'
  );
  if (select estado from public.pedido where id = -40401) <> 'RECIBIDO_COCINA' then
    raise exception 'H4-T04 RECIBIDO + PREPARACION no conservó mínimo';
  end if;
  perform public.actualizar_estado_detalle_cocina(
    -40412, 'RECIBIDO_COCINA', 'EN_PREPARACION'
  );
  if (select estado from public.pedido where id = -40401) <> 'EN_PREPARACION' then
    raise exception 'H4-T04 no derivó EN_PREPARACION';
  end if;

  perform public.actualizar_estado_detalle_cocina(
    -40411, 'EN_PREPARACION', 'LISTO'
  );
  if (select estado from public.pedido where id = -40401) <> 'EN_PREPARACION'
    or (select estado from public.mesa where id = v_table_main) <> 'OCUPADA' then
    raise exception 'H4-T04 PREPARACION + LISTO no conservó pedido/mesa';
  end if;
  perform public.actualizar_estado_detalle_cocina(
    -40412, 'EN_PREPARACION', 'LISTO'
  );
  if (select estado from public.pedido where id = -40401) <> 'LISTO'
    or (select estado from public.mesa where id = v_table_main) <> 'PEDIDO_LISTO' then
    raise exception 'H4-T04 todos LISTO no actualizó cabecera y mesa';
  end if;

  perform pg_temp.h4_t04_set_user(v_waiter);
  perform public.agregar_detalle_pedido(-40401, v_product, 1, 'Agregado posterior');
  if (select estado from public.pedido where id = -40401) <> 'ABIERTO'
    or (select estado from public.mesa where id = v_table_main) <> 'OCUPADA'
    or (select count(*) from public.detalle_pedido where pedido_id = -40401 and estado = 'LISTO') <> 2
    or not exists (
      select 1 from public.historial_estado
      where pedido_id = -40401 and estado_anterior = 'LISTO'
        and estado_nuevo = 'ABIERTO' and usuario_id = v_waiter
    ) then
    raise exception 'H4-T04 alta posterior no recalculó o retrocedió detalles previos';
  end if;

  select modificado_en into strict v_order_modified
  from public.pedido where id = -40401;
  perform public.enviar_pedido_cocina(-40401);
  if (select estado from public.pedido where id = -40401) <> 'ENVIADO'
    or (select estado from public.mesa where id = v_table_main) <> 'OCUPADA'
    or (select count(*) from public.detalle_pedido where pedido_id = -40401 and estado = 'LISTO') <> 2
    or (select modificado_en from public.pedido where id = -40401)
      is distinct from v_order_modified
    or not exists (
      select 1 from public.historial_estado
      where pedido_id = -40401 and estado_anterior = 'ABIERTO'
        and estado_nuevo = 'ENVIADO' and usuario_id = v_waiter
    ) then
    raise exception 'H4-T04 envío posterior, historial o auditoría comercial incorrectos';
  end if;

  create trigger h4_t04_induced_failure
  before insert on public.historial_estado
  for each row execute function pg_temp.h4_t04_fail_history();

  perform pg_temp.h4_t04_set_user(v_kitchen);
  begin
    perform public.actualizar_estado_detalle_cocina(
      -40421, 'ENVIADO', 'RECIBIDO_COCINA'
    );
    raise exception 'H4-T04 no propagó el error inducido';
  exception when sqlstate 'P0001' then null;
  end;

  if (select estado from public.detalle_pedido where id = -40421) <> 'ENVIADO'
    or (select estado from public.pedido where id = -40402) <> 'ENVIADO'
    or (select estado from public.mesa where id = v_table_rollback) <> 'OCUPADA'
    or exists (select 1 from public.historial_estado where pedido_id = -40402) then
    raise exception 'H4-T04 error inducido no revirtió toda la operación';
  end if;

  drop trigger h4_t04_induced_failure on public.historial_estado;
end;
$h4_t04_behaviour$;

rollback;
