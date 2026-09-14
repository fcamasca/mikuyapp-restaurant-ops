begin;

-- E1-T03: se conserva expresamente la nomenclatura semántica vigente.
-- Caja = maestra física; sesión = movimiento histórico. No se asocian pagos legacy.
create table public.caja (
  id uuid not null default gen_random_uuid(),
  local_id uuid not null,
  codigo text not null,
  nombre text not null,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  constraint pk_caja primary key (id),
  constraint uq_caja_id_local_id unique (id, local_id),
  constraint uq_caja_local_id_codigo unique (local_id, codigo),
  constraint ck_caja_codigo_no_vacio check (btrim(codigo) <> ''),
  constraint ck_caja_nombre_no_vacio check (btrim(nombre) <> ''),
  constraint fk_caja_local foreign key (local_id)
    references public.local (id) on delete restrict
);

create table public.sesion_caja (
  id uuid not null default gen_random_uuid(),
  caja_id uuid not null,
  local_id uuid not null,
  abierta_por uuid not null default auth.uid(),
  abierta_en timestamptz not null default now(),
  monto_inicial numeric(14,2) not null,
  idempotency_key uuid not null,
  estado text not null default 'ABIERTA',
  cerrada_por uuid null,
  cerrada_en timestamptz null,
  efectivo_esperado numeric(14,2) null,
  efectivo_contado numeric(14,2) null,
  diferencia numeric(14,2) null,
  motivo_diferencia text null,
  constraint pk_sesion_caja primary key (id),
  constraint uq_sesion_caja_idempotencia unique (caja_id, abierta_por, idempotency_key),
  constraint ck_sesion_caja_estado check (estado in ('ABIERTA', 'CERRADA')),
  constraint ck_sesion_caja_monto_inicial check (
    monto_inicial >= 0 and monto_inicial <> 'NaN'::numeric
  ),
  constraint ck_sesion_caja_motivo check (
    motivo_diferencia is null or btrim(motivo_diferencia) <> ''
  ),
  constraint ck_sesion_caja_cierre check (
    (estado = 'ABIERTA' and cerrada_por is null and cerrada_en is null
      and efectivo_esperado is null and efectivo_contado is null
      and diferencia is null and motivo_diferencia is null)
    or
    (estado = 'CERRADA' and cerrada_por is not null and cerrada_en is not null
      and cerrada_en >= abierta_en
      and efectivo_esperado is not null and efectivo_esperado <> 'NaN'::numeric
      and efectivo_contado is not null and efectivo_contado >= 0
      and efectivo_contado <> 'NaN'::numeric
      and diferencia is not null and diferencia = efectivo_contado - efectivo_esperado
      and (diferencia = 0 or motivo_diferencia is not null))
  ),
  constraint fk_sesion_caja_caja_local foreign key (caja_id, local_id)
    references public.caja (id, local_id) on delete restrict,
  constraint fk_sesion_caja_abierta_por foreign key (abierta_por)
    references public.perfil_usuario (id) on delete restrict,
  constraint fk_sesion_caja_cerrada_por foreign key (cerrada_por)
    references public.perfil_usuario (id) on delete restrict
);

create unique index uq_sesion_caja_abierta
  on public.sesion_caja (caja_id) where estado = 'ABIERTA';
create index idx_sesion_caja_local_abierta_en
  on public.sesion_caja (local_id, abierta_en desc);
create index idx_sesion_caja_abierta_por on public.sesion_caja (abierta_por);
create index idx_sesion_caja_cerrada_por on public.sesion_caja (cerrada_por);

-- Invariante estructural, no implementa apertura/cierre ni autorización de RPC.
create function public.tgf_sesion_caja_conservar_historia()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '23514', message = 'No se elimina una sesión de caja';
  end if;
  if old.estado = 'CERRADA' or
    row(new.id, new.caja_id, new.local_id, new.abierta_por, new.abierta_en,
      new.monto_inicial, new.idempotency_key)
    is distinct from
    row(old.id, old.caja_id, old.local_id, old.abierta_por, old.abierta_en,
      old.monto_inicial, old.idempotency_key) then
    raise exception using errcode = '23514', message = 'La historia de apertura/cierre es inmutable';
  end if;
  return new;
end;
$$;
alter function public.tgf_sesion_caja_conservar_historia() owner to postgres;
revoke all on function public.tgf_sesion_caja_conservar_historia()
  from public, anon, authenticated;
create trigger trg_sesion_caja_before_write_historia
  before update or delete on public.sesion_caja
  for each row execute function public.tgf_sesion_caja_conservar_historia();

alter table public.caja enable row level security;
alter table public.sesion_caja enable row level security;
revoke all on public.caja, public.sesion_caja from public, anon, authenticated;
-- Denegación por defecto. Lecturas/policies y RPC autenticadas corresponden a T04.

-- Configuración mínima para locales activos preexistentes; no crea turnos históricos.
-- No existe vínculo con navegador, cajero ni pagos anteriores.
insert into public.caja (local_id, codigo, nombre)
select id, 'CAJA-01', 'Caja principal' from public.local where activo;

comment on table public.caja is
  'Caja física configurable del local, independiente del navegador y de las sesiones. Clasificación maestra; conserva nombre semántico.';
comment on table public.sesion_caja is
  'Sesión histórica de caja/local, compartida por cajeros activos del local mediante RPC; no es propiedad del actor de apertura. Clasificación movimiento.';
comment on column public.sesion_caja.local_id is
  'Local explícito para aislamiento y consulta; FK compuesta impide combinar caja y local diferentes.';
comment on column public.sesion_caja.abierta_por is
  'Actor de apertura inmutable, no titular exclusivo. Las RPC validan el actor actual de cada operación.';
comment on column public.sesion_caja.cerrada_por is
  'Actor del cierre, que puede ser distinto de abierta_por; no altera la historia de apertura.';
comment on column public.sesion_caja.idempotency_key is
  'Identificador de solicitud de apertura único por caja y actor; no identifica propiedad de la sesión.';
comment on column public.sesion_caja.efectivo_esperado is
  'Snapshot de cierre calculado por PostgreSQL en T05; no es un saldo enviado por cliente. Puede ser negativo por salidas.';
comment on column public.sesion_caja.diferencia is
  'Snapshot de efectivo contado menos esperado; una diferencia distinta de cero exige motivo.';
comment on function public.tgf_sesion_caja_conservar_historia() is
  'Protege campos de apertura, impide borrar sesiones y modificar sesiones cerradas; no reemplaza autorización ni cálculo de cierre.';

notify pgrst, 'reload schema';
commit;
