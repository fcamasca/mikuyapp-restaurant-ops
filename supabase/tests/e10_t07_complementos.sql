-- E10-T07 — Escenarios complementarios de la campaña final (test-plan §3 sin cobertura en las pruebas
-- focales): TP06 vías históricas de pago, cobro fallido y descuento autorizado; TP07 retiro E7 del producto
-- nuevo y reapertura bloqueada tras cobro parcial; TP08 anulación sin solicitud; TP09 TRUNCATE de
-- service_role; TP14 matriz de lectura directa por rol. Fixture propia; termina con ROLLBACK.
begin;

create function pg_temp.as_user(p_user_id uuid) returns void
language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

create function pg_temp.sqlstate_as(p_user uuid, p_sql text) returns text
language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_temp.as_user(p_user);
  execute p_sql;
  return 'OK';
exception when others then
  return sqlstate;
end $$;

-- Ejecuta p_sql con el rol de base indicado; devuelve 'rows=N' o el SQLSTATE.
create function pg_temp.try_role(p_user uuid, p_role text, p_sql text) returns text
language plpgsql set search_path = pg_catalog as $$
declare v_rows bigint;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', p_role, true);
  begin
    execute format('set local role %I', p_role);
    execute p_sql;
    get diagnostics v_rows = row_count;
    execute 'reset role';
    return 'rows=' || v_rows;
  exception when others then
    execute 'reset role';
    return sqlstate;
  end;
end $$;

create function pg_temp.entregado(p_mozo uuid, p_mesa uuid, p_producto uuid, p_cantidad int) returns bigint
language plpgsql set search_path = pg_catalog as $$
declare v_pedido bigint;
begin
  perform pg_temp.as_user(p_mozo);
  select pedido_id into strict v_pedido from public.crear_o_recuperar_pedido_mesa(p_mesa);
  perform public.agregar_detalle_pedido(v_pedido, p_producto, p_cantidad, null);
  perform public.enviar_pedido_cocina(v_pedido);
  perform public.entregar_pedido(v_pedido);
  return v_pedido;
end $$;

create function pg_temp.solicitar(p_mozo uuid, p_pedido bigint) returns bigint
language plpgsql set search_path = pg_catalog as $$
declare v_id bigint;
begin
  perform pg_temp.as_user(p_mozo);
  select solicitud_id into strict v_id from public.rpc_solicitar_cuenta_pedido(p_pedido);
  return v_id;
end $$;

