-- E7-T11 — Escenarios complementarios de la campaña integral (validaciones de test-plan.md §3 sin
-- cobertura explícita en las pruebas focales T02–T10):
--   TP01 matriz de roles sobre producto.requiere_cocina; TP03 cambios de catálogo durante el flujo de cocina;
--   TP04/TP05 pedidos sólo con cocina / sólo sin cocina hasta cobro E1 (PAGADO, mesa LIBRE);
--   TP07 reapertura con sólo bebida; TP09 recepción sobre PAGADO; TP25 ADMINISTRADOR y anon sin operaciones E7.
-- Fixture propia en transacción; termina con ROLLBACK.
begin;

create function pg_temp.as_user(p_user_id uuid) returns void
language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

create function pg_temp.sqlstate_of(p_sql text) returns text
language plpgsql set search_path = pg_catalog as $$
begin
  execute p_sql; return 'OK';
exception when others then return sqlstate;
end $$;

-- Ejecuta p_sql con el rol de base indicado (authenticated/anon) y los claims del usuario:
-- devuelve 'rows=N' o el SQLSTATE del rechazo.
create function pg_temp.try_as(p_user uuid, p_role text, p_sql text) returns text
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

do $e7_t11$
declare
  v_admin uuid := '00000000-0000-0000-0000-0000000e7b01';
  v_admin_o uuid := '00000000-0000-0000-0000-0000000e7b02';
  v_mozo uuid := '00000000-0000-0000-0000-0000000e7b03';
  v_coc uuid := '00000000-0000-0000-0000-0000000e7b04';
  v_caja uuid := '00000000-0000-0000-0000-0000000e7b05';
  v_local uuid := '00000000-0000-0000-0000-0000000e7b10';
  v_local_o uuid := '00000000-0000-0000-0000-0000000e7b20';
  v_mesa1 uuid := '00000000-0000-0000-0000-0000000e7b11';
  v_mesa2 uuid := '00000000-0000-0000-0000-0000000e7b12';
  v_mesa3 uuid := '00000000-0000-0000-0000-0000000e7b13';
  v_cat uuid := '00000000-0000-0000-0000-0000000e7b14';
  v_cev uuid := '00000000-0000-0000-0000-0000000e7b15';
  v_chi uuid := '00000000-0000-0000-0000-0000000e7b16';
  v_pan uuid := '00000000-0000-0000-0000-0000000e7b17';
  v_caja_id uuid := '00000000-0000-0000-0000-0000000e7b30';
  v_sesion uuid := '00000000-0000-0000-0000-0000000e7b31';
  v_p4 bigint; v_p5 bigint; v_p3 bigint; v_a bigint; v_b bigint; v_c bigint; v_d bigint;
  v_res text; v_role text; v_user uuid; v_snap jsonb; r record;
