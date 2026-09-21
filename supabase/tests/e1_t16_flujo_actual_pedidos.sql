begin;

create function pg_temp.t16_user(p_usuario uuid)
returns void language plpgsql set search_path = pg_catalog as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_usuario::text, ''), true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

do $test$
declare
  v_admin uuid := 'e1160000-0000-0000-0000-000000000101';
  v_admin_otro uuid := 'e1160000-0000-0000-0000-000000000102';
  v_admin_vacio uuid := 'e1160000-0000-0000-0000-000000000103';
  v_caja uuid := 'e1160000-0000-0000-0000-000000000104';
  v_mozo uuid := 'e1160000-0000-0000-0000-000000000105';
  v_cocina uuid := 'e1160000-0000-0000-0000-000000000106';
  v_local uuid := 'e1160000-0000-0000-0000-000000000201';
  v_local_otro uuid := 'e1160000-0000-0000-0000-000000000202';
  v_local_vacio uuid := 'e1160000-0000-0000-0000-000000000203';
  v_ahora timestamptz := statement_timestamp();
  v_grupos jsonb;
  v_grupo jsonb;
  v_checks integer := 0;
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rpc_obtener_flujo_actual_pedidos_admin'
      and (not p.prosecdef or p.proowner <> (select oid from pg_roles where rolname = 'postgres')
        or p.proconfig <> array['search_path=pg_catalog'])
  ) then raise exception 'TP61 metadata insegura'; end if;
  if has_function_privilege('anon', 'public.rpc_obtener_flujo_actual_pedidos_admin()', 'EXECUTE')
    or has_function_privilege('public', 'public.rpc_obtener_flujo_actual_pedidos_admin()', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.rpc_obtener_flujo_actual_pedidos_admin()', 'EXECUTE')
  then raise exception 'TP61 grants incorrectos'; end if;
  v_checks := v_checks + 1;

  insert into auth.users(id, aud, role, email, encrypted_password) values
    (v_admin, 'authenticated', 'authenticated', 't16-admin@example.invalid', 'x'),
    (v_admin_otro, 'authenticated', 'authenticated', 't16-other@example.invalid', 'x'),
    (v_admin_vacio, 'authenticated', 'authenticated', 't16-empty@example.invalid', 'x'),
    (v_caja, 'authenticated', 'authenticated', 't16-cash@example.invalid', 'x'),
    (v_mozo, 'authenticated', 'authenticated', 't16-waiter@example.invalid', 'x'),
    (v_cocina, 'authenticated', 'authenticated', 't16-kitchen@example.invalid', 'x');
  insert into public.local(id, codigo, nombre) values
    (v_local, 'T16-A', 'Local T16'), (v_local_otro, 'T16-B', 'Otro local'),
    (v_local_vacio, 'T16-C', 'Local vacío');
  insert into public.perfil_usuario(id, local_id, rol_id, nombre)
    select v_admin, v_local, id, 'Admin T16' from public.rol where codigo = 'ADMINISTRADOR'
    union all select v_admin_otro, v_local_otro, id, 'Admin otro' from public.rol where codigo = 'ADMINISTRADOR'
    union all select v_admin_vacio, v_local_vacio, id, 'Admin vacío' from public.rol where codigo = 'ADMINISTRADOR'
    union all select v_caja, v_local, id, 'Caja T16' from public.rol where codigo = 'CAJA'
    union all select v_mozo, v_local, id, 'Mozo T16' from public.rol where codigo = 'MOZO'
    union all select v_cocina, v_local, id, 'Cocina T16' from public.rol where codigo = 'COCINA';

  insert into public.mesa(id, local_id, codigo, nombre, estado) values
    ('e1160000-0000-0000-0000-000000000301', v_local, 'M01', 'Mesa 1', 'OCUPADA'),
    ('e1160000-0000-0000-0000-000000000302', v_local, 'M02', 'Mesa 2', 'OCUPADA'),
    ('e1160000-0000-0000-0000-000000000303', v_local, 'M03', 'Mesa 3', 'OCUPADA'),
    ('e1160000-0000-0000-0000-000000000304', v_local, 'M04', 'Mesa 4', 'OCUPADA'),
    ('e1160000-0000-0000-0000-000000000305', v_local, 'M05', 'Mesa 5', 'PEDIDO_LISTO'),
    ('e1160000-0000-0000-0000-000000000306', v_local, 'M06', 'Mesa 6', 'PENDIENTE_PAGO'),
    ('e1160000-0000-0000-0000-000000000307', v_local, 'M07', 'Mesa 7', 'LIBRE'),
    ('e1160000-0000-0000-0000-000000000308', v_local, 'M08', 'Mesa 8', 'LIBRE'),
    ('e1160000-0000-0000-0000-000000000309', v_local_otro, 'X01', 'Mesa ajena', 'OCUPADA');
  insert into public.pedido(id, local_id, mesa_id, creado_por, estado, creado_en, enviado_en) overriding system value values
    (-11601, v_local, 'e1160000-0000-0000-0000-000000000301', v_mozo, 'ENVIADO', v_ahora - interval '30 minutes', v_ahora - interval '20 minutes'),
    (-11602, v_local, 'e1160000-0000-0000-0000-000000000302', v_mozo, 'ENVIADO', v_ahora - interval '20 minutes', v_ahora - interval '10 minutes'),
    (-11603, v_local, 'e1160000-0000-0000-0000-000000000303', v_mozo, 'EN_PREPARACION', v_ahora - interval '50 minutes', v_ahora - interval '40 minutes'),
    (-11604, v_local, 'e1160000-0000-0000-0000-000000000304', v_mozo, 'RECIBIDO_COCINA', v_ahora - interval '25 minutes', v_ahora - interval '20 minutes'),
    (-11605, v_local, 'e1160000-0000-0000-0000-000000000305', v_mozo, 'LISTO', v_ahora - interval '15 minutes', v_ahora - interval '12 minutes'),
    (-11606, v_local, 'e1160000-0000-0000-0000-000000000306', v_mozo, 'ENTREGADO', v_ahora - interval '60 minutes', v_ahora - interval '50 minutes'),
    (-11607, v_local, 'e1160000-0000-0000-0000-000000000307', v_mozo, 'PAGADO', v_ahora - interval '60 minutes', v_ahora - interval '50 minutes'),
    (-11608, v_local, 'e1160000-0000-0000-0000-000000000308', v_mozo, 'ANULADO', v_ahora - interval '60 minutes', v_ahora - interval '50 minutes'),
    (-11609, v_local_otro, 'e1160000-0000-0000-0000-000000000309', v_admin_otro, 'ENVIADO', v_ahora - interval '90 minutes', v_ahora - interval '80 minutes');
  insert into public.historial_estado(pedido_id, estado_anterior, estado_nuevo, usuario_id, creado_en) values
    (-11601, 'ABIERTO', 'ENVIADO', v_mozo, v_ahora - interval '20 minutes'),
    (-11602, 'ABIERTO', 'ENVIADO', v_mozo, v_ahora - interval '10 minutes'),
    (-11603, 'ABIERTO', 'ENVIADO', v_mozo, v_ahora - interval '40 minutes'),
    (-11603, 'ENVIADO', 'RECIBIDO_COCINA', v_cocina, v_ahora - interval '30 minutes'),
    (-11603, 'RECIBIDO_COCINA', 'EN_PREPARACION', v_cocina, v_ahora - interval '5 minutes'),
    (-11604, 'ABIERTO', 'ENVIADO', v_mozo, v_ahora - interval '20 minutes'),
    (-11604, 'ENVIADO', 'RECIBIDO_COCINA', v_cocina, v_ahora - interval '15 minutes'),
    (-11605, 'ABIERTO', 'ENVIADO', v_mozo, v_ahora - interval '12 minutes'),
    (-11605, 'ENVIADO', 'RECIBIDO_COCINA', v_cocina, v_ahora - interval '10 minutes'),
    (-11605, 'RECIBIDO_COCINA', 'EN_PREPARACION', v_cocina, v_ahora - interval '9 minutes'),
    (-11605, 'EN_PREPARACION', 'LISTO', v_cocina, v_ahora - interval '7 minutes'),
    (-11606, 'LISTO', 'ENTREGADO', v_mozo, v_ahora - interval '2 minutes'),
    (-11609, 'ABIERTO', 'ENVIADO', v_admin_otro, v_ahora - interval '80 minutes');

  perform pg_temp.t16_user(v_admin);
  select resultado.grupos into v_grupos from public.rpc_obtener_flujo_actual_pedidos_admin() resultado;
  if jsonb_array_length(v_grupos) <> 3 then raise exception 'TP59 no devolvió tres grupos'; end if;
  v_grupo := v_grupos -> 0;
  if (v_grupo ->> 'cantidad')::integer <> 2
    or (v_grupo ->> 'mayor_espera_segundos')::integer not between 1198 and 1202
    or (v_grupo ->> 'promedio_espera_segundos')::integer not between 898 and 902
    or v_grupo -> 'mesas' <> '["M01", "M02"]'::jsonb
    or (v_grupo #>> '{pedidos,0,pedido_id}')::bigint <> -11601
  then raise exception 'TP59/61 POR RECIBIR incorrecto: %', v_grupo; end if;
  v_grupo := v_grupos -> 1;
  if (v_grupo ->> 'cantidad')::integer <> 2
    or (v_grupo ->> 'mayor_espera_segundos')::integer not between 1798 and 1802
    or (v_grupo ->> 'promedio_espera_segundos')::integer not between 1348 and 1352
    or (v_grupo #>> '{pedidos,0,ingreso_grupo_en}')::timestamptz <> v_ahora - interval '30 minutes'
  then raise exception 'TP61 preparación reinició tiempo o agregó mal: %', v_grupo; end if;
  v_grupo := v_grupos -> 2;
  if (v_grupo ->> 'cantidad')::integer <> 1
    or (v_grupo ->> 'mayor_espera_segundos')::integer not between 418 and 422
    or (v_grupo #>> '{pedidos,0,pedido_id}')::bigint <> -11605
  then raise exception 'TP61 LISTOS incorrecto: %', v_grupo; end if;
  if v_grupos::text like '%-11606%' or v_grupos::text like '%-11607%'
    or v_grupos::text like '%-11608%' or v_grupos::text like '%-11609%'
  then raise exception 'TP61 incluyó terminales u otro local'; end if;
  v_checks := v_checks + 1;

  perform pg_temp.t16_user(v_admin_vacio);
  select resultado.grupos into v_grupos from public.rpc_obtener_flujo_actual_pedidos_admin() resultado;
  if exists (select 1 from jsonb_array_elements(v_grupos) g where (g ->> 'cantidad')::integer <> 0
    or g -> 'pedidos' <> '[]'::jsonb or g -> 'mesas' <> '[]'::jsonb)
  then raise exception 'TP59 estado vacío incorrecto: %', v_grupos; end if;
  v_checks := v_checks + 1;

  perform pg_temp.t16_user(v_admin_otro);
  select resultado.grupos into v_grupos from public.rpc_obtener_flujo_actual_pedidos_admin() resultado;
  if v_grupos::text not like '%-11609%' or v_grupos::text like '%-11601%'
  then raise exception 'TP61 aislamiento local incorrecto'; end if;
  v_checks := v_checks + 1;

  perform pg_temp.t16_user(v_caja);
  begin perform public.rpc_obtener_flujo_actual_pedidos_admin(); raise exception 'CAJA autorizada'; exception when insufficient_privilege then null; end;
  perform pg_temp.t16_user(v_mozo);
  begin perform public.rpc_obtener_flujo_actual_pedidos_admin(); raise exception 'MOZO autorizado'; exception when insufficient_privilege then null; end;
  perform pg_temp.t16_user(v_cocina);
  begin perform public.rpc_obtener_flujo_actual_pedidos_admin(); raise exception 'COCINA autorizada'; exception when insufficient_privilege then null; end;
  perform pg_temp.t16_user(null);
  begin perform public.rpc_obtener_flujo_actual_pedidos_admin(); raise exception 'anon autorizado'; exception when insufficient_privilege then null; end;
  v_checks := v_checks + 1;

  raise notice 'E1-T16 grupos SQL aprobados: %', v_checks;
end;
$test$;

select 'E1-T16 SQL: flujo actual, tiempos y seguridad aprobados';
rollback;
