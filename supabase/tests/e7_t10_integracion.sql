-- E7-T10 — Recorrido integrado (TP06, TP07, parte base de datos de TP27) con dos mozos y dos cocinas.
-- Incluye verificación de visibilidad RLS de las filas-señal que Supabase Realtime entrega a cada rol
-- (Realtime aplica RLS con el rol authenticated del suscriptor). Termina con ROLLBACK.
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

-- Visibilidad RLS (lo que Realtime/PostgREST mostraría al suscriptor) ejecutada como authenticated.
create function pg_temp.visible(p_user uuid, p_sql text) returns bigint
language plpgsql set search_path = pg_catalog as $$
declare v bigint;
begin
  perform pg_temp.as_user(p_user);
  execute 'set local role authenticated';
  execute p_sql into v;
  execute 'reset role';
  return v;
end $$;

do $e7_t10$
declare
  v_mozo_a uuid := '00000000-0000-0000-0000-0000000e7a01';
  v_mozo_b uuid := '00000000-0000-0000-0000-0000000e7a02';
  v_coc_1 uuid := '00000000-0000-0000-0000-0000000e7a03';
  v_coc_2 uuid := '00000000-0000-0000-0000-0000000e7a04';
  v_caja uuid := '00000000-0000-0000-0000-0000000e7a05';
  v_local uuid := '00000000-0000-0000-0000-0000000e7a10';
  v_mesa uuid := '00000000-0000-0000-0000-0000000e7a11';
  v_cat uuid := '00000000-0000-0000-0000-0000000e7a12';
  v_cev uuid := '00000000-0000-0000-0000-0000000e7a13';
  v_chi uuid := '00000000-0000-0000-0000-0000000e7a14';
  v_p bigint; v_c1 bigint; v_c2 bigint; v_c3 bigint; v_b bigint; v_c4 bigint;
  v_snap jsonb; v_com bigint; r record; v_mod timestamptz; v_n bigint;
