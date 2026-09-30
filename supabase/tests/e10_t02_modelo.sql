-- E10-T02 — Verificación focal: estructura y catálogo (TP01), cierre automático por transición
-- del pedido (partes SQL de TP06–TP08) e inmutabilidad (TP09). Fixtures directas como postgres.
begin;

create function pg_temp.e10_set_user(p_user_id uuid) returns void
language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

create function pg_temp.e10_sqlstate(p_sql text) returns text
language plpgsql set search_path = pg_catalog as $$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlstate;
end $$;

-- ===== TP01: estructura, privilegios, RLS, triggers y publicación
do $e10_t02_catalogo$
declare
  v_tables text[];
begin
  if (select string_agg(column_name || ':' || data_type || ':' || is_nullable, ',' order by ordinal_position)
      from information_schema.columns where table_schema = 'public' and table_name = 'solicitud_cuenta')
    is distinct from 'id:bigint:NO,local_id:uuid:NO,pedido_id:bigint:NO,estado:text:NO,solicitada_por:uuid:NO,'
      || 'solicitada_en:timestamp with time zone:NO,cerrada_en:timestamp with time zone:YES,cerrada_por:uuid:YES,'
      || 'motivo_sin_efecto:text:YES' then
    raise exception 'E10-TP01: columnas inesperadas';
  end if;
  if (select count(*) from pg_constraint where conrelid = 'public.solicitud_cuenta'::regclass
      and conname in ('pk_solicitud_cuenta', 'fk_solicitud_cuenta_local', 'fk_solicitud_cuenta_pedido',
        'fk_solicitud_cuenta_solicitada_por', 'fk_solicitud_cuenta_cerrada_por', 'ck_solicitud_cuenta_estado_valido',
        'ck_solicitud_cuenta_motivo_valido', 'ck_solicitud_cuenta_cierre_coherente')) <> 8 then
    raise exception 'E10-TP01: restricciones incompletas';
  end if;
  if exists (select 1 from pg_constraint where conrelid = 'public.solicitud_cuenta'::regclass
      and contype = 'f' and confdeltype <> 'r') then
    raise exception 'E10-TP01: toda FK debe ser ON DELETE RESTRICT';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'uq_solicitud_cuenta_pedido_pendiente'
      and indexdef ilike 'CREATE UNIQUE INDEX%(pedido_id) WHERE (estado = ''PENDIENTE''::text)') then
    raise exception 'E10-TP01: índice único parcial ausente o distinto';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'idx_solicitud_cuenta_pedido_solicitada_en') then
    raise exception 'E10-TP01: índice por pedido ausente';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.solicitud_cuenta'::regclass) then
    raise exception 'E10-TP01: RLS deshabilitado';
  end if;
  if (select string_agg(policyname || ':' || cmd, ',') from pg_policies where schemaname = 'public' and tablename = 'solicitud_cuenta')
    is distinct from 'pol_solicitud_cuenta_select_local:SELECT' then
    raise exception 'E10-TP01: políticas inesperadas';
  end if;
  if not has_table_privilege('authenticated', 'public.solicitud_cuenta', 'select')
    or has_table_privilege('authenticated', 'public.solicitud_cuenta', 'insert')
    or has_table_privilege('authenticated', 'public.solicitud_cuenta', 'update')
    or has_table_privilege('authenticated', 'public.solicitud_cuenta', 'delete')
    or has_table_privilege('authenticated', 'public.solicitud_cuenta', 'truncate')
    or has_table_privilege('anon', 'public.solicitud_cuenta', 'select')
    or has_table_privilege('service_role', 'public.solicitud_cuenta', 'select')
    or has_table_privilege('service_role', 'public.solicitud_cuenta', 'truncate')
    or has_sequence_privilege('authenticated', 'public.solicitud_cuenta_id_seq', 'usage')
    or has_sequence_privilege('service_role', 'public.solicitud_cuenta_id_seq', 'usage') then
    raise exception 'E10-TP01: privilegios de tabla o secuencia inesperados';
  end if;
  if exists (select 1 from pg_proc p where p.proname in ('tgf_solicitud_cuenta_inmutable', 'tgf_pedido_cerrar_solicitud_cuenta')
      and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('service_role', p.oid, 'execute') or not p.prosecdef
        or pg_get_userbyid(p.proowner) <> 'postgres' or p.proconfig <> array['search_path=pg_catalog'])) then
    raise exception 'E10-TP01: funciones de trigger con privilegios o seguridad inesperados';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_pedido_after_update_cerrar_solicitud_cuenta'
      and tgrelid = 'public.pedido'::regclass and pg_get_triggerdef(oid) ilike '%AFTER UPDATE OF estado%(old.estado = ''ENTREGADO''::text) AND (new.estado IS DISTINCT FROM old.estado)%') then
    raise exception 'E10-TP01: trigger de cierre ausente o con condición distinta';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_solicitud_cuenta_before_update_delete_inmutable'
      and tgrelid = 'public.solicitud_cuenta'::regclass) then
    raise exception 'E10-TP01: trigger de inmutabilidad ausente';
  end if;
  select array_agg(schemaname || '.' || tablename order by schemaname, tablename) into v_tables
  from pg_publication_tables where pubname = 'supabase_realtime';
  if v_tables is distinct from array['public.detalle_pedido', 'public.mesa', 'public.pedido', 'public.solicitud_cuenta'] then
    raise exception 'E10-TP01: publicación inesperada %', v_tables;
  end if;
  if obj_description('public.solicitud_cuenta'::regclass, 'pg_class') is null
    or col_description('public.solicitud_cuenta'::regclass, 6) is null
    or obj_description((select oid from pg_proc where proname = 'tgf_pedido_cerrar_solicitud_cuenta'), 'pg_proc') is null then
    raise exception 'E10-TP01: comentarios ausentes';
  end if;
