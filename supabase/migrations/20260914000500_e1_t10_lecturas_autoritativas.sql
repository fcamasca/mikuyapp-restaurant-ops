begin;

drop function public.obtener_pedidos_pendientes_pago_caja();
create function public.obtener_pedidos_pendientes_pago_caja()
returns table(pedido_id bigint,pedido_estado text,pedido_creado_en timestamptz,mesa_id uuid,mesa_codigo text,mesa_nombre text,mesa_estado text,detalle_id bigint,producto_id uuid,producto_nombre text,cantidad integer,precio_unitario numeric,importe_linea numeric,total_pedido numeric,subtotal numeric,descuento numeric,total_neto numeric,pagado_acumulado numeric,saldo numeric)
language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_actor uuid:=auth.uid();v_local uuid;v_rol text;
begin
 select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
 if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then raise exception using errcode='42501',message='No autorizado para consultar pedidos pendientes de pago';end if;
 return query select p.id,p.estado,p.creado_en,m.id,m.codigo,m.nombre,m.estado,d.id,pr.id,pr.nombre,d.cantidad,d.precio_unitario,d.cantidad*d.precio_unitario,r.subtotal,r.subtotal,r.descuento,r.total_neto,coalesce(pg.pagado,0),r.total_neto-coalesce(pg.pagado,0)
 from public.pedido p join public.mesa m on m.id=p.mesa_id and m.local_id=p.local_id join public.detalle_pedido d on d.pedido_id=p.id join public.producto pr on pr.id=d.producto_id and pr.local_id=p.local_id
 cross join lateral public.fn_resolver_total_pedido(p.id) r
 left join lateral(select sum(x.importe) pagado from public.pago x where x.pedido_id=p.id)pg on true
 where p.local_id=v_local and p.estado='ENTREGADO' and m.estado='PENDIENTE_PAGO'
 order by p.creado_en,p.id,d.id;
end $$;

create function public.rpc_obtener_pagos_pedido_caja(p_pedido_id bigint)
returns table(pago_id bigint,importe numeric,medio text,propina numeric,actor_id uuid,actor_nombre text,pagado_en timestamptz,subtotal numeric,descuento numeric,total_neto numeric,pagado_acumulado numeric,saldo numeric)
language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_actor uuid:=auth.uid();v_local uuid;v_rol text;
begin
 select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado()c;
 if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then raise exception using errcode='42501',message='No autorizado para consultar pagos';end if;
 if not exists(select 1 from public.pedido p where p.id=p_pedido_id and p.local_id=v_local) then raise exception using errcode='42501',message='Pedido no disponible';end if;
 return query select x.id,x.importe,x.medio,x.propina,x.usuario_id,u.nombre,x.pagado_en,r.subtotal,r.descuento,r.total_neto,
   sum(x.importe)over(order by x.pagado_en,x.id),r.total_neto-sum(x.importe)over(order by x.pagado_en,x.id)
 from public.pago x join public.perfil_usuario u on u.id=x.usuario_id cross join lateral public.fn_resolver_total_pedido(x.pedido_id)r
 where x.pedido_id=p_pedido_id order by x.pagado_en,x.id;
end $$;

create function public.rpc_obtener_pedidos_operacion_admin()
returns table(pedido_id bigint,mesa_id uuid,mesa_codigo text,mesa_nombre text,pedido_estado text,mesa_estado text,creado_en timestamptz,tiene_pagos boolean,cantidad_pagos bigint,subtotal numeric,descuento numeric,total_neto numeric,pagado_acumulado numeric,saldo numeric)
language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_actor uuid:=auth.uid();v_local uuid;v_rol text;
begin
 select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado()c;
 if v_actor is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then raise exception using errcode='42501',message='No autorizado para consultar operación administrativa';end if;
 return query select p.id,m.id,m.codigo,m.nombre,p.estado,m.estado,p.creado_en,coalesce(pg.cantidad,0)>0,coalesce(pg.cantidad,0),r.subtotal,r.descuento,r.total_neto,coalesce(pg.pagado,0),r.total_neto-coalesce(pg.pagado,0)
 from public.pedido p join public.mesa m on m.id=p.mesa_id and m.local_id=p.local_id cross join lateral public.fn_resolver_total_pedido(p.id)r
 left join lateral(select count(*) cantidad,sum(x.importe) pagado from public.pago x where x.pedido_id=p.id)pg on true
 where p.local_id=v_local and p.estado in('ABIERTO','ENVIADO','RECIBIDO_COCINA','EN_PREPARACION','LISTO','ENTREGADO','PAGADO','ANULADO') order by p.creado_en,p.id;
end $$;

alter function public.obtener_pedidos_pendientes_pago_caja() owner to postgres;
alter function public.rpc_obtener_pagos_pedido_caja(bigint) owner to postgres;
alter function public.rpc_obtener_pedidos_operacion_admin() owner to postgres;
revoke all on function public.obtener_pedidos_pendientes_pago_caja(),public.rpc_obtener_pagos_pedido_caja(bigint),public.rpc_obtener_pedidos_operacion_admin() from public,anon,authenticated,service_role;
grant execute on function public.obtener_pedidos_pendientes_pago_caja(),public.rpc_obtener_pagos_pedido_caja(bigint),public.rpc_obtener_pedidos_operacion_admin() to authenticated;
comment on function public.obtener_pedidos_pendientes_pago_caja() is 'Lectura CAJA H5 compatible, enriquecida con subtotal, descuento, neto, pagado y saldo autoritativos.';
comment on function public.rpc_obtener_pagos_pedido_caja(bigint) is 'Pagos confirmados del pedido local para documentos internos de CAJA; incluye actor, propina y saldo posterior.';
comment on function public.rpc_obtener_pedidos_operacion_admin() is 'Lectura operacional ADMINISTRADOR del mismo local para descuento/anulación; no concede cobro.';
notify pgrst,'reload schema';commit;
