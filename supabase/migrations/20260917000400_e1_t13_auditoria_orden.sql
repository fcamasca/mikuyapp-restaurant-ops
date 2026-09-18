begin;

create or replace function public.rpc_obtener_auditoria_financiera(
  p_sesion_caja_id uuid default null,
  p_pedido_id bigint default null,
  p_limite integer default 200
)
returns setof public.auditoria_caja
language plpgsql stable security definer set search_path=pg_catalog as $$
declare
  v_actor uuid:=auth.uid();
  v_local uuid;
  v_rol text;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol
  from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol not in ('CAJA','ADMINISTRADOR') then
    raise exception using errcode='42501',message='No autorizado para consultar auditoría financiera';
  end if;
  if (p_sesion_caja_id is null and p_pedido_id is null)
    or p_limite is null or p_limite<1 or p_limite>500 then
    raise exception using errcode='22023',message='Filtro o límite de auditoría inválido';
  end if;
  return query
    select a.* from public.auditoria_caja a
    where a.local_id=v_local
      and (p_sesion_caja_id is null or a.sesion_caja_id=p_sesion_caja_id)
      and (p_pedido_id is null or a.pedido_id=p_pedido_id)
    order by a.creado_en,
      case a.tipo
        when 'APERTURA' then 10
        when 'ENTRADA' then 20 when 'SALIDA' then 20
        when 'SOLICITUD_DESCUENTO' then 30
        when 'AUTORIZACION_DESCUENTO' then 40 when 'RECHAZO_DESCUENTO' then 40
        when 'PAGO' then 50 when 'ANULACION' then 50
        when 'CIERRE' then 60 when 'CIERRE_SUPERVISOR' then 60
        else 99
      end,a.id
    limit p_limite;
end $$;
alter function public.rpc_obtener_auditoria_financiera(uuid,bigint,integer) owner to postgres;
revoke all on function public.rpc_obtener_auditoria_financiera(uuid,bigint,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.rpc_obtener_auditoria_financiera(uuid,bigint,integer)
  to authenticated;
comment on function public.rpc_obtener_auditoria_financiera(uuid,bigint,integer) is
  'CAJA/ADMINISTRADOR activo: reconstrucción append-only por sesión/pedido del mismo local, con precedencia determinista cuando eventos comparten timestamp.';

commit;
