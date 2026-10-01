-- E9-T07 — TP08: matriz de operaciones con el local cerrado (DC-10). Con datos terminales de una jornada
-- anterior, cada operación de design.md E9-D05 se rechaza sin efectos (con su conflicto vigente o con
-- "Local cerrado"), incluidas las escrituras directas de detalle_pedido por RLS; ADMINISTRADOR conserva sus
-- funciones administrativas no operativas y puede abrir una nueva jornada. Fixture propia; ROLLBACK.
begin;

create function pg_temp.as_user(p_user_id uuid) returns void
language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

create function pg_temp.try_as(p_user uuid, p_sql text) returns text
language plpgsql set search_path = pg_catalog as $$
declare v_rows bigint;
begin
  perform pg_temp.as_user(p_user);
  begin
    execute 'set local role authenticated';
    execute p_sql;
    get diagnostics v_rows = row_count;
    execute 'reset role';
    return 'OK:' || v_rows;
  exception when others then
    execute 'reset role';
    return sqlstate || ':' || sqlerrm;
  end;
end $$;

create function pg_temp.estado() returns text
language sql set search_path = pg_catalog as $$
  select md5(concat_ws('|',
    (select string_agg(id || ':' || estado || ':' || jornada_operativa_id, ',' order by id) from public.pedido),
    (select string_agg(id || ':' || estado || ':' || cantidad || ':' || coalesce(observacion, ''), ',' order by id) from public.detalle_pedido),
    (select string_agg(id::text || ':' || estado, ',' order by id) from public.mesa),
    (select string_agg(id::text || ':' || estado, ',' order by id) from public.sesion_caja),
    (select count(*) from public.historial_estado), (select count(*) from public.historial_detalle_pedido),
    (select string_agg(id || ':' || impresiones, ',' order by id) from public.comanda),
    (select string_agg(id || ':' || estado, ',' order by id) from public.solicitud_cuenta),
    (select string_agg(id::text || ':' || estado, ',' order by id) from public.descuento_pedido),
    (select count(*) from public.anulacion_pedido), (select count(*) from public.cobro), (select count(*) from public.pago),
    (select count(*) from public.movimiento_caja), (select count(*) from public.resumen_cierre_sesion_caja),
    (select count(*) from public.auditoria_caja), (select string_agg(id || ':' || estado, ',' order by id) from public.jornada_operativa)))
$$;

