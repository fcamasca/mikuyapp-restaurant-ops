-- E9-T03 — Verificación focal de RPC y lecturas: apertura (TP03), idempotencia (TP04), fecha
-- operativa / correlativo / medianoche (TP05), cierre y rechazos (TP10), pendientes (TP11),
-- estado actual e historial (TP12), seguridad y catálogo (TP14) y trazabilidad (TP15).
-- Fixture propia como postgres en una transacción que termina con ROLLBACK.
begin;

create function pg_temp.as_user(p_user_id uuid) returns void
language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

-- Ejecuta p_sql como authenticated; devuelve 'OK' o 'SQLSTATE:mensaje'.
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

create function pg_temp.code(p_result text) returns text
language sql immutable as $$ select split_part(p_result, ':', 1) $$;

create function pg_temp.abrir(p_admin uuid, p_key uuid) returns record
language plpgsql set search_path = pg_catalog as $$
declare r record;
begin
  perform pg_temp.as_user(p_admin);
  select * into strict r from public.rpc_abrir_jornada_operativa(p_key);
  return r;
end $$;

create function pg_temp.cerrar(p_admin uuid, p_id bigint) returns record
language plpgsql set search_path = pg_catalog as $$
declare r record;
begin
  perform pg_temp.as_user(p_admin);
  select * into strict r from public.rpc_cerrar_jornada_operativa(p_id);
  return r;
end $$;

-- ===== TP14: catálogo de seguridad de las RPC
do $e9_t03_catalogo$
begin
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in (
        'rpc_abrir_jornada_operativa', 'rpc_cerrar_jornada_operativa', 'rpc_obtener_jornada_operativa_actual',
        'rpc_obtener_pendientes_cierre_jornada', 'rpc_obtener_historial_jornadas_operativas')
      and p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres' and p.proconfig = array['search_path=pg_catalog']
      and has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('service_role', p.oid, 'execute')
      and obj_description(p.oid, 'pg_proc') is not null) <> 5 then
    raise exception 'E9-TP14: RPC con seguridad, privilegios o comentarios inesperados';
  end if;
  if (select string_agg(p.proname || ':' || p.provolatile::text, ',' order by p.proname) from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.proname like 'rpc_%jornada%')
    is distinct from 'rpc_abrir_jornada_operativa:v,rpc_cerrar_jornada_operativa:v,rpc_obtener_historial_jornadas_operativas:s,'
      || 'rpc_obtener_jornada_operativa_actual:s,rpc_obtener_pendientes_cierre_jornada:s' then
    raise exception 'E9-TP14: volatilidad inesperada';
  end if;
  if exists (select 1 from pg_proc p where p.proname = 'fn_formatear_identificacion_jornada'
      and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
        or p.provolatile <> 'i')) then
    raise exception 'E9-TP14: función de identificación expuesta o no inmutable';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
      and pg_get_functiondef(p.oid) ~ 'errcode\s*=\s*''40001''') then
    raise exception 'E9-TP14: aparece 40001 manual en una función vigente';
  end if;
end;
$e9_t03_catalogo$;

