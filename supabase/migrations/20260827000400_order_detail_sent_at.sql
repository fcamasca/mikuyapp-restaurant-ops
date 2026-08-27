begin;

alter table public.detalle_pedido
  add column enviado_en timestamptz null;

-- Los registros anteriores a H4 no conservaban un timestamp individual de envío.
-- Se prioriza la auditoría individual cuando demuestra una modificación posterior
-- a la creación; para datos preauditoría se usa el primer envío de la cabecera.
update public.detalle_pedido as detail_row
set enviado_en = coalesce(
  case
    when detail_row.modificado_en > detail_row.creado_en
      then detail_row.modificado_en
    else null
  end,
  order_row.enviado_en,
  detail_row.modificado_en,
  detail_row.creado_en
)
from public.pedido as order_row
where order_row.id = detail_row.pedido_id
  and detail_row.estado in (
    'ENVIADO',
    'RECIBIDO_COCINA',
    'EN_PREPARACION',
    'LISTO'
  );

alter table public.detalle_pedido
  add constraint ck_detalle_pedido_envio_coherente check (
    (estado = 'ABIERTO' and enviado_en is null)
    or (
      estado in (
        'ENVIADO',
        'RECIBIDO_COCINA',
        'EN_PREPARACION',
        'LISTO'
      )
      and enviado_en is not null
    )
  ) not valid;

alter table public.detalle_pedido
  validate constraint ck_detalle_pedido_envio_coherente;

create index idx_detalle_pedido_cocina_enviado_en
  on public.detalle_pedido (enviado_en, pedido_id)
  where estado in (
    'ENVIADO',
    'RECIBIDO_COCINA',
    'EN_PREPARACION',
    'LISTO'
  );

create or replace function public.registrar_auditoria_detalle_pedido()
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
    if old.enviado_en is not null
      and new.enviado_en is distinct from old.enviado_en then
      raise exception using
        errcode = '22000',
        message = 'El timestamp de envío del detalle es inmutable';
    end if;

    if old.enviado_en is null
      and new.enviado_en is not null
      and not (
        old.estado = 'ABIERTO'
        and new.estado = 'ENVIADO'
      ) then
      raise exception using
        errcode = '22000',
        message = 'El timestamp de envío solo puede fijarse al enviar un detalle abierto';
    end if;

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

create or replace function public.enviar_pedido_cocina(
  p_pedido_id bigint
)
returns table (
  pedido_id bigint,
  detalles_enviados integer,
  cabecera_actualizada boolean,
  pedido_estado text,
  enviado_en timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $enviar_pedido_cocina$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_pedido public.pedido%rowtype;
  v_detalles_enviados integer;
  v_envio_detalles timestamptz;
begin
  if p_pedido_id is null or v_usuario_id is null then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para enviar pedidos';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para enviar pedidos';
  end if;

  select order_row.*
  into v_pedido
  from public.pedido as order_row
  where order_row.id = p_pedido_id
    and order_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO',
      'ENVIADO',
      'RECIBIDO_COCINA',
      'EN_PREPARACION',
      'LISTO',
      'ENTREGADO'
    )
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Pedido no disponible para el usuario autenticado';
  end if;

  v_envio_detalles := pg_catalog.clock_timestamp();

  update public.detalle_pedido as detail_row
  set estado = 'ENVIADO', enviado_en = v_envio_detalles
  where detail_row.pedido_id = v_pedido.id
    and detail_row.estado = 'ABIERTO';

  get diagnostics v_detalles_enviados = row_count;

  if v_detalles_enviados = 0 then
    return query
    select
      v_pedido.id,
      0,
      false,
      v_pedido.estado,
      v_pedido.enviado_en;
    return;
  end if;

  if v_pedido.estado = 'ABIERTO' then
    update public.pedido as order_row
    set
      estado = 'ENVIADO',
      enviado_en = v_envio_detalles
    where order_row.id = v_pedido.id;

    insert into public.historial_estado (
      pedido_id,
      estado_anterior,
      estado_nuevo,
      usuario_id
    )
    values (
      v_pedido.id,
      'ABIERTO',
      'ENVIADO',
      v_usuario_id
    );

    v_pedido.estado := 'ENVIADO';
    v_pedido.enviado_en := v_envio_detalles;

    return query
    select
      v_pedido.id,
      v_detalles_enviados,
      true,
      v_pedido.estado,
      v_pedido.enviado_en;
    return;
  end if;

  return query
  select
    v_pedido.id,
    v_detalles_enviados,
    false,
    v_pedido.estado,
    v_pedido.enviado_en;
end;
$enviar_pedido_cocina$;

alter function public.enviar_pedido_cocina(bigint) owner to postgres;
revoke all on function public.enviar_pedido_cocina(bigint) from public;
revoke all on function public.enviar_pedido_cocina(bigint) from anon;
grant execute on function public.enviar_pedido_cocina(bigint) to authenticated;

notify pgrst, 'reload schema';

commit;
