begin;

create function public.rpc_obtener_flujo_actual_pedidos_admin()
returns table(servidor_ahora timestamptz, grupos jsonb)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $function$
declare
  v_local_id uuid;
  v_rol_codigo text;
  v_ahora timestamptz := pg_catalog.statement_timestamp();
begin
  select contexto.local_id, contexto.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as contexto;

  if auth.uid() is null
    or v_local_id is null
    or v_rol_codigo is distinct from 'ADMINISTRADOR' then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para consultar el flujo actual de pedidos';
  end if;

  return query
  with definiciones(orden, codigo, nombre) as (
    values
      (1, 'POR_RECIBIR'::text, 'POR RECIBIR'::text),
      (2, 'EN_PREPARACION'::text, 'EN PREPARACIÓN'::text),
      (3, 'LISTOS_PARA_ENTREGAR'::text, 'LISTOS PARA ENTREGAR'::text)
  ), pedidos_actuales as (
    select
      pedido.id as pedido_id,
      mesa.codigo as mesa_codigo,
      mesa.nombre as mesa_nombre,
      pedido.estado,
      case
        when pedido.estado = 'ENVIADO' then 'POR_RECIBIR'
        when pedido.estado in ('RECIBIDO_COCINA', 'EN_PREPARACION') then 'EN_PREPARACION'
        when pedido.estado = 'LISTO' then 'LISTOS_PARA_ENTREGAR'
      end as grupo_codigo,
      coalesce(
        (
          select pg_catalog.max(historial.creado_en)
          from public.historial_estado as historial
          where historial.pedido_id = pedido.id
            and (
              (pedido.estado = 'ENVIADO' and historial.estado_nuevo = 'ENVIADO')
              or (
                pedido.estado in ('RECIBIDO_COCINA', 'EN_PREPARACION')
                and historial.estado_nuevo in ('RECIBIDO_COCINA', 'EN_PREPARACION')
                and (
                  historial.estado_anterior is null
                  or historial.estado_anterior not in ('RECIBIDO_COCINA', 'EN_PREPARACION')
                )
              )
              or (pedido.estado = 'LISTO' and historial.estado_nuevo = 'LISTO')
            )
        ),
        case when pedido.estado = 'ENVIADO' then pedido.enviado_en end,
        pedido.creado_en
      ) as ingreso_grupo_en
    from public.pedido as pedido
    join public.mesa as mesa
      on mesa.id = pedido.mesa_id
      and mesa.local_id = pedido.local_id
    where pedido.local_id = v_local_id
      and pedido.estado in ('ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO')
  ), esperas as (
    select pedidos_actuales.*,
      greatest(
        0,
        pg_catalog.floor(extract(epoch from (v_ahora - ingreso_grupo_en)))
      )::bigint as espera_segundos
    from pedidos_actuales
  )
  select v_ahora,
    coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'codigo', definiciones.codigo,
          'nombre', definiciones.nombre,
          'cantidad', (select pg_catalog.count(*) from esperas where esperas.grupo_codigo = definiciones.codigo),
          'mayor_espera_segundos', (select pg_catalog.max(esperas.espera_segundos) from esperas where esperas.grupo_codigo = definiciones.codigo),
          'promedio_espera_segundos', (select pg_catalog.round(pg_catalog.avg(esperas.espera_segundos))::bigint from esperas where esperas.grupo_codigo = definiciones.codigo),
          'mesas', coalesce((
            select pg_catalog.jsonb_agg(mesas.mesa_codigo order by mesas.mesa_codigo)
            from (
              select distinct esperas.mesa_codigo
              from esperas
              where esperas.grupo_codigo = definiciones.codigo
            ) as mesas
          ), '[]'::jsonb),
          'pedidos', coalesce((
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'pedido_id', esperas.pedido_id,
                'mesa_codigo', esperas.mesa_codigo,
                'mesa_nombre', esperas.mesa_nombre,
                'estado_actual', esperas.estado,
                'ingreso_grupo_en', esperas.ingreso_grupo_en,
                'espera_segundos', esperas.espera_segundos
              ) order by esperas.espera_segundos desc, esperas.pedido_id
            )
            from esperas
            where esperas.grupo_codigo = definiciones.codigo
          ), '[]'::jsonb)
        ) order by definiciones.orden
      ),
      '[]'::jsonb
    )
  from definiciones;
end;
$function$;

alter function public.rpc_obtener_flujo_actual_pedidos_admin() owner to postgres;
revoke all on function public.rpc_obtener_flujo_actual_pedidos_admin()
  from public, anon, authenticated, service_role;
grant execute on function public.rpc_obtener_flujo_actual_pedidos_admin()
  to authenticated;

comment on function public.rpc_obtener_flujo_actual_pedidos_admin() is
  'ADMINISTRADOR: snapshot no persistido del flujo actual de pedidos abiertos del local autenticado, con tiempos calculados usando hora servidor.';

notify pgrst, 'reload schema';
commit;