do $e9_tp08$
declare
  v_admin uuid := '00000000-0000-0000-0000-0000000e9801';
  v_mozo uuid := '00000000-0000-0000-0000-0000000e9802';
  v_coc uuid := '00000000-0000-0000-0000-0000000e9803';
  v_caja uuid := '00000000-0000-0000-0000-0000000e9804';
  v_local uuid := '00000000-0000-0000-0000-0000000e9811';
  v_caja_id uuid := '00000000-0000-0000-0000-0000000e9812';
  v_cat uuid := '00000000-0000-0000-0000-0000000e9813';
  v_cev uuid := '00000000-0000-0000-0000-0000000e9814';
  v_chi uuid := '00000000-0000-0000-0000-0000000e9815';
  v_m1 uuid := '00000000-0000-0000-0000-0000000e9821';
  v_m2 uuid := '00000000-0000-0000-0000-0000000e9822';
  v_m3 uuid := '00000000-0000-0000-0000-0000000e9823';
  v_j bigint; v_p1 bigint; v_p2 bigint; v_s jsonb; v_s_id uuid; v_d1 bigint; v_d2 bigint; v_comanda bigint;
  v_before text; v_res text; r record; v_call record;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  select u, 'authenticated', 'authenticated', 'e9-tp08-' || u || '@example.invalid', 't'
  from unnest(array[v_admin, v_mozo, v_coc, v_caja]) u;
  insert into public.local (id, codigo, nombre) values (v_local, 'E9-TP08', 'Local TP08');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_admin, v_local, id, 'Admin' from public.rol where codigo = 'ADMINISTRADOR'
  union all select v_mozo, v_local, id, 'Mozo' from public.rol where codigo = 'MOZO'
  union all select v_coc, v_local, id, 'Cocina' from public.rol where codigo = 'COCINA'
  union all select v_caja, v_local, id, 'Caja' from public.rol where codigo = 'CAJA';
  insert into public.mesa (id, local_id, codigo, nombre) values (v_m1, v_local, 'P8-1', 'Mesa 1'), (v_m2, v_local, 'P8-2', 'Mesa 2'), (v_m3, v_local, 'P8-3', 'Mesa 3');
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'P8', 'Carta');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
    (v_cev, v_local, v_cat, 'CEV', 'Ceviche', 30, true), (v_chi, v_local, v_cat, 'CHI', 'Chicha', 8, false);
  insert into public.caja (id, local_id, codigo, nombre) values (v_caja_id, v_local, 'P8', 'Caja P8');

  -- Jornada anterior con datos terminales: P1 PAGADO (con comanda impresa y solicitud ATENDIDA),
  -- P2 ANULADO con descuento pendiente; sesión de caja cerrada; jornada cerrada.
  perform pg_temp.as_user(v_admin);
  select jornada_operativa_id into strict v_j from public.rpc_abrir_jornada_operativa(gen_random_uuid());
  perform pg_temp.as_user(v_caja);
  v_s := public.rpc_abrir_sesion_caja(v_caja_id, 0, gen_random_uuid()); v_s_id := (v_s->>'id')::uuid;
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p1 from public.crear_o_recuperar_pedido_mesa(v_m1);
  perform public.agregar_detalle_pedido(v_p1, v_cev, 1, null);
  perform public.enviar_pedido_cocina(v_p1);
  select id into strict v_d1 from public.detalle_pedido where pedido_id = v_p1;
  select id into strict v_comanda from public.comanda where pedido_id = v_p1;
  perform pg_temp.as_user(v_coc);
  perform public.rpc_registrar_impresion_comanda(v_comanda, false);
  perform public.rpc_recibir_pedido_cocina(v_p1);
  perform public.actualizar_estado_detalle_cocina(v_d1, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  perform public.actualizar_estado_detalle_cocina(v_d1, 'EN_PREPARACION', 'LISTO');
  perform pg_temp.as_user(v_mozo);
  perform public.entregar_pedido(v_p1);
  perform public.rpc_solicitar_cuenta_pedido(v_p1);
  perform pg_temp.as_user(v_caja);
  perform public.rpc_registrar_cobro_pedido(v_p1, v_s_id, 'TOTAL', '[{"medio":"EFECTIVO","importe":30,"propina":0}]'::jsonb, gen_random_uuid());
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p2 from public.crear_o_recuperar_pedido_mesa(v_m2);
  perform public.agregar_detalle_pedido(v_p2, v_chi, 1, null);
  perform public.enviar_pedido_cocina(v_p2);
  select id into strict v_d2 from public.detalle_pedido where pedido_id = v_p2;
  perform public.entregar_pedido(v_p2);
  perform pg_temp.as_user(v_caja);
  perform public.rpc_solicitar_descuento_pedido(v_p2, 1, null, 'TP08', gen_random_uuid());
  perform pg_temp.as_user(v_admin);
  perform public.anular_pedido_supervisado(v_p2, 'TP08', gen_random_uuid());
  perform pg_temp.as_user(v_caja);
  perform public.fn_cerrar_sesion_caja(v_s_id, 30, null, gen_random_uuid(), false);
  perform pg_temp.as_user(v_admin);
  perform public.rpc_cerrar_jornada_operativa(v_j);
  perform pg_temp.as_user(null);
  if exists (select 1 from public.pedido where local_id = v_local and estado not in ('PAGADO', 'ANULADO'))
    or exists (select 1 from public.sesion_caja where local_id = v_local and estado = 'ABIERTA')
    or exists (select 1 from public.jornada_operativa where local_id = v_local and estado = 'ABIERTA') then
    raise exception 'E9-TP08: fixture no terminal';
  end if;

  -- ===== Matriz: toda operación del restaurante se rechaza sin efectos con el local cerrado
  v_before := pg_temp.estado();
  for v_call in select * from (values
    (v_mozo, format('select * from public.crear_o_recuperar_pedido_mesa(%L)', v_m3), 'PT409:Local cerrado — el sistema no se encuentra aperturado'),
    (v_mozo, format('select * from public.h3_abrir_o_recuperar_pedido(%L)', v_m3), null),
    (v_caja, format('select public.rpc_abrir_sesion_caja(%L, 0, gen_random_uuid())', v_caja_id), 'PT409:Local cerrado — el sistema no se encuentra aperturado'),
    (v_mozo, format('select public.agregar_detalle_pedido(%s, %L, 1, null)', v_p1, v_chi), null),
    (v_mozo, format('select * from public.rpc_modificar_detalle_pedido(%s, 2, null, 1, null)', v_d1), null),
    (v_mozo, format('select * from public.rpc_retirar_detalle_pedido(%s)', v_d1), null),
    (v_mozo, format('select * from public.enviar_pedido_cocina(%s)', v_p1), null),
    (v_coc, format('select * from public.actualizar_estado_detalle_cocina(%s, ''LISTO'', ''EN_PREPARACION'')', v_d1), null),
    (v_coc, format('select * from public.rpc_recibir_pedido_cocina(%s)', v_p1), null),
    (v_coc, format('select * from public.rpc_registrar_impresion_comanda(%s, true)', v_comanda), null),
    (v_mozo, format('select * from public.rpc_cancelar_detalle_pedido(%s, ''TP08'')', v_d1), null),
    (v_mozo, format('select * from public.entregar_pedido(%s)', v_p1), null),
    (v_mozo, format('select * from public.rpc_solicitar_cuenta_pedido(%s)', v_p1), null),
    (v_mozo, format('select * from public.liberar_mesa_pedido_vacio(%s)', v_p1), null),
    (v_caja, format('select * from public.rpc_solicitar_descuento_pedido(%s, 1, null, ''TP08'', gen_random_uuid())', v_p1), null),
    (v_admin, format('select * from public.rpc_decidir_descuento_pedido(%s, ''AUTORIZAR'', ''TP08'', gen_random_uuid())', v_p2), null),
    (v_admin, format('select * from public.anular_pedido_supervisado(%s, ''TP08'', gen_random_uuid())', v_p1), null),
    (v_caja, format('select * from public.rpc_registrar_cobro_pedido(%s, %L, ''TOTAL'', ''[{"medio":"EFECTIVO","importe":30,"propina":0}]''::jsonb, gen_random_uuid())', v_p1, v_s_id), null),
    (v_caja, format('select * from public.registrar_pago_pedido(%s, ''EFECTIVO'')', v_p1), null),
    (v_caja, format('select * from public.rpc_registrar_pago_total_pedido(%s, %L, ''EFECTIVO'', 0, gen_random_uuid())', v_p1, v_s_id), null),
    (v_caja, format('select * from public.rpc_registrar_pago_pedido_v2(%s, %L, 30, ''EFECTIVO'', 0, gen_random_uuid())', v_p1, v_s_id), null),
    (v_caja, format('select public.rpc_registrar_movimiento_caja(%L, ''ENTRADA'', 5, ''TP08'', gen_random_uuid())', v_s_id), null),
    (v_caja, format('select public.registrar_movimientos_caja(%L, ''[{"tipo":"ENTRADA","importe":5,"motivo":"TP08"}]''::jsonb, gen_random_uuid())', v_s_id), null),
    (v_caja, format('select public.rpc_cerrar_sesion_caja(%L, 30, null, gen_random_uuid())', v_s_id), null),
    (v_admin, format('select public.rpc_cerrar_sesion_caja_supervisor(%L, 30, ''TP08'', gen_random_uuid())', v_s_id), null)
  ) as c(usuario, sql, esperado) loop
    v_res := pg_temp.try_as(v_call.usuario, v_call.sql);
    if v_res like 'OK%' or v_res like '40001%' or (v_call.esperado is not null and v_res <> v_call.esperado) then
      raise exception 'E9-TP08: operación no rechazada como se esperaba: % => %', v_call.sql, v_res;
    end if;
    raise notice 'TP08 rechazo % => %', split_part(split_part(v_call.sql, 'public.', 2), '(', 1), left(v_res, 90);
  end loop;
  -- Escrituras directas de detalle_pedido (MOZO): sin privilegio (42501) o sin filas visibles por RLS (OK:0).
  for v_call in select * from (values
    (format('update public.detalle_pedido set cantidad = 5 where id in (%s, %s)', v_d1, v_d2)),
    (format('delete from public.detalle_pedido where id in (%s, %s)', v_d1, v_d2))
  ) as c(sql) loop
    v_res := pg_temp.try_as(v_mozo, v_call.sql);
    if v_res <> 'OK:0' and v_res not like '42501:%' then
      raise exception 'E9-TP08: escritura directa de detalle_pedido con el local cerrado: % => %', v_call.sql, v_res;
    end if;
    raise notice 'TP08 rechazo escritura directa => %', v_res;
  end loop;
  if pg_temp.estado() <> v_before then
    raise exception 'E9-TP08: un rechazo dejó efectos';
  end if;

  -- ===== ADMINISTRADOR conserva sus funciones no operativas con el local cerrado
  for v_call in select * from (values
    ('select * from public.rpc_obtener_jornada_operativa_actual()'),
    ('select * from public.rpc_obtener_historial_jornadas_operativas(50, 0)'),
    ('select * from public.rpc_obtener_pendientes_cierre_jornada()'),
    ('select * from public.rpc_obtener_pedidos_operacion_admin()'),
    ('select * from public.rpc_obtener_reportes_sesion_caja(null)'),
    ('select * from public.rpc_obtener_resumen_diario_caja()'),
    ('select * from public.obtener_resumen_ventas_hoy()'),
    ('select * from public.exportar_ventas_hoy()'),
    ('select * from public.exportar_productos_local()'),
    (format('select * from public.rpc_obtener_auditoria_financiera(%L, null, 50)', v_s_id)),
    ('select * from public.rpc_obtener_notificaciones_caja()'),
    (format('update public.producto set precio = 31 where id = %L', v_cev)),
    (format('update public.mesa set nombre = ''Mesa 3 renombrada'' where id = %L', v_m3))
  ) as c(sql) loop
    v_res := pg_temp.try_as(v_admin, v_call.sql);
    if v_res not like 'OK%' then
      raise exception 'E9-TP08: función administrativa no operativa rechazada con el local cerrado: % => %', v_call.sql, v_res;
    end if;
  end loop;
  if (select precio from public.producto where id = v_cev) <> 31 then
    raise exception 'E9-TP08: la administración de carta no se aplicó';
  end if;
  -- ... y puede abrir una nueva jornada, tras lo cual la operación vuelve a estar disponible.
  perform pg_temp.as_user(v_admin);
  select * into strict r from public.rpc_abrir_jornada_operativa(gen_random_uuid());
  if r.ya_existia or r.numero <> 2 then raise exception 'E9-TP08: reapertura del local %', r; end if;
  if pg_temp.try_as(v_mozo, format('select * from public.crear_o_recuperar_pedido_mesa(%L)', v_m3)) not like 'OK%' then
    raise exception 'E9-TP08: tras abrir la jornada no se pudo operar';
  end if;
  raise notice 'E9-TP08 matriz de local cerrado: PASS';
end;
$e9_tp08$;

rollback;
