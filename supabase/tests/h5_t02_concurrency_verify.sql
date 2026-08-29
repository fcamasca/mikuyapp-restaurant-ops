do $h5_t02_concurrency_verify$
begin
  if (select estado from public.pedido where id = -50291) <> 'ENTREGADO'
    or (select estado from public.mesa
      where id = '00000000-0000-0000-0000-00000000e291') <> 'PENDIENTE_PAGO'
    or (select estado from public.detalle_pedido where id = -50291) <> 'LISTO'
    or (select count(*) from public.historial_estado
      where pedido_id = -50291
        and estado_anterior = 'LISTO'
        and estado_nuevo = 'ENTREGADO') <> 1 then
    raise exception 'H5-T02 concurrencia produjo estado o historial incorrectos';
  end if;
end;
$h5_t02_concurrency_verify$;
