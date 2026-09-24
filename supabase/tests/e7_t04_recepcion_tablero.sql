-- E7-T04 — Verificación focal: recepción completa (TP08, parte SQL TP09), tablero sin productos
-- sin cocina (parte tablero TP05) y PT409 de detalle cancelado.
begin;

create function pg_temp.e7_set_user(p_user_id uuid) returns void
language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

do $e7_t04$
declare
  v_mozo uuid := '00000000-0000-0000-0000-0000000e7041';
  v_cocina uuid := '00000000-0000-0000-0000-0000000e7042';
  v_caja uuid := '00000000-0000-0000-0000-0000000e7043';
  v_cocina_otro uuid := '00000000-0000-0000-0000-0000000e7044';
  v_local uuid := '00000000-0000-0000-0000-0000000e7045';
  v_local2 uuid := '00000000-0000-0000-0000-0000000e7046';
  v_m1 uuid := '00000000-0000-0000-0000-0000000e7047';
  v_m2 uuid := '00000000-0000-0000-0000-0000000e7048';
  v_cat uuid := '00000000-0000-0000-0000-0000000e7049';
  v_cev uuid := '00000000-0000-0000-0000-0000000e704a';
  v_arr uuid := '00000000-0000-0000-0000-0000000e704b';
  v_chi uuid := '00000000-0000-0000-0000-0000000e704c';
  v_p1 bigint; v_p2 bigint;
  v_a bigint; v_b bigint; v_c bigint; v_d bigint; v_e bigint; v_x bigint;
  r record; v_snap jsonb; v_n bigint; v_ok boolean; v_state text;
