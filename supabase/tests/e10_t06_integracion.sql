-- E10-T06 — Recorrido integrado (dos mozos, dos cajas, cocina, administrador y otro local) con las RPC
-- reales: solicitud, repetición, cobro parcial y total, reapertura, anulación, cobro sin solicitud;
-- visibilidad Realtime emulada (RLS evaluada como cada suscriptor) incluida la confirmación de HZ-02;
-- y derivación de los intervalos de E8 sin reglas adicionales (TP15/TP19 en SQL). Termina con ROLLBACK.
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

-- Emulación de la autorización de Supabase Realtime (postgres_changes): el evento se entrega a un
-- suscriptor sólo si, con su rol y claims, puede leer la fila nueva según la RLS.
create function pg_temp.visible_as(p_user uuid, p_role text, p_table text, p_key text, p_value text) returns boolean
language plpgsql set search_path = pg_catalog as $$
declare v_visible boolean;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', p_role, true);
  execute format('set local role %I', p_role);
  begin
    execute format('select exists (select 1 from public.%I where %I::text = %L)', p_table, p_key, p_value) into v_visible;
  exception when insufficient_privilege then
    v_visible := false;
  end;
  execute 'reset role';
  return v_visible;
end $$;

do $e10_t06$
declare
  v_mozo1 uuid := '00000000-0000-0000-0000-0000000e1601';
  v_mozo2 uuid := '00000000-0000-0000-0000-0000000e1602';
  v_caja1 uuid := '00000000-0000-0000-0000-0000000e1603';
  v_caja2 uuid := '00000000-0000-0000-0000-0000000e1604';
  v_coc uuid := '00000000-0000-0000-0000-0000000e1605';
  v_admin uuid := '00000000-0000-0000-0000-0000000e1606';
  v_mozo_o uuid := '00000000-0000-0000-0000-0000000e1607';
  v_caja_o uuid := '00000000-0000-0000-0000-0000000e1608';
  v_local uuid := '00000000-0000-0000-0000-0000000e1610';
  v_local_o uuid := '00000000-0000-0000-0000-0000000e1611';
  v_cat uuid := '00000000-0000-0000-0000-0000000e1612';
  v_cev uuid := '00000000-0000-0000-0000-0000000e1613';
  v_chi uuid := '00000000-0000-0000-0000-0000000e1614';
  v_pan uuid := '00000000-0000-0000-0000-0000000e1615';
  v_caja_id uuid := '00000000-0000-0000-0000-0000000e1616';
  v_sesion uuid := '00000000-0000-0000-0000-0000000e1617';
  v_m uuid[] := array(select ('00000000-0000-0000-0000-0000000e16' || (20 + g))::uuid from generate_series(1, 4) g);
  v_p1 bigint; v_p2 bigint; v_p3 bigint; v_p4 bigint; v_ids bigint[];
  r record; r2 record; v_sol1 bigint; v_sol2a bigint; v_sol2b bigint; v_sol3 bigint; u uuid; v_state text;
  v_entregado timestamptz; v_cliente interval; v_caja_t interval; v_total interval;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  select x, 'authenticated', 'authenticated', 'e10-t06-' || x || '@example.invalid', 't'
  from unnest(array[v_mozo1, v_mozo2, v_caja1, v_caja2, v_coc, v_admin, v_mozo_o, v_caja_o]) x;
  insert into public.local (id, codigo, nombre) values (v_local, 'E10-T06', 'Local T06'), (v_local_o, 'E10-T06-O', 'Otro');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo1, v_local, id, 'Mozo Uno' from public.rol where codigo = 'MOZO'
  union all select v_mozo2, v_local, id, 'Mozo Dos' from public.rol where codigo = 'MOZO'
  union all select v_caja1, v_local, id, 'Caja Uno' from public.rol where codigo = 'CAJA'
  union all select v_caja2, v_local, id, 'Caja Dos' from public.rol where codigo = 'CAJA'
  union all select v_coc, v_local, id, 'Cocina' from public.rol where codigo = 'COCINA'
  union all select v_admin, v_local, id, 'Admin' from public.rol where codigo = 'ADMINISTRADOR'
  union all select v_mozo_o, v_local_o, id, 'Mozo otro' from public.rol where codigo = 'MOZO'
  union all select v_caja_o, v_local_o, id, 'Caja otro' from public.rol where codigo = 'CAJA';
  insert into public.mesa (id, local_id, codigo, nombre) select v_m[g], v_local, 'T6-' || g, 'Mesa ' || g from generate_series(1, 4) g;
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'T6', 'Carta');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
    (v_cev, v_local, v_cat, 'CEV', 'Ceviche', 30, true), (v_chi, v_local, v_cat, 'CHI', 'Chicha', 8, false),
    (v_pan, v_local, v_cat, 'PAN', 'Pan', 5, false);
  insert into public.caja (id, local_id, codigo, nombre) values (v_caja_id, v_local, 'T6', 'Caja T6');
  insert into public.sesion_caja (id, caja_id, local_id, abierta_por, monto_inicial, idempotency_key)
  values (v_sesion, v_caja_id, v_local, v_caja1, 0, '00000000-0000-0000-0000-0000000e1618');

  -- ===== Flujo 1: pedido mixto con cocina -> entrega -> solicitud (mozo 1) -> repetición (mozo 2)
  --       -> cobro parcial (solicitud sigue PENDIENTE) -> cobro total (ATENDIDA) -> segunda caja rechazada
  perform pg_temp.as_user(v_mozo1);
  select pedido_id into strict v_p1 from public.crear_o_recuperar_pedido_mesa(v_m[1]);
  perform public.agregar_detalle_pedido(v_p1, v_cev, 1, null);
  perform public.agregar_detalle_pedido(v_p1, v_chi, 2, null);
  perform public.enviar_pedido_cocina(v_p1);
  perform pg_temp.as_user(v_coc);
  perform public.rpc_recibir_pedido_cocina(v_p1);
  select array_agg(id) into v_ids from public.detalle_pedido where pedido_id = v_p1 and requiere_cocina;
  perform public.actualizar_estado_detalle_cocina(v_ids[1], 'RECIBIDO_COCINA', 'EN_PREPARACION');
  perform public.actualizar_estado_detalle_cocina(v_ids[1], 'EN_PREPARACION', 'LISTO');
  perform pg_temp.as_user(v_mozo2);
  if pg_temp.sqlstate_as(v_mozo2, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p1)) <> 'PT409' then
    raise exception 'E10-T06: solicitud admitida antes de la entrega';
  end if;
  perform pg_temp.as_user(v_mozo1);
  perform public.entregar_pedido(v_p1);
  select * into strict r from public.rpc_solicitar_cuenta_pedido(v_p1);
  v_sol1 := r.solicitud_id;
  perform pg_temp.as_user(v_mozo2);
  select * into strict r2 from public.rpc_solicitar_cuenta_pedido(v_p1);
  if r.ya_existia or not r2.ya_existia or r2.solicitud_id <> v_sol1 or r2.solicitada_por <> v_mozo1 then
    raise exception 'E10-T06: repetición del segundo mozo inesperada % / %', r, r2;
  end if;
  perform pg_temp.as_user(v_caja2);
  if (select count(distinct x.pedido_id) from public.obtener_pedidos_pendientes_pago_caja() x
      where x.pedido_id = v_p1 and x.solicitud_cuenta_id = v_sol1 and x.cuenta_solicitada_por_nombre = 'Mozo Uno') <> 1 then
    raise exception 'E10-T06: la segunda caja no ve la solicitud';
  end if;
  perform pg_temp.as_user(v_caja1);
  perform public.rpc_registrar_cobro_pedido(v_p1, v_sesion, 'PARCIAL', '[{"medio":"YAPE","importe":20,"propina":0}]'::jsonb, gen_random_uuid());
  if (select estado from public.solicitud_cuenta where id = v_sol1) <> 'PENDIENTE' then raise exception 'E10-T06: el cobro parcial cerró la solicitud'; end if;
  if (select count(distinct x.pedido_id) from public.obtener_pedidos_pendientes_pago_caja() x where x.pedido_id = v_p1 and x.solicitud_cuenta_id = v_sol1 and x.saldo = 26) <> 1 then
    raise exception 'E10-T06: tras el parcial la solicitud o el saldo no se leen';
  end if;
  select * into strict r from public.rpc_registrar_cobro_pedido(v_p1, v_sesion, 'TOTAL', '[{"medio":"EFECTIVO","importe":16,"propina":2},{"medio":"PLIN","importe":10,"propina":0}]'::jsonb, gen_random_uuid());
  if r.pedido_estado <> 'PAGADO' or r.mesa_estado <> 'LIBRE' then raise exception 'E10-T06: cobro total %', r; end if;
  select * into strict r from public.solicitud_cuenta where id = v_sol1;
  if r.estado <> 'ATENDIDA' or r.cerrada_por <> v_caja1 or r.cerrada_en < r.solicitada_en then raise exception 'E10-T06: cierre ATENDIDA %', r; end if;
  v_state := pg_temp.sqlstate_as(v_caja2, format('select public.rpc_registrar_cobro_pedido(%s, %L, ''TOTAL'', ''[{"medio":"EFECTIVO","importe":1,"propina":0}]''::jsonb, gen_random_uuid())', v_p1, v_sesion));
  if v_state <> 'PT409' then raise exception 'E10-T06: segunda caja no rechazada con el conflicto E1 (%)', v_state; end if;
  if pg_temp.sqlstate_as(v_mozo1, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p1)) <> 'PT409' then
    raise exception 'E10-T06: solicitud sobre PAGADO admitida';
  end if;

  -- ===== Flujo 2: solicitud -> reapertura (SIN_EFECTO/REAPERTURA) -> nueva entrega -> nueva solicitud -> cobro total
  perform pg_temp.as_user(v_mozo1);
  select pedido_id into strict v_p2 from public.crear_o_recuperar_pedido_mesa(v_m[2]);
  perform public.agregar_detalle_pedido(v_p2, v_chi, 1, null);
  perform public.enviar_pedido_cocina(v_p2); perform public.entregar_pedido(v_p2);
  select solicitud_id into strict v_sol2a from public.rpc_solicitar_cuenta_pedido(v_p2);
  perform pg_temp.as_user(v_mozo2);
  perform public.agregar_detalle_pedido(v_p2, v_pan, 1, null);
  select * into strict r from public.solicitud_cuenta where id = v_sol2a;
  if r.estado <> 'SIN_EFECTO' or r.motivo_sin_efecto <> 'REAPERTURA' or r.cerrada_por <> v_mozo2 then raise exception 'E10-T06: reapertura %', r; end if;
  -- HZ-02 (confirmación): la fila nueva del pedido reabierto no es visible para CAJA (no hay evento Realtime
  -- de pedido para Caja), pero la solicitud SIN_EFECTO sí lo es (Caja recibe la señal de E10).
  if pg_temp.visible_as(v_caja1, 'authenticated', 'pedido', 'id', v_p2::text) then
    raise exception 'E10-T06/HZ-02: CAJA ve el pedido reabierto; revisar la hipótesis HZ-02';
  end if;
  if not pg_temp.visible_as(v_caja1, 'authenticated', 'solicitud_cuenta', 'id', v_sol2a::text) then
    raise exception 'E10-T06/HZ-02: CAJA no ve la solicitud SIN_EFECTO (sin mitigación)';
  end if;
  if exists (select 1 from public.mesa m where m.id = v_m[2]) and pg_temp.visible_as(v_caja1, 'authenticated', 'mesa', 'id', v_m[2]::text) then
    raise exception 'E10-T06/HZ-02: CAJA ve la mesa; revisar la hipótesis HZ-02';
  end if;
  perform pg_temp.as_user(v_mozo2);
  perform public.enviar_pedido_cocina(v_p2); perform public.entregar_pedido(v_p2);
  select solicitud_id into strict v_sol2b from public.rpc_solicitar_cuenta_pedido(v_p2);
  if v_sol2b = v_sol2a then raise exception 'E10-T06: no se creó una nueva solicitud tras la reentrega'; end if;
  perform pg_temp.as_user(v_caja2);
  perform public.rpc_registrar_cobro_pedido(v_p2, v_sesion, 'TOTAL', '[{"medio":"TARJETA","importe":13,"propina":0}]'::jsonb, gen_random_uuid());
  if (select string_agg(estado || coalesce('/' || motivo_sin_efecto, ''), ',' order by id) from public.solicitud_cuenta where pedido_id = v_p2)
    <> 'SIN_EFECTO/REAPERTURA,ATENDIDA' then
    raise exception 'E10-T06: historia de solicitudes del pedido reabierto inesperada';
  end if;

  -- ===== Flujo 3: solicitud -> anulación ADMIN (SIN_EFECTO/ANULACION)
  perform pg_temp.as_user(v_mozo1);
  select pedido_id into strict v_p3 from public.crear_o_recuperar_pedido_mesa(v_m[3]);
  perform public.agregar_detalle_pedido(v_p3, v_chi, 1, null);
  perform public.enviar_pedido_cocina(v_p3); perform public.entregar_pedido(v_p3);
  select solicitud_id into strict v_sol3 from public.rpc_solicitar_cuenta_pedido(v_p3);
  perform pg_temp.as_user(v_admin);
  perform public.anular_pedido_supervisado(v_p3, 'Recorrido E10', gen_random_uuid());
  select * into strict r from public.solicitud_cuenta where id = v_sol3;
  if r.estado <> 'SIN_EFECTO' or r.motivo_sin_efecto <> 'ANULACION' or r.cerrada_por <> v_admin then raise exception 'E10-T06: anulación %', r; end if;

  -- ===== Flujo 4: cobro directo sin solicitud (DH-01 A) -> sin filas, identificable como "sin solicitud registrada"
  perform pg_temp.as_user(v_mozo2);
  select pedido_id into strict v_p4 from public.crear_o_recuperar_pedido_mesa(v_m[4]);
  perform public.agregar_detalle_pedido(v_p4, v_chi, 1, null);
  perform public.enviar_pedido_cocina(v_p4); perform public.entregar_pedido(v_p4);
  perform pg_temp.as_user(v_caja1);
  perform public.rpc_registrar_cobro_pedido(v_p4, v_sesion, 'TOTAL', '[{"medio":"EFECTIVO","importe":8,"propina":0}]'::jsonb, gen_random_uuid());
  if (select estado from public.pedido where id = v_p4) <> 'PAGADO'
    or exists (select 1 from public.solicitud_cuenta where pedido_id = v_p4) then
    raise exception 'E10-T06: cobro sin solicitud alterado';
  end if;

  -- ===== TP15 (emulación de autorización Realtime): quién recibe los eventos de solicitud_cuenta
  foreach u in array array[v_mozo1, v_mozo2, v_caja1, v_caja2] loop
    if not pg_temp.visible_as(u, 'authenticated', 'solicitud_cuenta', 'id', v_sol1::text) then
      raise exception 'E10-TP15: % no recibiría el evento de solicitud', u;
    end if;
  end loop;
  foreach u in array array[v_coc, v_admin, v_mozo_o, v_caja_o] loop
    if pg_temp.visible_as(u, 'authenticated', 'solicitud_cuenta', 'id', v_sol1::text) then
      raise exception 'E10-TP15: % recibiría el evento de solicitud', u;
    end if;
  end loop;
  if pg_temp.visible_as(null, 'anon', 'solicitud_cuenta', 'id', v_sol1::text) then raise exception 'E10-TP15: anon recibiría eventos'; end if;
  -- El cierre por cobro también llega a Caja por pedido PAGADO (política vigente H5).
  if not pg_temp.visible_as(v_caja2, 'authenticated', 'pedido', 'id', v_p1::text) then raise exception 'E10-TP15: CAJA no ve pedido PAGADO'; end if;

  -- ===== TP19: derivación de intervalos de E8 (design E10-D15) sin reglas adicionales
  for r in
    select p.id, p.creado_en, s.solicitada_en, s.cerrada_en,
      (select max(h.creado_en) from public.historial_estado h where h.pedido_id = p.id and h.estado_nuevo = 'ENTREGADO' and h.creado_en <= s.solicitada_en) as entregado_en,
      (select h.creado_en from public.historial_estado h where h.pedido_id = p.id and h.estado_anterior = 'ENTREGADO' and h.estado_nuevo = 'PAGADO') as pagado_en
    from public.pedido p join public.solicitud_cuenta s on s.pedido_id = p.id and s.estado = 'ATENDIDA'
    where p.id in (v_p1, v_p2)
  loop
    if r.entregado_en is null or r.pagado_en is null then raise exception 'E10-TP19: faltan eventos del pedido %', r.id; end if;
    v_cliente := r.solicitada_en - r.entregado_en;
    v_caja_t := r.cerrada_en - r.solicitada_en;
    v_total := r.pagado_en - r.creado_en;
    if v_cliente < interval '0' or v_caja_t < interval '0' or v_total < interval '0' then
      raise exception 'E10-TP19: intervalos negativos en % (cliente %, caja %, total %)', r.id, v_cliente, v_caja_t, v_total;
    end if;
  end loop;
  if (select count(*) from public.solicitud_cuenta where pedido_id = v_p1 and estado = 'ATENDIDA') <> 1
    or (select count(*) from public.solicitud_cuenta where pedido_id = v_p2 and estado = 'ATENDIDA') <> 1 then
    raise exception 'E10-TP19: debe existir exactamente una ATENDIDA por pedido pagado con solicitud';
  end if;
  if (select count(*) from public.pedido p where p.id in (v_p1, v_p2, v_p4) and p.estado = 'PAGADO'
      and not exists (select 1 from public.solicitud_cuenta s where s.pedido_id = p.id and s.estado = 'ATENDIDA')) <> 1 then
    raise exception 'E10-TP19: el pedido pagado sin solicitud no es identificable';
  end if;
  -- Ningún objeto financiero cambió de semántica: el cobro final de p1 es el único con saldo 0.
  if (select count(*) from public.cobro where pedido_id = v_p1 and saldo_posterior = 0) <> 1 then
    raise exception 'E10-TP19: cobro final no unívoco';
  end if;
end;
$e10_t06$;

do $e10_t06_fin$ begin raise notice 'E10-T06 recorrido integrado: PASS'; end $e10_t06_fin$;

rollback;
