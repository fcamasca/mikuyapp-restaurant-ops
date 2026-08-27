begin;

do $tp10$
declare
  actual_constraint text;
  actual_state text;
  demo_local_id uuid;
  demo_product_id uuid;
begin
  select id into strict demo_local_id
  from public.local
  where codigo = 'MIKUY-DEMO';

  select id into strict demo_product_id
  from public.producto
  where local_id = demo_local_id
  order by codigo
  limit 1;

  begin
    insert into public.rol (id, codigo, nombre, activo)
    values (-32000, 'ROL_INVALIDO_TP10', 'Rol inválido TP-10', true);
    raise exception using errcode = 'P0001', message = 'TP-10: código de rol inválido fue aceptado';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23514' or actual_constraint <> 'ck_rol_codigo_valido' then
      raise exception 'TP-10 rol inválido: se esperaba 23514/ck_rol_codigo_valido, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.mesa (id, local_id, codigo, nombre, estado, activo)
    values ('00000000-0000-0000-0000-00000000a001', demo_local_id, 'TP10-MESA-ESTADO', 'Mesa TP-10', 'ESTADO_INVALIDO', true);
    raise exception using errcode = 'P0001', message = 'TP-10: estado de mesa inválido fue aceptado';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23514' or actual_constraint <> 'ck_mesa_estado_valido' then
      raise exception 'TP-10 mesa inválida: se esperaba 23514/ck_mesa_estado_valido, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.pedido (id, local_id, mesa_id, creado_por, estado)
    overriding system value
    values (-91001, demo_local_id, '00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000a003', 'ESTADO_INVALIDO');
    raise exception using errcode = 'P0001', message = 'TP-10: estado de pedido inválido fue aceptado';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23514' or actual_constraint <> 'ck_pedido_estado_valido' then
      raise exception 'TP-10 pedido inválido: se esperaba 23514/ck_pedido_estado_valido, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.historial_estado (id, pedido_id, estado_anterior, estado_nuevo, usuario_id)
    overriding system value
    values (-91002, -91001, 'ESTADO_INVALIDO', 'ABIERTO', '00000000-0000-0000-0000-00000000a003');
    raise exception using errcode = 'P0001', message = 'TP-10: estado de historial inválido fue aceptado';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23514' or actual_constraint <> 'ck_historial_estado_anterior_valido' then
      raise exception 'TP-10 historial inválido: se esperaba 23514/ck_historial_estado_anterior_valido, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.detalle_pedido (id, pedido_id, producto_id, cantidad, precio_unitario)
    overriding system value
    values (-91003, -91001, demo_product_id, '1.5', 1.00);
    raise exception using errcode = 'P0001', message = 'TP-10: cantidad fraccionaria fue aceptada';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '22P02' then
      raise exception 'TP-10 cantidad fraccionaria: se esperaba 22P02, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.detalle_pedido (id, pedido_id, producto_id, cantidad, precio_unitario)
    overriding system value
    values (-91004, -91001, demo_product_id, 0, 1.00);
    raise exception using errcode = 'P0001', message = 'TP-10: cantidad cero fue aceptada';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23514' or actual_constraint <> 'ck_detalle_pedido_cantidad_positiva' then
      raise exception 'TP-10 cantidad cero: se esperaba 23514/ck_detalle_pedido_cantidad_positiva, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.detalle_pedido (id, pedido_id, producto_id, cantidad, precio_unitario)
    overriding system value
    values (-91005, -91001, demo_product_id, -1, 1.00);
    raise exception using errcode = 'P0001', message = 'TP-10: cantidad negativa fue aceptada';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23514' or actual_constraint <> 'ck_detalle_pedido_cantidad_positiva' then
      raise exception 'TP-10 cantidad negativa: se esperaba 23514/ck_detalle_pedido_cantidad_positiva, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, activo)
    values ('00000000-0000-0000-0000-00000000a004', demo_local_id, '00000000-0000-0000-0000-00000000a005', 'TP10-PRECIO', 'Producto TP-10', -0.01, true);
    raise exception using errcode = 'P0001', message = 'TP-10: precio de producto negativo fue aceptado';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23514' or actual_constraint <> 'ck_producto_precio_no_negativo' then
      raise exception 'TP-10 precio producto: se esperaba 23514/ck_producto_precio_no_negativo, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.detalle_pedido (id, pedido_id, producto_id, cantidad, precio_unitario)
    overriding system value
    values (-91006, -91001, demo_product_id, 1, -0.01);
    raise exception using errcode = 'P0001', message = 'TP-10: precio unitario negativo fue aceptado';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23514' or actual_constraint <> 'ck_detalle_pedido_precio_no_negativo' then
      raise exception 'TP-10 precio unitario: se esperaba 23514/ck_detalle_pedido_precio_no_negativo, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.pago (id, pedido_id, importe, medio, usuario_id)
    overriding system value
    values (-91007, -91001, 1.00, 'MEDIO_INVALIDO', '00000000-0000-0000-0000-00000000a003');
    raise exception using errcode = 'P0001', message = 'TP-10: medio de pago inválido fue aceptado';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23514' or actual_constraint <> 'ck_pago_medio_valido' then
      raise exception 'TP-10 medio de pago: se esperaba 23514/ck_pago_medio_valido, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.pago (id, pedido_id, importe, medio, usuario_id)
    overriding system value
    values (-91008, -91001, 0, 'EFECTIVO', '00000000-0000-0000-0000-00000000a003');
    raise exception using errcode = 'P0001', message = 'TP-10: importe cero fue aceptado';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23514' or actual_constraint <> 'ck_pago_importe_positivo' then
      raise exception 'TP-10 importe cero: se esperaba 23514/ck_pago_importe_positivo, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.pago (id, pedido_id, importe, medio, usuario_id)
    overriding system value
    values (-91009, -91001, -0.01, 'EFECTIVO', '00000000-0000-0000-0000-00000000a003');
    raise exception using errcode = 'P0001', message = 'TP-10: importe negativo fue aceptado';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23514' or actual_constraint <> 'ck_pago_importe_positivo' then
      raise exception 'TP-10 importe negativo: se esperaba 23514/ck_pago_importe_positivo, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.local (id, codigo, nombre, activo)
    values ('00000000-0000-0000-0000-00000000a006', 'MIKUY-DEMO', 'Duplicado TP-10', true);
    raise exception using errcode = 'P0001', message = 'TP-10: código natural duplicado fue aceptado';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23505' or actual_constraint <> 'uq_local_codigo' then
      raise exception 'TP-10 código duplicado: se esperaba 23505/uq_local_codigo, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.mesa (id, local_id, codigo, nombre, estado, activo)
    values ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-00000000a008', 'TP10-FK', 'Mesa FK TP-10', 'LIBRE', true);
    raise exception using errcode = 'P0001', message = 'TP-10: FK inexistente fue aceptada';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate, actual_constraint = constraint_name;
    if actual_state <> '23503' or actual_constraint <> 'fk_mesa_local' then
      raise exception 'TP-10 FK inexistente: se esperaba 23503/fk_mesa_local, se obtuvo %/%', actual_state, actual_constraint;
    end if;
  end;
