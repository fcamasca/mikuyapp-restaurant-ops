-- E10 — Verificación de carrera. Variables psql: :mesa (1..9), :esperado (texto de la regla).
select pg_catalog.set_config('e10.mesa', :'mesa', false);
select pg_catalog.set_config('e10.esperado', :'esperado', false);
do $verify$
declare v_pedido bigint; v_estado text; v_resumen text; v_esperado text := current_setting('e10.esperado');
begin
  select p.id, p.estado into strict v_pedido, v_estado from public.pedido p
  where p.mesa_id = ('00000000-0000-0000-0000-00000e10cc' || (20 + current_setting('e10.mesa')::int))::uuid
  order by p.id desc limit 1;
  select v_estado || ':' || coalesce(string_agg(s.estado || coalesce('/' || s.motivo_sin_efecto, '')
      || case when s.cerrada_en is not null and s.cerrada_en < s.solicitada_en then '!orden' else '' end, ',' order by s.id), '-')
  into v_resumen from public.solicitud_cuenta s where s.pedido_id = v_pedido;
  if v_resumen <> v_esperado then
    raise exception 'E10-RACE verify mesa %: obtenido %, esperado %', current_setting('e10.mesa'), v_resumen, v_esperado;
  end if;
  raise notice 'E10-RACE verify mesa % OK: %', current_setting('e10.mesa'), v_resumen;
end $verify$;
