-- E9-T02 — Jornada operativa del local: modelo, asociación obligatoria, triggers y Realtime.
-- Spec aprobado: specs/E9-OperationalDay (E9-D03, D04, D05, D06, D09, D11, D12, D17; DC-07, DC-10, DC-12).
-- Migración aditiva. No agrega estados a pedido, detalle_pedido, mesa ni sesion_caja, no modifica
-- RPC operativas ni financieras existentes y no realiza backfill: aborta si encuentra datos incompatibles.
begin;

-- E9-D04 / DC-12: precondición explícita. Sin backfill ni jornadas ficticias.
do $e9_precondicion$
declare
  v_pedidos bigint;
  v_sesiones bigint;
begin
  select count(*) into v_pedidos from public.pedido;
  select count(*) into v_sesiones from public.sesion_caja;
  if v_pedidos > 0 or v_sesiones > 0 then
    raise exception using
      errcode = 'P0001',
      message = format(
        'E9: la migración requiere pedido y sesion_caja vacías (encontradas: %s pedidos, %s sesiones de caja)',
        v_pedidos, v_sesiones),
      hint = 'E9 no realiza backfill (DC-07/DC-12). La preparación o limpieza del ambiente es una acción separada y autorizada por el responsable del proyecto.';
  end if;
end;
$e9_precondicion$;

-- E9-D03: una fila por periodo real de atención; cierre único; identificación derivada.
create table public.jornada_operativa (
  id bigint generated always as identity not null,
  local_id uuid not null,
  fecha_operativa date not null,
  numero integer not null,
  estado text not null default 'ABIERTA',
  abierta_por uuid not null,
  abierta_en timestamptz not null,
  cerrada_por uuid null,
  cerrada_en timestamptz null,
  idempotency_key uuid not null,
  constraint pk_jornada_operativa primary key (id),
  constraint uq_jornada_operativa_id_local_id unique (id, local_id),
  constraint uq_jornada_operativa_local_fecha_numero unique (local_id, fecha_operativa, numero),
  constraint uq_jornada_operativa_idempotencia unique (local_id, abierta_por, idempotency_key),
  constraint fk_jornada_operativa_local foreign key (local_id)
    references public.local (id) on delete restrict,
  constraint fk_jornada_operativa_abierta_por foreign key (abierta_por)
    references public.perfil_usuario (id) on delete restrict,
  constraint fk_jornada_operativa_cerrada_por foreign key (cerrada_por)
    references public.perfil_usuario (id) on delete restrict,
  constraint ck_jornada_operativa_estado_valido check (estado in ('ABIERTA', 'CERRADA')),
  constraint ck_jornada_operativa_numero_positivo check (numero > 0),
  constraint ck_jornada_operativa_cierre_coherente check (
    (estado = 'ABIERTA' and cerrada_por is null and cerrada_en is null)
    or (estado = 'CERRADA' and cerrada_por is not null and cerrada_en is not null and cerrada_en >= abierta_en)
  ),
  constraint ck_jornada_operativa_fecha_operativa check (
    fecha_operativa = (abierta_en at time zone 'America/Lima')::date
  )
);

create unique index uq_jornada_operativa_local_abierta
  on public.jornada_operativa (local_id)
  where estado = 'ABIERTA';

create index idx_jornada_operativa_local_abierta_en
  on public.jornada_operativa (local_id, abierta_en desc);

comment on table public.jornada_operativa is
  'E9-D03: jornada operativa del local. Entidad transaccional (no maestra ni calendario): nace sólo cuando un ADMINISTRADOR la abre y termina cuando la cierra. Local abierto ⇔ existe una jornada ABIERTA. Identificación visible derivada: Jornada YYYY-MM-DD (N).';
comment on column public.jornada_operativa.fecha_operativa is
  'E9-D03: fecha America/Lima del instante de apertura. No cambia aunque la jornada cruce la medianoche.';
comment on column public.jornada_operativa.numero is
  'E9-D03: correlativo N >= 1 por local y fecha operativa, asignado al abrir.';
