-- E9-T02 — Verificación focal: estructura y catálogo (TP01), creación con y sin jornada por
-- toda vía (TP06), asignación por servidor e inmutabilidad de la asociación (TP07), coherencia
-- pedido/sesión en el cobro (TP09) e inmutabilidad de la jornada (TP13, parte de modelo).
-- Fixtures propias como postgres en una transacción que termina con ROLLBACK.
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
  execute p_sql;
  return 'OK';
exception when others then
  return sqlstate;
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

-- Jornada ABIERTA válida insertada como owner (fixture; la RPC de apertura se prueba en T03).
create function pg_temp.abrir_jornada(p_local uuid, p_admin uuid) returns bigint
language plpgsql set search_path = pg_catalog as $$
declare v_id bigint; v_ahora timestamptz := pg_catalog.clock_timestamp();
begin
  insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
  values (p_local, (v_ahora at time zone 'America/Lima')::date,
    coalesce((select max(numero) from public.jornada_operativa
      where local_id = p_local and fecha_operativa = (v_ahora at time zone 'America/Lima')::date), 0) + 1,
    p_admin, v_ahora, gen_random_uuid())
  returning id into v_id;
  return v_id;
end $$;

-- ===== TP01 (T02): estructura, privilegios, RLS, triggers, asociación y publicación
do $e9_t02_catalogo$
declare
  v_tables text[];
