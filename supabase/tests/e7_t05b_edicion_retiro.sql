-- E7-T05B — Verificación focal: edición vía RPC con semántica H3 (TP11) y retiro vía RPC con
-- corrección de HZ-01 (TP12), más privilegios sustituidos (parte TP26).
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
  execute p_sql; return 'OK';
exception when others then return sqlstate;
end $$;

do $e7_t05b$
declare
  v_mozo uuid := '00000000-0000-0000-0000-0000000e75b1';
  v_cocina uuid := '00000000-0000-0000-0000-0000000e75b2';
  v_mozo2 uuid := '00000000-0000-0000-0000-0000000e75b3';
  v_local uuid := '00000000-0000-0000-0000-0000000e75b4';
  v_local2 uuid := '00000000-0000-0000-0000-0000000e75b5';
  v_m1 uuid := '00000000-0000-0000-0000-0000000e75b6';
  v_m2 uuid := '00000000-0000-0000-0000-0000000e75b7';
  v_m3 uuid := '00000000-0000-0000-0000-0000000e75b8';
  v_cat uuid := '00000000-0000-0000-0000-0000000e75b9';
  v_cev uuid := '00000000-0000-0000-0000-0000000e75ba';
  v_chi uuid := '00000000-0000-0000-0000-0000000e75bb';
  v_p bigint; v_p2 bigint; v_p3 bigint; v_a bigint; v_b bigint; v_c bigint; r record; v_mod timestamptz; v_creado uuid;
