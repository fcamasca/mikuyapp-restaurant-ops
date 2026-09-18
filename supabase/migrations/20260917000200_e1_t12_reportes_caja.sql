begin;

create function public.rpc_obtener_reportes_sesion_caja(p_sesion_caja_id uuid default null)
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
    coalesce(p.cantidad_pagos,0),coalesce(p.pagos_parciales,0),coalesce(p.pedidos_completados,0)
  from public.sesion_caja s join public.caja c on c.id=s.caja_id
  join public.perfil_usuario ua on ua.id=s.abierta_por
  left join public.perfil_usuario uc on uc.id=s.cerrada_por
  left join public.resumen_cierre_sesion_caja rc on rc.sesion_caja_id=s.id
  cross join lateral public.fn_totales_sesion_caja(s.id) t
  left join lateral(
    select count(*)::bigint cantidad_pagos,
      count(*) filter(where (select count(*) from public.pago px where px.pedido_id=pp.pedido_id)>1)::bigint pagos_parciales,
      count(distinct pp.pedido_id) filter(where po.estado='PAGADO' and pp.id=(select max(px.id) from public.pago px where px.pedido_id=pp.pedido_id))::bigint pedidos_completados
    from public.pago pp join public.pedido po on po.id=pp.pedido_id where pp.sesion_caja_id=s.id
  )p on true
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

create function public.rpc_obtener_resumen_diario_caja()
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
      coalesce(sum(propina) filter(where medio='TARJETA'),0)::numeric propina_ta,
      count(*)::bigint pagos,
      count(*) filter(where (select count(*) from public.pago px where px.pedido_id=pagos_hoy.pedido_id)>1)::bigint parciales
    from pagos_hoy
  ), completados as(
    select count(distinct ph.pedido_id)::bigint cantidad from pagos_hoy ph join public.pedido pe on pe.id=ph.pedido_id
    where pe.estado='PAGADO' and ph.id=(select max(px.id) from public.pago px where px.pedido_id=ph.pedido_id)
  ), descuentos_hoy as(
    select coalesce(sum(dp.importe_aplicado),0)::numeric total from public.descuento_pedido dp
    where dp.local_id=v_local and dp.estado='AUTORIZADO' and exists(select 1 from pagos_hoy ph
      where ph.pedido_id=dp.pedido_id and ph.id=(select min(px.id) from public.pago px where px.pedido_id=dp.pedido_id))
  ), anulaciones_hoy as(
    select count(*)::bigint cantidad from public.anulacion_pedido ap where ap.local_id=v_local
      and (ap.anulado_en at time zone 'America/Lima')::date=v_fecha
  )
  select v_fecha,p.total,p.efectivo,p.yape,p.plin,p.tarjeta,p.propinas,p.propina_ef,p.propina_ya,
    p.propina_pl,p.propina_ta,d.total,a.cantidad,p.pagos,p.parciales,c.cantidad
  from pagos_agregados p cross join completados c cross join descuentos_hoy d cross join anulaciones_hoy a;
end $$;

alter function public.rpc_obtener_reportes_sesion_caja(uuid) owner to postgres;
alter function public.rpc_obtener_resumen_diario_caja() owner to postgres;
revoke all on function public.rpc_obtener_reportes_sesion_caja(uuid),public.rpc_obtener_resumen_diario_caja()
  from public,anon,authenticated,service_role;
grant execute on function public.rpc_obtener_reportes_sesion_caja(uuid),public.rpc_obtener_resumen_diario_caja()
  to authenticated;
comment on function public.rpc_obtener_reportes_sesion_caja(uuid) is 'CAJA/ADMINISTRADOR: reporte autoritativo por sesión del local, con snapshots de cierre y pagos divididos.';
comment on function public.rpc_obtener_resumen_diario_caja() is 'CAJA/ADMINISTRADOR: resumen del día operativo America/Lima; pagos monetarios y pedidos completados sin duplicar por parciales.';
notify pgrst,'reload schema';
commit;