begin
  insert into auth.users (id, aud, role, email, encrypted_password) values
    (v_admin, 'authenticated', 'authenticated', 'e7t11-admin@example.invalid', 't'),
    (v_admin_o, 'authenticated', 'authenticated', 'e7t11-admin-o@example.invalid', 't'),
    (v_mozo, 'authenticated', 'authenticated', 'e7t11-mozo@example.invalid', 't'),
    (v_coc, 'authenticated', 'authenticated', 'e7t11-coc@example.invalid', 't'),
    (v_caja, 'authenticated', 'authenticated', 'e7t11-caja@example.invalid', 't');
  insert into public.local (id, codigo, nombre) values
    (v_local, 'E7-T11', 'Local T11'), (v_local_o, 'E7-T11-O', 'Local T11 otro');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_admin, v_local, id, 'Admin' from public.rol where codigo = 'ADMINISTRADOR'
  union all select v_admin_o, v_local_o, id, 'Admin otro' from public.rol where codigo = 'ADMINISTRADOR'
  union all select v_mozo, v_local, id, 'Mozo' from public.rol where codigo = 'MOZO'
  union all select v_coc, v_local, id, 'Cocina' from public.rol where codigo = 'COCINA'
  union all select v_caja, v_local, id, 'Caja' from public.rol where codigo = 'CAJA';
  insert into public.mesa (id, local_id, codigo, nombre) values
    (v_mesa1, v_local, 'T11-1', 'Mesa 1'), (v_mesa2, v_local, 'T11-2', 'Mesa 2'), (v_mesa3, v_local, 'T11-3', 'Mesa 3');
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'T11', 'Carta');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
    (v_cev, v_local, v_cat, 'CEV', 'Ceviche', 30, true),
    (v_chi, v_local, v_cat, 'CHI', 'Chicha', 8, false),
    (v_pan, v_local, v_cat, 'PAN', 'Pan', 5, false);
  insert into public.caja (id, local_id, codigo, nombre) values (v_caja_id, v_local, 'T11', 'Caja T11');
  insert into public.sesion_caja (id, caja_id, local_id, abierta_por, monto_inicial, idempotency_key)
  values (v_sesion, v_caja_id, v_local, v_caja, 0, '00000000-0000-0000-0000-0000000e7b32');

  -- ===== TP01: sólo ADMINISTRADOR del local modifica requiere_cocina =====
  foreach v_user in array array[v_mozo, v_coc, v_caja, v_admin_o] loop
    v_res := pg_temp.try_as(v_user, 'authenticated', format('update public.producto set requiere_cocina = false where id = %L', v_cev));
    if v_res not in ('rows=0', '42501') then raise exception 'E7-TP01: rol no ADMIN del local modificó requiere_cocina (%: %)', v_user, v_res; end if;
  end loop;
  v_res := pg_temp.try_as(null, 'anon', format('update public.producto set requiere_cocina = false where id = %L', v_cev));
  if v_res <> '42501' then raise exception 'E7-TP01: anon modificó requiere_cocina (%)', v_res; end if;
  v_res := pg_temp.try_as(v_mozo, 'authenticated', format(
    'insert into public.producto (local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values (%L, %L, %L, %L, 1, false)', v_local, v_cat, 'X-MOZO', 'X'));
  if v_res <> '42501' then raise exception 'E7-TP01: MOZO creó producto (%)', v_res; end if;
  if (select requiere_cocina from public.producto where id = v_cev) is distinct from true then
    raise exception 'E7-TP01: un rechazo alteró requiere_cocina';
  end if;
  v_res := pg_temp.try_as(v_admin, 'authenticated', format('update public.producto set requiere_cocina = false where id = %L', v_pan));
  if v_res <> 'rows=1' then raise exception 'E7-TP01: ADMIN del local no pudo editar requiere_cocina (%)', v_res; end if;
  v_res := pg_temp.try_as(v_admin, 'authenticated', format(
    'insert into public.producto (local_id, categoria_id, codigo, nombre, precio) values (%L, %L, %L, %L, 3)', v_local, v_cat, 'T11-DEF', 'Por defecto'));
  if v_res <> 'rows=1' or (select requiere_cocina from public.producto where local_id = v_local and codigo = 'T11-DEF') is distinct from true then
    raise exception 'E7-TP01: alta ADMIN sin indicar condición (%)', v_res;
  end if;

  -- ===== TP04: pedido sólo con cocina hasta cobro =====
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p4 from public.crear_o_recuperar_pedido_mesa(v_mesa1);
  select detalle_id into strict v_a from public.agregar_detalle_pedido(v_p4, v_cev, 1, 'sin ají');
  select detalle_id into strict v_b from public.agregar_detalle_pedido(v_p4, v_cev, 1, 'bien cocido');
  select * into strict r from public.enviar_pedido_cocina(v_p4);
  if r.detalles_enviados <> 2 or r.pedido_estado <> 'ENVIADO' then raise exception 'E7-TP04: envío %', r; end if;
  if (select count(*) from public.comanda where pedido_id = v_p4) <> 1
    or pg_catalog.jsonb_array_length((select lineas from public.comanda where pedido_id = v_p4 and numero = 1)) <> 2 then
    raise exception 'E7-TP04: comanda 1';
  end if;
  perform pg_temp.as_user(v_coc);
  perform public.actualizar_estado_detalle_cocina(v_a, 'ENVIADO', 'RECIBIDO_COCINA');
  perform public.actualizar_estado_detalle_cocina(v_a, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  perform public.actualizar_estado_detalle_cocina(v_a, 'EN_PREPARACION', 'LISTO');
  if (select estado from public.pedido where id = v_p4) = 'LISTO' then raise exception 'E7-TP04: LISTO con un detalle pendiente'; end if;
  perform public.actualizar_estado_detalle_cocina(v_b, 'ENVIADO', 'RECIBIDO_COCINA');
  perform public.actualizar_estado_detalle_cocina(v_b, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  perform public.actualizar_estado_detalle_cocina(v_b, 'EN_PREPARACION', 'LISTO');
  if (select estado from public.pedido where id = v_p4) <> 'LISTO' or (select estado from public.mesa where id = v_mesa1) <> 'PEDIDO_LISTO' then
    raise exception 'E7-TP04: agregado final no LISTO/PEDIDO_LISTO';
  end if;
  perform pg_temp.as_user(v_mozo);
  perform public.entregar_pedido(v_p4);
  perform pg_temp.as_user(v_caja);
  perform public.rpc_registrar_cobro_pedido(v_p4, v_sesion, 'TOTAL', '[{"medio":"EFECTIVO","importe":60,"propina":0}]'::jsonb, '00000000-0000-0000-0000-0000000e7b41');
  if (select estado from public.pedido where id = v_p4) <> 'PAGADO' or (select estado from public.mesa where id = v_mesa1) <> 'LIBRE' then
    raise exception 'E7-TP04: cobro no dejó PAGADO/LIBRE';
  end if;
  -- TP09: recepción completa sobre pedido PAGADO
  perform pg_temp.as_user(v_coc);
  if pg_temp.sqlstate_of(format('select public.rpc_recibir_pedido_cocina(%s)', v_p4)) <> 'PT409' then
    raise exception 'E7-TP09: recepción sobre PAGADO no devolvió PT409';
  end if;

  -- ===== TP05 + TP07: sólo sin cocina hasta cobro, con reapertura sólo de bebida =====
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p5 from public.crear_o_recuperar_pedido_mesa(v_mesa2);
  perform public.agregar_detalle_pedido(v_p5, v_chi, 2, null);
  select * into strict r from public.enviar_pedido_cocina(v_p5);
  if r.pedido_estado <> 'LISTO' or (select estado from public.mesa where id = v_mesa2) <> 'PEDIDO_LISTO'
    or exists (select 1 from public.comanda where pedido_id = v_p5) then
    raise exception 'E7-TP05: envío sólo bebidas %', r;
  end if;
  perform public.entregar_pedido(v_p5);
  -- TP07: reapertura H5 con sólo bebida -> LISTO/PEDIDO_LISTO sin comanda y nueva entrega
  select detalle_id into strict v_c from public.agregar_detalle_pedido(v_p5, v_chi, 1, 'al tiempo');
  perform public.enviar_pedido_cocina(v_p5);
  if (select estado from public.detalle_pedido where id = v_c) <> 'LISTO'
    or (select estado from public.pedido where id = v_p5) <> 'LISTO'
    or (select estado from public.mesa where id = v_mesa2) <> 'PEDIDO_LISTO'
    or exists (select 1 from public.comanda where pedido_id = v_p5) then
    raise exception 'E7-TP07: reapertura con sólo bebida';
  end if;
  perform public.entregar_pedido(v_p5);
  perform pg_temp.as_user(v_caja);
  perform public.rpc_registrar_cobro_pedido(v_p5, v_sesion, 'TOTAL', '[{"medio":"YAPE","importe":24,"propina":0}]'::jsonb, '00000000-0000-0000-0000-0000000e7b42');
  if (select estado from public.pedido where id = v_p5) <> 'PAGADO' or (select estado from public.mesa where id = v_mesa2) <> 'LIBRE' then
    raise exception 'E7-TP05: cobro no dejó PAGADO/LIBRE';
  end if;

  -- ===== TP03: cambios de catálogo durante el flujo =====
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p3 from public.crear_o_recuperar_pedido_mesa(v_mesa3);
  select detalle_id into strict v_a from public.agregar_detalle_pedido(v_p3, v_cev, 1, 'tp03');
  select detalle_id into strict v_b from public.agregar_detalle_pedido(v_p3, v_chi, 1, 'tp03');
  perform public.enviar_pedido_cocina(v_p3);
  perform pg_temp.as_user(v_coc);
  perform public.actualizar_estado_detalle_cocina(v_a, 'ENVIADO', 'RECIBIDO_COCINA');
  perform public.actualizar_estado_detalle_cocina(v_a, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  -- con cocina -> sin cocina y sin cocina -> con cocina, con detalles ya enviados
  update public.producto set requiere_cocina = false where id = v_cev;
  update public.producto set requiere_cocina = true where id = v_chi;
  v_snap := public.rpc_obtener_tablero_cocina();
  if not (v_snap -> 'detalles') @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('detalle_id', v_a))
    or (v_snap -> 'detalles') @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('detalle_id', v_b)) then
    raise exception 'E7-TP03: el tablero no respeta el snapshot tras el cambio de catálogo';
  end if;
  perform public.actualizar_estado_detalle_cocina(v_a, 'EN_PREPARACION', 'LISTO');
  if (select estado from public.detalle_pedido where id = v_a) <> 'LISTO' or (select estado from public.detalle_pedido where id = v_b) <> 'LISTO' then
    raise exception 'E7-TP03: el detalle con cocina no terminó su flujo tras el cambio de catálogo';
  end if;
  -- nuevos agregados usan la condición nueva: chicha ahora va a cocina, ceviche ya no
  perform pg_temp.as_user(v_mozo);
  select detalle_id into strict v_c from public.agregar_detalle_pedido(v_p3, v_chi, 1, 'nueva');
  select detalle_id into strict v_d from public.agregar_detalle_pedido(v_p3, v_cev, 1, 'nuevo');
  perform public.enviar_pedido_cocina(v_p3);
  if (select requiere_cocina from public.detalle_pedido where id = v_c) is distinct from true
    or (select estado from public.detalle_pedido where id = v_c) <> 'ENVIADO'
    or (select requiere_cocina from public.detalle_pedido where id = v_d) is distinct from false
    or (select estado from public.detalle_pedido where id = v_d) <> 'LISTO'
    or ((select lineas from public.comanda where pedido_id = v_p3 and numero = 2) -> 0 ->> 'detalle_id')::bigint <> v_c
    or pg_catalog.jsonb_array_length((select lineas from public.comanda where pedido_id = v_p3 and numero = 2)) <> 1 then
    raise exception 'E7-TP03: nuevos agregados no usan la condición vigente';
  end if;

  -- ===== TP25: ADMINISTRADOR no opera el flujo E7; anon sin EXECUTE =====
  perform pg_temp.as_user(v_admin);
  foreach v_res in array array[
    format('select public.rpc_recibir_pedido_cocina(%s)', v_p3),
    format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_c, 'admin'),
    format('select public.rpc_registrar_impresion_comanda(%s, false)', (select id from public.comanda where pedido_id = v_p3 and numero = 2)),
    'select public.rpc_obtener_tablero_cocina()'
  ] loop
    if pg_temp.sqlstate_of(v_res) <> '42501' then raise exception 'E7-TP25: ADMINISTRADOR ejecutó %', v_res; end if;
  end loop;
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p3 from public.crear_o_recuperar_pedido_mesa(v_mesa1);
  select detalle_id into strict v_a from public.agregar_detalle_pedido(v_p3, v_chi, 1, null);
  perform pg_temp.as_user(v_admin);
  if pg_temp.sqlstate_of(format('select public.rpc_modificar_detalle_pedido(%s, 2, null, 1, null)', v_a)) <> '42501'
    or pg_temp.sqlstate_of(format('select public.rpc_retirar_detalle_pedido(%s)', v_a)) <> '42501' then
    raise exception 'E7-TP25: ADMINISTRADOR editó o retiró un borrador';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p where p.pronamespace = 'public'::regnamespace
             and p.proname in ('rpc_obtener_tablero_cocina', 'rpc_recibir_pedido_cocina', 'rpc_cancelar_detalle_pedido',
                               'rpc_obtener_cancelaciones_pedido', 'rpc_modificar_detalle_pedido', 'rpc_retirar_detalle_pedido',
                               'rpc_registrar_impresion_comanda')
             and pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')) then
    raise exception 'E7-TP25: anon con EXECUTE sobre RPC E7';
  end if;

  raise notice 'E7-T11 complementos OK: TP01, TP03, TP04, TP05, TP07, TP09 (PAGADO), TP25 (ADMINISTRADOR/anon)';
end;
$e7_t11$;

rollback;
