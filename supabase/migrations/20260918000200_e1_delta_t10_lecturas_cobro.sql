begin;

create function public.rpc_obtener_cobros_pedido_caja(p_pedido_id bigint)
returns table(
  cobro_id uuid,tipo_cobro text,total_aplicado numeric,propina_total numeric,
  actor_id uuid,actor_nombre text,cobrado_en timestamptz,saldo_anterior numeric,
  saldo_posterior numeric,subtotal numeric,descuento numeric,total_neto numeric,medios jsonb
)
language plpgsql stable security definer set search_path=pg_catalog as $$
declare v_actor uuid:=auth.uid();v_local uuid;v_rol text;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado()c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode='42501',message='No autorizado para consultar cobros';
  end if;
  if not exists(select 1 from public.pedido p where p.id=p_pedido_id and p.local_id=v_local) then
    raise exception using errcode='42501',message='Pedido no disponible';
  end if;
  return query
  select c.id,c.tipo,c.total_aplicado,c.propina_total,c.actor_id,u.nombre,c.cobrado_en,
    c.saldo_anterior,c.saldo_posterior,r.subtotal,r.descuento,r.total_neto,
    coalesce(jsonb_agg(jsonb_build_object('pago_id',p.id,'orden',p.orden,'medio',p.medio,
      'importe',p.importe,'propina',p.propina) order by p.orden),'[]'::jsonb)
  from public.cobro c join public.perfil_usuario u on u.id=c.actor_id
  join public.pago p on p.cobro_id=c.id
  cross join lateral public.fn_resolver_total_pedido(c.pedido_id)r
  where c.pedido_id=p_pedido_id
  group by c.id,u.nombre,r.subtotal,r.descuento,r.total_neto
  order by c.cobrado_en,c.id;
end $$;

alter function public.rpc_obtener_cobros_pedido_caja(bigint) owner to postgres;
revoke all on function public.rpc_obtener_cobros_pedido_caja(bigint) from public,anon,authenticated,service_role;
grant execute on function public.rpc_obtener_cobros_pedido_caja(bigint) to authenticated;
comment on function public.rpc_obtener_cobros_pedido_caja(bigint) is
  'CAJA local: actos de cobro confirmados agrupados con sus N medios, actor, hora y saldos autoritativos.';
notify pgrst,'reload schema';
commit;