do $e9_t03$
declare
  v_admin uuid := '00000000-0000-0000-0000-0000000e9301';
  v_admin2 uuid := '00000000-0000-0000-0000-0000000e9302';
  v_mozo uuid := '00000000-0000-0000-0000-0000000e9303';
  v_coc uuid := '00000000-0000-0000-0000-0000000e9304';
  v_caja uuid := '00000000-0000-0000-0000-0000000e9305';
  v_inact uuid := '00000000-0000-0000-0000-0000000e9306';
  v_admin_b uuid := '00000000-0000-0000-0000-0000000e9307';
  v_caja_b uuid := '00000000-0000-0000-0000-0000000e9308';
  v_local uuid := '00000000-0000-0000-0000-0000000e9311';
  v_local_b uuid := '00000000-0000-0000-0000-0000000e9312';
  v_caja_id uuid := '00000000-0000-0000-0000-0000000e9313';
  v_cat uuid := '00000000-0000-0000-0000-0000000e9314';
  v_chi uuid := '00000000-0000-0000-0000-0000000e9315';
  v_k1 uuid := '00000000-0000-0000-0000-0000000e9321';
  v_k2 uuid := '00000000-0000-0000-0000-0000000e9322';
  v_m uuid[] := array(select ('00000000-0000-0000-0000-0000000e93' || lpad(g::text, 2, '0'))::uuid from generate_series(31, 40) g);
  v_hoy date := (clock_timestamp() at time zone 'America/Lima')::date;
  v_ayer timestamptz := ((clock_timestamp() at time zone 'America/Lima')::date - 1 + time '21:00') at time zone 'America/Lima';
  r record; r2 record; v_j bigint; v_jm bigint; v_p bigint; v_p2 bigint; v_p3 bigint; v_p4 bigint; v_s jsonb; v_res text;
  v_estado text; v_desc uuid; v_n bigint;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  select u, 'authenticated', 'authenticated', 'e9-t03-' || u || '@example.invalid', 't'
  from unnest(array[v_admin, v_admin2, v_mozo, v_coc, v_caja, v_inact, v_admin_b, v_caja_b]) u;
  insert into public.local (id, codigo, nombre) values (v_local, 'E9-T03', 'Local T03'), (v_local_b, 'E9-T03-B', 'Otro');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre, activo)
  select v_admin, v_local, id, 'Ana Admin', true from public.rol where codigo = 'ADMINISTRADOR'
  union all select v_admin2, v_local, id, 'Beto Admin', true from public.rol where codigo = 'ADMINISTRADOR'
  union all select v_mozo, v_local, id, 'Mozo', true from public.rol where codigo = 'MOZO'
  union all select v_coc, v_local, id, 'Cocina', true from public.rol where codigo = 'COCINA'
  union all select v_caja, v_local, id, 'Caja', true from public.rol where codigo = 'CAJA'
  union all select v_inact, v_local, id, 'Inactivo', false from public.rol where codigo = 'ADMINISTRADOR'
  union all select v_admin_b, v_local_b, id, 'Admin B', true from public.rol where codigo = 'ADMINISTRADOR'
  union all select v_caja_b, v_local_b, id, 'Caja B', true from public.rol where codigo = 'CAJA';
  insert into public.mesa (id, local_id, codigo, nombre)
  select v_m[g], v_local, 'T3-' || g, 'Mesa ' || g from generate_series(1, 10) g;
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'T3', 'Carta');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina)
  values (v_chi, v_local, v_cat, 'CHI', 'Chicha', 10, false);
  insert into public.caja (id, local_id, codigo, nombre) values (v_caja_id, v_local, 'T3', 'Caja T3');

  -- ===== TP03: rechazos de apertura y apertura válida
  if pg_temp.code(pg_temp.try_as(v_mozo, format('select * from public.rpc_abrir_jornada_operativa(%L)', v_k1))) <> '42501'
    or pg_temp.code(pg_temp.try_as(v_coc, format('select * from public.rpc_abrir_jornada_operativa(%L)', v_k1))) <> '42501'
    or pg_temp.code(pg_temp.try_as(v_caja, format('select * from public.rpc_abrir_jornada_operativa(%L)', v_k1))) <> '42501'
    or pg_temp.code(pg_temp.try_as(v_inact, format('select * from public.rpc_abrir_jornada_operativa(%L)', v_k1))) <> '42501'
    or pg_temp.code(pg_temp.try_as(null, format('select * from public.rpc_abrir_jornada_operativa(%L)', v_k1))) <> '42501'
    or pg_temp.code(pg_temp.try_as(v_admin, 'select * from public.rpc_abrir_jornada_operativa(null)')) <> '22023' then
    raise exception 'E9-TP03: rechazos de apertura inesperados';
  end if;
  if exists (select 1 from public.jornada_operativa where local_id = v_local) then
    raise exception 'E9-TP03: un rechazo creó filas';
  end if;
  r := pg_temp.abrir(v_admin, v_k1);
  select * into strict r2 from public.jornada_operativa where id = r.jornada_operativa_id;
  if r.ya_existia or r.estado <> 'ABIERTA' or r.numero <> 1 or r.fecha_operativa <> v_hoy
    or r.identificacion <> 'Jornada ' || to_char(v_hoy, 'YYYY-MM-DD') || ' (1)'
    or r2.local_id <> v_local or r2.abierta_por <> v_admin or r2.fecha_operativa <> (r2.abierta_en at time zone 'America/Lima')::date
    or r2.abierta_en > clock_timestamp() or r2.idempotency_key <> v_k1 then
    raise exception 'E9-TP03: apertura válida inesperada % / %', r, r2;
  end if;
  v_j := r.jornada_operativa_id;

  -- ===== TP04: idempotencia
  r := pg_temp.abrir(v_admin, v_k1);
  if not r.ya_existia or r.jornada_operativa_id <> v_j then raise exception 'E9-TP04: misma clave'; end if;
  r := pg_temp.abrir(v_admin, v_k2);
  if not r.ya_existia or r.jornada_operativa_id <> v_j then raise exception 'E9-TP04: otra clave con abierta'; end if;
  r := pg_temp.abrir(v_admin2, v_k1);
  if not r.ya_existia or r.jornada_operativa_id <> v_j then raise exception 'E9-TP04: otro ADMIN con abierta'; end if;
  if (select count(*) from public.jornada_operativa where local_id = v_local) <> 1 then
    raise exception 'E9-TP04: la idempotencia creó filas';
  end if;

  -- ===== TP12: estado actual para los cuatro roles; otro local sin filas
  for v_res in select unnest(array[v_admin::text, v_mozo::text, v_coc::text, v_caja::text]) loop
    perform pg_temp.as_user(v_res::uuid);
    select * into strict r from public.rpc_obtener_jornada_operativa_actual();
    if r.jornada_operativa_id <> v_j or r.abierta_por_nombre <> 'Ana Admin' or r.numero <> 1
      or r.identificacion <> 'Jornada ' || to_char(v_hoy, 'YYYY-MM-DD') || ' (1)' or r.servidor_ahora is null then
      raise exception 'E9-TP12: estado actual inesperado para %: %', v_res, r;
    end if;
  end loop;
  perform pg_temp.as_user(v_caja_b);
  if exists (select 1 from public.rpc_obtener_jornada_operativa_actual()) then
    raise exception 'E9-TP12: otro local ve la jornada';
  end if;
  if pg_temp.code(pg_temp.try_as(null, 'select * from public.rpc_obtener_jornada_operativa_actual()')) <> '42501'
    or pg_temp.code(pg_temp.try_as(v_inact, 'select * from public.rpc_obtener_jornada_operativa_actual()')) <> '42501' then
    raise exception 'E9-TP12: lectura sin contexto válido no rechazada';
  end if;
  -- TP14: pendientes e historial sólo ADMIN
  if pg_temp.code(pg_temp.try_as(v_mozo, 'select * from public.rpc_obtener_pendientes_cierre_jornada()')) <> '42501'
    or pg_temp.code(pg_temp.try_as(v_caja, 'select * from public.rpc_obtener_historial_jornadas_operativas()')) <> '42501'
    or pg_temp.code(pg_temp.try_as(v_coc, format('select * from public.rpc_cerrar_jornada_operativa(%s)', v_j))) <> '42501'
    or pg_temp.code(pg_temp.try_as(v_admin, 'select * from public.rpc_obtener_historial_jornadas_operativas(0, 0)')) <> '22023'
    or pg_temp.code(pg_temp.try_as(v_admin, 'select * from public.rpc_obtener_historial_jornadas_operativas(201, 0)')) <> '22023'
    or pg_temp.code(pg_temp.try_as(v_admin, 'select * from public.rpc_obtener_historial_jornadas_operativas(10, -1)')) <> '22023' then
    raise exception 'E9-TP14: matriz de roles de lecturas o cierre inesperada';
  end if;

  -- ===== TP10 / TP11: cierre con pendientes, cada bloqueo por separado
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p from public.crear_o_recuperar_pedido_mesa(v_m[1]);   -- ABIERTO vacío
  perform pg_temp.as_user(v_admin);
  select count(*) into v_n from public.rpc_obtener_pendientes_cierre_jornada() x
  where x.tipo = 'PEDIDO' and x.pedido_id = v_p and x.mesa_codigo = 'T3-1' and x.estado = 'ABIERTO' and x.desde is not null;
  if v_n <> 1 then raise exception 'E9-TP11: pendiente de pedido no listado'; end if;
  v_res := pg_temp.try_as(v_admin, format('select * from public.rpc_cerrar_jornada_operativa(%s)', v_j));
  if v_res <> 'PT409:No se puede cerrar la jornada: 1 pedidos pendientes y 0 sesiones de caja abiertas' then
    raise exception 'E9-TP10: cierre con pedido ABIERTO vacío: %', v_res;
  end if;
  foreach v_estado in array array['ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO', 'ENTREGADO'] loop
    perform pg_temp.as_user(null);
    update public.pedido set estado = v_estado where id = v_p;
    if pg_temp.code(pg_temp.try_as(v_admin, format('select * from public.rpc_cerrar_jornada_operativa(%s)', v_j))) <> 'PT409' then
      raise exception 'E9-TP10: cierre admitido con pedido %', v_estado;
    end if;
  end loop;
  perform pg_temp.as_user(null);
  update public.pedido set estado = 'ABIERTO' where id = v_p;
  -- Resolución con operación vigente H3: liberar mesa con pedido vacío (ANULADO).
  perform pg_temp.as_user(v_mozo);
  perform public.liberar_mesa_pedido_vacio(v_p);
  -- Sesión de caja abierta bloquea
  perform pg_temp.as_user(v_caja);
  v_s := public.rpc_abrir_sesion_caja(v_caja_id, 0, gen_random_uuid());
  perform pg_temp.as_user(v_admin);
  if (select count(*) from public.rpc_obtener_pendientes_cierre_jornada() x where x.tipo = 'SESION_CAJA'
      and x.sesion_caja_id = (v_s->>'id')::uuid and x.caja_codigo = 'T3' and x.abierta_por_nombre = 'Caja') <> 1 then
    raise exception 'E9-TP11: pendiente de sesión no listado';
  end if;
  v_res := pg_temp.try_as(v_admin, format('select * from public.rpc_cerrar_jornada_operativa(%s)', v_j));
  if v_res <> 'PT409:No se puede cerrar la jornada: 0 pedidos pendientes y 1 sesiones de caja abiertas' then
    raise exception 'E9-TP10: cierre con sesión abierta: %', v_res;
  end if;
  -- ENTREGADO con cobro parcial, con solicitud de cuenta y con descuento pendiente
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p2 from public.crear_o_recuperar_pedido_mesa(v_m[2]);
  perform public.agregar_detalle_pedido(v_p2, v_chi, 2, null);
  perform public.enviar_pedido_cocina(v_p2);
  perform public.entregar_pedido(v_p2);
  perform public.rpc_solicitar_cuenta_pedido(v_p2);
  select pedido_id into strict v_p3 from public.crear_o_recuperar_pedido_mesa(v_m[3]);
  perform public.agregar_detalle_pedido(v_p3, v_chi, 1, null);
  perform public.enviar_pedido_cocina(v_p3);
  perform public.entregar_pedido(v_p3);
  perform pg_temp.as_user(v_caja);
  perform public.rpc_registrar_cobro_pedido(v_p2, (v_s->>'id')::uuid, 'PARCIAL',
    '[{"medio":"YAPE","importe":5,"propina":0}]'::jsonb, gen_random_uuid());
  perform public.rpc_solicitar_descuento_pedido(v_p3, 1, null, 'Prueba E9', gen_random_uuid());
  v_res := pg_temp.try_as(v_admin, format('select * from public.rpc_cerrar_jornada_operativa(%s)', v_j));
  if v_res <> 'PT409:No se puede cerrar la jornada: 2 pedidos pendientes y 1 sesiones de caja abiertas' then
    raise exception 'E9-TP10: cierre con cobro parcial/solicitud/descuento: %', v_res;
  end if;
  perform pg_temp.as_user(v_admin);
  if (select count(*) from public.rpc_obtener_pendientes_cierre_jornada()) <> 3 then
    raise exception 'E9-TP11: cantidad de pendientes inesperada';
  end if;
  -- Resolución con operaciones vigentes: cobro total (E1), anulación (E1), cierre de caja (E1).
  perform pg_temp.as_user(v_caja);
  perform public.rpc_registrar_cobro_pedido(v_p2, (v_s->>'id')::uuid, 'TOTAL',
    '[{"medio":"EFECTIVO","importe":15,"propina":0}]'::jsonb, gen_random_uuid());
  perform pg_temp.as_user(v_admin);
  perform public.anular_pedido_supervisado(v_p3, 'Prueba E9', gen_random_uuid());
  if (select string_agg(estado, ',' order by id) from public.solicitud_cuenta where pedido_id = v_p2) <> 'ATENDIDA' then
    raise exception 'E9-TP10: la solicitud no quedó atendida por el cobro (E10)';
  end if;
  perform pg_temp.as_user(v_caja);
  perform public.fn_cerrar_sesion_caja((v_s->>'id')::uuid, 15, null, gen_random_uuid(), false);
  -- Sin pendientes: el cierre procede
  perform pg_temp.as_user(v_admin);
  if exists (select 1 from public.rpc_obtener_pendientes_cierre_jornada()) then
    raise exception 'E9-TP11: quedan pendientes tras resolver';
  end if;
  if pg_temp.code(pg_temp.try_as(v_admin_b, format('select * from public.rpc_cerrar_jornada_operativa(%s)', v_j))) <> '42501'
    or pg_temp.code(pg_temp.try_as(v_admin, 'select * from public.rpc_cerrar_jornada_operativa(-1)')) <> '42501'
    or pg_temp.code(pg_temp.try_as(v_admin, 'select * from public.rpc_cerrar_jornada_operativa(null)')) <> '22023' then
    raise exception 'E9-TP10: cierre de otro local, inexistente o nulo no rechazado';
  end if;
  r := pg_temp.cerrar(v_admin2, v_j);
  select * into strict r2 from public.jornada_operativa where id = v_j;
  if r.ya_estaba_cerrada or r.estado <> 'CERRADA' or r2.cerrada_por <> v_admin2 or r2.cerrada_en < r2.abierta_en then
    raise exception 'E9-TP10: cierre válido inesperado %', r;
  end if;
  r := pg_temp.cerrar(v_admin, v_j);
  if not r.ya_estaba_cerrada or r.cerrada_por <> v_admin2 or r.cerrada_en <> r2.cerrada_en then
    raise exception 'E9-TP10: repetición del cierre no idempotente %', r;
  end if;
  -- Local cerrado: lectura vacía para todos; creación rechazada
  perform pg_temp.as_user(v_mozo);
  if exists (select 1 from public.rpc_obtener_jornada_operativa_actual()) then
    raise exception 'E9-TP12: local cerrado devuelve jornada';
  end if;
  perform pg_temp.as_user(v_admin);
  if exists (select 1 from public.rpc_obtener_pendientes_cierre_jornada()) then
    raise exception 'E9-TP11: pendientes con local cerrado';
  end if;

  -- ===== TP04 (tras cierre) y TP05: correlativo en la misma fecha; misma clave devuelve la cerrada
  r := pg_temp.abrir(v_admin, v_k1);
  if not r.ya_existia or r.jornada_operativa_id <> v_j or r.estado <> 'CERRADA' then
    raise exception 'E9-TP04: la misma clave tras el cierre abrió otra jornada %', r;
  end if;
  r := pg_temp.abrir(v_admin, gen_random_uuid());
  if r.ya_existia or r.numero <> 2 or r.fecha_operativa <> v_hoy then raise exception 'E9-TP05: segunda jornada %', r; end if;
  perform pg_temp.cerrar(v_admin, r.jornada_operativa_id);
  r := pg_temp.abrir(v_admin2, gen_random_uuid());
  if r.numero <> 3 or r.identificacion <> 'Jornada ' || to_char(v_hoy, 'YYYY-MM-DD') || ' (3)' then
    raise exception 'E9-TP05: tercera jornada %', r;
  end if;
  perform pg_temp.cerrar(v_admin2, r.jornada_operativa_id);
  r := pg_temp.abrir(v_admin_b, gen_random_uuid());
  if r.numero <> 1 then raise exception 'E9-TP05: el otro local no numera de forma independiente'; end if;
  perform pg_temp.cerrar(v_admin_b, r.jornada_operativa_id);

  -- TP05: cruce de medianoche con fixture coherente (abierta ayer 21:00 Lima)
  perform pg_temp.as_user(null);
  insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
  values (v_local, v_hoy - 1, 1, v_admin, v_ayer, gen_random_uuid()) returning id into v_jm;
  perform pg_temp.as_user(v_mozo);
  select pedido_id into strict v_p4 from public.crear_o_recuperar_pedido_mesa(v_m[4]);
  perform pg_temp.as_user(v_caja);
  v_s := public.rpc_abrir_sesion_caja(v_caja_id, 0, gen_random_uuid());
  if (select jornada_operativa_id from public.pedido where id = v_p4) <> v_jm
    or (v_s->>'jornada_operativa_id')::bigint <> v_jm then
    raise exception 'E9-TP05: lo creado hoy no pertenece a la jornada abierta ayer';
  end if;
  perform pg_temp.as_user(v_mozo);
  select * into strict r from public.rpc_obtener_jornada_operativa_actual();
  if r.identificacion <> 'Jornada ' || to_char(v_hoy - 1, 'YYYY-MM-DD') || ' (1)' then
    raise exception 'E9-TP05: la identificación cambió al cruzar la medianoche %', r;
  end if;
  perform public.liberar_mesa_pedido_vacio(v_p4);
  perform pg_temp.as_user(v_caja);
  perform public.fn_cerrar_sesion_caja((v_s->>'id')::uuid, 0, null, gen_random_uuid(), false);
  r := pg_temp.cerrar(v_admin, v_jm);
  if r.estado <> 'CERRADA' or r.cerrada_en <= r.abierta_en then raise exception 'E9-TP05: cierre tras medianoche %', r; end if;
  r := pg_temp.abrir(v_admin, gen_random_uuid());
  if r.numero <> 4 or r.fecha_operativa <> v_hoy then raise exception 'E9-TP05: numeración tras medianoche %', r; end if;

  -- ===== TP12: historial (orden, nombres, paginación, sin totales)
  perform pg_temp.as_user(v_admin);
  if (select string_agg(x.identificacion || '|' || x.estado || '|' || x.abierta_por_nombre || '|' || coalesce(x.cerrada_por_nombre, '-'), ';')
      from public.rpc_obtener_historial_jornadas_operativas(50, 0) x)
    <> format('Jornada %1$s (4)|ABIERTA|Ana Admin|-;Jornada %1$s (3)|CERRADA|Beto Admin|Beto Admin;Jornada %1$s (2)|CERRADA|Ana Admin|Ana Admin;'
      || 'Jornada %1$s (1)|CERRADA|Ana Admin|Beto Admin;Jornada %2$s (1)|CERRADA|Ana Admin|Ana Admin', to_char(v_hoy, 'YYYY-MM-DD'), to_char(v_hoy - 1, 'YYYY-MM-DD')) then
    raise exception 'E9-TP12: historial inesperado %', (select string_agg(x.identificacion, ';') from public.rpc_obtener_historial_jornadas_operativas(50, 0) x);
  end if;
  if (select count(*) from public.rpc_obtener_historial_jornadas_operativas(2, 3)) <> 2
    or (select min(x.identificacion) from public.rpc_obtener_historial_jornadas_operativas(1, 4) x)
      <> 'Jornada ' || to_char(v_hoy - 1, 'YYYY-MM-DD') || ' (1)' then
    raise exception 'E9-TP12: paginación inesperada';
  end if;
  if pg_get_function_result('public.rpc_obtener_historial_jornadas_operativas(integer,integer)'::regprocedure)
    ~* '(total|importe|venta|monto|cantidad|count)' then
    raise exception 'E9-TP12/R25: el historial expone totales o conteos';
  end if;
  perform pg_temp.as_user(v_admin_b);
  if (select count(*) from public.rpc_obtener_historial_jornadas_operativas()) <> 1 then
    raise exception 'E9-TP12: historial cruzado entre locales';
  end if;

  -- ===== TP15: trazabilidad reconstruible e invariantes I-2/I-3/I-4 en toda la base
  if exists (select 1 from public.pedido p join public.jornada_operativa j on j.id = p.jornada_operativa_id
        where p.estado not in ('PAGADO', 'ANULADO') and j.estado <> 'ABIERTA')
    or exists (select 1 from public.sesion_caja s join public.jornada_operativa j on j.id = s.jornada_operativa_id
        where s.estado = 'ABIERTA' and j.estado <> 'ABIERTA')
    or exists (select 1 from public.pago g join public.pedido p on p.id = g.pedido_id join public.sesion_caja s on s.id = g.sesion_caja_id
        where p.jornada_operativa_id <> s.jornada_operativa_id)
    or exists (select 1 from public.pedido p where p.local_id <> (select local_id from public.jornada_operativa where id = p.jornada_operativa_id)) then
    raise exception 'E9-TP15: invariantes I-2/I-3/I-4 violadas';
  end if;
  if (select count(distinct x.jornada) from (
        select p.jornada_operativa_id as jornada from public.detalle_pedido d join public.pedido p on p.id = d.pedido_id where p.id = v_p2
        union all select p.jornada_operativa_id from public.historial_estado h join public.pedido p on p.id = h.pedido_id where p.id = v_p2
        union all select p.jornada_operativa_id from public.solicitud_cuenta c join public.pedido p on p.id = c.pedido_id where p.id = v_p2
        union all select s.jornada_operativa_id from public.cobro c join public.sesion_caja s on s.id = c.sesion_caja_id where c.pedido_id = v_p2
        union all select p.jornada_operativa_id from public.pago g join public.pedido p on p.id = g.pedido_id where p.id = v_p2
        union all select p.jornada_operativa_id from public.descuento_pedido d join public.pedido p on p.id = d.pedido_id where p.id = v_p3
        union all select p.jornada_operativa_id from public.anulacion_pedido a join public.pedido p on p.id = a.pedido_id where p.id = v_p3
        union all select s.jornada_operativa_id from public.resumen_cierre_sesion_caja rc join public.sesion_caja s on s.id = rc.sesion_caja_id
          where s.jornada_operativa_id = v_j
        union all select s.jornada_operativa_id from public.auditoria_caja a join public.sesion_caja s on s.id = a.sesion_caja_id
          where s.jornada_operativa_id = v_j
      ) x) <> 1 then
    raise exception 'E9-TP15: la jornada no se deriva unívocamente de pedido/sesión';
  end if;
  if (select count(*) from public.jornada_operativa where id = v_j and abierta_por = v_admin and cerrada_por = v_admin2
      and abierta_en is not null and cerrada_en is not null) <> 1 then
    raise exception 'E9-TP15: apertura/cierre sin actor u hora';
  end if;
end;
$e9_t03$;

rollback;
