-- E10 — Llamada de carrera. Variables psql: :op (solicitar|cobro_total|reapertura|anulacion), :usuario (uuid), :mesa (1..9).
select pg_catalog.set_config('request.jwt.claim.sub', :'usuario', false);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', false);
select pg_catalog.set_config('e10.op', :'op', false);
select pg_catalog.set_config('e10.mesa', :'mesa', false);
do $call$
declare v_pedido bigint; r record; v_saldo numeric;
begin
  select p.id into strict v_pedido from public.pedido p
  where p.mesa_id = ('00000000-0000-0000-0000-00000e10cc' || (20 + current_setting('e10.mesa')::int))::uuid
  order by p.id desc limit 1;
  case current_setting('e10.op')
    when 'solicitar' then
      select * into strict r from public.rpc_solicitar_cuenta_pedido(v_pedido);
      raise notice 'E10-RACE solicitar pedido=% solicitud=% ya_existia=%', v_pedido, r.solicitud_id, r.ya_existia;
    when 'cobro_total' then
      select coalesce(sum(saldo), 0) into v_saldo from (select distinct x.pedido_id, x.saldo from public.obtener_pedidos_pendientes_pago_caja() x where x.pedido_id = v_pedido) s;
      if v_saldo = 0 then v_saldo := 8; end if;
      select * into strict r from public.rpc_registrar_cobro_pedido(v_pedido, '00000000-0000-0000-0000-00000e10cc15', 'TOTAL',
        jsonb_build_array(jsonb_build_object('medio', 'EFECTIVO', 'importe', v_saldo, 'propina', 0)), gen_random_uuid());
      raise notice 'E10-RACE cobro pedido=% estado=%', v_pedido, r.pedido_estado;
    when 'reapertura' then
      perform public.agregar_detalle_pedido(v_pedido, '00000000-0000-0000-0000-00000e10cc13', 1, null);
      raise notice 'E10-RACE reapertura pedido=%', v_pedido;
    when 'anulacion' then
      perform public.anular_pedido_supervisado(v_pedido, 'Carrera E10', gen_random_uuid());
      raise notice 'E10-RACE anulacion pedido=%', v_pedido;
  end case;
end $call$;
