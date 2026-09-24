-- E7-T02 — Verificación focal del modelo (partes estructurales de E7-TP02, E7-TP21, E7-TP26).
begin;

do $e7_t02_estructura$
declare
  v_count bigint;
begin
  -- Columnas y defaults
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'producto' and column_name = 'requiere_cocina'
      and is_nullable = 'NO' and data_type = 'boolean' and column_default = 'true'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'detalle_pedido' and column_name = 'requiere_cocina'
      and is_nullable = 'NO' and data_type = 'boolean' and column_default = 'true'
  ) then
    raise exception 'E7-TP02: requiere_cocina ausente o sin default true';
  end if;

  -- Backfill compatible
  select count(*) into v_count from public.detalle_pedido where not requiere_cocina;
  if v_count <> 0 then raise exception 'E7-TP02: backfill distinto de true (%)', v_count; end if;
  select count(*) into v_count from public.producto where not requiere_cocina;
  if v_count <> 0 then raise exception 'E7-TP02: productos existentes cambiaron de condición'; end if;

  -- Constraint validado
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'ck_detalle_pedido_sin_cocina_estado' and convalidated
  ) then raise exception 'E7-TP02: check de coherencia ausente o no validado'; end if;

  -- Tablas nuevas con RLS y sin grants directos
  if exists (
    select 1 from pg_catalog.pg_class
    where oid in ('public.historial_detalle_pedido'::regclass, 'public.comanda'::regclass)
      and not relrowsecurity
  ) then raise exception 'E7-TP26: RLS no habilitado en tablas nuevas'; end if;
  if exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'public' and table_name in ('historial_detalle_pedido', 'comanda')
      and grantee in ('anon', 'authenticated', 'PUBLIC')
  ) or exists (
    select 1 from information_schema.column_privileges
    where table_schema = 'public' and table_name in ('historial_detalle_pedido', 'comanda')
      and grantee in ('anon', 'authenticated', 'PUBLIC')
  ) then raise exception 'E7-TP26: grants directos sobre tablas nuevas'; end if;

  -- detalle_pedido.requiere_cocina no actualizable por clientes
  if pg_catalog.has_column_privilege('authenticated', 'public.detalle_pedido', 'requiere_cocina', 'UPDATE')
    or pg_catalog.has_column_privilege('authenticated', 'public.detalle_pedido', 'requiere_cocina', 'INSERT') then
    raise exception 'E7-TP26: requiere_cocina del detalle es escribible por clientes';
  end if;
  -- producto.requiere_cocina gestionable (RLS limita a ADMINISTRADOR)
  if not pg_catalog.has_column_privilege('authenticated', 'public.producto', 'requiere_cocina', 'SELECT')
    or not pg_catalog.has_column_privilege('authenticated', 'public.producto', 'requiere_cocina', 'INSERT')
    or not pg_catalog.has_column_privilege('authenticated', 'public.producto', 'requiere_cocina', 'UPDATE')
    or pg_catalog.has_column_privilege('anon', 'public.producto', 'requiere_cocina', 'UPDATE') then
    raise exception 'E7-TP26: grants de columna de producto.requiere_cocina inesperados';
  end if;

  -- Funciones de trigger: SECURITY DEFINER, owner postgres, search_path, sin EXECUTE
  select count(*) into v_count
  from pg_catalog.pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.proname in ('tgf_historial_detalle_pedido_inmutable', 'tgf_comanda_contenido_inmutable', 'tgf_detalle_pedido_historial_estado')
    and p.prosecdef
    and p.proowner = (select oid from pg_catalog.pg_roles where rolname = 'postgres')
    and p.proconfig @> array['search_path=pg_catalog']
    and not pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
    and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_count <> 3 then raise exception 'E7-TP26: metadatos de funciones trigger incorrectos (%)', v_count; end if;

  if not exists (select 1 from pg_catalog.pg_trigger where tgname = 'trg_detalle_pedido_after_update_historial_estado')
    or not exists (select 1 from pg_catalog.pg_trigger where tgname = 'trg_historial_detalle_pedido_before_write_inmutable')
    or not exists (select 1 from pg_catalog.pg_trigger where tgname = 'trg_comanda_before_write_inmutable') then
    raise exception 'E7-TP02: triggers ausentes';
  end if;
end;
$e7_t02_estructura$;

