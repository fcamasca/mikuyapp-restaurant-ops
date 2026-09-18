begin;

create or replace function public.rpc_obtener_reportes_sesion_caja(p_sesion_caja_id uuid default null)
returns table(
  sesion_caja_id uuid,caja_id uuid,caja_codigo text,caja_nombre text,estado text,
  abierta_por uuid,abierta_por_nombre text,abierta_en timestamptz,cerrada_por uuid,
  cerrada_por_nombre text,cerrada_en timestamptz,monto_inicial numeric,
  venta_efectivo numeric,venta_yape numeric,venta_plin numeric,venta_tarjeta numeric,
  propina_efectivo numeric,propina_yape numeric,propina_plin numeric,propina_tarjeta numeric,
  entradas numeric,salidas numeric,efectivo_esperado numeric,efectivo_contado numeric,
  diferencia numeric,descuentos numeric,cantidad_anulaciones bigint,cantidad_pagos bigint,
  pagos_parciales bigint,cantidad_pedidos_completados bigint
)
language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_local uuid;v_rol text;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if auth.uid() is null or v_local is null or v_rol not in('CAJA','ADMINISTRADOR') then
    raise exception using errcode='42501',message='No autorizado para consultar reportes de caja';
  end if;
  return query
  select s.id,s.caja_id,c.codigo,c.nombre,s.estado,s.abierta_por,ua.nombre,s.abierta_en,
    s.cerrada_por,uc.nombre,s.cerrada_en,s.monto_inicial,
    coalesce(rc.pago_efectivo,t.pago_efectivo,0),coalesce(rc.pago_yape,t.pago_yape,0),
    coalesce(rc.pago_plin,t.pago_plin,0),coalesce(rc.pago_tarjeta,t.pago_tarjeta,0),
    coalesce(rc.propina_efectivo,t.propina_efectivo,0),coalesce(rc.propina_yape,t.propina_yape,0),
    coalesce(rc.propina_plin,t.propina_plin,0),coalesce(rc.propina_tarjeta,t.propina_tarjeta,0),
    coalesce(rc.entradas,t.entradas,0),coalesce(rc.salidas,t.salidas,0),
    coalesce(rc.efectivo_esperado,s.monto_inicial+t.pago_efectivo+t.propina_efectivo+t.entradas-t.salidas),
    rc.efectivo_contado,rc.diferencia,coalesce(d.descuentos,0),coalesce(a.anulaciones,0),
    coalesce(ps.cantidad_cobros,0),coalesce(ps.cobros_parciales,0),coalesce(ps.pedidos_completados,0)
  from public.sesion_caja s join public.caja c on c.id=s.caja_id
  join public.perfil_usuario ua on ua.id=s.abierta_por
  left join public.perfil_usuario uc on uc.id=s.cerrada_por
  left join public.resumen_cierre_sesion_caja rc on rc.sesion_caja_id=s.id
  cross join lateral public.fn_totales_sesion_caja(s.id) t
  left join lateral(
    with lineas as(
      select p.*,coalesce('C:'||p.cobro_id::text,'P:'||p.id::text) acto
      from public.pago p where p.sesion_caja_id=s.id
    ),actos as(
      select l.acto,l.pedido_id,max(l.id) ultimo_pago,max(l.cobro_id::text)::uuid cobro_id
      from lineas l group by l.acto,l.pedido_id
    )
    select count(*)::bigint cantidad_cobros,
      count(*) filter(where coalesce(cb.tipo,(select case when count(*)>1 then 'PARCIAL' else 'TOTAL' end from public.pago px where px.pedido_id=x.pedido_id))='PARCIAL')::bigint cobros_parciales,
      count(distinct x.pedido_id) filter(where po.estado='PAGADO' and x.ultimo_pago=(select max(px.id) from public.pago px where px.pedido_id=x.pedido_id))::bigint pedidos_completados
    from actos x join public.pedido po on po.id=x.pedido_id left join public.cobro cb on cb.id=x.cobro_id
  )ps on true
  left join lateral(
    select coalesce(sum(dp.importe_aplicado),0)::numeric descuentos from public.descuento_pedido dp
    where dp.estado='AUTORIZADO' and exists(select 1 from public.pago pp where pp.pedido_id=dp.pedido_id
      and pp.sesion_caja_id=s.id and pp.id=(select min(px.id) from public.pago px where px.pedido_id=dp.pedido_id))
  )d on true
  left join lateral(
    select count(*)::bigint anulaciones from public.anulacion_pedido ap where ap.local_id=s.local_id
      and ap.anulado_en>=s.abierta_en and ap.anulado_en<coalesce(s.cerrada_en,'infinity'::timestamptz)
  )a on true
  where s.local_id=v_local and (p_sesion_caja_id is null or s.id=p_sesion_caja_id)
  order by s.abierta_en desc,s.id;
end $$;

