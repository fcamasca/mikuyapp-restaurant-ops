-- E7-T03 — Verificación focal: snapshot/consolidación (TP03), sin cocina (parte SQL TP05),
-- pedido mixto (parte SQL TP06), comandas (TP22) e historial ENVIO (parte TP20).
begin;

create function pg_temp.e7_set_user(p_user_id uuid) returns void
language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

do $e7_t03$
declare
  v_mozo uuid := '00000000-0000-0000-0000-0000000e7031';
  v_local uuid := '00000000-0000-0000-0000-0000000e7032';
  v_m1 uuid := '00000000-0000-0000-0000-0000000e7033';
  v_m2 uuid := '00000000-0000-0000-0000-0000000e7034';
  v_m3 uuid := '00000000-0000-0000-0000-0000000e7035';
  v_cat uuid := '00000000-0000-0000-0000-0000000e7036';
  v_ceviche uuid := '00000000-0000-0000-0000-0000000e7037';
  v_arroz uuid := '00000000-0000-0000-0000-0000000e7038';
  v_chicha uuid := '00000000-0000-0000-0000-0000000e7039';
  v_p1 bigint; v_p2 bigint; v_p3 bigint;
  v_d1 bigint; v_d2 bigint; v_d3 bigint; v_d4 bigint;
  r record; v_n bigint; v_lineas jsonb;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values (v_mozo, 'authenticated', 'authenticated', 'e7-t03@example.invalid', 'test');
  insert into public.local (id, codigo, nombre) values (v_local, 'E7-T03', 'Local E7 T03');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo, v_local, id, 'Mozo E7' from public.rol where codigo = 'MOZO';
  insert into public.mesa (id, local_id, codigo, nombre) values
    (v_m1, v_local, 'E7-1', 'Mesa 1'), (v_m2, v_local, 'E7-2', 'Mesa 2'), (v_m3, v_local, 'E7-3', 'Mesa 3');
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'E7', 'Cat');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
    (v_ceviche, v_local, v_cat, 'CEV', 'Ceviche', 30, true),
    (v_arroz, v_local, v_cat, 'ARR', 'Arroz', 25, true),
    (v_chicha, v_local, v_cat, 'CHI', 'Chicha', 8, false);

  perform pg_temp.e7_set_user(v_mozo);

  -- ===== TP05 (SQL): pedido sólo con productos sin cocina
  select pedido_id into strict v_p1 from public.crear_o_recuperar_pedido_mesa(v_m1);
  select detalle_id into strict v_d1 from public.agregar_detalle_pedido(v_p1, v_chicha, 2, null);
  if (select requiere_cocina from public.detalle_pedido where id = v_d1) then
    raise exception 'E7-TP03: snapshot sin cocina no copiado';
  end if;
  select * into strict r from public.enviar_pedido_cocina(v_p1);
  if r.detalles_enviados <> 1 or r.pedido_estado <> 'LISTO' then
    raise exception 'E7-TP05: envío sólo bebidas inesperado %', r;
  end if;
  if not exists (select 1 from public.detalle_pedido where id = v_d1 and estado = 'LISTO' and enviado_en is not null)
    or (select estado from public.mesa where id = v_m1) <> 'PEDIDO_LISTO' then
    raise exception 'E7-TP05: detalle/mesa sin cocina inesperados';
  end if;
  select count(*) into v_n from public.historial_estado where pedido_id = v_p1 and estado_anterior = 'ABIERTO' and estado_nuevo = 'LISTO';
  if v_n <> 1 or exists (select 1 from public.historial_estado where pedido_id = v_p1 and estado_nuevo = 'ENVIADO') then
    raise exception 'E7-TP05: historial de cabecera inesperado';
  end if;
  if exists (select 1 from public.comanda where pedido_id = v_p1) then
    raise exception 'E7-TP05/TP22: pedido sin cocina generó comanda';
  end if;
  if not exists (select 1 from public.historial_detalle_pedido where detalle_id = v_d1 and operacion = 'ENVIO'
      and estado_anterior = 'ABIERTO' and estado_nuevo = 'LISTO' and not requiere_cocina and usuario_id = v_mozo) then
    raise exception 'E7-TP20: ENVIO sin cocina no registrado';
  end if;
  -- entrega H5 funciona sin cambios
  select * into strict r from public.entregar_pedido(v_p1);
  if r.pedido_estado <> 'ENTREGADO' or r.mesa_estado <> 'PENDIENTE_PAGO' then raise exception 'E7-TP05: entrega falló'; end if;

  -- ===== TP06 (SQL) + TP22: pedido mixto, comanda sólo con líneas de cocina
  select pedido_id into strict v_p2 from public.crear_o_recuperar_pedido_mesa(v_m2);
  select detalle_id into strict v_d2 from public.agregar_detalle_pedido(v_p2, v_ceviche, 1, 'sin ají');
  select detalle_id into strict v_d3 from public.agregar_detalle_pedido(v_p2, v_arroz, 2, null);
  select detalle_id into strict v_d4 from public.agregar_detalle_pedido(v_p2, v_chicha, 1, null);
  select * into strict r from public.enviar_pedido_cocina(v_p2);
  if r.detalles_enviados <> 3 or r.pedido_estado <> 'ENVIADO' then raise exception 'E7-TP06: envío mixto %', r; end if;
  if (select estado from public.detalle_pedido where id = v_d2) <> 'ENVIADO'
    or (select estado from public.detalle_pedido where id = v_d4) <> 'LISTO'
    or (select estado from public.mesa where id = v_m2) <> 'OCUPADA'
    or (select count(distinct enviado_en) from public.detalle_pedido where pedido_id = v_p2) <> 1 then
    raise exception 'E7-TP06: estados mixtos inesperados';
  end if;
  select count(*) into v_n from public.comanda where pedido_id = v_p2;
  select lineas into v_lineas from public.comanda where pedido_id = v_p2 and numero = 1;
  if v_n <> 1 or pg_catalog.jsonb_array_length(v_lineas) <> 2
    or v_lineas @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('detalle_id', v_d4))
    or not v_lineas @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('detalle_id', v_d2, 'producto_nombre', 'Ceviche', 'cantidad', 1, 'observacion', 'sin ají'))
    or (select creado_por from public.comanda where pedido_id = v_p2) <> v_mozo
    or (select impresiones from public.comanda where pedido_id = v_p2) <> 0 then
    raise exception 'E7-TP22: comanda 1 inesperada %', v_lineas;
  end if;
  -- envío repetido sin ABIERTO: sin comanda ni historial
  select * into strict r from public.enviar_pedido_cocina(v_p2);
  if r.detalles_enviados <> 0 or (select count(*) from public.comanda where pedido_id = v_p2) <> 1 then
    raise exception 'E7-TP22: reenvío generó comanda';
  end if;
  -- agregado posterior de cocina -> comanda 2 sólo con línea nueva
  select detalle_id into strict v_d1 from public.agregar_detalle_pedido(v_p2, v_ceviche, 3, null);
  perform public.enviar_pedido_cocina(v_p2);
  select lineas into v_lineas from public.comanda where pedido_id = v_p2 and numero = 2;
  if v_lineas is null or pg_catalog.jsonb_array_length(v_lineas) <> 1
    or (v_lineas -> 0 ->> 'detalle_id')::bigint <> v_d1 then
    raise exception 'E7-TP22: comanda 2 inesperada';
  end if;
  -- agregado posterior sólo bebida -> sin comanda nueva
  perform public.agregar_detalle_pedido(v_p2, v_chicha, 1, 'helada');
  perform public.enviar_pedido_cocina(v_p2);
  if (select count(*) from public.comanda where pedido_id = v_p2) <> 2 then
    raise exception 'E7-TP22: bebida posterior generó comanda';
  end if;
  -- ceviche avanza a LISTO: el pedido sólo queda LISTO cuando terminan los de cocina (sin transiciones: estados)
  if (select estado from public.pedido where id = v_p2) <> 'ENVIADO' then
    raise exception 'E7-TP06: pedido mixto debería seguir ENVIADO';
  end if;

  -- ===== TP03: snapshot y consolidación ante cambio de catálogo
  select pedido_id into strict v_p3 from public.crear_o_recuperar_pedido_mesa(v_m3);
  select detalle_id into strict v_d1 from public.agregar_detalle_pedido(v_p3, v_arroz, 1, null);
  update public.producto set requiere_cocina = false where id = v_arroz;   -- ADMIN cambia catálogo
  select detalle_id into strict v_d2 from public.agregar_detalle_pedido(v_p3, v_arroz, 1, null);
  if v_d1 = v_d2 then raise exception 'E7-TP03: consolidó condiciones distintas'; end if;
  select detalle_id into strict v_d3 from public.agregar_detalle_pedido(v_p3, v_arroz, 2, null);
  if v_d3 <> v_d2 or (select cantidad from public.detalle_pedido where id = v_d2) <> 3 then
    raise exception 'E7-TP03: no consolidó misma condición';
  end if;
  perform public.enviar_pedido_cocina(v_p3);
  if (select estado from public.detalle_pedido where id = v_d1) <> 'ENVIADO'
    or (select estado from public.detalle_pedido where id = v_d2) <> 'LISTO' then
    raise exception 'E7-TP03: el envío no respetó el snapshot de creación';
  end if;
  -- cambio posterior no altera detalles registrados
  update public.producto set requiere_cocina = true where id = v_arroz;
  if (select requiere_cocina from public.detalle_pedido where id = v_d2)
    or not (select requiere_cocina from public.detalle_pedido where id = v_d1) then
    raise exception 'E7-TP03: snapshot alterado por el catálogo';
  end if;
end;
$e7_t03$;

rollback;
