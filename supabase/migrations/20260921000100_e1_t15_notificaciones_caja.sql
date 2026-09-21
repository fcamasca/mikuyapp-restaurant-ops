begin;

create table public.notificacion_caja (
  id uuid not null default gen_random_uuid(),
  auditoria_caja_id uuid not null,
  local_id uuid not null,
  sesion_caja_id uuid not null,
  tipo text not null,
  prioridad text not null,
  creado_en timestamptz not null,
  constraint pk_notificacion_caja primary key (id),
  constraint uq_notificacion_caja_auditoria unique (auditoria_caja_id),
  constraint ck_notificacion_caja_tipo check (tipo in ('APERTURA', 'CIERRE')),
  constraint ck_notificacion_caja_prioridad check (prioridad in ('INFORMATIVA', 'ALERTA')),
  constraint ck_notificacion_caja_prioridad_evento check (
    tipo = 'CIERRE' or prioridad = 'INFORMATIVA'
  ),
  constraint fk_notificacion_caja_auditoria foreign key (auditoria_caja_id)
    references public.auditoria_caja (id) on delete restrict,
  constraint fk_notificacion_caja_local foreign key (local_id)
    references public.local (id) on delete restrict,
  constraint fk_notificacion_caja_sesion foreign key (sesion_caja_id)
    references public.sesion_caja (id) on delete restrict
);

create table public.notificacion_caja_destinatario (
  notificacion_caja_id uuid not null,
  administrador_id uuid not null,
  leida_en timestamptz null,
  constraint pk_notificacion_caja_destinatario
    primary key (notificacion_caja_id, administrador_id),
  constraint fk_notificacion_caja_destinatario_notificacion
    foreign key (notificacion_caja_id)
    references public.notificacion_caja (id) on delete restrict,
  constraint fk_notificacion_caja_destinatario_administrador
    foreign key (administrador_id)
    references public.perfil_usuario (id) on delete restrict
);

create index idx_notificacion_caja_local_creado_en
  on public.notificacion_caja (local_id, creado_en desc, id);
create index idx_notificacion_caja_destinatario_admin_no_leida
  on public.notificacion_caja_destinatario (administrador_id, notificacion_caja_id)
  where leida_en is null;

alter table public.notificacion_caja enable row level security;
alter table public.notificacion_caja_destinatario enable row level security;
revoke all on public.notificacion_caja, public.notificacion_caja_destinatario
  from public, anon, authenticated, service_role;

create trigger trg_notificacion_caja_before_write
  before update or delete on public.notificacion_caja
  for each row execute function public.tgf_evento_caja_inmutable();

create function public.tgf_generar_notificacion_caja()
returns trigger language plpgsql security definer set search_path = pg_catalog as $$
declare
  v_notificacion_id uuid;
  v_tipo text;
  v_prioridad text;
begin
  if new.tipo not in ('APERTURA', 'CIERRE', 'CIERRE_SUPERVISOR') then
    return new;
  end if;

  v_tipo := case when new.tipo = 'APERTURA' then 'APERTURA' else 'CIERRE' end;
  v_prioridad := case
    when v_tipo = 'CIERRE' and new.diferencia is distinct from 0 then 'ALERTA'
    else 'INFORMATIVA'
  end;

  insert into public.notificacion_caja (
    auditoria_caja_id, local_id, sesion_caja_id, tipo, prioridad, creado_en
  ) values (
    new.id, new.local_id, new.sesion_caja_id, v_tipo, v_prioridad, new.creado_en
  )
  returning id into v_notificacion_id;

  insert into public.notificacion_caja_destinatario (
    notificacion_caja_id, administrador_id
  )
  select v_notificacion_id, p.id
  from public.perfil_usuario p
  join public.rol r on r.id = p.rol_id
  where p.local_id = new.local_id
    and p.activo
    and r.activo
    and r.codigo = 'ADMINISTRADOR'
  on conflict (notificacion_caja_id, administrador_id) do nothing;

  return new;
end;
$$;

alter function public.tgf_generar_notificacion_caja() owner to postgres;
revoke all on function public.tgf_generar_notificacion_caja()
  from public, anon, authenticated, service_role;

create trigger trg_auditoria_caja_after_insert_notificacion
  after insert on public.auditoria_caja
  for each row
  when (new.tipo in ('APERTURA', 'CIERRE', 'CIERRE_SUPERVISOR'))
  execute function public.tgf_generar_notificacion_caja();

create function public.rpc_obtener_notificaciones_caja()
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

create function public.rpc_marcar_notificacion_caja_leida(p_notificacion_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare
  v_actor uuid := auth.uid();
  v_local uuid;
  v_rol text;
  v_leida_en timestamptz;
begin
  select c.local_id, c.rol_codigo into v_local, v_rol
  from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then
    raise exception using errcode = '42501', message = 'No autorizado para actualizar notificaciones';
  end if;
  if p_notificacion_id is null then
    raise exception using errcode = '22023', message = 'Notificación inválida';
  end if;

  update public.notificacion_caja_destinatario d
  set leida_en = coalesce(d.leida_en, clock_timestamp())
  from public.notificacion_caja n
  where d.notificacion_caja_id = p_notificacion_id
    and d.administrador_id = v_actor
    and n.id = d.notificacion_caja_id
    and n.local_id = v_local
  returning d.leida_en into v_leida_en;

  if v_leida_en is null then
    raise exception using errcode = '42501', message = 'Notificación no disponible';
  end if;
  return jsonb_build_object('id', p_notificacion_id, 'leida_en', v_leida_en);
end;
$$;

alter function public.rpc_obtener_notificaciones_caja() owner to postgres;
alter function public.rpc_marcar_notificacion_caja_leida(uuid) owner to postgres;
revoke all on function public.rpc_obtener_notificaciones_caja(),
  public.rpc_marcar_notificacion_caja_leida(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.rpc_obtener_notificaciones_caja(),
  public.rpc_marcar_notificacion_caja_leida(uuid) to authenticated;

comment on table public.notificacion_caja is
  'Notificación interna mínima de APERTURA/CIERRE referenciada a auditoría; no duplica importes ni snapshots financieros.';
comment on table public.notificacion_caja_destinatario is
  'Entrega individual a cada ADMINISTRADOR activo del local al producirse el evento; conserva únicamente su lectura.';
comment on function public.rpc_obtener_notificaciones_caja() is
  'ADMINISTRADOR activo: lista sus avisos recientes y contador no leído del mismo local; resuelve actor legible internamente sin ampliar SELECT directo de perfil_usuario.';
comment on function public.rpc_marcar_notificacion_caja_leida(uuid) is
  'ADMINISTRADOR activo: marca idempotentemente como leída únicamente su propia entrega local.';

notify pgrst, 'reload schema';
commit;
