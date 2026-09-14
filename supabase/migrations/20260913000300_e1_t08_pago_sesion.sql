begin;

-- E1-T08 estructural/legacy. Las filas existentes quedan identificables por
-- sesion_caja_id/idempotency_key NULL y propina cero; no se inventan sesiones.
alter table public.pago
  add column sesion_caja_id uuid null,
  add column propina numeric(10,2) not null default 0,
  add column idempotency_key uuid null;

alter table public.pago
  add constraint ck_pago_propina_no_negativa check (
    propina >= 0 and propina <> 'NaN'::numeric
  ),
  add constraint ck_pago_asociacion_e1 check (
    (sesion_caja_id is null and idempotency_key is null and propina = 0)
    or (sesion_caja_id is not null and idempotency_key is not null)
  ),
  add constraint fk_pago_sesion_caja foreign key (sesion_caja_id)
    references public.sesion_caja (id) on delete restrict;

alter table public.pago drop constraint uq_pago_pedido_id;
create index idx_pago_pedido_id on public.pago (pedido_id);
create index idx_pago_sesion_caja_id on public.pago (sesion_caja_id)
  where sesion_caja_id is not null;
create unique index uq_pago_sesion_actor_idempotencia
  on public.pago (sesion_caja_id, usuario_id, idempotency_key)
  where idempotency_key is not null;