begin
  insert into auth.users (id, aud, role, email, encrypted_password) values
    (v_mozo, 'authenticated', 'authenticated', 'e7-t05b-m@example.invalid', 't'),
    (v_cocina, 'authenticated', 'authenticated', 'e7-t05b-c@example.invalid', 't'),
    (v_mozo2, 'authenticated', 'authenticated', 'e7-t05b-o@example.invalid', 't');
  insert into public.local (id, codigo, nombre) values (v_local, 'E7-T5B', 'Local'), (v_local2, 'E7-T5B2', 'Otro');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo, v_local, id, 'Mozo' from public.rol where codigo = 'MOZO'
  union all select v_cocina, v_local, id, 'Cocina' from public.rol where codigo = 'COCINA'
  union all select v_mozo2, v_local2, id, 'Mozo otro' from public.rol where codigo = 'MOZO';
  insert into public.mesa (id, local_id, codigo, nombre) values (v_m1, v_local, '5B-1', 'M1'), (v_m2, v_local, '5B-2', 'M2'), (v_m3, v_local, '5B-3', 'M3');
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, '5B', 'Cat');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
    (v_cev, v_local, v_cat, 'CEV', 'Ceviche', 30, true), (v_chi, v_local, v_cat, 'CHI', 'Chicha', 8, false);

  -- ===== TP11: edición parcial con semántica H3
  perform pg_temp.e7_set_user(v_mozo);
  select pedido_id into strict v_p from public.crear_o_recuperar_pedido_mesa(v_m1);
  select detalle_id into strict v_a from public.agregar_detalle_pedido(v_p, v_cev, 1, null);
  select detalle_id into strict v_b from public.agregar_detalle_pedido(v_p, v_cev, 1, 'sin ají');
  select creado_por, modificado_en into v_creado, v_mod from public.pedido where id = v_p;
  -- sólo cantidad, con esperado
  select * into strict r from public.rpc_modificar_detalle_pedido(v_a, 3, null, 1, null);
  if r.cantidad <> 3 or r.observacion is not null then raise exception 'E7-TP11: cantidad %', r; end if;
  -- sólo observación (trim), con esperado "sin observación" ('')
  select * into strict r from public.rpc_modificar_detalle_pedido(v_a, null, '  Sin cebolla ', null, '');
  if r.observacion <> 'Sin cebolla' or r.cantidad <> 3 then raise exception 'E7-TP11: observación %', r; end if;
  -- observación vacía => sin observación
  select * into strict r from public.rpc_modificar_detalle_pedido(v_a, null, '   ', null, 'Sin cebolla');
  if r.observacion is not null then raise exception 'E7-TP11: observación vacía no eliminó'; end if;
  -- no consolida con otra línea igual ('sin ají')
  perform public.rpc_modificar_detalle_pedido(v_a, null, 'sin ají', null, null);
  if (select count(*) from public.detalle_pedido where pedido_id = v_p) <> 2 then raise exception 'E7-TP11: consolidó por edición'; end if;
  -- auditoría igual que H3: modificación comercial del pedido, creador intacto
  if (select modificado_en from public.pedido where id = v_p) <= v_mod
    or (select creado_por from public.pedido where id = v_p) <> v_creado
    or (select modificado_por from public.detalle_pedido where id = v_a) <> v_mozo then
    raise exception 'E7-TP11: auditoría distinta de H3';
  end if;
  -- validaciones
  if pg_temp.e7_sqlstate(format('select public.rpc_modificar_detalle_pedido(%s, 0, null, null, null)', v_a)) <> '22023'
    or pg_temp.e7_sqlstate(format('select public.rpc_modificar_detalle_pedido(%s, -2, null, null, null)', v_a)) <> '22023' then
    raise exception 'E7-TP11: cantidad inválida aceptada';
  end if;
  -- esperado obsoleto => PT409 sin cambios
  if pg_temp.e7_sqlstate(format('select public.rpc_modificar_detalle_pedido(%s, 5, null, 1, null)', v_a)) <> 'PT409'
    or pg_temp.e7_sqlstate(format('select public.rpc_modificar_detalle_pedido(%s, null, %L, null, %L)', v_a, 'x', 'otra')) <> 'PT409'
    or (select cantidad from public.detalle_pedido where id = v_a) <> 3 then
    raise exception 'E7-TP11: conflicto optimista no detectado';
  end if;
  -- total recalculado desde persistencia
  if (select sum(cantidad * precio_unitario) from public.detalle_pedido where pedido_id = v_p) <> 120 then
    raise exception 'E7-TP11: total inesperado';
  end if;
  -- detalle enviado no editable ni retirable
  perform public.enviar_pedido_cocina(v_p);
  if pg_temp.e7_sqlstate(format('select public.rpc_modificar_detalle_pedido(%s, 4, null, null, null)', v_a)) <> 'PT409'
    or pg_temp.e7_sqlstate(format('select public.rpc_retirar_detalle_pedido(%s)', v_a)) <> 'PT409' then
    raise exception 'E7-TP11/TP12: detalle enviado editable o retirable';
  end if;
  -- otro local / otro rol
  perform pg_temp.e7_set_user(v_mozo2);
  if pg_temp.e7_sqlstate(format('select public.rpc_modificar_detalle_pedido(%s, 2, null, null, null)', v_a)) <> '42501'
    or pg_temp.e7_sqlstate(format('select public.rpc_retirar_detalle_pedido(%s)', v_a)) <> '42501' then
    raise exception 'E7-TP25: otro local pudo editar/retirar';
  end if;
  perform pg_temp.e7_set_user(v_cocina);
  if pg_temp.e7_sqlstate(format('select public.rpc_modificar_detalle_pedido(%s, 2, null, null, null)', v_a)) <> '42501'
    or pg_temp.e7_sqlstate(format('select public.rpc_retirar_detalle_pedido(%s)', v_a)) <> '42501' then
    raise exception 'E7-TP25: COCINA pudo editar/retirar';
  end if;

  -- ===== TP12: retiro normal y corrección HZ-01
  perform pg_temp.e7_set_user(v_mozo);
  select pedido_id into strict v_p2 from public.crear_o_recuperar_pedido_mesa(v_m2);
  select detalle_id into strict v_a from public.agregar_detalle_pedido(v_p2, v_cev, 1, null);
  perform public.enviar_pedido_cocina(v_p2);
  perform pg_temp.e7_set_user(v_cocina);
  perform public.rpc_recibir_pedido_cocina(v_p2);
  perform public.actualizar_estado_detalle_cocina(v_a, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  perform public.actualizar_estado_detalle_cocina(v_a, 'EN_PREPARACION', 'LISTO');
  perform pg_temp.e7_set_user(v_mozo);
  perform public.entregar_pedido(v_p2);
  select detalle_id into strict v_b from public.agregar_detalle_pedido(v_p2, v_cev, 1, 'nuevo');  -- reapertura H5
  if (select estado from public.pedido where id = v_p2) <> 'ABIERTO' then raise exception 'E7-TP12: reapertura esperada'; end if;
  select * into strict r from public.rpc_retirar_detalle_pedido(v_b);
  if r.pedido_estado <> 'LISTO' or r.mesa_estado <> 'PEDIDO_LISTO'
    or (select estado from public.pedido where id = v_p2) <> 'LISTO'
    or (select estado from public.mesa where id = v_m2) <> 'PEDIDO_LISTO' then
    raise exception 'E7-TP12: HZ-01 no corregido %', r;
  end if;
  select * into strict r from public.entregar_pedido(v_p2);
  if r.pedido_estado <> 'ENTREGADO' then raise exception 'E7-TP12: no se pudo volver a entregar'; end if;
  -- pedido con otros detalles enviados: cabecera derivada correcta tras retiro
  select pedido_id into strict v_p3 from public.crear_o_recuperar_pedido_mesa(v_m3);
  perform public.agregar_detalle_pedido(v_p3, v_cev, 1, null);
  perform public.enviar_pedido_cocina(v_p3);
  select detalle_id into strict v_c from public.agregar_detalle_pedido(v_p3, v_chi, 1, null);
  if (select estado from public.pedido where id = v_p3) <> 'ABIERTO' then raise exception 'E7-TP12: previo inesperado'; end if;
  select * into strict r from public.rpc_retirar_detalle_pedido(v_c);
  if r.pedido_estado <> 'ENVIADO' or (select estado from public.pedido where id = v_p3) <> 'ENVIADO' then
    raise exception 'E7-TP12: cabecera no derivada tras retiro %', r;
  end if;
  -- detalle inexistente / reintento => PT409
  if pg_temp.e7_sqlstate(format('select public.rpc_retirar_detalle_pedido(%s)', v_c)) <> 'PT409' then
    raise exception 'E7-TP12: reintento de retiro no devolvió PT409';
  end if;
end;
$e7_t05b$;

do $e7_t05b_vacio$
declare
  v_mozo uuid := '00000000-0000-0000-0000-0000000e75b1';
  v_m uuid := '00000000-0000-0000-0000-0000000e75bc';
  v_local uuid := '00000000-0000-0000-0000-0000000e75b4';
  v_cev uuid := '00000000-0000-0000-0000-0000000e75ba';
  v_p bigint; v_a bigint; r record;
begin
  insert into public.mesa (id, local_id, codigo, nombre) values (v_m, v_local, '5B-4', 'M4');
  perform pg_temp.e7_set_user(v_mozo);
  select pedido_id into strict v_p from public.crear_o_recuperar_pedido_mesa(v_m);
  select detalle_id into strict v_a from public.agregar_detalle_pedido(v_p, v_cev, 2, null);
  select * into strict r from public.rpc_retirar_detalle_pedido(v_a);
  if r.pedido_estado <> 'ABIERTO' or r.mesa_estado <> 'OCUPADA' or exists (select 1 from public.detalle_pedido where pedido_id = v_p) then
    raise exception 'E7-TP12: retiro del último detalle %', r;
  end if;
  perform public.liberar_mesa_pedido_vacio(v_p);
  if (select estado from public.mesa where id = v_m) <> 'LIBRE' then raise exception 'E7-TP12: liberar tras retiro'; end if;
end $e7_t05b_vacio$;

-- Privilegios: mutación directa sustituida (E7-D15)
do $e7_t05b_meta$
begin
  if pg_catalog.has_table_privilege('authenticated', 'public.detalle_pedido', 'DELETE')
    or pg_catalog.has_column_privilege('authenticated', 'public.detalle_pedido', 'cantidad', 'UPDATE')
    or pg_catalog.has_column_privilege('authenticated', 'public.detalle_pedido', 'observacion', 'UPDATE')
    or exists (select 1 from pg_catalog.pg_policy where polrelid = 'public.detalle_pedido'::regclass
               and polname in ('detalle_pedido_update_abierto_mozo', 'detalle_pedido_delete_abierto_mozo'))
    or not pg_catalog.has_table_privilege('authenticated', 'public.detalle_pedido', 'SELECT')
    or pg_catalog.has_function_privilege('anon', 'public.rpc_retirar_detalle_pedido(bigint)', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.rpc_modificar_detalle_pedido(bigint,integer,text,integer,text)', 'EXECUTE')
    or not exists (select 1 from pg_catalog.pg_proc where oid = 'public.rpc_retirar_detalle_pedido(bigint)'::regprocedure
                   and prosecdef and proconfig @> array['search_path=pg_catalog']) then
    raise exception 'E7-TP26: privilegios de edición/retiro inesperados';
  end if;
end $e7_t05b_meta$;

-- UPDATE/DELETE directos como authenticated ahora denegados
set local role authenticated;
do $e7_t05b_directo$
declare v_ok boolean;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000e75b1', true);
  begin update public.detalle_pedido set cantidad = 9 where false; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'E7-TP11: UPDATE directo permitido'; end if;
  begin delete from public.detalle_pedido where false; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'E7-TP12: DELETE directo permitido'; end if;
end $e7_t05b_directo$;
reset role;

rollback;
