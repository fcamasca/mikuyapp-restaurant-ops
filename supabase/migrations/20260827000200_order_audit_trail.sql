begin;

alter table public.pedido
  add column modificado_por uuid,
  add column modificado_en timestamptz;

update public.pedido
set modificado_por = creado_por,
    modificado_en = creado_en;

alter table public.pedido
  alter column modificado_por set not null,
  alter column modificado_en set not null,
  add constraint fk_pedido_modificado_por foreign key (modificado_por)
    references public.perfil_usuario (id) on delete restrict;

alter table public.detalle_pedido
  add column creado_por uuid,
  add column creado_en timestamptz,
  add column modificado_por uuid,
  add column modificado_en timestamptz;

update public.detalle_pedido as detail_row
set creado_por = order_row.creado_por,
    creado_en = order_row.creado_en,
    modificado_por = order_row.creado_por,
    modificado_en = order_row.creado_en
from public.pedido as order_row
where order_row.id = detail_row.pedido_id;

alter table public.detalle_pedido
  alter column creado_por set not null,
  alter column creado_en set not null,
  alter column modificado_por set not null,
  alter column modificado_en set not null,
  alter column creado_en set default now(),
  alter column modificado_en set default now(),
  add constraint fk_detalle_pedido_creado_por foreign key (creado_por)
    references public.perfil_usuario (id) on delete restrict,
  add constraint fk_detalle_pedido_modificado_por foreign key (modificado_por)
    references public.perfil_usuario (id) on delete restrict;

create function public.conservar_auditoria_pedido()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $conservar_auditoria_pedido$
begin
  if tg_op = 'INSERT' then
    new.modificado_por := new.creado_por;
    new.modificado_en := new.creado_en;
  else
    new.creado_por := old.creado_por;
    new.creado_en := old.creado_en;
  end if;
  return new;
end;
$conservar_auditoria_pedido$;

alter function public.conservar_auditoria_pedido() owner to postgres;
revoke all on function public.conservar_auditoria_pedido() from public;
revoke all on function public.conservar_auditoria_pedido() from anon;
revoke all on function public.conservar_auditoria_pedido() from authenticated;

create trigger pedido_conservar_auditoria_creacion
before insert or update on public.pedido
for each row execute function public.conservar_auditoria_pedido();

create function public.registrar_auditoria_detalle_pedido()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $registrar_auditoria_detalle_pedido$
declare
  v_usuario_id uuid := auth.uid();
  v_pedido_id bigint;
  v_actualiza_contenido boolean := false;
begin
  v_pedido_id := case when tg_op = 'DELETE' then old.pedido_id else new.pedido_id end;

  if v_usuario_id is null then
    select order_row.creado_por
    into v_usuario_id
    from public.pedido as order_row
    where order_row.id = v_pedido_id;
  end if;

  if v_usuario_id is null then
    raise exception using errcode = '42501', message = 'No se pudo determinar el autor de la modificación';
  end if;

  if tg_op = 'INSERT' then
    new.creado_por := v_usuario_id;
    new.modificado_por := v_usuario_id;
    new.modificado_en := new.creado_en;
    v_actualiza_contenido := true;
  elsif tg_op = 'UPDATE' then
    new.creado_por := old.creado_por;
    new.creado_en := old.creado_en;
    if new.cantidad is distinct from old.cantidad
      or new.observacion is distinct from old.observacion
      or new.estado is distinct from old.estado
      or new.pedido_id is distinct from old.pedido_id
      or new.producto_id is distinct from old.producto_id then
      new.modificado_por := v_usuario_id;
      new.modificado_en := pg_catalog.clock_timestamp();
    end if;
    v_actualiza_contenido := new.cantidad is distinct from old.cantidad
      or new.observacion is distinct from old.observacion
      or new.pedido_id is distinct from old.pedido_id
      or new.producto_id is distinct from old.producto_id;
  else
    v_actualiza_contenido := true;
  end if;

  if v_actualiza_contenido then
    update public.pedido as order_row
    set modificado_por = v_usuario_id,
        modificado_en = pg_catalog.clock_timestamp()
    where order_row.id = v_pedido_id;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$registrar_auditoria_detalle_pedido$;

alter function public.registrar_auditoria_detalle_pedido() owner to postgres;
revoke all on function public.registrar_auditoria_detalle_pedido() from public;
revoke all on function public.registrar_auditoria_detalle_pedido() from anon;
revoke all on function public.registrar_auditoria_detalle_pedido() from authenticated;

create trigger detalle_pedido_registrar_auditoria
before insert or update or delete on public.detalle_pedido
for each row execute function public.registrar_auditoria_detalle_pedido();

create function public.obtener_creadores_pedidos_vigentes(
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
  where order_row.id = any(pg_catalog.coalesce(p_pedido_ids, array[]::bigint[]))
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
