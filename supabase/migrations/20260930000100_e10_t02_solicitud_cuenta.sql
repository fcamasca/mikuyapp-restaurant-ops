-- E10-T02 — Solicitud de cuenta y atención en caja: modelo, cierre automático y Realtime.
-- Spec aprobado: specs/E10-AccountRequest (E10-D03, D05, D06, D07, D09, D17).
-- Migración aditiva. No agrega estados a pedido, detalle_pedido ni mesa y no modifica
-- ninguna RPC financiera de E1: el cierre se deriva de la transición de pedido.estado.
begin;

-- E10-D03: una fila por solicitud; cierre único; mesa derivada de pedido.mesa_id (inmutable).
create table public.solicitud_cuenta (
  id bigint generated always as identity not null,
  local_id uuid not null,
  pedido_id bigint not null,
  estado text not null default 'PENDIENTE',
  solicitada_por uuid not null,
  solicitada_en timestamptz not null,
  cerrada_en timestamptz null,
  cerrada_por uuid null,
  motivo_sin_efecto text null,
  constraint pk_solicitud_cuenta primary key (id),
  constraint fk_solicitud_cuenta_local foreign key (local_id)
    references public.local (id) on delete restrict,
  constraint fk_solicitud_cuenta_pedido foreign key (pedido_id)
    references public.pedido (id) on delete restrict,
  constraint fk_solicitud_cuenta_solicitada_por foreign key (solicitada_por)
    references public.perfil_usuario (id) on delete restrict,
  constraint fk_solicitud_cuenta_cerrada_por foreign key (cerrada_por)
    references public.perfil_usuario (id) on delete restrict,
  constraint ck_solicitud_cuenta_estado_valido check (
    estado in ('PENDIENTE', 'ATENDIDA', 'SIN_EFECTO')
  ),
  constraint ck_solicitud_cuenta_motivo_valido check (
    motivo_sin_efecto is null or motivo_sin_efecto in ('REAPERTURA', 'ANULACION')
  ),
  constraint ck_solicitud_cuenta_cierre_coherente check (
    (estado = 'PENDIENTE' and cerrada_en is null and cerrada_por is null and motivo_sin_efecto is null)
    or (estado = 'ATENDIDA' and cerrada_en is not null and motivo_sin_efecto is null)
    or (estado = 'SIN_EFECTO' and cerrada_en is not null and motivo_sin_efecto is not null)
  )
);

create unique index uq_solicitud_cuenta_pedido_pendiente
  on public.solicitud_cuenta (pedido_id)
  where estado = 'PENDIENTE';

create index idx_solicitud_cuenta_pedido_solicitada_en
  on public.solicitud_cuenta (pedido_id, solicitada_en);

comment on table public.solicitud_cuenta is
  'E10-D03: solicitud de cuenta total del MOZO a CAJA. Entidad operativa independiente del estado del pedido; cierre único automático (ATENDIDA al pagar, SIN_EFECTO al reabrir o anular). Fuente de E8 para separar tiempo del cliente y tiempo de Caja.';
comment on column public.solicitud_cuenta.estado is
  'E10-D03: PENDIENTE (Caja aún no completa el cobro), ATENDIDA (pedido PAGADO) o SIN_EFECTO (reapertura o anulación). ATENDIDA y SIN_EFECTO son terminales.';
comment on column public.solicitud_cuenta.solicitada_en is
  'E10-D04: hora de servidor (clock_timestamp) registrada después de bloquear el pedido. Inicio del tiempo atribuible a Caja.';
comment on column public.solicitud_cuenta.cerrada_en is
  'E10-D05: hora de servidor del cierre, en la misma transacción que saca al pedido de ENTREGADO; nunca anterior a solicitada_en. Para ATENDIDA es el fin del tiempo atribuible a Caja.';
comment on column public.solicitud_cuenta.cerrada_por is
  'E10-D05: actor autenticado del cierre (CAJA del cobro final, MOZO de la reapertura, ADMINISTRADOR de la anulación). Nulo sólo en PENDIENTE o en cierres sin actor autenticado (mantenimiento).';
comment on column public.solicitud_cuenta.motivo_sin_efecto is
  'E10-D05: REAPERTURA o ANULACION; obligatorio sólo en SIN_EFECTO.';
comment on constraint ck_solicitud_cuenta_cierre_coherente on public.solicitud_cuenta is
  'E10-D03: PENDIENTE sin datos de cierre; ATENDIDA con cerrada_en y sin motivo; SIN_EFECTO con cerrada_en y motivo.';
comment on index public.uq_solicitud_cuenta_pedido_pendiente is
  'E10-R04: como máximo una solicitud PENDIENTE por pedido; defensa final de la idempotencia.';