create function public.rpc_registrar_pago_total_pedido(
  p_pedido_id bigint,
  p_sesion_caja_id uuid,
  p_medio text,
  p_propina numeric,
  p_idempotency_key uuid
)
returns table (
  pago_id bigint,
  pedido_id bigint,
  pedido_estado text,
  mesa_id uuid,
  mesa_estado text,
  importe numeric,
  propina numeric,
  medio text,
  sesion_caja_id uuid,
  pagado_en timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $rpc_registrar_pago_total_pedido$
declare
  v_actor uuid := auth.uid();
  v_local uuid;
  v_rol text;
  v_caja_id uuid;
  v_sesion public.sesion_caja%rowtype;
  v_pedido public.pedido%rowtype;
  v_mesa public.mesa%rowtype;
  v_importe public.pago.importe%type;
  v_pago public.pago%rowtype;
begin
  select contexto.local_id, contexto.rol_codigo
  into v_local, v_rol
  from public.obtener_contexto_autenticado() as contexto;

  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode = '42501', message = 'No autorizado para registrar pagos';
  end if;
  if p_pedido_id is null or p_sesion_caja_id is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'Pedido, sesión y clave de solicitud son obligatorios';
  end if;
  if p_medio is null or p_medio not in ('EFECTIVO', 'YAPE', 'PLIN', 'TARJETA') then
    raise exception using errcode = '22023', message = 'Medio de pago inválido';
  end if;
  if p_propina is null or p_propina < 0 or p_propina >= 100000000
    or p_propina <> pg_catalog.round(p_propina, 2) then
    raise exception using errcode = '22023', message = 'Propina inválida';
  end if;

  -- Orden aprobado: caja -> sesión -> pedido -> mesa.
  select sesion.caja_id
  into v_caja_id
  from public.sesion_caja as sesion
  where sesion.id = p_sesion_caja_id
    and sesion.local_id = v_local;

  if v_caja_id is null then
    raise exception using errcode = '42501', message = 'Sesión no disponible para el usuario autenticado';
  end if;

  perform 1
  from public.caja as caja
  where caja.id = v_caja_id
    and caja.local_id = v_local
    and caja.activo
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Caja no disponible para el usuario autenticado';
  end if;

  select sesion.*
  into strict v_sesion
  from public.sesion_caja as sesion
  where sesion.id = p_sesion_caja_id
    and sesion.caja_id = v_caja_id
    and sesion.local_id = v_local
  for update;

  -- La idempotencia se resuelve antes de validar terminalidad. Un retry del
  -- pago confirmado devuelve el mismo resultado sin una segunda fila.
  select pago.*
  into v_pago
  from public.pago as pago
  where pago.sesion_caja_id = v_sesion.id
    and pago.usuario_id = v_actor
    and pago.idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_pago.pedido_id <> p_pedido_id
      or v_pago.medio <> p_medio
      or v_pago.propina <> p_propina then
      raise exception using errcode = '22023', message = 'Clave de solicitud reutilizada con otros datos';
    end if;
    select pedido.* into strict v_pedido
    from public.pedido as pedido where pedido.id = v_pago.pedido_id;
    return query select v_pago.id, v_pago.pedido_id, 'PAGADO'::text,
      v_pedido.mesa_id, 'LIBRE'::text, v_pago.importe, v_pago.propina,
      v_pago.medio, v_pago.sesion_caja_id, v_pago.pagado_en;
    return;
  end if;

  if v_sesion.estado is distinct from 'ABIERTA' then
    raise exception using errcode = '40001', message = 'La sesión de caja ya no está abierta';
  end if;

  select pedido.*
  into v_pedido
  from public.pedido as pedido
  where pedido.id = p_pedido_id
    and pedido.local_id = v_local
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Pedido no disponible para el usuario autenticado';
  end if;
  if v_pedido.estado is distinct from 'ENTREGADO' then
    raise exception using errcode = '40001', message = 'El pedido ya no está disponible para cobro';
  end if;

  select mesa.*
  into v_mesa
  from public.mesa as mesa
  where mesa.id = v_pedido.mesa_id
    and mesa.local_id = v_local
    and mesa.activo
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Mesa no disponible para el usuario autenticado';
  end if;
  if v_mesa.estado is distinct from 'PENDIENTE_PAGO' then
    raise exception using errcode = '40001', message = 'La mesa ya no está pendiente de pago';
  end if;

  select pg_catalog.sum(detalle.cantidad * detalle.precio_unitario)
  into v_importe
  from public.detalle_pedido as detalle
  where detalle.pedido_id = v_pedido.id;

  if v_importe is null or v_importe <= 0 then
    raise exception using errcode = '55000', message = 'El pedido no tiene un importe positivo para cobrar';
  end if;

  insert into public.pago (
    pedido_id, importe, medio, usuario_id, sesion_caja_id, propina, idempotency_key
  ) values (
    v_pedido.id, v_importe, p_medio, v_actor, v_sesion.id, p_propina, p_idempotency_key
  ) returning * into strict v_pago;

  update public.pedido as pedido
  set estado = 'PAGADO'
  where pedido.id = v_pedido.id and pedido.estado = 'ENTREGADO';
  if not found then
    raise exception using errcode = '40001', message = 'El pedido cambió durante el cobro';
  end if;

  insert into public.historial_estado (
    pedido_id, estado_anterior, estado_nuevo, usuario_id
  ) values (v_pedido.id, 'ENTREGADO', 'PAGADO', v_actor);

  update public.mesa as mesa
  set estado = 'LIBRE'
  where mesa.id = v_mesa.id
    and mesa.local_id = v_local
    and mesa.estado = 'PENDIENTE_PAGO';
  if not found then
    raise exception using errcode = '40001', message = 'La mesa cambió durante el cobro';
  end if;

  return query select v_pago.id, v_pedido.id, 'PAGADO'::text, v_mesa.id,
    'LIBRE'::text, v_pago.importe, v_pago.propina, v_pago.medio,
    v_pago.sesion_caja_id, v_pago.pagado_en;
end;
$rpc_registrar_pago_total_pedido$;

-- Compatibilidad de la UI H5: conserva firma y retorno. Sólo deriva sesión
-- cuando existe exactamente una ABIERTA en el local; nunca elige caja al azar.
create or replace function public.registrar_pago_pedido(
  p_pedido_id bigint,
  p_medio text
)
returns table (
  pago_id bigint,
  pedido_id bigint,
  pedido_estado text,
  mesa_id uuid,
  mesa_estado text,
  importe numeric,
  medio text,
  pagado_en timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $registrar_pago_pedido$
declare
  v_actor uuid := auth.uid();
  v_local uuid;
  v_rol text;
  v_sesion_id uuid;
  v_cantidad_sesiones bigint;
begin
  select contexto.local_id, contexto.rol_codigo
  into v_local, v_rol
  from public.obtener_contexto_autenticado() as contexto;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode = '42501', message = 'No autorizado para registrar pagos';
  end if;
  if p_medio is null or p_medio not in ('EFECTIVO', 'YAPE', 'PLIN', 'TARJETA') then
    raise exception using errcode = '22023', message = 'Medio de pago inválido';
  end if;
  if not exists (
    select 1 from public.pedido as pedido
    where pedido.id = p_pedido_id and pedido.local_id = v_local
  ) then
    raise exception using errcode = '42501', message = 'Pedido no disponible para el usuario autenticado';
  end if;

  select sesion.id
  into v_sesion_id
  from public.sesion_caja as sesion
  inner join public.caja as caja
    on caja.id = sesion.caja_id and caja.local_id = sesion.local_id
  where sesion.local_id = v_local and sesion.estado = 'ABIERTA' and caja.activo
  order by sesion.abierta_en, sesion.id
  limit 1;

  if v_sesion_id is null then
    raise exception using errcode = '40001', message = 'Debe abrir una sesión de caja antes de cobrar';
  end if;

  select pg_catalog.count(*)
  into v_cantidad_sesiones
  from public.sesion_caja as sesion
  inner join public.caja as caja
    on caja.id = sesion.caja_id and caja.local_id = sesion.local_id
  where sesion.local_id = v_local and sesion.estado = 'ABIERTA' and caja.activo;
  if v_cantidad_sesiones > 1 then
    raise exception using errcode = '22023', message = 'Seleccione explícitamente la sesión de caja para cobrar';
  end if;

  return query
  select resultado.pago_id, resultado.pedido_id, resultado.pedido_estado,
    resultado.mesa_id, resultado.mesa_estado, resultado.importe,
    resultado.medio, resultado.pagado_en
  from public.rpc_registrar_pago_total_pedido(
    p_pedido_id, v_sesion_id, p_medio, 0, gen_random_uuid()
  ) as resultado;
end;
$registrar_pago_pedido$;

alter function public.rpc_registrar_pago_total_pedido(bigint,uuid,text,numeric,uuid) owner to postgres;
alter function public.registrar_pago_pedido(bigint,text) owner to postgres;
revoke all on function public.rpc_registrar_pago_total_pedido(bigint,uuid,text,numeric,uuid),
  public.registrar_pago_pedido(bigint,text) from public, anon, authenticated, service_role;
grant execute on function public.rpc_registrar_pago_total_pedido(bigint,uuid,text,numeric,uuid),
  public.registrar_pago_pedido(bigint,text) to authenticated;

comment on column public.pago.sesion_caja_id is
  'Sesión abierta que confirmó el pago. NULL identifica exclusivamente filas legacy sin evidencia; no se fabrica asociación retroactiva.';
comment on column public.pago.propina is
  'Importe de propina separado de pago.importe; no reduce el total de venta. Cero para filas legacy.';
comment on column public.pago.idempotency_key is
  'Clave de solicitud obligatoria para pagos E1 nuevos y NULL sólo en filas legacy.';
comment on function public.rpc_registrar_pago_total_pedido(bigint,uuid,text,numeric,uuid) is
  'T08: cobro total H5 asociado a sesión abierta, actor autenticado, propina separada e idempotencia. No implementa parciales ni descuentos.';
comment on function public.registrar_pago_pedido(bigint,text) is
  'Adaptador H5 de cobro total: exige una única sesión abierta del local y delega en la RPC T08 con propina cero.';

notify pgrst, 'reload schema';
commit;
