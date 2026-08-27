begin;

delete from public.historial_estado where pedido_id = -95501;
delete from public.detalle_pedido where pedido_id = -95501;
delete from public.pedido where id = -95501;
delete from public.mesa where id = '00000000-0000-0000-0000-00000000f5c3';
delete from public.producto where id = '00000000-0000-0000-0000-00000000f5c2';
delete from public.categoria where id = '00000000-0000-0000-0000-00000000f5c1';

do $h3_t05_cleanup_verified$
begin
  if exists (select 1 from public.pedido where id = -95501)
    or exists (select 1 from public.detalle_pedido where pedido_id = -95501)
    or exists (select 1 from public.historial_estado where pedido_id = -95501)
    or exists (
      select 1 from public.mesa
      where id = '00000000-0000-0000-0000-00000000f5c3'
    )
    or exists (
      select 1 from public.producto
      where id = '00000000-0000-0000-0000-00000000f5c2'
    )
    or exists (
      select 1 from public.categoria
      where id = '00000000-0000-0000-0000-00000000f5c1'
    ) then
    raise exception 'H3-T05 no limpió completamente el fixture concurrente';
  end if;
end;
$h3_t05_cleanup_verified$;

commit;