do $e10_t07$
declare
  v_mozo uuid := '00000000-0000-0000-0000-0000000e1701';
  v_caja uuid := '00000000-0000-0000-0000-0000000e1702';
  v_admin uuid := '00000000-0000-0000-0000-0000000e1703';
  v_coc uuid := '00000000-0000-0000-0000-0000000e1704';
  v_mozo_o uuid := '00000000-0000-0000-0000-0000000e1705';
  v_local uuid := '00000000-0000-0000-0000-0000000e1710';
  v_local_o uuid := '00000000-0000-0000-0000-0000000e1711';
  v_cat uuid := '00000000-0000-0000-0000-0000000e1712';
  v_chi uuid := '00000000-0000-0000-0000-0000000e1713';
  v_pan uuid := '00000000-0000-0000-0000-0000000e1714';
  v_caja_id uuid := '00000000-0000-0000-0000-0000000e1715';
  v_sesion uuid := '00000000-0000-0000-0000-0000000e1716';
  v_m uuid[] := array(select ('00000000-0000-0000-0000-0000000e17' || (20 + g))::uuid from generate_series(1, 9) g);
  v_p bigint; v_s bigint; v_s2 bigint; v_d bigint; v_state text; r record; v_desc jsonb;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  select x, 'authenticated', 'authenticated', 'e10-t07-' || x || '@example.invalid', 't'
  from unnest(array[v_mozo, v_caja, v_admin, v_coc, v_mozo_o]) x;
  insert into public.local (id, codigo, nombre) values (v_local, 'E10-T07', 'Local T07'), (v_local_o, 'E10-T07-O', 'Otro');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo, v_local, id, 'Mozo' from public.rol where codigo = 'MOZO'
  union all select v_caja, v_local, id, 'Caja' from public.rol where codigo = 'CAJA'
  union all select v_admin, v_local, id, 'Admin' from public.rol where codigo = 'ADMINISTRADOR'
  union all select v_coc, v_local, id, 'Cocina' from public.rol where codigo = 'COCINA'
  union all select v_mozo_o, v_local_o, id, 'Mozo otro' from public.rol where codigo = 'MOZO';
  insert into public.mesa (id, local_id, codigo, nombre) select v_m[g], v_local, 'T7-' || g, 'Mesa ' || g from generate_series(1, 9) g;
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'T7', 'Carta');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
    (v_chi, v_local, v_cat, 'CHI', 'Chicha', 8, false), (v_pan, v_local, v_cat, 'PAN', 'Pan', 5, false);
  insert into public.caja (id, local_id, codigo, nombre) values (v_caja_id, v_local, 'T7', 'Caja T7');
  insert into public.sesion_caja (id, caja_id, local_id, abierta_por, monto_inicial, idempotency_key)
  values (v_sesion, v_caja_id, v_local, v_caja, 0, '00000000-0000-0000-0000-0000000e1717');

  -- ===== TP06: vías históricas de pago aún ejecutables también cierran la solicitud
  v_p := pg_temp.entregado(v_mozo, v_m[1], v_chi, 1); v_s := pg_temp.solicitar(v_mozo, v_p);
  perform pg_temp.as_user(v_caja);
  perform public.rpc_registrar_pago_total_pedido(v_p, v_sesion, 'EFECTIVO', 0, gen_random_uuid());
  if (select estado from public.pedido where id = v_p) <> 'PAGADO' or (select estado || '/' || cerrada_por from public.solicitud_cuenta where id = v_s) <> 'ATENDIDA/' || v_caja then
    raise exception 'E10-TP06: rpc_registrar_pago_total_pedido no cerró la solicitud';
  end if;
  v_p := pg_temp.entregado(v_mozo, v_m[2], v_chi, 1); v_s := pg_temp.solicitar(v_mozo, v_p);
  perform pg_temp.as_user(v_caja);
  perform public.rpc_registrar_pago_pedido_v2(v_p, v_sesion, 8, 'YAPE', 0, gen_random_uuid());
  if (select estado from public.solicitud_cuenta where id = v_s) <> 'ATENDIDA' then raise exception 'E10-TP06: rpc_registrar_pago_pedido_v2 no cerró la solicitud'; end if;
  -- registrar_pago_pedido (H5) exige sesión desde E1: si rechaza, la solicitud permanece PENDIENTE.
  v_p := pg_temp.entregado(v_mozo, v_m[3], v_chi, 1); v_s := pg_temp.solicitar(v_mozo, v_p);
  v_state := pg_temp.sqlstate_as(v_caja, format('select public.registrar_pago_pedido(%s, ''EFECTIVO'')', v_p));
  if (select estado from public.pedido where id = v_p) = 'PAGADO' then
    if (select estado from public.solicitud_cuenta where id = v_s) <> 'ATENDIDA' then raise exception 'E10-TP06: registrar_pago_pedido pagó sin cerrar'; end if;
  elsif (select estado from public.solicitud_cuenta where id = v_s) <> 'PENDIENTE' then
    raise exception 'E10-TP06: registrar_pago_pedido rechazado (%) alteró la solicitud', v_state;
  end if;
  raise notice 'E10-TP06 registrar_pago_pedido(bigint,text) -> % (solicitud %)', v_state, (select estado from public.solicitud_cuenta where id = v_s);
  -- Cobro que falla (suma inválida / exceso) deja PENDIENTE
  v_p := pg_temp.entregado(v_mozo, v_m[7], v_chi, 1); v_s := pg_temp.solicitar(v_mozo, v_p);
  if pg_temp.sqlstate_as(v_caja, format('select public.rpc_registrar_cobro_pedido(%s, %L, ''TOTAL'', ''[{"medio":"EFECTIVO","importe":99,"propina":0}]''::jsonb, gen_random_uuid())', v_p, v_sesion)) = 'OK'
    or (select estado from public.solicitud_cuenta where id = v_s) <> 'PENDIENTE' then
    raise exception 'E10-TP06: un cobro fallido alteró la solicitud';
  end if;
  -- Descuento autorizado: el neto E1 no cambia por la solicitud y el cobro del neto la cierra
  v_p := pg_temp.entregado(v_mozo, v_m[4], v_chi, 5); v_s := pg_temp.solicitar(v_mozo, v_p);
  perform pg_temp.as_user(v_caja);
  v_desc := public.rpc_solicitar_descuento_pedido(v_p, 10, null, 'Cliente frecuente', gen_random_uuid());
  perform pg_temp.as_user(v_admin);
  perform public.rpc_decidir_descuento_pedido(v_p, 'AUTORIZAR', null, gen_random_uuid());
  perform pg_temp.as_user(v_caja);
  if (select distinct x.total_neto::text || '/' || x.saldo::text || '/' || x.solicitud_cuenta_id::text from public.obtener_pedidos_pendientes_pago_caja() x where x.pedido_id = v_p)
    <> '30.00/30.00/' || v_s then
    raise exception 'E10-TP06: neto con descuento o solicitud mal leídos';
  end if;
  perform public.rpc_registrar_cobro_pedido(v_p, v_sesion, 'TOTAL', '[{"medio":"EFECTIVO","importe":30,"propina":0}]'::jsonb, gen_random_uuid());
  if (select estado from public.solicitud_cuenta where id = v_s) <> 'ATENDIDA' then raise exception 'E10-TP06: cobro con descuento no cerró'; end if;

  -- ===== TP07: retiro del producto nuevo (E7 HZ-01) y reapertura bloqueada tras cobro parcial
  v_p := pg_temp.entregado(v_mozo, v_m[5], v_chi, 1); v_s := pg_temp.solicitar(v_mozo, v_p);
  perform pg_temp.as_user(v_mozo);
  select detalle_id into strict v_d from public.agregar_detalle_pedido(v_p, v_pan, 1, null);
  perform public.rpc_retirar_detalle_pedido(v_d);
  if (select estado from public.pedido where id = v_p) <> 'LISTO'
    or (select estado || '/' || motivo_sin_efecto from public.solicitud_cuenta where id = v_s) <> 'SIN_EFECTO/REAPERTURA'
    or exists (select 1 from public.solicitud_cuenta where pedido_id = v_p and estado = 'PENDIENTE') then
    raise exception 'E10-TP07: retiro E7 del producto nuevo inesperado';
  end if;
  perform public.entregar_pedido(v_p); v_s2 := pg_temp.solicitar(v_mozo, v_p);
  if v_s2 = v_s then raise exception 'E10-TP07: la solicitud SIN_EFECTO se reactivó'; end if;
  perform pg_temp.as_user(v_caja);
  perform public.rpc_registrar_cobro_pedido(v_p, v_sesion, 'PARCIAL', '[{"medio":"EFECTIVO","importe":3,"propina":0}]'::jsonb, gen_random_uuid());
  v_state := pg_temp.sqlstate_as(v_mozo, format('select public.agregar_detalle_pedido(%s, %L, 1, null)', v_p, v_pan));
  if v_state = 'OK' or (select estado from public.solicitud_cuenta where id = v_s2) <> 'PENDIENTE' then
    raise exception 'E10-TP07: reapertura tras cobro parcial admitida o solicitud alterada (%)', v_state;
  end if;

  -- ===== TP08: anulación de un pedido sin solicitud no crea filas
  v_p := pg_temp.entregado(v_mozo, v_m[6], v_chi, 1);
  perform pg_temp.as_user(v_admin);
  perform public.anular_pedido_supervisado(v_p, 'Sin solicitud', gen_random_uuid());
  if exists (select 1 from public.solicitud_cuenta where pedido_id = v_p) then raise exception 'E10-TP08: anulación creó filas'; end if;

  -- ===== TP09: TRUNCATE / escritura de service_role rechazados
  v_state := pg_temp.try_role(null, 'service_role', 'truncate public.solicitud_cuenta');
  if v_state <> '42501' then raise exception 'E10-TP09: TRUNCATE de service_role -> %', v_state; end if;
  v_state := pg_temp.try_role(null, 'service_role', format('delete from public.solicitud_cuenta where id = %s', v_s));
  if v_state <> '42501' then raise exception 'E10-TP09: DELETE de service_role -> %', v_state; end if;

  -- ===== TP14: matriz de lectura directa por rol (RLS)
  if pg_temp.try_role(v_caja, 'authenticated', format('select 1 from public.solicitud_cuenta where local_id = %L', v_local)) = 'rows=0'
    or pg_temp.try_role(v_mozo, 'authenticated', format('select 1 from public.solicitud_cuenta where local_id = %L', v_local)) = 'rows=0' then
    raise exception 'E10-TP14: MOZO o CAJA del local no leen';
  end if;
  if pg_temp.try_role(v_coc, 'authenticated', 'select 1 from public.solicitud_cuenta') <> 'rows=0'
    or pg_temp.try_role(v_admin, 'authenticated', 'select 1 from public.solicitud_cuenta') <> 'rows=0'
    or pg_temp.try_role(v_mozo_o, 'authenticated', 'select 1 from public.solicitud_cuenta') <> 'rows=0'
    or pg_temp.try_role(null, 'anon', 'select 1 from public.solicitud_cuenta') <> '42501' then
    raise exception 'E10-TP14: un rol ajeno lee solicitudes';
  end if;
  if pg_temp.sqlstate_as(v_admin, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p)) <> '42501' then
    raise exception 'E10-TP14: ADMINISTRADOR crea solicitudes';
  end if;
end;
$e10_t07$;

do $e10_t07_fin$ begin raise notice 'E10-T07 complementos: PASS'; end $e10_t07_fin$;

rollback;
