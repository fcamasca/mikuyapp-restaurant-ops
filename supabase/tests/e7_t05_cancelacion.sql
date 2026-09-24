-- E7-T05 — Verificación focal: cancelación permitida (TP14), rechazada (TP15), último detalle (TP16),
-- idempotencia (TP17) e historial CANCELACION (parte TP20).
begin;

create function pg_temp.e7_set_user(p_user_id uuid) returns void
language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

create function pg_temp.e7_sqlstate(p_sql text) returns text
language plpgsql set search_path = pg_catalog as $$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlstate;
end $$;

do $e7_t05$
declare
  v_mozo uuid := '00000000-0000-0000-0000-0000000e7051';
  v_cocina uuid := '00000000-0000-0000-0000-0000000e7052';
  v_caja uuid := '00000000-0000-0000-0000-0000000e7053';
  v_mozo2 uuid := '00000000-0000-0000-0000-0000000e7054';
  v_local uuid := '00000000-0000-0000-0000-0000000e7055';
  v_local2 uuid := '00000000-0000-0000-0000-0000000e7056';
  v_cat uuid := '00000000-0000-0000-0000-0000000e7057';
  v_cev uuid := '00000000-0000-0000-0000-0000000e7058';
  v_chi uuid := '00000000-0000-0000-0000-0000000e7059';
  v_m uuid[] := array['00000000-0000-0000-0000-0000000e7061','00000000-0000-0000-0000-0000000e7062',
                      '00000000-0000-0000-0000-0000000e7063','00000000-0000-0000-0000-0000000e7064']::uuid[];
  v_p1 bigint; v_p2 bigint; v_p3 bigint; v_p4 bigint;
  v_a bigint; v_b bigint; v_c bigint; v_d bigint; v_e bigint;
  r record; v_hist bigint; v_mod timestamptz;