begin
  insert into auth.users (id, aud, role, email, encrypted_password) values
    (v_mozo, 'authenticated', 'authenticated', 'e7-t04-m@example.invalid', 't'),
    (v_cocina, 'authenticated', 'authenticated', 'e7-t04-c@example.invalid', 't'),
    (v_caja, 'authenticated', 'authenticated', 'e7-t04-k@example.invalid', 't'),
    (v_cocina_otro, 'authenticated', 'authenticated', 'e7-t04-o@example.invalid', 't');
  insert into public.local (id, codigo, nombre) values (v_local, 'E7-T04', 'Local T04'), (v_local2, 'E7-T04B', 'Otro');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo, v_local, id, 'Mozo' from public.rol where codigo = 'MOZO'
  union all select v_cocina, v_local, id, 'Cocina' from public.rol where codigo = 'COCINA'
  union all select v_caja, v_local, id, 'Caja' from public.rol where codigo = 'CAJA'
  union all select v_cocina_otro, v_local2, id, 'Cocina otro' from public.rol where codigo = 'COCINA';
  insert into public.mesa (id, local_id, codigo, nombre) values (v_m1, v_local, 'T4-1', 'M1'), (v_m2, v_local, 'T4-2', 'M2');
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'T4', 'Cat');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
    (v_cev, v_local, v_cat, 'CEV', 'Ceviche', 30, true),
    (v_arr, v_local, v_cat, 'ARR', 'Arroz', 25, true),
    (v_chi, v_local, v_cat, 'CHI', 'Chicha', 8, false);

  -- Pedido 1: cuatro de cocina + una bebida, enviados
  perform pg_temp.e7_set_user(v_mozo);
  select pedido_id into strict v_p1 from public.crear_o_recuperar_pedido_mesa(v_m1);
  select detalle_id into strict v_a from public.agregar_detalle_pedido(v_p1, v_cev, 1, null);
  select detalle_id into strict v_b from public.agregar_detalle_pedido(v_p1, v_arr, 1, null);
  select detalle_id into strict v_c from public.agregar_detalle_pedido(v_p1, v_cev, 1, 'sin cebolla');
  select detalle_id into strict v_d from public.agregar_detalle_pedido(v_p1, v_arr, 1, 'poco arroz');
  select detalle_id into strict v_e from public.agregar_detalle_pedido(v_p1, v_chi, 1, null);
  perform public.enviar_pedido_cocina(v_p1);

  -- Tablero: bebidas ausentes en tablero nuevo y legado (parte TP05)
  perform pg_temp.e7_set_user(v_cocina);
  v_snap := public.rpc_obtener_tablero_cocina();
  if pg_catalog.jsonb_array_length(v_snap -> 'detalles') <> 4
    or v_snap -> 'detalles' @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('detalle_id', v_e))
    or pg_catalog.jsonb_array_length(v_snap -> 'comandas') <> 1 then
    raise exception 'E7-TP05: tablero nuevo inesperado %', v_snap;
  end if;
  if exists (select 1 from public.obtener_tablero_cocina() t where t.detalle_id = v_e)
    or (select count(*) from public.obtener_tablero_cocina() t where t.pedido_id = v_p1) <> 4 then
    raise exception 'E7-TP05: tablero legado muestra productos sin cocina';
  end if;
  -- Transición de cocina sobre bebida LISTO rechazada
  begin
    perform public.actualizar_estado_detalle_cocina(v_e, 'LISTO', 'LISTO');
    v_ok := false;
  exception when others then v_ok := sqlstate = '22023';
  end;
  if not v_ok then raise exception 'E7-TP05: transición sobre bebida no rechazada'; end if;

  -- Preparar combinación: b RECIBIDO, c EN_PREPARACION, d LISTO; a sigue ENVIADO
  perform public.actualizar_estado_detalle_cocina(v_b, 'ENVIADO', 'RECIBIDO_COCINA');
  perform public.actualizar_estado_detalle_cocina(v_c, 'ENVIADO', 'RECIBIDO_COCINA');
  perform public.actualizar_estado_detalle_cocina(v_c, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  perform public.actualizar_estado_detalle_cocina(v_d, 'ENVIADO', 'RECIBIDO_COCINA');
  perform public.actualizar_estado_detalle_cocina(v_d, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  perform public.actualizar_estado_detalle_cocina(v_d, 'EN_PREPARACION', 'LISTO');

  -- TP08: sólo el ENVIADO cambia; nada retrocede; bebida intacta
  select * into strict r from public.rpc_recibir_pedido_cocina(v_p1);
  if r.detalles_recibidos <> 1 or r.detalle_ids <> array[v_a] or r.pedido_estado <> 'RECIBIDO_COCINA' then
    raise exception 'E7-TP08: recepción inesperada %', r;
  end if;
  if (select array_agg(estado order by id) from public.detalle_pedido where pedido_id = v_p1)
     <> array['RECIBIDO_COCINA','RECIBIDO_COCINA','EN_PREPARACION','LISTO','LISTO'] then
    raise exception 'E7-TP08: estados tras recepción inesperados';
  end if;
  if (select count(*) from public.historial_detalle_pedido where pedido_id = v_p1 and operacion = 'RECEPCION_COMPLETA') <> 1
    or not exists (select 1 from public.historial_detalle_pedido where detalle_id = v_a and operacion = 'RECEPCION_COMPLETA'
                   and estado_anterior = 'ENVIADO' and estado_nuevo = 'RECIBIDO_COCINA' and usuario_id = v_cocina)
    or (select count(*) from public.historial_detalle_pedido where detalle_id = v_b and operacion = 'TRANSICION_COCINA') <> 1
    or exists (select 1 from public.historial_detalle_pedido where detalle_id = v_e and operacion <> 'ENVIO') then
    raise exception 'E7-TP08: historial de detalle inesperado';
  end if;

  -- TP09: reintento -> 0 recibidos sin error, sin historial ni derivación duplicados
  select count(*) into v_n from public.historial_estado where pedido_id = v_p1;
  select * into strict r from public.rpc_recibir_pedido_cocina(v_p1);
  if r.detalles_recibidos <> 0 or r.detalle_ids <> array[]::bigint[] or r.pedido_estado <> 'RECIBIDO_COCINA' then
    raise exception 'E7-TP09: reintento inesperado %', r;
  end if;
  if (select count(*) from public.historial_estado where pedido_id = v_p1) <> v_n
    or (select count(*) from public.historial_detalle_pedido where pedido_id = v_p1 and operacion = 'RECEPCION_COMPLETA') <> 1 then
    raise exception 'E7-TP09: reintento duplicó historial';
  end if;
  if pg_catalog.current_setting('mikuyapp.operacion_detalle', true) <> '' then
    raise exception 'E7-TP08: marca de operación no restablecida';
  end if;

  -- TP08: después de la recepción completa el avance individual sigue funcionando
  perform public.actualizar_estado_detalle_cocina(v_a, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  if not exists (select 1 from public.historial_detalle_pedido where detalle_id = v_a and operacion = 'TRANSICION_COCINA'
                 and estado_nuevo = 'EN_PREPARACION') then
    raise exception 'E7-TP08: transición individual posterior no registrada';
  end if;

  -- TP09: rol/local no autorizados -> 42501
  foreach v_x in array array[1, 2] loop
    perform pg_temp.e7_set_user(case v_x when 1 then v_caja else v_cocina_otro end);
    begin
      perform public.rpc_recibir_pedido_cocina(v_p1); v_ok := false;
    exception when others then v_ok := sqlstate = '42501';
    end;
    if not v_ok then raise exception 'E7-TP09: acceso no autorizado permitido (%)', v_x; end if;
    begin
      perform public.rpc_obtener_tablero_cocina(); v_ok := v_x = 2; -- otro local: sin datos, no error
    exception when others then v_ok := sqlstate = '42501' and v_x = 1;
    end;
    if not v_ok then raise exception 'E7-TP09: lectura de tablero no autorizada (%)', v_x; end if;
  end loop;
  perform pg_temp.e7_set_user(v_cocina_otro);
  if pg_catalog.jsonb_array_length(public.rpc_obtener_tablero_cocina() -> 'detalles') <> 0 then
    raise exception 'E7-TP09: fuga de datos entre locales';
  end if;

  -- TP09: pedido terminal/entregado -> PT409
  perform pg_temp.e7_set_user(v_mozo);
  select pedido_id into strict v_p2 from public.crear_o_recuperar_pedido_mesa(v_m2);
  perform public.agregar_detalle_pedido(v_p2, v_chi, 1, null);
  perform public.enviar_pedido_cocina(v_p2);
  perform public.entregar_pedido(v_p2);
  perform pg_temp.e7_set_user(v_cocina);
  begin
    perform public.rpc_recibir_pedido_cocina(v_p2); v_ok := false;
  exception when others then v_ok := sqlstate = 'PT409';
  end;
  if not v_ok then raise exception 'E7-TP09: pedido ENTREGADO no devolvió PT409'; end if;
  update public.pedido set estado = 'ANULADO' where id = v_p2;
  begin
    perform public.rpc_recibir_pedido_cocina(v_p2); v_ok := false;
  exception when others then v_ok := sqlstate = 'PT409';
  end;
  if not v_ok then raise exception 'E7-TP09: pedido ANULADO no devolvió PT409'; end if;

  -- PT409 en transición individual de un detalle cancelado (evento simulado; la RPC de cancelación es T05)
  insert into public.historial_detalle_pedido (local_id, pedido_id, detalle_id, producto_id, operacion,
    estado_anterior, estado_nuevo, requiere_cocina, cantidad, precio_unitario, motivo, usuario_id)
  values (v_local, v_p1, -999001, v_cev, 'CANCELACION', 'ENVIADO', null, true, 1, 30, 'prueba', v_mozo);
  begin
    perform public.actualizar_estado_detalle_cocina(-999001, 'ENVIADO', 'RECIBIDO_COCINA'); v_ok := false;
  exception when others then v_ok := sqlstate = 'PT409';
  end;
  if not v_ok then raise exception 'E7-T04: detalle cancelado no devolvió PT409'; end if;
  begin
    perform public.actualizar_estado_detalle_cocina(-999002, 'ENVIADO', 'RECIBIDO_COCINA'); v_ok := false;
  exception when others then v_ok := sqlstate = '42501';
  end;
  if not v_ok then raise exception 'E7-T04: detalle inexistente dejó de devolver 42501'; end if;
  v_snap := public.rpc_obtener_tablero_cocina();
  if pg_catalog.jsonb_array_length(v_snap -> 'cancelaciones') <> 1 then
    raise exception 'E7-T04: cancelaciones no expuestas en tablero';
  end if;
end;
$e7_t04$;

-- Privilegios de las RPC nuevas
do $e7_t04_meta$
begin
  if pg_catalog.has_function_privilege('anon', 'public.rpc_recibir_pedido_cocina(bigint)', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.rpc_obtener_tablero_cocina()', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.rpc_recibir_pedido_cocina(bigint)', 'EXECUTE')
    or not exists (select 1 from pg_catalog.pg_proc where oid = 'public.rpc_recibir_pedido_cocina(bigint)'::regprocedure
                   and prosecdef and proconfig @> array['search_path=pg_catalog']) then
    raise exception 'E7-TP26: metadatos de RPC de cocina inesperados';
  end if;
end $e7_t04_meta$;

rollback;
