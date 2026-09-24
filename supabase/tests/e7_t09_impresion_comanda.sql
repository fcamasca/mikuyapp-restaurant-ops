-- E7-T09 — Verificación focal: solicitudes de impresión (TP23), sin efecto en estados (parte SQL TP24)
-- y columnas de impresión como única mutación de la comanda (parte TP21).
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

do $e7_t09$
declare
  v_mozo uuid := '00000000-0000-0000-0000-0000000e7091';
  v_c1 uuid := '00000000-0000-0000-0000-0000000e7092';
  v_c2 uuid := '00000000-0000-0000-0000-0000000e7093';
  v_caja uuid := '00000000-0000-0000-0000-0000000e7094';
  v_otro uuid := '00000000-0000-0000-0000-0000000e7095';
  v_local uuid := '00000000-0000-0000-0000-0000000e7096';
  v_local2 uuid := '00000000-0000-0000-0000-0000000e7097';
  v_mesa uuid := '00000000-0000-0000-0000-0000000e7098';
  v_cat uuid := '00000000-0000-0000-0000-0000000e7099';
  v_cev uuid := '00000000-0000-0000-0000-0000000e709a';
  v_p bigint; v_com bigint; v_d bigint; r record;
  v_antes text; v_despues text; v_hist_antes bigint; v_mod timestamptz; v_lineas jsonb;