begin
  if (select string_agg(column_name || ':' || data_type || ':' || is_nullable, ',' order by ordinal_position)
      from information_schema.columns where table_schema = 'public' and table_name = 'jornada_operativa')
    is distinct from 'id:bigint:NO,local_id:uuid:NO,fecha_operativa:date:NO,numero:integer:NO,estado:text:NO,'
      || 'abierta_por:uuid:NO,abierta_en:timestamp with time zone:NO,cerrada_por:uuid:YES,'
      || 'cerrada_en:timestamp with time zone:YES,idempotency_key:uuid:NO' then
    raise exception 'E9-TP01: columnas inesperadas';
  end if;
  if (select count(*) from pg_constraint where conrelid = 'public.jornada_operativa'::regclass
      and conname in ('pk_jornada_operativa', 'uq_jornada_operativa_id_local_id', 'uq_jornada_operativa_local_fecha_numero',
        'uq_jornada_operativa_idempotencia', 'fk_jornada_operativa_local', 'fk_jornada_operativa_abierta_por',
        'fk_jornada_operativa_cerrada_por', 'ck_jornada_operativa_estado_valido', 'ck_jornada_operativa_numero_positivo',
        'ck_jornada_operativa_cierre_coherente', 'ck_jornada_operativa_fecha_operativa')) <> 11 then
    raise exception 'E9-TP01: restricciones incompletas';
  end if;
  if exists (select 1 from pg_constraint where conrelid in ('public.jornada_operativa'::regclass)
        and contype = 'f' and confdeltype <> 'r')
    or exists (select 1 from pg_constraint where conname in ('fk_pedido_jornada_operativa_local', 'fk_sesion_caja_jornada_operativa_local')
        and confdeltype <> 'r') then
    raise exception 'E9-TP01: toda FK debe ser ON DELETE RESTRICT';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'uq_jornada_operativa_local_abierta'
      and indexdef ilike 'CREATE UNIQUE INDEX%(local_id) WHERE (estado = ''ABIERTA''::text)')
    or not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'idx_jornada_operativa_local_abierta_en')
    or not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'idx_pedido_jornada_operativa_id_estado'
      and indexdef ilike '%(jornada_operativa_id, estado)')
    or not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'idx_sesion_caja_jornada_operativa_id_estado'
      and indexdef ilike '%(jornada_operativa_id, estado)') then
    raise exception 'E9-TP01: índices ausentes o distintos';
  end if;
  if (select string_agg(table_name || ':' || is_nullable, ',' order by table_name) from information_schema.columns
      where table_schema = 'public' and column_name = 'jornada_operativa_id')
    is distinct from 'pedido:NO,sesion_caja:NO' then
    raise exception 'E9-TP01/R19: jornada_operativa_id debe existir sólo en pedido y sesion_caja, NOT NULL';
  end if;
  if pg_get_constraintdef((select oid from pg_constraint where conname = 'fk_pedido_jornada_operativa_local'))
      <> 'FOREIGN KEY (jornada_operativa_id, local_id) REFERENCES jornada_operativa(id, local_id) ON DELETE RESTRICT'
    or pg_get_constraintdef((select oid from pg_constraint where conname = 'fk_sesion_caja_jornada_operativa_local'))
      <> 'FOREIGN KEY (jornada_operativa_id, local_id) REFERENCES jornada_operativa(id, local_id) ON DELETE RESTRICT' then
    raise exception 'E9-TP01: FK compuestas distintas';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.jornada_operativa'::regclass) then
    raise exception 'E9-TP01: RLS deshabilitado';
  end if;
  if (select string_agg(policyname || ':' || cmd, ',') from pg_policies where schemaname = 'public' and tablename = 'jornada_operativa')
    is distinct from 'pol_jornada_operativa_select_local:SELECT' then
    raise exception 'E9-TP01: políticas inesperadas';
  end if;
  if not has_table_privilege('authenticated', 'public.jornada_operativa', 'select')
    or has_table_privilege('authenticated', 'public.jornada_operativa', 'insert')
    or has_table_privilege('authenticated', 'public.jornada_operativa', 'update')
    or has_table_privilege('authenticated', 'public.jornada_operativa', 'delete')
    or has_table_privilege('authenticated', 'public.jornada_operativa', 'truncate')
    or has_table_privilege('anon', 'public.jornada_operativa', 'select')
    or has_table_privilege('service_role', 'public.jornada_operativa', 'select')
    or has_table_privilege('service_role', 'public.jornada_operativa', 'truncate')
    or has_sequence_privilege('authenticated', 'public.jornada_operativa_id_seq', 'usage')
    or has_sequence_privilege('service_role', 'public.jornada_operativa_id_seq', 'usage') then
    raise exception 'E9-TP01: privilegios de tabla o secuencia inesperados';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in (
        'tgf_jornada_operativa_inmutable', 'fn_obtener_jornada_operativa_abierta', 'tgf_pedido_asignar_jornada_operativa',
        'tgf_sesion_caja_asignar_jornada_operativa', 'tgf_pago_validar_jornada_operativa')
      and p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres' and p.proconfig = array['search_path=pg_catalog']
      and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('service_role', p.oid, 'execute')
      and obj_description(p.oid, 'pg_proc') is not null) <> 5 then
    raise exception 'E9-TP01: funciones internas o de trigger con seguridad, privilegios o comentarios inesperados';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_pedido_before_insert_update_jornada_operativa'
        and tgrelid = 'public.pedido'::regclass and pg_get_triggerdef(oid) ilike '%BEFORE INSERT OR UPDATE OF jornada_operativa_id ON public.pedido%')
    or not exists (select 1 from pg_trigger where tgname = 'trg_sesion_caja_before_insert_update_jornada_operativa'
        and tgrelid = 'public.sesion_caja'::regclass and pg_get_triggerdef(oid) ilike '%BEFORE INSERT OR UPDATE OF jornada_operativa_id ON public.sesion_caja%')
    or not exists (select 1 from pg_trigger where tgname = 'trg_pago_before_insert_validar_jornada_operativa'
        and tgrelid = 'public.pago'::regclass and pg_get_triggerdef(oid) ilike '%BEFORE INSERT ON public.pago%')
    or not exists (select 1 from pg_trigger where tgname = 'trg_jornada_operativa_before_update_delete_inmutable'
        and tgrelid = 'public.jornada_operativa'::regclass) then
    raise exception 'E9-TP01: triggers ausentes o distintos';
  end if;
  select array_agg(schemaname || '.' || tablename order by schemaname, tablename) into v_tables
  from pg_publication_tables where pubname = 'supabase_realtime';
  if v_tables is distinct from array['public.detalle_pedido', 'public.jornada_operativa', 'public.mesa', 'public.pedido', 'public.solicitud_cuenta'] then
    raise exception 'E9-TP01: publicación inesperada %', v_tables;
  end if;
  if obj_description('public.jornada_operativa'::regclass, 'pg_class') is null
    or col_description('public.jornada_operativa'::regclass, 3) is null
    or col_description('public.pedido'::regclass,
        (select attnum from pg_attribute where attrelid = 'public.pedido'::regclass and attname = 'jornada_operativa_id')) is null
    or col_description('public.sesion_caja'::regclass,
        (select attnum from pg_attribute where attrelid = 'public.sesion_caja'::regclass and attname = 'jornada_operativa_id')) is null
    or obj_description((select oid from pg_policy where polname = 'pol_jornada_operativa_select_local'), 'pg_policy') is null then
    raise exception 'E9-TP01: comentarios ausentes';
  end if;
  -- DC-10: ninguna RPC operativa existente fue modificada para validar la jornada.
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
      and (p.proname like 'rpc_%' or p.proname in ('crear_o_recuperar_pedido_mesa', 'h3_abrir_o_recuperar_pedido',
        'agregar_detalle_pedido', 'enviar_pedido_cocina', 'entregar_pedido', 'registrar_pago_pedido', 'anular_pedido_supervisado',
        'liberar_mesa_pedido_vacio', 'actualizar_estado_detalle_cocina', 'registrar_movimientos_caja', 'fn_cerrar_sesion_caja'))
      and p.proname not like '%jornada%'
      and pg_get_functiondef(p.oid) ilike '%jornada%') then
    raise exception 'E9-TP01/DC-10: una RPC operativa existente referencia la jornada';
  end if;