comment on column public.jornada_operativa.estado is
  'E9-D03: ABIERTA (local operando) o CERRADA (terminal; nunca se reabre).';
comment on column public.jornada_operativa.abierta_en is
  'E9-D07: hora de servidor (clock_timestamp) tomada después de serializar la apertura del local.';
comment on column public.jornada_operativa.cerrada_en is
  'E9-D08: hora de servidor del cierre; nunca anterior a abierta_en.';
comment on column public.jornada_operativa.idempotency_key is
  'E9-D07: clave de solicitud de apertura por administrador; un reintento con la misma clave devuelve siempre la misma jornada y nunca abre otra.';
comment on constraint ck_jornada_operativa_cierre_coherente on public.jornada_operativa is
  'E9-D03: ABIERTA sin datos de cierre; CERRADA con actor y hora de cierre no anterior a la apertura.';
comment on constraint ck_jornada_operativa_fecha_operativa on public.jornada_operativa is
  'E9-D03: la fecha operativa es la fecha America/Lima de abierta_en.';
comment on index public.uq_jornada_operativa_local_abierta is
  'E9-R02 / I-1: como máximo una jornada ABIERTA por local; defensa final ante cualquier carrera.';
comment on constraint uq_jornada_operativa_local_fecha_numero on public.jornada_operativa is
  'E9-R06: unicidad de la identificación visible Jornada YYYY-MM-DD (N) por local.';
comment on constraint uq_jornada_operativa_id_local_id on public.jornada_operativa is
  'E9-D04: destino de las FK compuestas desde pedido y sesion_caja (misma jornada y mismo local).';

-- E9-D11: lectura de las filas del propio local para los cuatro roles (autorización Realtime).
alter table public.jornada_operativa enable row level security;
revoke all on table public.jornada_operativa from public, anon, authenticated, service_role;
revoke all on sequence public.jornada_operativa_id_seq from public, anon, authenticated, service_role;
grant select on table public.jornada_operativa to authenticated;

create policy pol_jornada_operativa_select_local
on public.jornada_operativa
for select
to authenticated
using (
  exists (
    select 1
    from public.obtener_contexto_autenticado() as auth_context
    where auth_context.local_id = jornada_operativa.local_id
  )
);

comment on policy pol_jornada_operativa_select_local on public.jornada_operativa is
  'E9-D11: los cuatro roles activos leen las jornadas de su local (sólo identificadores y horas) para recibir la señal Realtime de apertura y cierre. Sin políticas de escritura.';

-- E9-D09: sólo se admite el cierre único ABIERTA -> CERRADA; nunca borrado ni reapertura.
create function public.tgf_jornada_operativa_inmutable()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $tgf_jornada_operativa_inmutable$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '23514', message = 'La jornada operativa es inmutable';
  end if;
  if old.estado is distinct from 'ABIERTA'
    or new.estado is distinct from 'CERRADA'
    or new.id is distinct from old.id
    or new.local_id is distinct from old.local_id
    or new.fecha_operativa is distinct from old.fecha_operativa
    or new.numero is distinct from old.numero
    or new.abierta_por is distinct from old.abierta_por
    or new.abierta_en is distinct from old.abierta_en
    or new.idempotency_key is distinct from old.idempotency_key then
    raise exception using errcode = '23514',
      message = 'La jornada operativa sólo admite un cierre desde ABIERTA';
  end if;
  return new;
end;
$tgf_jornada_operativa_inmutable$;

create trigger trg_jornada_operativa_before_update_delete_inmutable
before update or delete on public.jornada_operativa
for each row execute function public.tgf_jornada_operativa_inmutable();

-- E9-D04: obtención y bloqueo compartido de la jornada abierta del local.
create function public.fn_obtener_jornada_operativa_abierta(p_local_id uuid)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog
as $fn_obtener_jornada_operativa_abierta$
declare
  v_jornada_id bigint;
begin
  select day_row.id
  into v_jornada_id
  from public.jornada_operativa as day_row
  where day_row.local_id = p_local_id
    and day_row.estado = 'ABIERTA'
  for share;
  if v_jornada_id is null then
    raise exception using errcode = 'PT409',
      message = 'Local cerrado — el sistema no se encuentra aperturado';
  end if;
  return v_jornada_id;
