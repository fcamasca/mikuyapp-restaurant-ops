create or replace function public.obtener_resumen_ventas_hoy()
returns table(medio text, pedidos_pagados bigint, importe numeric)
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_local uuid; v_rol text;
begin
  select p.local_id, r.codigo into v_local, v_rol
  from public.perfil_usuario p join public.rol r on r.id=p.rol_id
  where p.id=auth.uid() and p.activo and r.activo;
  if v_rol not in ('ADMINISTRADOR','CAJA') then raise exception using errcode='42501', message='No autorizado'; end if;
  return query select pay.medio, count(*)::bigint, coalesce(sum(pay.importe),0)::numeric
  from public.pago pay join public.pedido o on o.id=pay.pedido_id
  where o.local_id=v_local and o.estado='PAGADO'
    and (pay.pagado_en at time zone 'America/Lima')::date=(pg_catalog.now() at time zone 'America/Lima')::date
  group by pay.medio;
end $$;
alter function public.obtener_resumen_ventas_hoy() owner to postgres;
revoke all on function public.obtener_resumen_ventas_hoy() from public, anon;
grant execute on function public.obtener_resumen_ventas_hoy() to authenticated;

create or replace function public.exportar_ventas_hoy()
returns table(pedido_id bigint, mesa text, pagado_en timestamptz, medio text, importe numeric)
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_local uuid; v_rol text;
begin
  select p.local_id,r.codigo into v_local,v_rol from public.perfil_usuario p join public.rol r on r.id=p.rol_id where p.id=auth.uid() and p.activo and r.activo;
  if v_rol <> 'ADMINISTRADOR' then raise exception using errcode='42501', message='No autorizado'; end if;
  return query select o.id,m.codigo,pay.pagado_en,pay.medio,pay.importe
  from public.pago pay join public.pedido o on o.id=pay.pedido_id join public.mesa m on m.id=o.mesa_id
  where o.local_id=v_local and o.estado='PAGADO'
    and (pay.pagado_en at time zone 'America/Lima')::date=(pg_catalog.now() at time zone 'America/Lima')::date
  order by pay.pagado_en;
end $$;
alter function public.exportar_ventas_hoy() owner to postgres;
revoke all on function public.exportar_ventas_hoy() from public, anon;
grant execute on function public.exportar_ventas_hoy() to authenticated;

create or replace function public.exportar_productos_local()
returns table(codigo_categoria text, categoria text, codigo_producto text, producto text, precio numeric, activo boolean)
language plpgsql security definer set search_path = pg_catalog
as $$
declare v_local uuid; v_rol text;
begin
  select p.local_id,r.codigo into v_local,v_rol from public.perfil_usuario p join public.rol r on r.id=p.rol_id where p.id=auth.uid() and p.activo and r.activo;
  if v_rol <> 'ADMINISTRADOR' then raise exception using errcode='42501', message='No autorizado'; end if;
  return query select c.codigo,c.nombre,pr.codigo,pr.nombre,pr.precio,pr.activo
  from public.producto pr join public.categoria c on c.id=pr.categoria_id and c.local_id=pr.local_id
  where pr.local_id=v_local order by c.orden,c.nombre,pr.nombre;
end $$;
alter function public.exportar_productos_local() owner to postgres;
revoke all on function public.exportar_productos_local() from public, anon;
grant execute on function public.exportar_productos_local() to authenticated;
