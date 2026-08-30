do $$
declare v_order text; v_table text; v_payments bigint; v_new bigint;
begin
 select estado into strict v_order from public.pedido where id=-50821;
 select estado into strict v_table from public.mesa where id='00000000-0000-0000-0000-00000000f827';
 select count(*) into v_payments from public.pago where pedido_id=-50821;
 select count(*) into v_new from public.detalle_pedido where pedido_id=-50821 and producto_id='00000000-0000-0000-0000-00000000f826';
 if not ((v_order='PAGADO' and v_table='LIBRE' and v_payments=1 and v_new=0)
   or (v_order='ABIERTO' and v_table='OCUPADA' and v_payments=0 and v_new=1)) then
   raise exception 'TA18 carrera no fue atómica: pedido %, mesa %, pagos %, nuevos %',v_order,v_table,v_payments,v_new;
 end if;
 if (select estado from public.detalle_pedido where id=-50821)<>'LISTO' then
   raise exception 'TA18 alteró el detalle previamente entregado';
 end if;
end $$;
select p.estado pedido_estado,m.estado mesa_estado,
 (select count(*) from public.pago where pedido_id=p.id) pagos,
 (select count(*) from public.detalle_pedido where pedido_id=p.id and producto_id='00000000-0000-0000-0000-00000000f826') detalles_nuevos
from public.pedido p join public.mesa m on m.id=p.mesa_id where p.id=-50821;