end;
$fn_obtener_jornada_operativa_abierta$;

-- E9-D04: asociación obligatoria, por FK compuesta al mismo local. Tablas vacías (precondición).
alter table public.pedido
  add column jornada_operativa_id bigint not null,
  add constraint fk_pedido_jornada_operativa_local foreign key (jornada_operativa_id, local_id)
    references public.jornada_operativa (id, local_id) on delete restrict;
create index idx_pedido_jornada_operativa_id_estado
  on public.pedido (jornada_operativa_id, estado);

alter table public.sesion_caja
  add column jornada_operativa_id bigint not null,
  add constraint fk_sesion_caja_jornada_operativa_local foreign key (jornada_operativa_id, local_id)
    references public.jornada_operativa (id, local_id) on delete restrict;
create index idx_sesion_caja_jornada_operativa_id_estado
  on public.sesion_caja (jornada_operativa_id, estado);

comment on column public.pedido.jornada_operativa_id is
  'E9-D04: jornada ABIERTA del local al crear el pedido. La asigna PostgreSQL (trigger), nunca el cliente; inmutable.';
comment on column public.sesion_caja.jornada_operativa_id is
  'E9-D04: jornada ABIERTA del local al abrir la sesión de caja. La asigna PostgreSQL (trigger), nunca el cliente; inmutable.';
comment on index public.idx_pedido_jornada_operativa_id_estado is
  'E9-D08/D10: verificación de cierre y lectura de pendientes por jornada.';
comment on index public.idx_sesion_caja_jornada_operativa_id_estado is
  'E9-D08/D10: verificación de cierre y lectura de pendientes por jornada.';

create function public.tgf_pedido_asignar_jornada_operativa()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $tgf_pedido_asignar_jornada_operativa$
declare
  v_jornada_id bigint;
begin
  if tg_op = 'UPDATE' then
    if new.jornada_operativa_id is distinct from old.jornada_operativa_id then
      raise exception using errcode = '23514',
        message = 'La jornada operativa de un pedido es inmutable';
    end if;
    return new;
  end if;
  v_jornada_id := public.fn_obtener_jornada_operativa_abierta(new.local_id);
  if new.jornada_operativa_id is not null and new.jornada_operativa_id <> v_jornada_id then
    raise exception using errcode = '42501',
      message = 'La jornada operativa la asigna el servidor';
  end if;
  new.jornada_operativa_id := v_jornada_id;
  return new;
end;
$tgf_pedido_asignar_jornada_operativa$;

create trigger trg_pedido_before_insert_update_jornada_operativa
before insert or update of jornada_operativa_id on public.pedido
for each row execute function public.tgf_pedido_asignar_jornada_operativa();

create function public.tgf_sesion_caja_asignar_jornada_operativa()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $tgf_sesion_caja_asignar_jornada_operativa$
declare
  v_jornada_id bigint;
begin
  if tg_op = 'UPDATE' then
    if new.jornada_operativa_id is distinct from old.jornada_operativa_id then
      raise exception using errcode = '23514',
        message = 'La jornada operativa de una sesión de caja es inmutable';
    end if;
    return new;
  end if;
  v_jornada_id := public.fn_obtener_jornada_operativa_abierta(new.local_id);
  if new.jornada_operativa_id is not null and new.jornada_operativa_id <> v_jornada_id then
    raise exception using errcode = '42501',
      message = 'La jornada operativa la asigna el servidor';
  end if;
  new.jornada_operativa_id := v_jornada_id;
  return new;
end;
$tgf_sesion_caja_asignar_jornada_operativa$;

create trigger trg_sesion_caja_before_insert_update_jornada_operativa
before insert or update of jornada_operativa_id on public.sesion_caja
for each row execute function public.tgf_sesion_caja_asignar_jornada_operativa();

