begin;

create or replace function public.rpc_obtener_notificaciones_caja()
returns jsonb language plpgsql stable security definer set search_path = pg_catalog as $$
declare
  v_actor uuid := auth.uid();
  v_local uuid;
  v_rol text;
  v_no_leidas integer;
  v_notificaciones jsonb;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol
  from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then
    raise exception using errcode = '42501', message = 'No autorizado para consultar notificaciones';
  end if;

  select count(*)::integer into v_no_leidas
  from public.notificacion_caja_destinatario d
  join public.notificacion_caja n on n.id = d.notificacion_caja_id
  where d.administrador_id = v_actor and n.local_id = v_local and d.leida_en is null;

  select coalesce(jsonb_agg(item order by creado_en desc, id desc), '[]'::jsonb)
  into v_notificaciones
  from (
    select
      n.id,
      n.tipo,
      n.prioridad,
      n.creado_en,
      d.leida_en,
      c.codigo as caja_codigo,
      c.nombre as caja_nombre,
      a.actor_id,
      p.nombre as actor_nombre,
      a.monto_inicial,
      a.efectivo_esperado,
      a.efectivo_contado,
      a.diferencia,
      a.motivo
    from public.notificacion_caja_destinatario d
    join public.notificacion_caja n on n.id = d.notificacion_caja_id
    join public.auditoria_caja a on a.id = n.auditoria_caja_id
    join public.caja c on c.id = a.caja_id and c.local_id = n.local_id
    join public.perfil_usuario p on p.id = a.actor_id
    where d.administrador_id = v_actor and n.local_id = v_local
    order by n.creado_en desc, n.id desc
    limit 50
  ) item;

  return jsonb_build_object('no_leidas', v_no_leidas, 'notificaciones', v_notificaciones);
end;
$$;

create function public.rpc_marcar_notificaciones_caja_leidas()
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare
  v_actor uuid := auth.uid();
  v_local uuid;
  v_rol text;
  v_leida_en timestamptz := clock_timestamp();
  v_actualizadas integer;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol
  from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then
    raise exception using errcode = '42501', message = 'No autorizado para actualizar notificaciones';
  end if;

  update public.notificacion_caja_destinatario d
  set leida_en = v_leida_en
  from public.notificacion_caja n
  where d.administrador_id = v_actor
    and d.leida_en is null
    and n.id = d.notificacion_caja_id
    and n.local_id = v_local;

  get diagnostics v_actualizadas = row_count;
  return jsonb_build_object('actualizadas', v_actualizadas, 'leida_en', v_leida_en);
end;
$$;

alter function public.rpc_marcar_notificaciones_caja_leidas() owner to postgres;
revoke all on function public.rpc_marcar_notificaciones_caja_leidas()
  from public, anon, authenticated, service_role;
grant execute on function public.rpc_marcar_notificaciones_caja_leidas() to authenticated;

comment on function public.rpc_obtener_notificaciones_caja() is
  'ADMINISTRADOR activo: devuelve sus 50 avisos más recientes y el contador total no leído del mismo local; resuelve actor legible sin ampliar SELECT directo de perfil_usuario.';
comment on function public.rpc_marcar_notificaciones_caja_leidas() is
  'ADMINISTRADOR activo: marca como leídas todas sus entregas pendientes del mismo local sin afectar a otros destinatarios.';

notify pgrst, 'reload schema';
commit;