create or replace function public.rpc_obtener_resumen_diario_caja()
returns table(
  fecha_operativa date,total_vendido numeric,venta_efectivo numeric,venta_yape numeric,
  venta_plin numeric,venta_tarjeta numeric,total_propinas numeric,propina_efectivo numeric,
  propina_yape numeric,propina_plin numeric,propina_tarjeta numeric,descuentos numeric,
  cantidad_anulaciones bigint,cantidad_pagos bigint,pagos_parciales bigint,
  cantidad_pedidos_completados bigint
)
language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_local uuid;v_rol text;v_fecha date:=(now() at time zone 'America/Lima')::date;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if auth.uid() is null or v_local is null or v_rol not in('CAJA','ADMINISTRADOR') then
    raise exception using errcode='42501',message='No autorizado para consultar el resumen diario';
  end if;
  return query
  with pagos_hoy as(
    select p.* from public.pago p join public.pedido pe on pe.id=p.pedido_id
    where pe.local_id=v_local and (p.pagado_en at time zone 'America/Lima')::date=v_fecha
  ), pagos_agregados as(
    select coalesce(sum(importe),0)::numeric total,
      coalesce(sum(importe) filter(where medio='EFECTIVO'),0)::numeric efectivo,
      coalesce(sum(importe) filter(where medio='YAPE'),0)::numeric yape,
      coalesce(sum(importe) filter(where medio='PLIN'),0)::numeric plin,
      coalesce(sum(importe) filter(where medio='TARJETA'),0)::numeric tarjeta,
      coalesce(sum(propina),0)::numeric propinas,
      coalesce(sum(propina) filter(where medio='EFECTIVO'),0)::numeric propina_ef,
      coalesce(sum(propina) filter(where medio='YAPE'),0)::numeric propina_ya,
      coalesce(sum(propina) filter(where medio='PLIN'),0)::numeric propina_pl,
      coalesce(sum(propina) filter(where medio='TARJETA'),0)::numeric propina_ta
    from pagos_hoy
  ), actos as(
    select coalesce('C:'||p.cobro_id::text,'P:'||p.id::text) acto,p.pedido_id,max(p.id) ultimo_pago,max(p.cobro_id::text)::uuid cobro_id
    from pagos_hoy p group by coalesce('C:'||p.cobro_id::text,'P:'||p.id::text),p.pedido_id
  ), conteos as(
    select count(*)::bigint pagos,
      count(*) filter(where coalesce(c.tipo,(select case when count(*)>1 then 'PARCIAL' else 'TOTAL' end from public.pago px where px.pedido_id=a.pedido_id))='PARCIAL')::bigint parciales,
      count(distinct a.pedido_id) filter(where pe.estado='PAGADO' and a.ultimo_pago=(select max(px.id) from public.pago px where px.pedido_id=a.pedido_id))::bigint completados
    from actos a join public.pedido pe on pe.id=a.pedido_id left join public.cobro c on c.id=a.cobro_id
  ), descuentos_hoy as(
    select coalesce(sum(dp.importe_aplicado),0)::numeric total from public.descuento_pedido dp
    where dp.local_id=v_local and dp.estado='AUTORIZADO' and exists(select 1 from pagos_hoy ph
      where ph.pedido_id=dp.pedido_id and ph.id=(select min(px.id) from public.pago px where px.pedido_id=dp.pedido_id))
  ), anulaciones_hoy as(
    select count(*)::bigint cantidad from public.anulacion_pedido ap where ap.local_id=v_local
      and (ap.anulado_en at time zone 'America/Lima')::date=v_fecha
  )
  select v_fecha,p.total,p.efectivo,p.yape,p.plin,p.tarjeta,p.propinas,p.propina_ef,p.propina_ya,
    p.propina_pl,p.propina_ta,d.total,n.cantidad,c.pagos,c.parciales,c.completados
  from pagos_agregados p cross join conteos c cross join descuentos_hoy d cross join anulaciones_hoy n;
end $$;

alter function public.rpc_obtener_reportes_sesion_caja(uuid) owner to postgres;
alter function public.rpc_obtener_resumen_diario_caja() owner to postgres;
revoke all on function public.rpc_obtener_reportes_sesion_caja(uuid),public.rpc_obtener_resumen_diario_caja() from public,anon,authenticated,service_role;
grant execute on function public.rpc_obtener_reportes_sesion_caja(uuid),public.rpc_obtener_resumen_diario_caja() to authenticated;
comment on function public.rpc_obtener_reportes_sesion_caja(uuid) is 'CAJA/ADMINISTRADOR: importes por línea y conteos por acto de cobro, sin duplicar pedidos completados.';
comment on function public.rpc_obtener_resumen_diario_caja() is 'CAJA/ADMINISTRADOR: resumen diario; importes por línea, conteos por cobro y pedidos completados una vez.';
notify pgrst,'reload schema';
commit;