end;
$e10_t02_catalogo$;

-- ===== TP06–TP09 (partes SQL): cierre por transición del pedido e inmutabilidad
do $e10_t02_cierre$
declare
  v_mozo uuid := '00000000-0000-0000-0000-0000000e1021';
  v_caja uuid := '00000000-0000-0000-0000-0000000e1022';
  v_admin uuid := '00000000-0000-0000-0000-0000000e1023';
  v_local uuid := '00000000-0000-0000-0000-0000000e1024';
  v_m uuid[] := array['00000000-0000-0000-0000-0000000e1031','00000000-0000-0000-0000-0000000e1032',
                      '00000000-0000-0000-0000-0000000e1033','00000000-0000-0000-0000-0000000e1034']::uuid[];
  v_p bigint[] := array[]::bigint[]; v_id bigint; v_id2 bigint; r record; i int; v_state text;
begin
  insert into auth.users (id, aud, role, email, encrypted_password) values
    (v_mozo, 'authenticated', 'authenticated', 'e10-t02-m@example.invalid', 't'),
    (v_caja, 'authenticated', 'authenticated', 'e10-t02-k@example.invalid', 't'),
    (v_admin, 'authenticated', 'authenticated', 'e10-t02-a@example.invalid', 't');
  insert into public.local (id, codigo, nombre) values (v_local, 'E10-T02', 'Local E10 T02');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo, v_local, id, 'Mozo E10' from public.rol where codigo = 'MOZO'
  union all select v_caja, v_local, id, 'Caja E10' from public.rol where codigo = 'CAJA'
  union all select v_admin, v_local, id, 'Admin E10' from public.rol where codigo = 'ADMINISTRADOR';
  insert into public.mesa (id, local_id, codigo, nombre)
  select v_m[g], v_local, 'E10-' || g, 'Mesa ' || g from generate_series(1, 4) g;
  perform pg_temp.e10_set_user(v_mozo);
  for i in 1..4 loop
    v_p := v_p || (select pedido_id from public.crear_o_recuperar_pedido_mesa(v_m[i]));
  end loop;
  -- Fixture directa: pedidos ENTREGADO / mesa PENDIENTE_PAGO (sin pasar por cocina).
  update public.pedido set estado = 'ENTREGADO' where id = any (v_p);
  update public.mesa set estado = 'PENDIENTE_PAGO' where id = any (v_m);
  insert into public.solicitud_cuenta (local_id, pedido_id, solicitada_por, solicitada_en)
  select v_local, p, v_mozo, clock_timestamp() from unnest(v_p) p;

  -- Máximo una PENDIENTE por pedido
  if pg_temp.e10_sqlstate(format('insert into public.solicitud_cuenta (local_id, pedido_id, solicitada_por, solicitada_en) values (%L, %s, %L, now())',
      v_local, v_p[1], v_mozo)) <> '23505' then
    raise exception 'E10-TP04/TP09: se admitió una segunda solicitud PENDIENTE';
  end if;
  -- Coherencia de cierre
  if pg_temp.e10_sqlstate(format('insert into public.solicitud_cuenta (local_id, pedido_id, estado, solicitada_por, solicitada_en) values (%L, %s, ''ATENDIDA'', %L, now())',
      v_local, v_p[1], v_mozo)) <> '23514' then
    raise exception 'E10-TP09: ATENDIDA sin cerrada_en admitida';
  end if;

  -- Cambios que no salen de ENTREGADO no cierran
  update public.pedido set estado = 'ENTREGADO' where id = v_p[1];
  if (select estado from public.solicitud_cuenta where pedido_id = v_p[1]) <> 'PENDIENTE' then
    raise exception 'E10-TP06: una actualización sin cambio de estado cerró la solicitud';
  end if;

  -- TP06: ENTREGADO -> PAGADO => ATENDIDA con actor CAJA
  perform pg_temp.e10_set_user(v_caja);
  update public.pedido set estado = 'PAGADO' where id = v_p[1];
  select * into strict r from public.solicitud_cuenta where pedido_id = v_p[1];
  if r.estado <> 'ATENDIDA' or r.motivo_sin_efecto is not null or r.cerrada_por <> v_caja or r.cerrada_en < r.solicitada_en then
    raise exception 'E10-TP06: cierre por pago inesperado %', r;
  end if;
  -- TP07: ENTREGADO -> ABIERTO (reapertura) => SIN_EFECTO/REAPERTURA con actor MOZO
  perform pg_temp.e10_set_user(v_mozo);
  update public.pedido set estado = 'ABIERTO' where id = v_p[2];
  select * into strict r from public.solicitud_cuenta where pedido_id = v_p[2];
  if r.estado <> 'SIN_EFECTO' or r.motivo_sin_efecto <> 'REAPERTURA' or r.cerrada_por <> v_mozo then
    raise exception 'E10-TP07: cierre por reapertura inesperado %', r;
  end if;
  -- Una nueva solicitud es posible tras volver a ENTREGADO; la anterior se conserva
  update public.pedido set estado = 'ENTREGADO' where id = v_p[2];
  if (select count(*) from public.solicitud_cuenta where pedido_id = v_p[2]) <> 1 then
    raise exception 'E10-TP07: la nueva entrega creó o reactivó solicitudes';
  end if;
  insert into public.solicitud_cuenta (local_id, pedido_id, solicitada_por, solicitada_en)
  values (v_local, v_p[2], v_mozo, clock_timestamp()) returning id into v_id2;
  if (select count(*) from public.solicitud_cuenta where pedido_id = v_p[2]) <> 2 then
    raise exception 'E10-TP07: no se conservaron ambas solicitudes';
  end if;
  -- TP08: ENTREGADO -> ANULADO => SIN_EFECTO/ANULACION con actor ADMIN
  perform pg_temp.e10_set_user(v_admin);
  update public.pedido set estado = 'ANULADO' where id = v_p[3];
  select * into strict r from public.solicitud_cuenta where pedido_id = v_p[3];
  if r.estado <> 'SIN_EFECTO' or r.motivo_sin_efecto <> 'ANULACION' or r.cerrada_por <> v_admin then
    raise exception 'E10-TP08: cierre por anulación inesperado %', r;
  end if;
  -- Cierre sin actor autenticado (mantenimiento): cerrada_por nulo permitido
  perform pg_temp.e10_set_user(null);
  update public.pedido set estado = 'PAGADO' where id = v_p[4];
  select * into strict r from public.solicitud_cuenta where pedido_id = v_p[4];
  if r.estado <> 'ATENDIDA' or r.cerrada_por is not null then
    raise exception 'E10-D05: cierre sin actor inesperado %', r;
  end if;

  -- TP09: inmutabilidad (como owner, los triggers son la defensa)
  select id into strict v_id from public.solicitud_cuenta where pedido_id = v_p[1];
  if pg_temp.e10_sqlstate(format('delete from public.solicitud_cuenta where id = %s', v_id)) <> '42501' then
    raise exception 'E10-TP09: DELETE admitido';
  end if;
  if pg_temp.e10_sqlstate(format('update public.solicitud_cuenta set estado = ''PENDIENTE'', cerrada_en = null, cerrada_por = null where id = %s', v_id)) <> '42501' then
    raise exception 'E10-TP09: reapertura ATENDIDA -> PENDIENTE admitida';
  end if;
  if pg_temp.e10_sqlstate(format('update public.solicitud_cuenta set estado = ''SIN_EFECTO'', motivo_sin_efecto = ''ANULACION'' where id = %s', v_id)) <> '42501' then
    raise exception 'E10-TP09: segundo cierre admitido';
  end if;
  if pg_temp.e10_sqlstate(format('update public.solicitud_cuenta set solicitada_en = now() - interval ''1 hour'' where id = %s', v_id2)) <> '42501'
    or pg_temp.e10_sqlstate(format('update public.solicitud_cuenta set pedido_id = %s, estado = ''ATENDIDA'', cerrada_en = now() where id = %s', v_p[1], v_id2)) <> '42501' then
    raise exception 'E10-TP09: cambio de datos de solicitud admitido';
  end if;

  -- TP09/TP14: escritura directa de authenticated denegada; lectura por RLS del local
  perform pg_temp.e10_set_user(v_mozo);
  set local role authenticated;
  v_state := pg_temp.e10_sqlstate(format('insert into public.solicitud_cuenta (local_id, pedido_id, solicitada_por, solicitada_en) values (%L, %s, %L, now())', v_local, v_p[1], v_mozo));
  if v_state <> '42501' then raise exception 'E10-TP09: INSERT directo de authenticated: %', v_state; end if;
  if pg_temp.e10_sqlstate(format('update public.solicitud_cuenta set estado = ''ATENDIDA'' where id = %s', v_id2)) <> '42501'
    or pg_temp.e10_sqlstate(format('delete from public.solicitud_cuenta where id = %s', v_id2)) <> '42501' then
    raise exception 'E10-TP09: UPDATE/DELETE directo de authenticated admitido';
  end if;
  if (select count(*) from public.solicitud_cuenta where local_id = v_local) <> 5 then
    raise exception 'E10-TP14: MOZO del local no ve las solicitudes';
  end if;
  reset role;
end;
$e10_t02_cierre$;

do $e10_t02_fin$ begin raise notice 'E10-T02 modelo: PASS'; end $e10_t02_fin$;

rollback;