end;
$e9_t02_catalogo$;

-- ===== TP06, TP07, TP09, TP13 con fixture propia
do $e9_t02_asociacion$
declare
  v_mozo uuid := '00000000-0000-0000-0000-0000000e9021';
  v_caja uuid := '00000000-0000-0000-0000-0000000e9022';
  v_admin uuid := '00000000-0000-0000-0000-0000000e9023';
  v_local uuid := '00000000-0000-0000-0000-0000000e9024';
  v_local_b uuid := '00000000-0000-0000-0000-0000000e9025';
  v_admin_b uuid := '00000000-0000-0000-0000-0000000e9026';
  v_caja_id uuid := '00000000-0000-0000-0000-0000000e9027';
  v_cat uuid := '00000000-0000-0000-0000-0000000e9028';
  v_chi uuid := '00000000-0000-0000-0000-0000000e9029';
  v_m uuid[] := array['00000000-0000-0000-0000-0000000e9031','00000000-0000-0000-0000-0000000e9032',
                      '00000000-0000-0000-0000-0000000e9033','00000000-0000-0000-0000-0000000e9034']::uuid[];
  v_j1 bigint; v_j2 bigint; v_jb bigint; v_p1 bigint; v_p2 bigint; v_p3 bigint; v_s1 jsonb; v_s2 jsonb;
  v_before text; v_after text; v_state text; r record;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  select u, 'authenticated', 'authenticated', 'e9-t02-' || u || '@example.invalid', 't'
  from unnest(array[v_mozo, v_caja, v_admin, v_admin_b]) u;
  insert into public.local (id, codigo, nombre) values (v_local, 'E9-T02', 'Local E9 T02'), (v_local_b, 'E9-T02-B', 'Otro');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo, v_local, id, 'Mozo E9' from public.rol where codigo = 'MOZO'
  union all select v_caja, v_local, id, 'Caja E9' from public.rol where codigo = 'CAJA'
  union all select v_admin, v_local, id, 'Admin E9' from public.rol where codigo = 'ADMINISTRADOR'
  union all select v_admin_b, v_local_b, id, 'Admin B' from public.rol where codigo = 'ADMINISTRADOR';
  insert into public.mesa (id, local_id, codigo, nombre)
  select v_m[g], v_local, 'E9-' || g, 'Mesa ' || g from generate_series(1, 4) g;
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'E9', 'Carta');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina)
  values (v_chi, v_local, v_cat, 'CHI', 'Chicha', 8, false);
  insert into public.caja (id, local_id, codigo, nombre) values (v_caja_id, v_local, 'E9', 'Caja E9');

  -- ----- TP06: local cerrado -> toda vía de creación rechazada con PT409, sin residuos
  select md5(concat_ws('|', (select count(*) from public.pedido), (select count(*) from public.historial_estado),
    (select string_agg(estado, ',' order by id) from public.mesa where local_id = v_local),
    (select count(*) from public.sesion_caja), (select count(*) from public.solicitud_apertura_caja),
    (select count(*) from public.auditoria_caja), (select count(*) from public.notificacion_caja))) into v_before;
  if pg_temp.try_as(v_mozo, format('select * from public.crear_o_recuperar_pedido_mesa(%L)', v_m[1])) <> 'PT409'
    -- Vía heredada: en la baseline falla con 42883 (llama a h2_auth_context, renombrada; hallazgo
    -- preexistente HZ-E9-01). Se verifica que tampoco crea pedidos sin jornada.
    or pg_temp.try_as(v_mozo, format('select * from public.h3_abrir_o_recuperar_pedido(%L)', v_m[1])) not in ('PT409', '42883')
    or pg_temp.try_as(v_caja, format('select public.rpc_abrir_sesion_caja(%L, 0, gen_random_uuid())', v_caja_id)) <> 'PT409' then
    raise exception 'E9-TP06: creación sin jornada no rechazada con PT409';
  end if;
  perform pg_temp.as_user(null);
  if pg_temp.sqlstate_of(format('insert into public.pedido (local_id, mesa_id, creado_por) values (%L, %L, %L)', v_local, v_m[2], v_mozo)) <> 'PT409'
    or pg_temp.sqlstate_of(format('insert into public.sesion_caja (caja_id, local_id, abierta_por, monto_inicial, idempotency_key) values (%L, %L, %L, 0, gen_random_uuid())',
        v_caja_id, v_local, v_caja)) <> 'PT409' then
    raise exception 'E9-TP06: inserción directa sin jornada no rechazada';
  end if;
  begin
    perform public.fn_obtener_jornada_operativa_abierta(v_local);
    raise exception 'E9-TP06: sin jornada no hubo error';
  exception when sqlstate 'PT409' then
    get stacked diagnostics v_state = message_text;
    if v_state <> 'Local cerrado — el sistema no se encuentra aperturado' then
      raise exception 'E9-TP06: mensaje inesperado %', v_state;
    end if;
  end;
  select md5(concat_ws('|', (select count(*) from public.pedido), (select count(*) from public.historial_estado),
    (select string_agg(estado, ',' order by id) from public.mesa where local_id = v_local),
    (select count(*) from public.sesion_caja), (select count(*) from public.solicitud_apertura_caja),
    (select count(*) from public.auditoria_caja), (select count(*) from public.notificacion_caja))) into v_after;
  if v_before <> v_after then
    raise exception 'E9-TP06: los rechazos dejaron residuos';
  end if;

  -- Con jornada abierta: toda vía asigna la jornada del local; otro local no la usa.
  v_j1 := pg_temp.abrir_jornada(v_local, v_admin);
  v_jb := pg_temp.abrir_jornada(v_local_b, v_admin_b);
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p1 from public.crear_o_recuperar_pedido_mesa(v_m[1]);
  select pedido_id into strict v_p2 from public.crear_o_recuperar_pedido_mesa(v_m[2]);
  perform pg_temp.as_user(v_caja);
  v_s1 := public.rpc_abrir_sesion_caja(v_caja_id, 0, '00000000-0000-0000-0000-0000000e9041');
  if (select count(*) from public.pedido where id in (v_p1, v_p2) and jornada_operativa_id = v_j1) <> 2
    or (select jornada_operativa_id from public.sesion_caja where id = (v_s1->>'id')::uuid) <> v_j1
    or (v_s1->>'jornada_operativa_id')::bigint <> v_j1 then
    raise exception 'E9-TP06: la jornada asignada no es la abierta del local';
  end if;
  -- E1-R02: la recuperación idempotente de la sesión abierta sigue funcionando.
  v_s2 := public.rpc_abrir_sesion_caja(v_caja_id, 0, '00000000-0000-0000-0000-0000000e9042');
  if v_s2->>'id' <> v_s1->>'id' then
    raise exception 'E9-TP06: la recuperación de la sesión abierta cambió';
  end if;

  -- ----- TP07: asignación por servidor e inmutabilidad
  perform pg_temp.as_user(null);
  if pg_temp.sqlstate_of(format('insert into public.pedido (local_id, mesa_id, creado_por, jornada_operativa_id) values (%L, %L, %L, %s)',
      v_local, v_m[3], v_mozo, v_jb)) <> '42501' then
    raise exception 'E9-TP07: valor distinto suministrado no rechazado con 42501';
  end if;
  insert into public.pedido (local_id, mesa_id, creado_por, jornada_operativa_id)
  values (v_local, v_m[3], v_mozo, v_j1) returning id into v_p3;
  if pg_temp.sqlstate_of(format('update public.pedido set jornada_operativa_id = %s where id = %s', v_jb, v_p1)) <> '23514'
    or pg_temp.sqlstate_of(format('update public.sesion_caja set jornada_operativa_id = %s where id = %L', v_jb, v_s1->>'id')) <> '23514' then
    raise exception 'E9-TP07: la jornada de pedido o sesión no es inmutable (owner)';
  end if;
  update public.pedido set jornada_operativa_id = v_j1 where id = v_p1;  -- mismo valor: admitido
  update public.pedido set estado = 'ENTREGADO' where id = v_p3;
  update public.pedido set estado = 'ABIERTO' where id = v_p3;          -- reapertura H5 (fixture)
  update public.pedido set estado = 'ANULADO' where id = v_p3;
  if (select jornada_operativa_id from public.pedido where id = v_p3) <> v_j1 then
    raise exception 'E9-TP07: una transición cambió la jornada del pedido';
  end if;

  -- ----- TP09: coherencia pedido/sesión. Fixture controlada sin desactivar defensas:
  -- como owner se cierra J1 directamente (el cierre condicionado lo impone la RPC, que el
  -- cliente no puede eludir) para fabricar un pedido vigente de J1 y una sesión de J2.
  perform pg_temp.as_user(v_mozo);
  perform public.agregar_detalle_pedido(v_p1, v_chi, 2, null);
  perform public.enviar_pedido_cocina(v_p1);
  perform public.entregar_pedido(v_p1);
  perform pg_temp.as_user(v_caja);
  perform public.fn_cerrar_sesion_caja((v_s1->>'id')::uuid, 0, null, gen_random_uuid(), false);
  perform pg_temp.as_user(null);
  update public.jornada_operativa set estado = 'CERRADA', cerrada_por = v_admin, cerrada_en = clock_timestamp() where id = v_j1;
  v_j2 := pg_temp.abrir_jornada(v_local, v_admin);
  perform pg_temp.as_user(v_caja);
  v_s2 := public.rpc_abrir_sesion_caja(v_caja_id, 0, '00000000-0000-0000-0000-0000000e9043');
  if (v_s2->>'jornada_operativa_id')::bigint <> v_j2 or (select jornada_operativa_id from public.pedido where id = v_p1) <> v_j1 then
    raise exception 'E9-TP09: fixture inconsistente';
  end if;
  select md5(concat_ws('|', (select count(*) from public.cobro), (select count(*) from public.pago),
    (select count(*) from public.auditoria_caja), (select estado from public.pedido where id = v_p1))) into v_before;
  if pg_temp.try_as(v_caja, format('select * from public.rpc_registrar_cobro_pedido(%s, %L, ''TOTAL'', ''[{"medio":"EFECTIVO","importe":16,"propina":0}]''::jsonb, gen_random_uuid())',
        v_p1, v_s2->>'id')) <> 'PT409'
    or pg_temp.try_as(v_caja, format('select * from public.registrar_pago_pedido(%s, ''EFECTIVO'')', v_p1)) <> 'PT409'
    or pg_temp.try_as(v_caja, format('select * from public.rpc_registrar_pago_total_pedido(%s, %L, ''YAPE'', 0, gen_random_uuid())',
        v_p1, v_s2->>'id')) <> 'PT409'
    or pg_temp.try_as(v_caja, format('select * from public.rpc_registrar_pago_pedido_v2(%s, %L, 16, ''YAPE'', 0, gen_random_uuid())',
        v_p1, v_s2->>'id')) <> 'PT409' then
    raise exception 'E9-TP09: un cobro entre jornadas distintas no fue rechazado con PT409';
  end if;
  select md5(concat_ws('|', (select count(*) from public.cobro), (select count(*) from public.pago),
    (select count(*) from public.auditoria_caja), (select estado from public.pedido where id = v_p1))) into v_after;
  if v_before <> v_after then
    raise exception 'E9-TP09: un cobro rechazado dejó residuos';
  end if;
  begin
    perform pg_temp.as_user(v_caja);
    perform public.rpc_registrar_cobro_pedido(v_p1, (v_s2->>'id')::uuid, 'TOTAL',
      '[{"medio":"EFECTIVO","importe":16,"propina":0}]'::jsonb, gen_random_uuid());
  exception when sqlstate 'PT409' then
    get stacked diagnostics v_state = message_text;
    if v_state <> 'El pedido y la sesión de caja pertenecen a jornadas distintas' then
      raise exception 'E9-TP09: mensaje inesperado %', v_state;
    end if;
  end;

  -- Misma jornada: el cobro funciona como hoy (pedido de J2 con sesión de J2).
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p2 from public.crear_o_recuperar_pedido_mesa(v_m[4]);
  perform public.agregar_detalle_pedido(v_p2, v_chi, 1, null);
  perform public.enviar_pedido_cocina(v_p2);
  perform public.entregar_pedido(v_p2);
  perform pg_temp.as_user(v_caja);
  select * into strict r from public.rpc_registrar_cobro_pedido(v_p2, (v_s2->>'id')::uuid, 'TOTAL',
    '[{"medio":"EFECTIVO","importe":8,"propina":0}]'::jsonb, gen_random_uuid());
  if r.pedido_estado <> 'PAGADO' or (select jornada_operativa_id from public.pedido where id = v_p2) <> v_j2 then
    raise exception 'E9-TP09: cobro en la misma jornada alterado %', r;
  end if;

  -- ----- TP13 (modelo): inmutabilidad de la jornada
  perform pg_temp.as_user(null);
  if pg_temp.sqlstate_of(format('delete from public.jornada_operativa where id = %s', v_j1)) <> '23514'
    or pg_temp.sqlstate_of(format('update public.jornada_operativa set estado = ''ABIERTA'', cerrada_por = null, cerrada_en = null where id = %s', v_j1)) <> '23514'
    or pg_temp.sqlstate_of(format('update public.jornada_operativa set cerrada_en = clock_timestamp() where id = %s', v_j1)) <> '23514'
    or pg_temp.sqlstate_of(format('update public.jornada_operativa set numero = 9 where id = %s', v_j2)) <> '23514'
    or pg_temp.sqlstate_of(format('update public.jornada_operativa set local_id = %L where id = %s', v_local_b, v_j2)) <> '23514'
    or pg_temp.sqlstate_of(format('update public.jornada_operativa set abierta_en = abierta_en - interval ''1 minute'' where id = %s', v_j2)) <> '23514'
    or pg_temp.sqlstate_of(format('update public.jornada_operativa set idempotency_key = gen_random_uuid() where id = %s', v_j2)) <> '23514' then
    raise exception 'E9-TP13: la jornada admite cambios distintos del cierre único';
  end if;
  -- Dos abiertas por local, fecha incoherente y cierre incoherente: rechazados por constraint.
  if pg_temp.sqlstate_of(format('insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key) values (%L, (now() at time zone ''America/Lima'')::date, 99, %L, now(), gen_random_uuid())',
      v_local, v_admin)) <> '23505'
    or pg_temp.sqlstate_of(format('insert into public.jornada_operativa (local_id, fecha_operativa, numero, estado, abierta_por, abierta_en, cerrada_por, cerrada_en, idempotency_key) values (%L, ''2000-01-01'', 1, ''CERRADA'', %L, now(), %L, now(), gen_random_uuid())',
      v_local, v_admin, v_admin)) <> '23514'
    or pg_temp.sqlstate_of(format('insert into public.jornada_operativa (local_id, fecha_operativa, numero, estado, abierta_por, abierta_en, idempotency_key) values (%L, (now() at time zone ''America/Lima'')::date, 98, ''CERRADA'', %L, now(), gen_random_uuid())',
      v_local, v_admin)) <> '23514' then
    raise exception 'E9-TP13: restricciones de la jornada no aplicadas';
  end if;
  if pg_temp.try_as(v_admin, format('insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key) values (%L, current_date, 50, %L, now(), gen_random_uuid())', v_local, v_admin)) <> '42501'
    or pg_temp.try_as(v_admin, format('update public.jornada_operativa set estado = ''CERRADA'' where id = %s', v_j2)) <> '42501'
    or pg_temp.try_as(v_admin, format('delete from public.jornada_operativa where id = %s', v_j2)) <> '42501' then
    raise exception 'E9-TP13: authenticated escribe directamente la jornada';
  end if;
  -- RLS: cada rol del local lee sólo las jornadas de su local.
  perform pg_temp.as_user(v_mozo);
  set local role authenticated;
  if (select count(*) from public.jornada_operativa) <> 2
    or exists (select 1 from public.jornada_operativa where local_id <> v_local) then
    raise exception 'E9-TP01: RLS de lectura inesperada';
  end if;
  reset role;
end;
$e9_t02_asociacion$;

rollback;