begin
  insert into auth.users (id, aud, role, email, encrypted_password) values
    (v_mozo, 'authenticated', 'authenticated', 'e7-t09-m@example.invalid', 't'),
    (v_c1, 'authenticated', 'authenticated', 'e7-t09-c1@example.invalid', 't'),
    (v_c2, 'authenticated', 'authenticated', 'e7-t09-c2@example.invalid', 't'),
    (v_caja, 'authenticated', 'authenticated', 'e7-t09-k@example.invalid', 't'),
    (v_otro, 'authenticated', 'authenticated', 'e7-t09-o@example.invalid', 't');
  insert into public.local (id, codigo, nombre) values (v_local, 'E7-T09', 'Local T09'), (v_local2, 'E7-T09B', 'Otro');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo, v_local, id, 'Mozo' from public.rol where codigo = 'MOZO'
  union all select v_c1, v_local, id, 'Cocina 1' from public.rol where codigo = 'COCINA'
  union all select v_c2, v_local, id, 'Cocina 2' from public.rol where codigo = 'COCINA'
  union all select v_caja, v_local, id, 'Caja' from public.rol where codigo = 'CAJA'
  union all select v_otro, v_local2, id, 'Cocina otro' from public.rol where codigo = 'COCINA';
  insert into public.mesa (id, local_id, codigo, nombre) values (v_mesa, v_local, 'T9', 'Mesa T9');
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'T9', 'Cat');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio) values (v_cev, v_local, v_cat, 'CEV', 'Ceviche', 30);

  perform pg_temp.e7_set_user(v_mozo);
  select pedido_id into strict v_p from public.crear_o_recuperar_pedido_mesa(v_mesa);
  select detalle_id into strict v_d from public.agregar_detalle_pedido(v_p, v_cev, 2, 'sin ají');
  perform public.enviar_pedido_cocina(v_p);
  select id, lineas into strict v_com, v_lineas from public.comanda where pedido_id = v_p and numero = 1;

  -- Estado operativo antes de imprimir
  select string_agg(d.id || ':' || d.estado || ':' || d.modificado_en, ',' order by d.id) || '|' || p.estado || ':' || p.modificado_en || '|' || m.estado
  into v_antes
  from public.pedido p join public.mesa m on m.id = p.mesa_id join public.detalle_pedido d on d.pedido_id = p.id
  where p.id = v_p group by p.estado, p.modificado_en, m.estado;
  select count(*) into v_hist_antes from public.historial_estado where pedido_id = v_p;

  -- TP23: reimpresión antes de la primera => PT409
  perform pg_temp.e7_set_user(v_c1);
  if pg_temp.e7_sqlstate(format('select public.rpc_registrar_impresion_comanda(%s, true)', v_com)) <> 'PT409' then
    raise exception 'E7-TP23: reimpresión sin primera impresión aceptada';
  end if;
  -- primera solicitud
  select * into strict r from public.rpc_registrar_impresion_comanda(v_com, false);
  if r.impresiones <> 1 or r.es_reimpresion or r.numero <> 1 or r.pedido_id <> v_p then raise exception 'E7-TP23: primera impresión %', r; end if;
  if not exists (select 1 from public.comanda where id = v_com and primera_impresion_por = v_c1 and ultima_impresion_por = v_c1
                 and primera_impresion_en is not null and impresiones = 1) then
    raise exception 'E7-TP23: trazabilidad de primera solicitud';
  end if;
  -- segunda "primera" desde otra sesión => PT409 y sin cambios
  perform pg_temp.e7_set_user(v_c2);
  if pg_temp.e7_sqlstate(format('select public.rpc_registrar_impresion_comanda(%s, false)', v_com)) <> 'PT409'
    or (select impresiones from public.comanda where id = v_com) <> 1 then
    raise exception 'E7-TP23: segunda primera impresión no rechazada';
  end if;
  -- dos reimpresiones => impresiones = 3, última por c2, primera se conserva
  select * into strict r from public.rpc_registrar_impresion_comanda(v_com, true);
  if r.impresiones <> 2 or not r.es_reimpresion then raise exception 'E7-TP23: reimpresión 1 %', r; end if;
  select * into strict r from public.rpc_registrar_impresion_comanda(v_com, true);
  if r.impresiones <> 3 then raise exception 'E7-TP23: reimpresión 2 %', r; end if;
  if not exists (select 1 from public.comanda where id = v_com and impresiones = 3 and primera_impresion_por = v_c1
                 and ultima_impresion_por = v_c2 and ultima_impresion_en >= primera_impresion_en
                 and lineas = v_lineas and numero = 1) then
    raise exception 'E7-TP23/TP21: trazabilidad o contenido alterados';
  end if;

  -- TP24: estados operativos intactos, sin historial
  select string_agg(d.id || ':' || d.estado || ':' || d.modificado_en, ',' order by d.id) || '|' || p.estado || ':' || p.modificado_en || '|' || m.estado
  into v_despues
  from public.pedido p join public.mesa m on m.id = p.mesa_id join public.detalle_pedido d on d.pedido_id = p.id
  where p.id = v_p group by p.estado, p.modificado_en, m.estado;
  if v_antes is distinct from v_despues
    or (select count(*) from public.historial_estado where pedido_id = v_p) <> v_hist_antes
    or exists (select 1 from public.historial_detalle_pedido where pedido_id = v_p and operacion <> 'ENVIO') then
    raise exception 'E7-TP24: la impresión alteró estados (% -> %)', v_antes, v_despues;
  end if;

  -- Tablero expone la cuenta de impresiones
  if ((public.rpc_obtener_tablero_cocina() -> 'comandas') -> 0 ->> 'impresiones')::int <> 3 then
    raise exception 'E7-TP23: tablero sin impresiones actualizadas';
  end if;

  -- Seguridad: otros roles/local
  perform pg_temp.e7_set_user(v_mozo);
  if pg_temp.e7_sqlstate(format('select public.rpc_registrar_impresion_comanda(%s, true)', v_com)) <> '42501' then raise exception 'E7-TP25: MOZO imprimió'; end if;
  perform pg_temp.e7_set_user(v_caja);
  if pg_temp.e7_sqlstate(format('select public.rpc_registrar_impresion_comanda(%s, true)', v_com)) <> '42501' then raise exception 'E7-TP25: CAJA imprimió'; end if;
  perform pg_temp.e7_set_user(v_otro);
  if pg_temp.e7_sqlstate(format('select public.rpc_registrar_impresion_comanda(%s, true)', v_com)) <> '42501' then raise exception 'E7-TP25: otro local imprimió'; end if;

  -- Pedido fuera de cocina => PT409 (no se imprime)
  update public.pedido set estado = 'ANULADO' where id = v_p;
  perform pg_temp.e7_set_user(v_c1);
  if pg_temp.e7_sqlstate(format('select public.rpc_registrar_impresion_comanda(%s, true)', v_com)) <> 'PT409' then
    raise exception 'E7-TP23: pedido fuera de cocina aceptó impresión';
  end if;
end;
$e7_t09$;

do $e7_t09_meta$
begin
  if pg_catalog.has_function_privilege('anon', 'public.rpc_registrar_impresion_comanda(bigint,boolean)', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.rpc_registrar_impresion_comanda(bigint,boolean)', 'EXECUTE')
    or not exists (select 1 from pg_catalog.pg_proc where oid = 'public.rpc_registrar_impresion_comanda(bigint,boolean)'::regprocedure
                   and prosecdef and proconfig @> array['search_path=pg_catalog'])
    or pg_catalog.pg_get_functiondef('public.rpc_registrar_impresion_comanda(bigint,boolean)'::regprocedure) ~ '40001' then
    raise exception 'E7-TP26: metadatos de impresión inesperados';
  end if;
end $e7_t09_meta$;

rollback;
