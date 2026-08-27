begin;

create or replace function public.obtener_creadores_pedidos_vigentes(
  p_pedido_ids bigint[]
)
returns table (
  pedido_id bigint,
  creador_nombre text
)
language plpgsql
security definer
set search_path = pg_catalog
as $obtener_creadores_pedidos_vigentes$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
begin
  if v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No autorizado para consultar responsables de pedidos';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using errcode = '42501', message = 'No autorizado para consultar responsables de pedidos';
  end if;

  return query
  select order_row.id, profile_row.nombre
  from public.pedido as order_row
  inner join public.perfil_usuario as profile_row on profile_row.id = order_row.creado_por
  where order_row.id = any(coalesce(p_pedido_ids, array[]::bigint[]))
    and order_row.local_id = v_local_id
    and order_row.estado in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO', 'ENTREGADO');
end;
$obtener_creadores_pedidos_vigentes$;

alter function public.obtener_creadores_pedidos_vigentes(bigint[]) owner to postgres;
revoke all on function public.obtener_creadores_pedidos_vigentes(bigint[]) from public;
revoke all on function public.obtener_creadores_pedidos_vigentes(bigint[]) from anon;
grant execute on function public.obtener_creadores_pedidos_vigentes(bigint[]) to authenticated;

notify pgrst, 'reload schema';

commit;