end
$tp10$;

do $tp10_catalogs$
declare
  actual_names text[];
begin
  select array_agg(con.conname order by con.conname)
  into actual_names
  from pg_constraint con
  join pg_namespace n on n.oid = con.connamespace
  where n.nspname = 'public'
    and con.contype = 'u';

  if actual_names <> array[
    'uq_categoria_id_local_id',
    'uq_categoria_local_id_codigo',
    'uq_local_codigo',
    'uq_mesa_id_local_id',
    'uq_mesa_local_id_codigo',
    'uq_pago_pedido_id',
    'uq_producto_local_id_codigo',
    'uq_rol_codigo',
    'uq_rol_nombre'
  ]::text[] then
    raise exception 'TP-10: UNIQUE de D-08 diferentes: %', actual_names;
  end if;

  select array_agg(indexname order by indexname)
  into actual_names
  from pg_indexes
  where schemaname = 'public'
    and indexname like 'idx_%';

  if actual_names <> array[
    'idx_categoria_local_id_activo_orden',
    'idx_detalle_pedido_pedido_id',
    'idx_detalle_pedido_pedido_id_estado',
    'idx_detalle_pedido_producto_id',
    'idx_historial_estado_pedido_id_creado_en',
    'idx_mesa_local_id_estado',
    'idx_pago_pagado_en',
    'idx_pedido_local_id_estado_creado_en',
    'idx_pedido_mesa_id_estado',
    'idx_perfil_usuario_local_id',
    'idx_perfil_usuario_rol_id',
    'idx_producto_categoria_id_activo',
    'idx_producto_local_id_activo'
  ]::text[] then
    raise exception 'TP-10: índices adicionales vigentes diferentes: %', actual_names;
  end if;

  raise notice 'TP-10 aprobada: rechazos dinámicos, 9 UNIQUE y 13 índices idx_* verificados';
end
$tp10_catalogs$;

rollback;
