-- E10-T03 — Solicitud de cuenta por el MOZO y lectura extendida de Caja.
-- Spec aprobado: specs/E10-AccountRequest (E10-D04, D08, D09, D12). Migración aditiva separada de T02
-- (permitido por E10-D17). No modifica RPC financieras de E1: sólo agrega columnas al final de la
-- lectura de pendientes de Caja, conservando nombre, filtros, orden, seguridad y columnas previas.
begin;

-- E10-D04: crea u obtiene la única solicitud PENDIENTE de un pedido ENTREGADO / mesa PENDIENTE_PAGO.
create function public.rpc_solicitar_cuenta_pedido(p_pedido_id bigint)
returns table (
  solicitud_id bigint,
  pedido_id bigint,
  estado text,
  solicitada_en timestamptz,
  solicitada_por uuid,
  ya_existia boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $rpc_solicitar_cuenta_pedido$
declare
  v_actor uuid := auth.uid();
  v_local uuid;
  v_rol text;
  v_pedido public.pedido%rowtype;
  v_mesa_estado text;
  v_solicitud public.solicitud_cuenta%rowtype;
begin
  select auth_context.local_id, auth_context.rol_codigo
  into v_local, v_rol
  from public.obtener_contexto_autenticado() as auth_context;
  if v_actor is null or v_local is null or v_rol is distinct from 'MOZO' then
    raise exception using errcode = '42501', message = 'No autorizado para solicitar la cuenta';
  end if;
  if p_pedido_id is null then
    raise exception using errcode = '22023', message = 'El pedido es obligatorio';
  end if;

  -- Orden de locks E10-D05: pedido -> solicitud_cuenta.
  select order_row.* into v_pedido
  from public.pedido as order_row
  where order_row.id = p_pedido_id and order_row.local_id = v_local
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Pedido no disponible para el usuario autenticado';
  end if;
  if v_pedido.estado in ('PAGADO', 'ANULADO') then
    raise exception using errcode = 'PT409', message = 'El pedido ya no está pendiente de pago';
  end if;
  if v_pedido.estado <> 'ENTREGADO' then
    raise exception using errcode = 'PT409', message = 'El pedido todavía no fue entregado';
  end if;

  -- Toda salida de esta mesa de PENDIENTE_PAGO ocurre con este pedido bloqueado.
  select table_row.estado into v_mesa_estado
  from public.mesa as table_row
  where table_row.id = v_pedido.mesa_id and table_row.local_id = v_local;
  if v_mesa_estado is distinct from 'PENDIENTE_PAGO' then
    raise exception using errcode = 'PT409', message = 'La mesa ya no está pendiente de pago';
  end if;

  select request_row.* into v_solicitud
  from public.solicitud_cuenta as request_row
  where request_row.pedido_id = v_pedido.id and request_row.estado = 'PENDIENTE';
  if found then
    return query select v_solicitud.id, v_solicitud.pedido_id, v_solicitud.estado,
      v_solicitud.solicitada_en, v_solicitud.solicitada_por, true;
    return;
  end if;

  begin
    insert into public.solicitud_cuenta (local_id, pedido_id, estado, solicitada_por, solicitada_en)
    values (v_pedido.local_id, v_pedido.id, 'PENDIENTE', v_actor, pg_catalog.clock_timestamp())
    returning * into v_solicitud;
  exception when unique_violation then
    -- Defensa: imposible bajo el lock del pedido; nunca se expone como error al cliente.
    select request_row.* into strict v_solicitud
    from public.solicitud_cuenta as request_row
    where request_row.pedido_id = v_pedido.id and request_row.estado = 'PENDIENTE';
    return query select v_solicitud.id, v_solicitud.pedido_id, v_solicitud.estado,
      v_solicitud.solicitada_en, v_solicitud.solicitada_por, true;
    return;
  end;

  return query select v_solicitud.id, v_solicitud.pedido_id, v_solicitud.estado,
    v_solicitud.solicitada_en, v_solicitud.solicitada_por, false;
end;
$rpc_solicitar_cuenta_pedido$;

alter function public.rpc_solicitar_cuenta_pedido(bigint) owner to postgres;
revoke all on function public.rpc_solicitar_cuenta_pedido(bigint) from public, anon, authenticated, service_role;
grant execute on function public.rpc_solicitar_cuenta_pedido(bigint) to authenticated;
comment on function public.rpc_solicitar_cuenta_pedido(bigint) is
  'E10-D04: MOZO solicita la cuenta total de un pedido ENTREGADO/mesa PENDIENTE_PAGO de su local. Idempotente: devuelve la PENDIENTE existente con ya_existia = true. Conflictos funcionales PT409; no modifica pedido, mesa ni datos financieros.';

-- E10-D08: lectura CAJA extendida (DROP + CREATE atómico, patrón E1-T10). Columnas previas intactas;
-- nuevas al final: solicitud PENDIENTE (o nulos) y hora de servidor.
drop function public.obtener_pedidos_pendientes_pago_caja();
create function public.obtener_pedidos_pendientes_pago_caja()
returns table(pedido_id bigint,pedido_estado text,pedido_creado_en timestamptz,mesa_id uuid,mesa_codigo text,mesa_nombre text,mesa_estado text,detalle_id bigint,producto_id uuid,producto_nombre text,cantidad integer,precio_unitario numeric,importe_linea numeric,total_pedido numeric,subtotal numeric,descuento numeric,total_neto numeric,pagado_acumulado numeric,saldo numeric,solicitud_cuenta_id bigint,cuenta_solicitada_en timestamptz,cuenta_solicitada_por_nombre text,servidor_ahora timestamptz)
language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_actor uuid:=auth.uid();v_local uuid;v_rol text;
begin
 select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
 if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then raise exception using errcode='42501',message='No autorizado para consultar pedidos pendientes de pago';end if;
 return query select p.id,p.estado,p.creado_en,m.id,m.codigo,m.nombre,m.estado,d.id,pr.id,pr.nombre,d.cantidad,d.precio_unitario,d.cantidad*d.precio_unitario,r.subtotal,r.subtotal,r.descuento,r.total_neto,coalesce(pg.pagado,0),r.total_neto-coalesce(pg.pagado,0),
   sc.id,sc.solicitada_en,sc.solicitada_por_nombre,now()
 from public.pedido p join public.mesa m on m.id=p.mesa_id and m.local_id=p.local_id join public.detalle_pedido d on d.pedido_id=p.id join public.producto pr on pr.id=d.producto_id and pr.local_id=p.local_id
 cross join lateral public.fn_resolver_total_pedido(p.id) r
 left join lateral(select sum(x.importe) pagado from public.pago x where x.pedido_id=p.id)pg on true
 left join lateral(select s.id,s.solicitada_en,u.nombre solicitada_por_nombre from public.solicitud_cuenta s join public.perfil_usuario u on u.id=s.solicitada_por where s.pedido_id=p.id and s.estado='PENDIENTE')sc on true
 where p.local_id=v_local and p.estado='ENTREGADO' and m.estado='PENDIENTE_PAGO'
 order by p.creado_en,p.id,d.id;
end $$;

alter function public.obtener_pedidos_pendientes_pago_caja() owner to postgres;
revoke all on function public.obtener_pedidos_pendientes_pago_caja() from public,anon,authenticated,service_role;
grant execute on function public.obtener_pedidos_pendientes_pago_caja() to authenticated;
comment on function public.obtener_pedidos_pendientes_pago_caja() is 'Lectura CAJA H5 compatible, enriquecida con subtotal, descuento, neto, pagado y saldo autoritativos. E10-D08: agrega al final la solicitud de cuenta PENDIENTE (id, hora, mozo) y la hora de servidor, en el mismo snapshot.';

notify pgrst, 'reload schema';

commit;
