-- E9-T06 — Recorrido técnico integrado (TP23) con las RPC reales de cada rol, sin dispositivos físicos:
-- local cerrado → apertura → caja → pedido → cocina → entrega → solicitud de cuenta → cobro parcial →
-- cierre de caja con pedido pendiente (E1 DF-01) → cierre de jornada rechazado → nueva sesión de caja en la
-- misma jornada → cobro total → cierre de caja → cierre de jornada → segunda jornada de la misma fecha →
-- jornada que cruza la medianoche (fixture). Fixture propia; termina con ROLLBACK.
begin;

create function pg_temp.as_user(p_user_id uuid) returns void
language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

create function pg_temp.try_as(p_user uuid, p_sql text) returns text
language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_temp.as_user(p_user);
  begin
    execute 'set local role authenticated';
    execute p_sql;
    execute 'reset role';
    return 'OK';
  exception when others then
    execute 'reset role';
    return sqlstate || ':' || sqlerrm;
  end;
end $$;

do $e9_t06$
declare
  v_admin uuid := '00000000-0000-0000-0000-0000000e9601';
  v_mozo uuid := '00000000-0000-0000-0000-0000000e9602';
  v_coc uuid := '00000000-0000-0000-0000-0000000e9603';
  v_caja uuid := '00000000-0000-0000-0000-0000000e9604';
  v_caja2 uuid := '00000000-0000-0000-0000-0000000e9605';
  v_local uuid := '00000000-0000-0000-0000-0000000e9611';
  v_caja_id uuid := '00000000-0000-0000-0000-0000000e9612';
  v_cat uuid := '00000000-0000-0000-0000-0000000e9613';
  v_cev uuid := '00000000-0000-0000-0000-0000000e9614';
  v_chi uuid := '00000000-0000-0000-0000-0000000e9615';
  v_m1 uuid := '00000000-0000-0000-0000-0000000e9621';
  v_m2 uuid := '00000000-0000-0000-0000-0000000e9622';
  v_hoy date := (clock_timestamp() at time zone 'America/Lima')::date;
  v_j1 bigint; v_j2 bigint; v_jm bigint; v_p bigint; v_p2 bigint; v_s1 jsonb; v_s2 jsonb; v_res text; r record; v_det bigint;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  select u, 'authenticated', 'authenticated', 'e9-t06-' || u || '@example.invalid', 't'
  from unnest(array[v_admin, v_mozo, v_coc, v_caja, v_caja2]) u;
  insert into public.local (id, codigo, nombre) values (v_local, 'E9-T06', 'Local T06');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_admin, v_local, id, 'Admin' from public.rol where codigo = 'ADMINISTRADOR'
  union all select v_mozo, v_local, id, 'Mozo' from public.rol where codigo = 'MOZO'
  union all select v_coc, v_local, id, 'Cocina' from public.rol where codigo = 'COCINA'
  union all select v_caja, v_local, id, 'Caja 1' from public.rol where codigo = 'CAJA'
  union all select v_caja2, v_local, id, 'Caja 2' from public.rol where codigo = 'CAJA';
  insert into public.mesa (id, local_id, codigo, nombre) values (v_m1, v_local, 'T6-1', 'Mesa 1'), (v_m2, v_local, 'T6-2', 'Mesa 2');
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'T6', 'Carta');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
    (v_cev, v_local, v_cat, 'CEV', 'Ceviche', 30, true), (v_chi, v_local, v_cat, 'CHI', 'Chicha', 8, false);
  insert into public.caja (id, local_id, codigo, nombre) values (v_caja_id, v_local, 'T6', 'Caja T6');

  -- 1. Local cerrado: los tres roles leen "cerrado" y no pueden operar
  perform pg_temp.as_user(v_mozo);
  if exists (select 1 from public.rpc_obtener_jornada_operativa_actual()) then raise exception 'TP23-1: local no cerrado'; end if;
  v_res := pg_temp.try_as(v_mozo, format('select * from public.crear_o_recuperar_pedido_mesa(%L)', v_m1));
  if v_res <> 'PT409:Local cerrado — el sistema no se encuentra aperturado' then raise exception 'TP23-1: crear pedido %', v_res; end if;
  v_res := pg_temp.try_as(v_caja, format('select public.rpc_abrir_sesion_caja(%L, 50, gen_random_uuid())', v_caja_id));
  if v_res <> 'PT409:Local cerrado — el sistema no se encuentra aperturado' then raise exception 'TP23-1: abrir caja %', v_res; end if;

  -- 2. Apertura
  perform pg_temp.as_user(v_admin);
  select jornada_operativa_id into strict v_j1 from public.rpc_abrir_jornada_operativa(gen_random_uuid());
  -- 3. Caja
  perform pg_temp.as_user(v_caja);
  v_s1 := public.rpc_abrir_sesion_caja(v_caja_id, 50, gen_random_uuid());
  -- 4. Pedido (con y sin cocina) → 5. cocina → 6. entrega → 7. solicitud de cuenta
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p from public.crear_o_recuperar_pedido_mesa(v_m1);
  perform public.agregar_detalle_pedido(v_p, v_cev, 1, 'sin ají');
  perform public.agregar_detalle_pedido(v_p, v_chi, 2, null);
  perform public.enviar_pedido_cocina(v_p);
  perform pg_temp.as_user(v_coc);
  perform public.rpc_recibir_pedido_cocina(v_p);
  select id into strict v_det from public.detalle_pedido where pedido_id = v_p and producto_id = v_cev;
  perform public.actualizar_estado_detalle_cocina(v_det, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  perform public.actualizar_estado_detalle_cocina(v_det, 'EN_PREPARACION', 'LISTO');
  perform pg_temp.as_user(v_mozo);
  perform public.entregar_pedido(v_p);
  perform public.rpc_solicitar_cuenta_pedido(v_p);
  -- 8. Cobro parcial
  perform pg_temp.as_user(v_caja);
  perform public.rpc_registrar_cobro_pedido(v_p, (v_s1->>'id')::uuid, 'PARCIAL', '[{"medio":"YAPE","importe":20,"propina":0}]'::jsonb, gen_random_uuid());
  -- 9. Cierre de caja con el pedido pendiente (E1 DF-01)
  perform public.fn_cerrar_sesion_caja((v_s1->>'id')::uuid, 50, null, gen_random_uuid(), false);
  -- 10. Intento de cierre de jornada: rechazado por el pedido pendiente
  v_res := pg_temp.try_as(v_admin, format('select * from public.rpc_cerrar_jornada_operativa(%s)', v_j1));
  if v_res <> 'PT409:No se puede cerrar la jornada: 1 pedidos pendientes y 0 sesiones de caja abiertas' then
    raise exception 'TP23-10: %', v_res;
  end if;
  -- 11. Nueva sesión de caja en la misma jornada (otro cajero) → 12. cobro total → 13. cierre de caja
  perform pg_temp.as_user(v_caja2);
  v_s2 := public.rpc_abrir_sesion_caja(v_caja_id, 0, gen_random_uuid());
  if (v_s2->>'jornada_operativa_id')::bigint <> v_j1 or v_s2->>'id' = v_s1->>'id' then
    raise exception 'TP23-11: la nueva sesión no pertenece a la misma jornada';
  end if;
  select * into strict r from public.rpc_registrar_cobro_pedido(v_p, (v_s2->>'id')::uuid, 'TOTAL',
    '[{"medio":"EFECTIVO","importe":26,"propina":2}]'::jsonb, gen_random_uuid());
  if r.pedido_estado <> 'PAGADO' or r.mesa_estado <> 'LIBRE' then raise exception 'TP23-12: cobro total %', r; end if;
  perform public.fn_cerrar_sesion_caja((v_s2->>'id')::uuid, 28, null, gen_random_uuid(), false);
  -- 14. Cierre de jornada
  perform pg_temp.as_user(v_admin);
  select * into strict r from public.rpc_cerrar_jornada_operativa(v_j1);
  if r.estado <> 'CERRADA' or r.ya_estaba_cerrada then raise exception 'TP23-14: cierre %', r; end if;
  v_res := pg_temp.try_as(v_mozo, format('select * from public.crear_o_recuperar_pedido_mesa(%L)', v_m2));
  if v_res not like 'PT409:Local cerrado%' then raise exception 'TP23-14: operación tras el cierre %', v_res; end if;

  -- Coherencia del recorrido: todo deriva de la jornada 1
  if (select jornada_operativa_id from public.pedido where id = v_p) <> v_j1
    or exists (select 1 from public.sesion_caja where id in ((v_s1->>'id')::uuid, (v_s2->>'id')::uuid) and jornada_operativa_id <> v_j1)
    or (select count(*) from public.cobro c join public.sesion_caja s on s.id = c.sesion_caja_id where c.pedido_id = v_p and s.jornada_operativa_id = v_j1) <> 2
    or (select string_agg(estado, ',') from public.solicitud_cuenta where pedido_id = v_p) <> 'ATENDIDA'
    or (select count(*) from public.historial_detalle_pedido h where h.pedido_id = v_p) = 0 then
    raise exception 'TP23: el recorrido no deriva de forma coherente de la jornada';
  end if;

  -- 15. Segunda jornada de la misma fecha
  perform pg_temp.as_user(v_admin);
  select * into strict r from public.rpc_abrir_jornada_operativa(gen_random_uuid());
  v_j2 := r.jornada_operativa_id;
  if r.numero <> 2 or r.identificacion <> 'Jornada ' || to_char(v_hoy, 'YYYY-MM-DD') || ' (2)' then raise exception 'TP23-15: %', r; end if;
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p2 from public.crear_o_recuperar_pedido_mesa(v_m2);
  if (select jornada_operativa_id from public.pedido where id = v_p2) <> v_j2 then raise exception 'TP23-15: pedido en otra jornada'; end if;
  perform public.liberar_mesa_pedido_vacio(v_p2);
  perform pg_temp.as_user(v_admin);
  perform public.rpc_cerrar_jornada_operativa(v_j2);

  -- 16. Cruce de medianoche (fixture: abierta ayer 21:00 Lima)
  perform pg_temp.as_user(null);
  insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
  values (v_local, v_hoy - 1, 1, v_admin, ((v_hoy - 1) + time '21:00') at time zone 'America/Lima', gen_random_uuid())
  returning id into v_jm;
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p2 from public.crear_o_recuperar_pedido_mesa(v_m2);
  select * into strict r from public.rpc_obtener_jornada_operativa_actual();
  if (select jornada_operativa_id from public.pedido where id = v_p2) <> v_jm
    or r.identificacion <> 'Jornada ' || to_char(v_hoy - 1, 'YYYY-MM-DD') || ' (1)' then
    raise exception 'TP23-16: cruce de medianoche %', r;
  end if;
  perform public.liberar_mesa_pedido_vacio(v_p2);
  perform pg_temp.as_user(v_admin);
  select * into strict r from public.rpc_cerrar_jornada_operativa(v_jm);
  if r.estado <> 'CERRADA' or r.cerrada_en <= r.abierta_en then raise exception 'TP23-16: cierre %', r; end if;

  raise notice 'E9-T06 recorrido integrado: PASS';
end;
$e9_t06$;

rollback;
