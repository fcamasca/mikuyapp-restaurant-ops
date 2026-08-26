-- T19: ejecutar manualmente en Supabase SQL Editor después de las pruebas.
-- Elimina solo fixtures identificados por el prefijo H2T19-FIX-, sin cascadas.

begin;

do $h2_t19_cleanup$
declare
  v_remaining bigint;
begin
  delete from public.pago as pay
  using public.pedido as p, public.mesa as m
  where pay.pedido_id = p.id
    and p.mesa_id = m.id
    and m.codigo like 'H2T19-FIX-%';

  delete from public.historial_estado as h
  using public.pedido as p, public.mesa as m
  where h.pedido_id = p.id
    and p.mesa_id = m.id
    and m.codigo like 'H2T19-FIX-%';

  delete from public.detalle_pedido as d
  using public.pedido as p, public.mesa as m
  where d.pedido_id = p.id
    and p.mesa_id = m.id
    and m.codigo like 'H2T19-FIX-%';

  delete from public.detalle_pedido as d
  using public.producto as pr
  where d.producto_id = pr.id
    and pr.codigo like 'H2T19-FIX-%';

  delete from public.pedido as p
  using public.mesa as m
  where p.mesa_id = m.id
    and m.codigo like 'H2T19-FIX-%';

  delete from public.producto as pr
  where pr.codigo like 'H2T19-FIX-%';

  delete from public.mesa as m
  where m.codigo like 'H2T19-FIX-%';

  delete from public.categoria as c
  where c.codigo like 'H2T19-FIX-%';

  delete from public.local as l
  where l.codigo like 'H2T19-FIX-%';

  select
      (select count(*) from public.local as l where l.codigo like 'H2T19-FIX-%')
    + (select count(*) from public.categoria as c where c.codigo like 'H2T19-FIX-%')
    + (select count(*) from public.producto as pr where pr.codigo like 'H2T19-FIX-%')
    + (select count(*) from public.mesa as m where m.codigo like 'H2T19-FIX-%')
    + (
        select count(*)
        from public.pedido as p
        join public.mesa as m on m.id = p.mesa_id
        where m.codigo like 'H2T19-FIX-%'
      )
    + (
        select count(*)
        from public.detalle_pedido as d
        join public.producto as pr on pr.id = d.producto_id
        where pr.codigo like 'H2T19-FIX-%'
      )
    into v_remaining;

  if v_remaining <> 0 then
    raise exception 'La limpieza T19 quedó incompleta: % registros fixture.', v_remaining;
  end if;
end
$h2_t19_cleanup$;

select 'Limpieza H2T19-FIX completa' as resultado;

commit;