-- E10-D09: lectura MOZO/CAJA del mismo local (lectura embebida del mozo y autorización Realtime).
alter table public.solicitud_cuenta enable row level security;
revoke all on table public.solicitud_cuenta from public, anon, authenticated, service_role;
revoke all on sequence public.solicitud_cuenta_id_seq from public, anon, authenticated, service_role;
grant select on table public.solicitud_cuenta to authenticated;

create policy pol_solicitud_cuenta_select_local
on public.solicitud_cuenta
for select
to authenticated
using (
  exists (
    select 1
    from public.obtener_contexto_autenticado() as auth_context
    where auth_context.local_id = solicitud_cuenta.local_id
      and auth_context.rol_codigo in ('MOZO', 'CAJA')
  )
);

comment on policy pol_solicitud_cuenta_select_local on public.solicitud_cuenta is
  'E10-D09: MOZO y CAJA activos leen las solicitudes de su local. Sin políticas de escritura: sólo escriben la RPC y los triggers.';

-- E10-D06: sólo se admite el cierre único PENDIENTE -> ATENDIDA/SIN_EFECTO; nunca borrado.
create function public.tgf_solicitud_cuenta_inmutable()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $tgf_solicitud_cuenta_inmutable$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '42501', message = 'La solicitud de cuenta es inmutable';
  end if;
  if old.estado is distinct from 'PENDIENTE'
    or new.estado not in ('ATENDIDA', 'SIN_EFECTO')
    or new.id is distinct from old.id
    or new.local_id is distinct from old.local_id
    or new.pedido_id is distinct from old.pedido_id
    or new.solicitada_por is distinct from old.solicitada_por
    or new.solicitada_en is distinct from old.solicitada_en then
    raise exception using errcode = '42501',
      message = 'La solicitud de cuenta sólo admite un cierre desde PENDIENTE';
  end if;
  return new;
end;
$tgf_solicitud_cuenta_inmutable$;

create trigger trg_solicitud_cuenta_before_update_delete_inmutable
before update or delete on public.solicitud_cuenta
for each row execute function public.tgf_solicitud_cuenta_inmutable();

-- E10-D05: cierre automático cuando el pedido sale de ENTREGADO, por cualquier vía
-- (cobro final E1 y vías históricas de pago, reapertura H5, anulación E1).
create function public.tgf_pedido_cerrar_solicitud_cuenta()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $tgf_pedido_cerrar_solicitud_cuenta$
begin
  update public.solicitud_cuenta as request_row
  set estado = case when new.estado = 'PAGADO' then 'ATENDIDA' else 'SIN_EFECTO' end,
      motivo_sin_efecto = case
        when new.estado = 'PAGADO' then null
        when new.estado = 'ANULADO' then 'ANULACION'
        else 'REAPERTURA'
      end,
      cerrada_en = greatest(pg_catalog.clock_timestamp(), request_row.solicitada_en),
      cerrada_por = auth.uid()
  where request_row.pedido_id = new.id
    and request_row.estado = 'PENDIENTE';
  return null;
end;
$tgf_pedido_cerrar_solicitud_cuenta$;

create trigger trg_pedido_after_update_cerrar_solicitud_cuenta
after update of estado on public.pedido
for each row
when (old.estado = 'ENTREGADO' and new.estado is distinct from old.estado)
execute function public.tgf_pedido_cerrar_solicitud_cuenta();

alter function public.tgf_solicitud_cuenta_inmutable() owner to postgres;
alter function public.tgf_pedido_cerrar_solicitud_cuenta() owner to postgres;
revoke all on function public.tgf_solicitud_cuenta_inmutable() from public, anon, authenticated, service_role;
revoke all on function public.tgf_pedido_cerrar_solicitud_cuenta() from public, anon, authenticated, service_role;

comment on function public.tgf_solicitud_cuenta_inmutable() is
  'E10-D06: rechaza DELETE y cualquier UPDATE distinto del cierre único PENDIENTE -> ATENDIDA/SIN_EFECTO.';
comment on function public.tgf_pedido_cerrar_solicitud_cuenta() is
  'E10-D05: al salir un pedido de ENTREGADO cierra su solicitud PENDIENTE en la misma transacción: PAGADO -> ATENDIDA; ANULADO -> SIN_EFECTO/ANULACION; estado operativo -> SIN_EFECTO/REAPERTURA.';

-- E10-D07: la solicitud es una señal Realtime propia (sin importes); no se quita ninguna tabla.
do $e10_realtime_publication$
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
      and tablename = 'solicitud_cuenta'
  ) then
    alter publication supabase_realtime add table public.solicitud_cuenta;
  end if;
end;
$e10_realtime_publication$;

notify pgrst, 'reload schema';

commit;