begin
  insert into auth.users (id, aud, role, email, encrypted_password) values
    (v_mozo_a, 'authenticated', 'authenticated', 'e7t10-ma@example.invalid', 't'),
    (v_mozo_b, 'authenticated', 'authenticated', 'e7t10-mb@example.invalid', 't'),
    (v_coc_1, 'authenticated', 'authenticated', 'e7t10-c1@example.invalid', 't'),
    (v_coc_2, 'authenticated', 'authenticated', 'e7t10-c2@example.invalid', 't'),
    (v_caja, 'authenticated', 'authenticated', 'e7t10-k@example.invalid', 't');
  insert into public.local (id, codigo, nombre) values (v_local, 'E7-T10', 'Local integración E7');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo_a, v_local, id, 'Mozo A' from public.rol where codigo = 'MOZO'
  union all select v_mozo_b, v_local, id, 'Mozo B' from public.rol where codigo = 'MOZO'
  union all select v_coc_1, v_local, id, 'Cocina 1' from public.rol where codigo = 'COCINA'
  union all select v_coc_2, v_local, id, 'Cocina 2' from public.rol where codigo = 'COCINA'
  union all select v_caja, v_local, id, 'Caja' from public.rol where codigo = 'CAJA';
  insert into public.mesa (id, local_id, codigo, nombre) values (v_mesa, v_local, 'T10', 'Mesa integración');
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'T10', 'Carta');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
    (v_cev, v_local, v_cat, 'CEV', 'Ceviche', 30, true),
    (v_chi, v_local, v_cat, 'CHI', 'Chicha', 8, false);

  -- 1. Mozo A abre la mesa y registra un pedido mixto con borradores
  perform pg_temp.as_user(v_mozo_a);
  select pedido_id into strict v_p from public.crear_o_recuperar_pedido_mesa(v_mesa);
  select detalle_id into strict v_c1 from public.agregar_detalle_pedido(v_p, v_cev, 1, null);
  select detalle_id into strict v_c2 from public.agregar_detalle_pedido(v_p, v_cev, 1, 'sin ají');
  select detalle_id into strict v_c3 from public.agregar_detalle_pedido(v_p, v_cev, 1, 'para retirar');
  select detalle_id into strict v_b from public.agregar_detalle_pedido(v_p, v_chi, 2, null);

  -- 2. Edición y retiro de borradores ABIERTO (vía RPC, verificación optimista)
  select * into strict r from public.rpc_modificar_detalle_pedido(v_c1, 2, 'bien frío', 1, null);
  if r.cantidad <> 2 or r.observacion <> 'bien frío' then raise exception 'T10 paso 2: edición %', r; end if;
  select * into strict r from public.rpc_retirar_detalle_pedido(v_c3);
  if r.pedido_estado <> 'ABIERTO' then raise exception 'T10 paso 2: retiro %', r; end if;
  -- Mozo B (otro dispositivo) ve el borrador actualizado por RLS; cocina todavía no ve ABIERTO
  if pg_temp.visible(v_mozo_b, format('select count(*) from public.detalle_pedido where pedido_id = %s', v_p)) <> 3
    or pg_temp.visible(v_coc_1, format('select count(*) from public.detalle_pedido where pedido_id = %s', v_p)) <> 0 then
    raise exception 'T10 paso 2: visibilidad RLS de borradores';
  end if;
  -- Mozo B con snapshot antiguo de v_c1 (1, NULL) no puede pisar la edición de A
  perform pg_temp.as_user(v_mozo_b);
  if pg_temp.sqlstate_of(format('select public.rpc_modificar_detalle_pedido(%s, 3, null, 1, null)', v_c1)) <> 'PT409' then
    raise exception 'T10 paso 2: edición concurrente no detectada';
  end if;

  -- 3. Envío: bebida sin cocina -> LISTO; ceviches -> ENVIADO; comanda 1 sólo con ceviches
  perform pg_temp.as_user(v_mozo_a);
  select * into strict r from public.enviar_pedido_cocina(v_p);
  if r.detalles_enviados <> 3 or r.pedido_estado <> 'ENVIADO' then raise exception 'T10 paso 3: envío %', r; end if;
  if (select estado from public.detalle_pedido where id = v_b) <> 'LISTO'
    or (select count(*) from public.detalle_pedido where pedido_id = v_p and estado = 'ENVIADO') <> 2 then
    raise exception 'T10 paso 3: estados tras envío';
  end if;
  select id into strict v_com from public.comanda where pedido_id = v_p and numero = 1;
  if pg_catalog.jsonb_array_length((select lineas from public.comanda where id = v_com)) <> 2 then
    raise exception 'T10 paso 3: comanda 1 con líneas incorrectas';
  end if;
  -- Señales Realtime: cocina ve (RLS) las filas de detalle con cocina y el pedido; mozo B ve todo
  if pg_temp.visible(v_coc_2, format('select count(*) from public.detalle_pedido where pedido_id = %s', v_p)) <> 3
    or pg_temp.visible(v_coc_2, format('select count(*) from public.pedido where id = %s', v_p)) <> 1
    or pg_temp.visible(v_mozo_b, format('select count(*) from public.pedido where id = %s', v_p)) <> 1 then
    raise exception 'T10 paso 3: visibilidad de señales tras envío';
  end if;

  -- 4. Tablero de ambas cocinas: sin bebida, con comanda
  perform pg_temp.as_user(v_coc_1);
  v_snap := public.rpc_obtener_tablero_cocina();
  if pg_catalog.jsonb_array_length(v_snap -> 'detalles') <> 2
    or v_snap -> 'detalles' @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('detalle_id', v_b))
    or pg_catalog.jsonb_array_length(v_snap -> 'comandas') <> 1 then
    raise exception 'T10 paso 4: tablero cocina 1 %', v_snap;
  end if;
  perform pg_temp.as_user(v_coc_2);
  if public.rpc_obtener_tablero_cocina() -> 'detalles' is distinct from v_snap -> 'detalles' then
    raise exception 'T10 paso 4: cocinas con snapshots distintos';
  end if;

  -- 5. Primera solicitud de impresión (cocina 1); la cocina 2 recibe PT409 y reimprime
  perform pg_temp.as_user(v_coc_1);
  select * into strict r from public.rpc_registrar_impresion_comanda(v_com, false);
  perform pg_temp.as_user(v_coc_2);
  if pg_temp.sqlstate_of(format('select public.rpc_registrar_impresion_comanda(%s, false)', v_com)) <> 'PT409' then
    raise exception 'T10 paso 5: segunda primera solicitud aceptada';
  end if;
  select * into strict r from public.rpc_registrar_impresion_comanda(v_com, true);
  if r.impresiones <> 2 then raise exception 'T10 paso 5: reimpresión %', r; end if;

  -- 6. Recepción completa (cocina 1) y reintento de la cocina 2 (0 sin error)
  perform pg_temp.as_user(v_coc_1);
  select * into strict r from public.rpc_recibir_pedido_cocina(v_p);
  if r.detalles_recibidos <> 2 or r.pedido_estado <> 'RECIBIDO_COCINA' then raise exception 'T10 paso 6: %', r; end if;
  perform pg_temp.as_user(v_coc_2);
  select * into strict r from public.rpc_recibir_pedido_cocina(v_p);
  if r.detalles_recibidos <> 0 then raise exception 'T10 paso 6: reintento %', r; end if;

  -- 7. Mozo B cancela un ceviche RECIBIDO_COCINA; cocina ve la cancelación y recibe la señal de pedido
  select modificado_en into v_mod from public.pedido where id = v_p;
  perform pg_temp.as_user(v_mozo_b);
  select * into strict r from public.rpc_cancelar_detalle_pedido(v_c2, 'Cliente cambió de opinión');
  if r.ya_cancelado or r.pedido_estado <> 'RECIBIDO_COCINA' then raise exception 'T10 paso 7: %', r; end if;
  if (select modificado_en from public.pedido where id = v_p) <= v_mod
    or pg_temp.visible(v_coc_1, format('select count(*) from public.pedido where id = %s', v_p)) <> 1 then
    raise exception 'T10 paso 7: señal Realtime de cancelación no visible para cocina';
  end if;
  perform pg_temp.as_user(v_coc_1);
  v_snap := public.rpc_obtener_tablero_cocina();
  if not (v_snap -> 'cancelaciones') @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('detalle_id', v_c2, 'motivo', 'Cliente cambió de opinión'))
    or (v_snap -> 'detalles') @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('detalle_id', v_c2)) then
    raise exception 'T10 paso 7: tablero tras cancelación %', v_snap;
  end if;
  -- la cocina 2 intentaba avanzar el ceviche cancelado: PT409
  perform pg_temp.as_user(v_coc_2);
  if pg_temp.sqlstate_of(format('select public.actualizar_estado_detalle_cocina(%s, %L, %L)', v_c2, 'RECIBIDO_COCINA', 'EN_PREPARACION')) <> 'PT409' then
    raise exception 'T10 paso 7: transición sobre cancelado no devolvió PT409';
  end if;
  perform pg_temp.as_user(v_mozo_a);
  if (select count(*) from public.rpc_obtener_cancelaciones_pedido(v_p)) <> 1 then raise exception 'T10 paso 7: mozo sin cancelados'; end if;

  -- 8. Avance individual del ceviche restante hasta LISTO: pedido LISTO, mesa PEDIDO_LISTO
  perform pg_temp.as_user(v_coc_2);
  perform public.actualizar_estado_detalle_cocina(v_c1, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  if pg_temp.sqlstate_of(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_c1, 'tarde')) <> '42501' then
    raise exception 'T10 paso 8: cocina pudo cancelar';
  end if;
  perform pg_temp.as_user(v_mozo_a);
  if pg_temp.sqlstate_of(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_c1, 'tarde')) <> 'PT409' then
    raise exception 'T10 paso 8: cancelación en preparación aceptada';
  end if;
  perform pg_temp.as_user(v_coc_2);
  perform public.actualizar_estado_detalle_cocina(v_c1, 'EN_PREPARACION', 'LISTO');
  if (select estado from public.pedido where id = v_p) <> 'LISTO' or (select estado from public.mesa where id = v_mesa) <> 'PEDIDO_LISTO' then
    raise exception 'T10 paso 8: agregado no LISTO';
  end if;
  if pg_temp.visible(v_mozo_a, format('select count(*) from public.mesa where id = %L and estado = %L', v_mesa, 'PEDIDO_LISTO')) <> 1 then
    raise exception 'T10 paso 8: mozo no ve mesa PEDIDO_LISTO';
  end if;

  -- 9. Entrega; agregado posterior con cocina -> comanda 2 sólo con lo nuevo; nueva entrega
  perform pg_temp.as_user(v_mozo_a);
  perform public.entregar_pedido(v_p);
  select detalle_id into strict v_c4 from public.agregar_detalle_pedido(v_p, v_cev, 1, 'extra');
  perform public.agregar_detalle_pedido(v_p, v_chi, 1, null);
  perform public.enviar_pedido_cocina(v_p);
  if pg_catalog.jsonb_array_length((select lineas from public.comanda where pedido_id = v_p and numero = 2)) <> 1
    or ((select lineas from public.comanda where pedido_id = v_p and numero = 2) -> 0 ->> 'detalle_id')::bigint <> v_c4 then
    raise exception 'T10 paso 9: comanda 2';
  end if;
  perform pg_temp.as_user(v_coc_1);
  perform public.rpc_recibir_pedido_cocina(v_p);
  perform public.actualizar_estado_detalle_cocina(v_c4, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  perform public.actualizar_estado_detalle_cocina(v_c4, 'EN_PREPARACION', 'LISTO');
  perform pg_temp.as_user(v_mozo_a);
  perform public.entregar_pedido(v_p);

  -- 10. Caja: total autoritativo excluye la línea cancelada (2*30 + 2*8 + 30 + 8 = 114)
  perform pg_temp.as_user(v_caja);
  if (select distinct total_pedido from public.obtener_pedidos_pendientes_pago_caja() where pedido_id = v_p) <> 114 then
    raise exception 'T10 paso 10: total de caja';
  end if;

  -- 11. Trazabilidad del recorrido
  select count(*) into v_n from public.historial_detalle_pedido where pedido_id = v_p;
  if v_n <> (select count(*) from public.historial_detalle_pedido where pedido_id = v_p
             and operacion in ('ENVIO', 'TRANSICION_COCINA', 'RECEPCION_COMPLETA', 'CANCELACION'))
    or (select count(*) from public.historial_detalle_pedido where pedido_id = v_p and operacion = 'CANCELACION') <> 1
    or (select count(*) from public.historial_detalle_pedido where pedido_id = v_p and operacion = 'RECEPCION_COMPLETA') <> 3 then
    raise exception 'T10 paso 11: historial de detalle';
  end if;
  raise notice 'E7-T10 recorrido integrado OK: pedido %, % eventos de detalle, 2 comandas, total caja 114', v_p, v_n;
end;
$e7_t10$;

-- Privilegios con los defaults de Supabase (corrección 20260924000800): ningún rol cliente ni
-- service_role escribe directo en historial/comanda ni ejecuta funciones internas de E7.
do $e7_t10_privilegios$
begin
  if exists (select 1 from information_schema.role_table_grants
             where table_schema = 'public' and table_name in ('historial_detalle_pedido', 'comanda')
               and grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC'))
    or exists (select 1 from pg_catalog.pg_proc p cross join unnest(array['anon', 'authenticated', 'service_role']) r
               where p.pronamespace = 'public'::regnamespace
                 and p.proname in ('tgf_historial_detalle_pedido_inmutable', 'tgf_comanda_contenido_inmutable', 'tgf_detalle_pedido_historial_estado')
                 and pg_catalog.has_function_privilege(r, p.oid, 'EXECUTE'))
    or exists (select 1 from pg_catalog.pg_proc p cross join unnest(array['anon', 'service_role']) r
               where p.pronamespace = 'public'::regnamespace
                 and p.proname in ('rpc_obtener_tablero_cocina', 'rpc_recibir_pedido_cocina', 'rpc_cancelar_detalle_pedido',
                                   'rpc_obtener_cancelaciones_pedido', 'rpc_modificar_detalle_pedido', 'rpc_retirar_detalle_pedido',
                                   'rpc_registrar_impresion_comanda')
                 and pg_catalog.has_function_privilege(r, p.oid, 'EXECUTE')) then
    raise exception 'E7-T10: privilegios por defecto de Supabase no revocados';
  end if;
end $e7_t10_privilegios$;

rollback;