-- E9-D06 / I-4: pedido y sesión de caja del cobro pertenecen a la misma jornada. Toda vía de
-- cobro (rpc_registrar_cobro_pedido y vías heredadas) inserta filas pago con su sesion_caja_id.
-- El rechazo adicional de pagos sin sesión previsto en E9-D06 queda detenido y pendiente de
-- decisión del responsable (implementation.md, desviación DV-01): ningún requisito lo exige,
-- ningún cliente puede insertar en pago y afectaría datos y aserciones de tests vigentes.
create function public.tgf_pago_validar_jornada_operativa()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $tgf_pago_validar_jornada_operativa$
declare
  v_jornada_pedido bigint;
  v_jornada_sesion bigint;
begin
  if new.sesion_caja_id is null then
    return new;
  end if;
  select order_row.jornada_operativa_id into v_jornada_pedido
  from public.pedido as order_row where order_row.id = new.pedido_id;
  select session_row.jornada_operativa_id into v_jornada_sesion
  from public.sesion_caja as session_row where session_row.id = new.sesion_caja_id;
  if v_jornada_pedido is distinct from v_jornada_sesion then
    raise exception using errcode = 'PT409',
      message = 'El pedido y la sesión de caja pertenecen a jornadas distintas';
  end if;
  return new;
end;
$tgf_pago_validar_jornada_operativa$;

create trigger trg_pago_before_insert_validar_jornada_operativa
before insert on public.pago
for each row execute function public.tgf_pago_validar_jornada_operativa();

alter function public.tgf_jornada_operativa_inmutable() owner to postgres;
alter function public.fn_obtener_jornada_operativa_abierta(uuid) owner to postgres;
alter function public.tgf_pedido_asignar_jornada_operativa() owner to postgres;
alter function public.tgf_sesion_caja_asignar_jornada_operativa() owner to postgres;
alter function public.tgf_pago_validar_jornada_operativa() owner to postgres;
revoke all on function public.tgf_jornada_operativa_inmutable() from public, anon, authenticated, service_role;
revoke all on function public.fn_obtener_jornada_operativa_abierta(uuid) from public, anon, authenticated, service_role;
revoke all on function public.tgf_pedido_asignar_jornada_operativa() from public, anon, authenticated, service_role;
revoke all on function public.tgf_sesion_caja_asignar_jornada_operativa() from public, anon, authenticated, service_role;
revoke all on function public.tgf_pago_validar_jornada_operativa() from public, anon, authenticated, service_role;

comment on function public.tgf_jornada_operativa_inmutable() is
  'E9-D09 / I-5: rechaza DELETE, reapertura y cualquier UPDATE distinto del cierre único ABIERTA -> CERRADA.';
comment on function public.fn_obtener_jornada_operativa_abierta(uuid) is
  'E9-D04 (interna): devuelve la jornada ABIERTA del local bloqueándola FOR SHARE (conflicto con el FOR UPDATE del cierre); sin jornada abierta rechaza con PT409 "Local cerrado — el sistema no se encuentra aperturado".';
comment on function public.tgf_pedido_asignar_jornada_operativa() is
  'E9-D04 / DC-10: al crear un pedido, por cualquier vía, asigna la jornada abierta del local; rechaza un valor distinto suministrado y cualquier cambio posterior.';
comment on function public.tgf_sesion_caja_asignar_jornada_operativa() is
  'E9-D04 / DC-10: al abrir una sesión de caja, por cualquier vía, asigna la jornada abierta del local; rechaza un valor distinto suministrado y cualquier cambio posterior.';
comment on function public.tgf_pago_validar_jornada_operativa() is
  'E9-D06 / I-4: rechaza con PT409 un pago cuyo pedido y sesión de caja pertenecen a jornadas distintas, para toda vía de cobro.';

-- E9-D12: señal Realtime de apertura y cierre; no se quita ninguna tabla publicada.
do $e9_realtime_publication$
begin
  if not exists (
    select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime'
  ) then
    create publication supabase_realtime;
  end if;
  if not exists (
    select 1 from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'jornada_operativa'
  ) then
    alter publication supabase_realtime add table public.jornada_operativa;
  end if;
end;
$e9_realtime_publication$;

notify pgrst, 'reload schema';

commit;
