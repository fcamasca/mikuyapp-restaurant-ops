-- E10-T03 — Verificación focal: solicitud válida (TP02), rechazos (TP03), idempotencia (TP04),
-- lectura extendida de Caja (TP12) y catálogo de seguridad de la RPC (parte SQL de TP14).
-- Fixture propia en transacción; termina con ROLLBACK.
begin;

create function pg_temp.as_user(p_user_id uuid) returns void
language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

-- Ejecuta p_sql como authenticated con los claims del usuario; devuelve 'OK' o el SQLSTATE.
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
    return sqlstate;
  end;
end $$;

-- Pedido entregado con una bebida sin cocina (E7): ABIERTO -> LISTO al enviar -> ENTREGADO.
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

do $e10_t03$
declare
  v_mozo uuid := '00000000-0000-0000-0000-0000000e1301';
  v_mozo2 uuid := '00000000-0000-0000-0000-0000000e1302';
  v_mozo_o uuid := '00000000-0000-0000-0000-0000000e1303';
  v_coc uuid := '00000000-0000-0000-0000-0000000e1304';
  v_caja uuid := '00000000-0000-0000-0000-0000000e1305';
  v_admin uuid := '00000000-0000-0000-0000-0000000e1306';
  v_caja_o uuid := '00000000-0000-0000-0000-0000000e1307';
  v_local uuid := '00000000-0000-0000-0000-0000000e1310';
  v_local_o uuid := '00000000-0000-0000-0000-0000000e1311';
  v_cat uuid := '00000000-0000-0000-0000-0000000e1312';
  v_cev uuid := '00000000-0000-0000-0000-0000000e1313';
  v_chi uuid := '00000000-0000-0000-0000-0000000e1314';
  v_pan uuid := '00000000-0000-0000-0000-0000000e1315';
  v_caja_id uuid := '00000000-0000-0000-0000-0000000e1316';
  v_sesion uuid := '00000000-0000-0000-0000-0000000e1317';
  v_m uuid[] := array(select ('00000000-0000-0000-0000-0000000e13' || lpad((20 + g)::text, 2, '0'))::uuid from generate_series(1, 10) g);
  v_p1 bigint; v_p2 bigint; v_p3 bigint; v_p4 bigint; v_p5 bigint; v_p6 bigint; v_p7 bigint; v_p8 bigint;
  r record; r2 record; v_state text; v_count bigint; v_before text; v_after text; v_result text;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  select u, 'authenticated', 'authenticated', 'e10-t03-' || u || '@example.invalid', 't'
  from unnest(array[v_mozo, v_mozo2, v_mozo_o, v_coc, v_caja, v_admin, v_caja_o]) u;
  insert into public.local (id, codigo, nombre) values (v_local, 'E10-T03', 'Local T03'), (v_local_o, 'E10-T03-O', 'Otro');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo, v_local, id, 'Mozo Uno' from public.rol where codigo = 'MOZO'
  union all select v_mozo2, v_local, id, 'Mozo Dos' from public.rol where codigo = 'MOZO'
  union all select v_mozo_o, v_local_o, id, 'Mozo otro' from public.rol where codigo = 'MOZO'
  union all select v_coc, v_local, id, 'Cocina' from public.rol where codigo = 'COCINA'
  union all select v_caja, v_local, id, 'Caja' from public.rol where codigo = 'CAJA'
  union all select v_admin, v_local, id, 'Admin' from public.rol where codigo = 'ADMINISTRADOR'
  union all select v_caja_o, v_local_o, id, 'Caja otro' from public.rol where codigo = 'CAJA';
  -- E9 (homologación mínima): precondición global de E9 — jornada operativa ABIERTA válida para los locales del fixture.
  insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
  select l.id, (now() at time zone 'America/Lima')::date,
    1 + coalesce((select max(j.numero) from public.jornada_operativa j where j.local_id = l.id and j.fecha_operativa = (now() at time zone 'America/Lima')::date), 0),
    (select p.id from public.perfil_usuario p where p.local_id = l.id order by p.id limit 1), now(), gen_random_uuid()
  from public.local l
  where l.id in (v_local, v_local_o)
    and exists (select 1 from public.perfil_usuario p where p.local_id = l.id)
    and not exists (select 1 from public.jornada_operativa j where j.local_id = l.id and j.estado = 'ABIERTA');
  insert into public.mesa (id, local_id, codigo, nombre)
  select v_m[g], v_local, 'T3-' || g, 'Mesa ' || g from generate_series(1, 10) g;
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'T3', 'Carta');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
    (v_cev, v_local, v_cat, 'CEV', 'Ceviche', 30, true),
    (v_chi, v_local, v_cat, 'CHI', 'Chicha', 8, false),
    (v_pan, v_local, v_cat, 'PAN', 'Pan', 5, false);
  insert into public.caja (id, local_id, codigo, nombre) values (v_caja_id, v_local, 'T3', 'Caja T3');
  insert into public.sesion_caja (id, caja_id, local_id, abierta_por, monto_inicial, idempotency_key)
  values (v_sesion, v_caja_id, v_local, v_caja, 0, '00000000-0000-0000-0000-0000000e1318');

  -- ===== TP02: solicitud válida sin efectos colaterales
  v_p1 := pg_temp.entregado(v_mozo, v_m[1], v_chi, 2);
  select pg_catalog.md5(string_agg(x, '|')) into v_before from (
    select (select row(p.*)::text from public.pedido p where p.id = v_p1) x
    union all select (select row(m.*)::text from public.mesa m where m.id = v_m[1])
    union all select (select count(*)::text from public.historial_estado where pedido_id = v_p1)
    union all select (select count(*)::text from public.cobro) || '/' || (select count(*) from public.pago)
      || '/' || (select count(*) from public.descuento_pedido) || '/' || (select count(*) from public.auditoria_caja)) s;
  perform pg_temp.as_user(v_mozo);
  select * into strict r from public.rpc_solicitar_cuenta_pedido(v_p1);
  if r.ya_existia or r.pedido_id <> v_p1 or r.estado <> 'PENDIENTE' or r.solicitada_por <> v_mozo then
    raise exception 'E10-TP02: resultado inesperado %', r;
  end if;
  if not exists (select 1 from public.solicitud_cuenta s join public.pedido p on p.id = s.pedido_id
      where s.id = r.solicitud_id and s.local_id = v_local and s.local_id = p.local_id and p.mesa_id = v_m[1]
        and s.solicitada_en > (select max(creado_en) from public.historial_estado where pedido_id = v_p1 and estado_nuevo = 'ENTREGADO')
        and s.cerrada_en is null and s.cerrada_por is null and s.motivo_sin_efecto is null) then
    raise exception 'E10-TP02: fila persistida incompleta o mesa no derivable';
  end if;
  select pg_catalog.md5(string_agg(x, '|')) into v_after from (
    select (select row(p.*)::text from public.pedido p where p.id = v_p1) x
    union all select (select row(m.*)::text from public.mesa m where m.id = v_m[1])
    union all select (select count(*)::text from public.historial_estado where pedido_id = v_p1)
    union all select (select count(*)::text from public.cobro) || '/' || (select count(*) from public.pago)
      || '/' || (select count(*) from public.descuento_pedido) || '/' || (select count(*) from public.auditoria_caja)) s;
  if v_before <> v_after then raise exception 'E10-TP02: la solicitud modificó pedido, mesa, historial o datos financieros'; end if;

  -- TP02: pedido con cobro parcial previo
  v_p2 := pg_temp.entregado(v_mozo, v_m[2], v_chi, 3);
  perform pg_temp.as_user(v_caja);
  perform public.rpc_registrar_cobro_pedido(v_p2, v_sesion, 'PARCIAL', '[{"medio":"YAPE","importe":10,"propina":0}]'::jsonb,
    '00000000-0000-0000-0000-0000000e1341');
  perform pg_temp.as_user(v_mozo);
  select * into strict r from public.rpc_solicitar_cuenta_pedido(v_p2);
  if r.ya_existia or r.estado <> 'PENDIENTE' then raise exception 'E10-TP02: con cobro parcial %', r; end if;

  -- ===== TP04: idempotencia (mismo mozo, otro mozo del local)
  select * into strict r from public.rpc_solicitar_cuenta_pedido(v_p1);
  perform pg_temp.as_user(v_mozo2);
  select * into strict r2 from public.rpc_solicitar_cuenta_pedido(v_p1);
  if not r.ya_existia or not r2.ya_existia or r.solicitud_id <> r2.solicitud_id or r2.solicitada_por <> v_mozo
    or r.solicitada_en <> r2.solicitada_en
    or (select count(*) from public.solicitud_cuenta where pedido_id = v_p1) <> 1 then
    raise exception 'E10-TP04: idempotencia rota % / %', r, r2;
  end if;

  -- ===== TP03: matriz de rechazos (sin filas nuevas)
  select count(*) into v_count from public.solicitud_cuenta;
  perform pg_temp.as_user(v_mozo);
  -- ABIERTO
  select pedido_id into strict v_p3 from public.crear_o_recuperar_pedido_mesa(v_m[3]);
  perform public.agregar_detalle_pedido(v_p3, v_cev, 1, null);
  v_state := pg_temp.try_as(v_mozo, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p3));
  if v_state <> 'PT409' then raise exception 'E10-TP03: ABIERTO -> %', v_state; end if;
  -- ENVIADO / RECIBIDO_COCINA / EN_PREPARACION / LISTO
  perform pg_temp.as_user(v_mozo); perform public.enviar_pedido_cocina(v_p3);
  foreach v_result in array array['ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'] loop
    if v_result <> 'ENVIADO' then
      perform pg_temp.as_user(v_coc);
      perform public.actualizar_estado_detalle_cocina(d.id, d.estado, v_result)
      from public.detalle_pedido d where d.pedido_id = v_p3;
    end if;
    if (select estado from public.pedido where id = v_p3) <> v_result then raise exception 'E10-TP03: fixture %', v_result; end if;
    v_state := pg_temp.try_as(v_mozo, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p3));
    if v_state <> 'PT409' then raise exception 'E10-TP03: % -> %', v_result, v_state; end if;
  end loop;
  -- Reabierto (ENTREGADO + producto nuevo antes del primer pago)
  v_p4 := pg_temp.entregado(v_mozo, v_m[4], v_chi, 1);
  perform pg_temp.as_user(v_mozo); perform public.agregar_detalle_pedido(v_p4, v_pan, 1, null);
  if (select estado from public.pedido where id = v_p4) = 'ENTREGADO' then raise exception 'E10-TP03: fixture reapertura'; end if;
  v_state := pg_temp.try_as(v_mozo, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p4));
  if v_state <> 'PT409' then raise exception 'E10-TP03: reabierto -> %', v_state; end if;
  -- PAGADO
  v_p5 := pg_temp.entregado(v_mozo, v_m[5], v_chi, 1);
  perform pg_temp.as_user(v_caja);
  perform public.rpc_registrar_cobro_pedido(v_p5, v_sesion, 'TOTAL', '[{"medio":"EFECTIVO","importe":8,"propina":0}]'::jsonb,
    '00000000-0000-0000-0000-0000000e1342');
  v_state := pg_temp.try_as(v_mozo, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p5));
  if v_state <> 'PT409' then raise exception 'E10-TP03: PAGADO -> %', v_state; end if;
  -- ANULADO
  v_p6 := pg_temp.entregado(v_mozo, v_m[6], v_chi, 1);
  perform pg_temp.as_user(v_admin);
  perform public.anular_pedido_supervisado(v_p6, 'Prueba E10', '00000000-0000-0000-0000-0000000e1343');
  v_state := pg_temp.try_as(v_mozo, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p6));
  if v_state <> 'PT409' then raise exception 'E10-TP03: ANULADO -> %', v_state; end if;
  -- Entradas y autorización
  v_p7 := pg_temp.entregado(v_mozo, v_m[7], v_chi, 1);
  if pg_temp.try_as(v_mozo, 'select public.rpc_solicitar_cuenta_pedido(null)') <> '22023' then raise exception 'E10-TP03: nulo'; end if;
  if pg_temp.try_as(v_mozo_o, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p7)) <> '42501' then raise exception 'E10-TP03: otro local'; end if;
  if pg_temp.try_as(v_coc, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p7)) <> '42501'
    or pg_temp.try_as(v_caja, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p7)) <> '42501'
    or pg_temp.try_as(v_admin, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p7)) <> '42501'
    or pg_temp.try_as(null, format('select public.rpc_solicitar_cuenta_pedido(%s)', v_p7)) <> '42501'
    or pg_temp.try_as(v_mozo, 'select public.rpc_solicitar_cuenta_pedido(999999999)') <> '42501' then
    raise exception 'E10-TP03: rol, sesión o pedido inexistente no rechazados con 42501';
  end if;
  if (select count(*) from public.solicitud_cuenta) <> v_count then raise exception 'E10-TP03: un rechazo creó filas'; end if;

  -- ===== TP12: lectura extendida de Caja
  select pg_get_function_result('public.obtener_pedidos_pendientes_pago_caja'::regproc) into v_result;
  if v_result <> 'TABLE(pedido_id bigint, pedido_estado text, pedido_creado_en timestamp with time zone, mesa_id uuid, '
    || 'mesa_codigo text, mesa_nombre text, mesa_estado text, detalle_id bigint, producto_id uuid, producto_nombre text, '
    || 'cantidad integer, precio_unitario numeric, importe_linea numeric, total_pedido numeric, subtotal numeric, '
    || 'descuento numeric, total_neto numeric, pagado_acumulado numeric, saldo numeric, solicitud_cuenta_id bigint, '
    || 'cuenta_solicitada_en timestamp with time zone, cuenta_solicitada_por_nombre text, servidor_ahora timestamp with time zone)' then
    raise exception 'E10-TP12: contrato inesperado %', v_result;
  end if;
  -- p8: dos líneas, sin solicitud; p4 reabierto no aparece; p1 y p2 con solicitud
  v_p8 := pg_temp.entregado(v_mozo, v_m[8], v_chi, 1);
  perform pg_temp.as_user(v_mozo); perform public.agregar_detalle_pedido(v_p8, v_pan, 2, null);
  perform public.enviar_pedido_cocina(v_p8); perform public.entregar_pedido(v_p8);
  perform pg_temp.as_user(v_caja);
  if exists (select 1 from public.obtener_pedidos_pendientes_pago_caja() x
      where x.pedido_id = v_p1 and (x.solicitud_cuenta_id is null or x.cuenta_solicitada_por_nombre <> 'Mozo Uno'
        or x.cuenta_solicitada_en is null or x.servidor_ahora is null or x.saldo <> 16 or x.total_neto <> 16))
    or (select count(*) from public.obtener_pedidos_pendientes_pago_caja() x where x.pedido_id = v_p1) <> 1 then
    raise exception 'E10-TP12: pedido con solicitud mal leído';
  end if;
  if (select count(*) from public.obtener_pedidos_pendientes_pago_caja() x where x.pedido_id = v_p2
      and x.solicitud_cuenta_id is not null and x.pagado_acumulado = 10 and x.saldo = 14) <> 1 then
    raise exception 'E10-TP12: pedido con parcial y solicitud mal leído';
  end if;
  if (select count(*) from public.obtener_pedidos_pendientes_pago_caja() x where x.pedido_id = v_p8
      and x.solicitud_cuenta_id is null and x.cuenta_solicitada_en is null and x.cuenta_solicitada_por_nombre is null) <> 2 then
    raise exception 'E10-TP12: pedido sin solicitud o multi-línea mal leído';
  end if;
  if exists (select 1 from public.obtener_pedidos_pendientes_pago_caja() x where x.pedido_id in (v_p3, v_p4, v_p5, v_p6)) then
    raise exception 'E10-TP12: pedido no pendiente listado';
  end if;
  -- Una solicitud SIN_EFECTO no aparece tras la nueva entrega
  perform pg_temp.as_user(v_mozo); perform public.enviar_pedido_cocina(v_p4); perform public.entregar_pedido(v_p4);
  perform pg_temp.as_user(v_caja);
  if (select count(*) from public.obtener_pedidos_pendientes_pago_caja() x where x.pedido_id = v_p4 and x.solicitud_cuenta_id is null) <> 2 then
    raise exception 'E10-TP12: pedido reentregado mal leído';
  end if;
  perform pg_temp.as_user(v_mozo);
  select * into strict r from public.rpc_solicitar_cuenta_pedido(v_p4);
  perform pg_temp.as_user(v_caja);
  if (select count(distinct x.solicitud_cuenta_id) from public.obtener_pedidos_pendientes_pago_caja() x where x.pedido_id = v_p4 and x.solicitud_cuenta_id = r.solicitud_id) <> 1 then
    raise exception 'E10-TP12: nueva solicitud tras la reentrega no leída';
  end if;
  -- Otros roles y locales
  if pg_temp.try_as(v_mozo, 'select public.obtener_pedidos_pendientes_pago_caja()') <> '42501'
    or pg_temp.try_as(v_coc, 'select public.obtener_pedidos_pendientes_pago_caja()') <> '42501'
    or pg_temp.try_as(v_admin, 'select public.obtener_pedidos_pendientes_pago_caja()') <> '42501' then
    raise exception 'E10-TP12: rol distinto de CAJA leyó pendientes';
  end if;
  perform pg_temp.as_user(v_caja_o);
  if exists (select 1 from public.obtener_pedidos_pendientes_pago_caja()) then raise exception 'E10-TP12: CAJA de otro local leyó'; end if;

  -- ===== TP12/TP14: seguridad de la RPC y de la lectura
  if exists (select 1 from pg_proc p where p.oid in ('public.rpc_solicitar_cuenta_pedido(bigint)'::regprocedure,
        'public.obtener_pedidos_pendientes_pago_caja()'::regprocedure)
      and (not p.prosecdef or pg_get_userbyid(p.proowner) <> 'postgres' or p.proconfig <> array['search_path=pg_catalog']
        or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')
        or not has_function_privilege('authenticated', p.oid, 'execute')
        or obj_description(p.oid, 'pg_proc') is null)) then
    raise exception 'E10-TP14: seguridad de funciones E10 inesperada';
  end if;
  if (select provolatile from pg_proc where oid = 'public.obtener_pedidos_pendientes_pago_caja()'::regprocedure) <> 's'
    or exists (select 1 from pg_proc where oid = 'public.rpc_solicitar_cuenta_pedido(bigint)'::regprocedure and prosrc like '%40001%') then
    raise exception 'E10-TP14: volatilidad o 40001 inesperados';
  end if;
end;
$e10_t03$;

do $e10_t03_fin$ begin raise notice 'E10-T03 solicitud y lectura de Caja: PASS'; end $e10_t03_fin$;

rollback;
