-- E7-T05B — Reproducción de HZ-01 sobre la baseline previa a E7 (retiro H3 por DELETE directo).
-- Ejecutar SOLO sobre una base con migraciones hasta 20260922000100 (antes de E7). Termina con ROLLBACK.
-- Resultado esperado en la baseline: NOTICE 'HZ-01 REPRODUCIDO' (pedido ABIERTO/mesa OCUPADA con todo LISTO).
begin;
do $hz01$
declare
  v_mozo uuid := '00000000-0000-0000-0000-0000000e7b01';
  v_cocina uuid := '00000000-0000-0000-0000-0000000e7b02';
  v_local uuid := '00000000-0000-0000-0000-0000000e7b03';
  v_mesa uuid := '00000000-0000-0000-0000-0000000e7b04';
  v_cat uuid := '00000000-0000-0000-0000-0000000e7b05';
  v_prod uuid := '00000000-0000-0000-0000-0000000e7b06';
  v_p bigint; v_d bigint; v_nuevo bigint;
begin
  insert into auth.users (id, aud, role, email, encrypted_password) values
    (v_mozo, 'authenticated', 'authenticated', 'hz01-m@example.invalid', 't'),
    (v_cocina, 'authenticated', 'authenticated', 'hz01-c@example.invalid', 't');
  insert into public.local (id, codigo, nombre) values (v_local, 'HZ01', 'HZ01');
  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_mozo, v_local, id, 'Mozo' from public.rol where codigo = 'MOZO'
  union all select v_cocina, v_local, id, 'Cocina' from public.rol where codigo = 'COCINA';
  insert into public.mesa (id, local_id, codigo, nombre) values (v_mesa, v_local, 'HZ', 'Mesa HZ');
  insert into public.categoria (id, local_id, codigo, nombre) values (v_cat, v_local, 'HZ', 'Cat');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio) values (v_prod, v_local, v_cat, 'HZ', 'Plato', 10);

  perform set_config('request.jwt.claim.sub', v_mozo::text, true);
  select pedido_id into v_p from public.crear_o_recuperar_pedido_mesa(v_mesa);
  select detalle_id into v_d from public.agregar_detalle_pedido(v_p, v_prod, 1, null);
  perform public.enviar_pedido_cocina(v_p);
  perform set_config('request.jwt.claim.sub', v_cocina::text, true);
  perform public.actualizar_estado_detalle_cocina(v_d, 'ENVIADO', 'RECIBIDO_COCINA');
  perform public.actualizar_estado_detalle_cocina(v_d, 'RECIBIDO_COCINA', 'EN_PREPARACION');
  perform public.actualizar_estado_detalle_cocina(v_d, 'EN_PREPARACION', 'LISTO');
  perform set_config('request.jwt.claim.sub', v_mozo::text, true);
  perform public.entregar_pedido(v_p);
  select detalle_id into v_nuevo from public.agregar_detalle_pedido(v_p, v_prod, 1, 'nuevo');  -- reapertura H5
  perform set_config('hz01.p', v_p::text, true);
  perform set_config('hz01.d', v_nuevo::text, true);
end $hz01$;

-- Retiro H3 tal como lo ejecuta el cliente: DELETE directo como authenticated bajo RLS.
set local role authenticated;
delete from public.detalle_pedido where id = current_setting('hz01.d')::bigint and estado = 'ABIERTO';
reset role;

do $hz01_check$
declare v_p bigint := current_setting('hz01.p')::bigint; v_pe text; v_me text; v_all boolean;
begin
  select p.estado, m.estado into v_pe, v_me from public.pedido p join public.mesa m on m.id = p.mesa_id where p.id = v_p;
  select bool_and(estado = 'LISTO') into v_all from public.detalle_pedido where pedido_id = v_p;
  if v_pe = 'ABIERTO' and v_me = 'OCUPADA' and v_all then
    raise notice 'HZ-01 REPRODUCIDO: pedido %, mesa %, todos los detalles LISTO', v_pe, v_me;
  else
    raise notice 'HZ-01 no reproducido: pedido %, mesa %, todos LISTO %', v_pe, v_me, v_all;
  end if;
end $hz01_check$;
rollback;
