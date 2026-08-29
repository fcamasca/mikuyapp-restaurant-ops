do $$ begin
  if (select count(*) from public.pago where pedido_id=-50491 and importe=33 and medio='EFECTIVO') <> 1
    or (select estado from public.pedido where id=-50491) <> 'PAGADO'
    or (select estado from public.mesa where id='00000000-0000-0000-0000-00000000e491') <> 'LIBRE'
    or (select count(*) from public.historial_estado where pedido_id=-50491 and estado_anterior='ENTREGADO' and estado_nuevo='PAGADO') <> 1 then
    raise exception 'H5-T04 resultado concurrente incorrecto';
  end if;
end $$;