begin
  insert into auth.users (id, aud, role, email, encrypted_password) values
    (v_mozo, 'authenticated', 'authenticated', 'e7-t05-m@example.invalid', 't'),
    (v_cocina, 'authenticated', 'authenticated', 'e7-t05-c@example.invalid', 't'),
    (v_caja, 'authenticated', 'authenticated', 'e7-t05-k@example.invalid', 't'),
    (v_mozo2, 'authenticated', 'authenticated', 'e7-t05-o@example.invalid', 't');
  insert into public.local (id, codigo, nombre) values (v_local, 'E7-T05', 'Local T05'), (v_local2, 'E7-T05B', 'Otro');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo, v_local, id, 'Mozo T05' from public.rol where codigo = 'MOZO'
  union all select v_cocina, v_local, id, 'Cocina T05' from public.rol where codigo = 'COCINA'
  union all select v_caja, v_local, id, 'Caja T05' from public.rol where codigo = 'CAJA'
  union all select v_mozo2, v_local2, id, 'Mozo otro' from public.rol where codigo = 'MOZO';
  insert into public.mesa (id, local_id, codigo, nombre)
  select v_m[i], v_local, 'T5-' || i, 'Mesa ' || i from generate_series(1, 4) i;
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'T5', 'Cat');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
    (v_cev, v_local, v_cat, 'CEV', 'Ceviche', 30, true), (v_chi, v_local, v_cat, 'CHI', 'Chicha', 8, false);

  -- ===== TP14: pedido mixto; cancelar ENVIADO (cantidad 3, línea completa) y RECIBIDO_COCINA
  perform pg_temp.e7_set_user(v_mozo);
  select pedido_id into strict v_p1 from public.crear_o_recuperar_pedido_mesa(v_m[1]);
  select detalle_id into strict v_a from public.agregar_detalle_pedido(v_p1, v_cev, 3, 'sin ají');
  select detalle_id into strict v_b from public.agregar_detalle_pedido(v_p1, v_cev, 1, 'extra limón');
  select detalle_id into strict v_c from public.agregar_detalle_pedido(v_p1, v_chi, 2, null);
  perform public.enviar_pedido_cocina(v_p1);
  perform pg_temp.e7_set_user(v_cocina);
  perform public.actualizar_estado_detalle_cocina(v_b, 'ENVIADO', 'RECIBIDO_COCINA');

  perform pg_temp.e7_set_user(v_mozo);
  select modificado_en into v_mod from public.pedido where id = v_p1;
  select * into strict r from public.rpc_cancelar_detalle_pedido(v_a, '  Cliente cambió de opinión  ');
  if r.ya_cancelado or r.pedido_estado <> 'RECIBIDO_COCINA' or r.mesa_estado <> 'OCUPADA' then
    raise exception 'E7-TP14: cancelación ENVIADO inesperada %', r;
  end if;
  if exists (select 1 from public.detalle_pedido where id = v_a) then raise exception 'E7-TP14: línea no eliminada'; end if;
  if not exists (select 1 from public.historial_detalle_pedido where detalle_id = v_a and operacion = 'CANCELACION'
      and pedido_id = v_p1 and producto_id = v_cev and cantidad = 3 and precio_unitario = 30 and observacion = 'sin ají'
      and estado_anterior = 'ENVIADO' and estado_nuevo is null and motivo = 'Cliente cambió de opinión'
      and usuario_id = v_mozo and local_id = v_local and requiere_cocina) then
    raise exception 'E7-TP14: snapshot de cancelación incompleto';
  end if;
  if (select modificado_en from public.pedido where id = v_p1) <= v_mod then
    raise exception 'E7-TP14/TP27: la cancelación no actualizó pedido.modificado_en (señal Realtime)';
  end if;
  if (select sum(cantidad * precio_unitario) from public.detalle_pedido where pedido_id = v_p1) <> 46 then
    raise exception 'E7-TP14: total no recalculado';
  end if;
  -- RECIBIDO_COCINA cancelable; queda sólo la bebida LISTO -> pedido LISTO / mesa PEDIDO_LISTO
  select * into strict r from public.rpc_cancelar_detalle_pedido(v_b, 'Demora');
  if r.pedido_estado <> 'LISTO' or r.mesa_estado <> 'PEDIDO_LISTO' then
    raise exception 'E7-TP14: pedido mixto tras cancelar no quedó LISTO %', r;
  end if;
  if not exists (select 1 from public.historial_estado where pedido_id = v_p1 and estado_anterior = 'RECIBIDO_COCINA' and estado_nuevo = 'LISTO') then
    raise exception 'E7-TP14: historial de cabecera no registrado';
  end if;
  -- entregable y total en caja excluye líneas canceladas
  select * into strict r from public.entregar_pedido(v_p1);
  perform pg_temp.e7_set_user(v_caja);
  if (select distinct total_pedido from public.obtener_pedidos_pendientes_pago_caja() where pedido_id = v_p1) <> 16 then
    raise exception 'E7-TP14: total de caja incluye cancelaciones';
  end if;

  -- ===== TP17: reintento idempotente
  perform pg_temp.e7_set_user(v_mozo);
  select count(*) into v_hist from public.historial_detalle_pedido where pedido_id = v_p1;
  select * into strict r from public.rpc_cancelar_detalle_pedido(v_a, 'Reintento');
  if not r.ya_cancelado or r.pedido_id <> v_p1 or r.detalle_id <> v_a then raise exception 'E7-TP17: reintento no idempotente %', r; end if;
  if (select count(*) from public.historial_detalle_pedido where pedido_id = v_p1) <> v_hist then
    raise exception 'E7-TP17: reintento duplicó historial';
  end if;
  -- otro local no ve la cancelación
  perform pg_temp.e7_set_user(v_mozo2);
  if pg_temp.e7_sqlstate(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_a, 'x')) <> '42501' then
    raise exception 'E7-TP17: reintento desde otro local no rechazado';
  end if;

  -- ===== TP15: rechazos
  perform pg_temp.e7_set_user(v_mozo);
  select pedido_id into strict v_p2 from public.crear_o_recuperar_pedido_mesa(v_m[2]);
  select detalle_id into strict v_a from public.agregar_detalle_pedido(v_p2, v_cev, 1, 'a');
  select detalle_id into strict v_b from public.agregar_detalle_pedido(v_p2, v_cev, 1, 'b');
  select detalle_id into strict v_c from public.agregar_detalle_pedido(v_p2, v_chi, 1, null);
  perform public.enviar_pedido_cocina(v_p2);
  select detalle_id into strict v_d from public.agregar_detalle_pedido(v_p2, v_cev, 1, 'abierto');
  perform pg_temp.e7_set_user(v_cocina);
  perform public.actualizar_estado_detalle_cocina(v_a, 'ENVIADO', 'RECIBIDO_COCINA');
  perform public.actualizar_estado_detalle_cocina(v_a, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  perform public.actualizar_estado_detalle_cocina(v_b, 'ENVIADO', 'RECIBIDO_COCINA');
  perform public.actualizar_estado_detalle_cocina(v_b, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  perform public.actualizar_estado_detalle_cocina(v_b, 'EN_PREPARACION', 'LISTO');
  perform pg_temp.e7_set_user(v_mozo);
  select count(*) into v_hist from public.historial_detalle_pedido where pedido_id = v_p2;
  if pg_temp.e7_sqlstate(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_a, 'x')) <> 'PT409'
    or pg_temp.e7_sqlstate(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_b, 'x')) <> 'PT409'
    or pg_temp.e7_sqlstate(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_c, 'x')) <> 'PT409'
    or pg_temp.e7_sqlstate(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_d, 'x')) <> 'PT409' then
    raise exception 'E7-TP15: EN_PREPARACION/LISTO/bebida enviada/ABIERTO no rechazados con PT409';
  end if;
  select detalle_id into strict v_e from public.agregar_detalle_pedido(v_p2, v_cev, 2, 'para motivo');
  perform public.enviar_pedido_cocina(v_p2);
  if pg_temp.e7_sqlstate(format('select public.rpc_cancelar_detalle_pedido(%s, null)', v_e)) <> '22023'
    or pg_temp.e7_sqlstate(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_e, '   ')) <> '22023'
    or pg_temp.e7_sqlstate(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_e, repeat('x', 201))) <> '22023' then
    raise exception 'E7-TP15: motivo inválido aceptado';
  end if;
  if (select count(*) from public.historial_detalle_pedido where pedido_id = v_p2 and operacion = 'CANCELACION') <> 0
    or not exists (select 1 from public.detalle_pedido where id = v_e and cantidad = 2) then
    raise exception 'E7-TP15: un rechazo dejó efectos';
  end if;
  -- roles no autorizados
  perform pg_temp.e7_set_user(v_cocina);
  if pg_temp.e7_sqlstate(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_e, 'x')) <> '42501' then
    raise exception 'E7-TP15/TP25: COCINA pudo cancelar';
  end if;
  perform pg_temp.e7_set_user(v_caja);
  if pg_temp.e7_sqlstate(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_e, 'x')) <> '42501' then
    raise exception 'E7-TP15/TP25: CAJA pudo cancelar';
  end if;
  -- pedido PAGADO / ANULADO / con pago parcial
  perform pg_temp.e7_set_user(v_mozo);
  update public.pedido set estado = 'ANULADO' where id = v_p2;
  if pg_temp.e7_sqlstate(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_e, 'x')) <> 'PT409' then
    raise exception 'E7-TP15: pedido ANULADO no rechazado';
  end if;
  update public.pedido set estado = 'ENVIADO' where id = v_p2;
  insert into public.pago (pedido_id, importe, medio, usuario_id) values (v_p2, 1, 'EFECTIVO', v_caja);
  if pg_temp.e7_sqlstate(format('select public.rpc_cancelar_detalle_pedido(%s, %L)', v_e, 'x')) <> 'PT409' then
    raise exception 'E7-TP15: pedido con pago no rechazado';
  end if;

  -- ===== TP16: cancelar el último detalle -> ABIERTO vacío, mesa OCUPADA, liberar funciona
  select pedido_id into strict v_p3 from public.crear_o_recuperar_pedido_mesa(v_m[3]);
  select detalle_id into strict v_a from public.agregar_detalle_pedido(v_p3, v_cev, 1, null);
  perform public.enviar_pedido_cocina(v_p3);
  perform pg_temp.e7_set_user(v_cocina);
  perform public.rpc_recibir_pedido_cocina(v_p3);
  perform pg_temp.e7_set_user(v_mozo);
  select * into strict r from public.rpc_cancelar_detalle_pedido(v_a, 'Se retiró el cliente');
  if r.pedido_estado <> 'ABIERTO' or r.mesa_estado <> 'OCUPADA'
    or (select estado from public.pedido where id = v_p3) <> 'ABIERTO'
    or not exists (select 1 from public.historial_estado where pedido_id = v_p3 and estado_anterior = 'RECIBIDO_COCINA' and estado_nuevo = 'ABIERTO') then
    raise exception 'E7-TP16: pedido vacío inesperado %', r;
  end if;
  -- lectura de cancelaciones del mozo
  if (select count(*) from public.rpc_obtener_cancelaciones_pedido(v_p3) c
      where c.detalle_id = v_a and c.estado_anterior = 'RECIBIDO_COCINA' and c.motivo = 'Se retiró el cliente'
        and c.producto_nombre = 'Ceviche' and c.cancelado_por_nombre = 'Mozo T05') <> 1 then
    raise exception 'E7-TP19: lectura de cancelaciones del mozo';
  end if;
  -- kitchen snapshot conserva la cancelación del pedido ABIERTO
  perform pg_temp.e7_set_user(v_cocina);
  if not (public.rpc_obtener_tablero_cocina() -> 'cancelaciones') @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('detalle_id', v_a)) then
    raise exception 'E7-TP19: cancelación no visible para cocina';
  end if;
  perform pg_temp.e7_set_user(v_mozo);
  select * into strict r from public.liberar_mesa_pedido_vacio(v_p3);
  if (select estado from public.mesa where id = v_m[3]) <> 'LIBRE' then raise exception 'E7-TP16: liberar mesa falló'; end if;
  -- agregar tras cancelación total (otro pedido)
  select pedido_id into strict v_p4 from public.crear_o_recuperar_pedido_mesa(v_m[4]);
  select detalle_id into strict v_a from public.agregar_detalle_pedido(v_p4, v_cev, 1, null);
  perform public.enviar_pedido_cocina(v_p4);
  perform public.rpc_cancelar_detalle_pedido(v_a, 'x');
  perform public.agregar_detalle_pedido(v_p4, v_chi, 1, null);
  if (select estado from public.pedido where id = v_p4) <> 'ABIERTO' then raise exception 'E7-TP16: agregar tras vaciado'; end if;
  -- rpc_obtener_cancelaciones_pedido: roles
  perform pg_temp.e7_set_user(v_cocina);
  if pg_temp.e7_sqlstate(format('select public.rpc_obtener_cancelaciones_pedido(%s)', v_p4)) <> '42501' then
    raise exception 'E7-TP25: COCINA lee cancelaciones del mozo';
  end if;
end;
$e7_t05$;

do $e7_t05_meta$
begin
  if pg_catalog.has_function_privilege('anon', 'public.rpc_cancelar_detalle_pedido(bigint,text)', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.rpc_obtener_cancelaciones_pedido(bigint)', 'EXECUTE')
    or not exists (select 1 from pg_catalog.pg_proc where oid = 'public.rpc_cancelar_detalle_pedido(bigint,text)'::regprocedure
                   and prosecdef and proconfig @> array['search_path=pg_catalog'])
    or pg_catalog.pg_get_functiondef('public.rpc_cancelar_detalle_pedido(bigint,text)'::regprocedure) ~ '40001' then
    raise exception 'E7-TP26: metadatos de cancelación inesperados';
  end if;
end $e7_t05_meta$;

rollback;