do $e7_t02_comportamiento$
declare
  v_mozo uuid := '00000000-0000-0000-0000-0000000e7021';
  v_local uuid := '00000000-0000-0000-0000-0000000e7022';
  v_mesa uuid := '00000000-0000-0000-0000-0000000e7023';
  v_cat uuid := '00000000-0000-0000-0000-0000000e7024';
  v_prod uuid := '00000000-0000-0000-0000-0000000e7025';
  v_ok boolean;
  v_hist bigint;
  v_com bigint;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values (v_mozo, 'authenticated', 'authenticated', 'e7-t02@example.invalid', 'test');
  insert into public.local (id, codigo, nombre) values (v_local, 'E7-T02', 'Local E7 T02');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo, v_local, id, 'Mozo E7' from public.rol where codigo = 'MOZO';
  insert into public.mesa (id, local_id, codigo, nombre, estado) values (v_mesa, v_local, 'E7', 'Mesa E7', 'OCUPADA');
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'E7', 'Cat E7');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio)
  values (v_prod, v_local, v_cat, 'E7B', 'Bebida', 5);
  if (select requiere_cocina from public.producto where id = v_prod) is not true then
    raise exception 'E7-TP01: default de producto distinto de true';
  end if;
  insert into public.pedido (id, local_id, mesa_id, creado_por, estado)
  overriding system value values (-70201, v_local, v_mesa, v_mozo, 'ABIERTO');

  -- Check de coherencia: detalle sin cocina en estado de cocina rechazado
  begin
    insert into public.detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, estado, enviado_en, requiere_cocina)
    values (-70201, v_prod, 1, 5, 'ENVIADO', now(), false);
    v_ok := false;
  exception when check_violation then v_ok := true;
  end;
  if not v_ok then raise exception 'E7-TP02: check aceptó detalle sin cocina ENVIADO'; end if;

  -- Transición ABIERTO -> ENVIADO: el trigger registra ENVIO en historial con actor autenticado
  perform pg_catalog.set_config('request.jwt.claim.sub', v_mozo::text, true);
  insert into public.detalle_pedido (id, pedido_id, producto_id, cantidad, precio_unitario, estado)
  overriding system value values (-70211, -70201, v_prod, 2, 5, 'ABIERTO');
  update public.detalle_pedido set estado = 'ENVIADO', enviado_en = now() where id = -70211;
  select count(*) into v_hist from public.historial_detalle_pedido
  where detalle_id = -70211 and operacion = 'ENVIO' and estado_anterior = 'ABIERTO'
    and estado_nuevo = 'ENVIADO' and requiere_cocina and usuario_id = v_mozo and local_id = v_local;
  if v_hist <> 1 then raise exception 'E7-TP20: historial ENVIO no registrado'; end if;
  -- Cambio sin variación de estado no registra
  update public.detalle_pedido set modificado_en = modificado_en where id = -70211;
  if (select count(*) from public.historial_detalle_pedido where detalle_id = -70211) <> 1 then
    raise exception 'E7-TP20: historial ficticio sin cambio de estado';
  end if;

  -- Inmutabilidad del historial
  begin
    update public.historial_detalle_pedido set motivo = 'x' where detalle_id = -70211;
    v_ok := false;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'E7-TP21: historial modificable'; end if;
  begin
    delete from public.historial_detalle_pedido where detalle_id = -70211;
    v_ok := false;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'E7-TP21: historial eliminable'; end if;

  -- Comanda: contenido inmutable, sólo columnas de impresión
  insert into public.comanda (local_id, pedido_id, numero, enviado_en, lineas, creado_por)
  values (v_local, -70201, 1, now(), '[{"detalle_id":1}]', v_mozo) returning id into v_com;
  begin
    update public.comanda set lineas = '[{"detalle_id":2}]' where id = v_com;
    v_ok := false;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'E7-TP21: lineas de comanda modificables'; end if;
  begin
    delete from public.comanda where id = v_com;
    v_ok := false;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'E7-TP21: comanda eliminable'; end if;
  update public.comanda set impresiones = 1, primera_impresion_en = now(), primera_impresion_por = v_mozo,
    ultima_impresion_en = now(), ultima_impresion_por = v_mozo where id = v_com;
  begin
    insert into public.comanda (local_id, pedido_id, numero, enviado_en, lineas, creado_por)
    values (v_local, -70201, 2, now(), '[]', v_mozo);
    v_ok := false;
  exception when check_violation then v_ok := true;
  end;
  if not v_ok then raise exception 'E7-TP21: comanda vacía aceptada'; end if;
end;
$e7_t02_comportamiento$;

-- Acceso directo como authenticated denegado
set local role authenticated;
do $e7_t02_rol$
declare v_ok boolean;
begin
  begin
    perform 1 from public.historial_detalle_pedido limit 1; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'E7-TP26: authenticated lee historial directo'; end if;
  begin
    perform 1 from public.comanda limit 1; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'E7-TP26: authenticated lee comanda directo'; end if;
end;
$e7_t02_rol$;
reset role;

rollback;
