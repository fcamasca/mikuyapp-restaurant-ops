-- E7-T02 — Modelo: condición de cocina, historial de detalle y comanda.
-- Spec: specs/E7-OrderOperationalImprovements (E7-D02, D03, D11, D12, D14, D19).
begin;

-- E7-D02: condición de cocina por producto (default compatible con el comportamiento aprobado).
alter table public.producto
  add column requiere_cocina boolean not null default true;

comment on column public.producto.requiere_cocina is
  'E7-D02: indica si el producto requiere preparación en cocina. Default true conserva el comportamiento previo.';

grant select (requiere_cocina) on table public.producto to authenticated;
grant insert (requiere_cocina) on table public.producto to authenticated;
grant update (requiere_cocina) on table public.producto to authenticated;

-- E7-D03: snapshot en el detalle. Backfill true: históricamente todo detalle pasó por cocina.
alter table public.detalle_pedido
  add column requiere_cocina boolean not null default true;

alter table public.detalle_pedido
  add constraint ck_detalle_pedido_sin_cocina_estado check (
    requiere_cocina or estado in ('ABIERTO', 'LISTO')
  );

comment on column public.detalle_pedido.requiere_cocina is
  'E7-D03: snapshot inmutable de producto.requiere_cocina al crear el detalle; no es actualizable por clientes.';
comment on constraint ck_detalle_pedido_sin_cocina_estado on public.detalle_pedido is
  'E7-D03: un detalle sin cocina sólo puede estar ABIERTO o LISTO.';

-- E7-D11: historial inmutable de transiciones y cancelaciones de detalle.
create table public.historial_detalle_pedido (
  id bigint generated always as identity not null,
  local_id uuid not null,
  pedido_id bigint not null,
  detalle_id bigint not null,
  producto_id uuid not null,
  operacion text not null,
  estado_anterior text not null,
  estado_nuevo text null,
  requiere_cocina boolean not null,
  cantidad integer not null,
  precio_unitario numeric(10,2) not null,
  observacion text null,
  motivo text null,
  usuario_id uuid not null,
  creado_en timestamptz not null default now(),
  constraint pk_historial_detalle_pedido primary key (id),
  constraint fk_historial_detalle_pedido_local foreign key (local_id)
    references public.local (id) on delete restrict,
  constraint fk_historial_detalle_pedido_pedido foreign key (pedido_id)
    references public.pedido (id) on delete restrict,
  constraint fk_historial_detalle_pedido_producto foreign key (producto_id)
    references public.producto (id) on delete restrict,
  constraint fk_historial_detalle_pedido_usuario foreign key (usuario_id)
    references public.perfil_usuario (id) on delete restrict,
  constraint ck_historial_detalle_pedido_operacion_valida check (
    operacion in ('ENVIO', 'TRANSICION_COCINA', 'RECEPCION_COMPLETA', 'CANCELACION')
  ),
  constraint ck_historial_detalle_pedido_estado_anterior_valido check (
    estado_anterior in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO')
  ),
  constraint ck_historial_detalle_pedido_estado_nuevo_valido check (
    estado_nuevo is null
    or estado_nuevo in ('ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO')
  ),
  constraint ck_historial_detalle_pedido_cancelacion_coherente check (
    (operacion = 'CANCELACION' and estado_nuevo is null
      and motivo is not null and pg_catalog.btrim(motivo) <> '')
    or (operacion <> 'CANCELACION' and estado_nuevo is not null
      and estado_nuevo <> estado_anterior and motivo is null)
  ),
  constraint ck_historial_detalle_pedido_cantidad_positiva check (cantidad > 0),
  constraint ck_historial_detalle_pedido_precio_no_negativo check (precio_unitario >= 0)
);

create index idx_historial_detalle_pedido_pedido_id_creado_en
  on public.historial_detalle_pedido (pedido_id, creado_en);
create index idx_historial_detalle_pedido_detalle_id_operacion
  on public.historial_detalle_pedido (detalle_id, operacion);

alter table public.historial_detalle_pedido enable row level security;
revoke all on table public.historial_detalle_pedido from public, anon, authenticated;

comment on table public.historial_detalle_pedido is
  'E7-D11: historial inmutable de transiciones reales de detalle (ENVIO, TRANSICION_COCINA, RECEPCION_COMPLETA) y cancelaciones con snapshot. Sin backfill retroactivo.';
comment on column public.historial_detalle_pedido.detalle_id is
  'E7-D11: identificador del detalle sin FK, porque la cancelación elimina la línea activa.';

-- E7-D12: comanda inmutable por envío con líneas de cocina.
create table public.comanda (
  id bigint generated always as identity not null,
  local_id uuid not null,
  pedido_id bigint not null,
  numero integer not null,
  enviado_en timestamptz not null,
  lineas jsonb not null,
  creado_por uuid not null,
  creado_en timestamptz not null default now(),
  impresiones integer not null default 0,
  primera_impresion_en timestamptz null,
  primera_impresion_por uuid null,
  ultima_impresion_en timestamptz null,
  ultima_impresion_por uuid null,
  constraint pk_comanda primary key (id),
  constraint uq_comanda_pedido_id_numero unique (pedido_id, numero),
  constraint fk_comanda_local foreign key (local_id)
    references public.local (id) on delete restrict,
  constraint fk_comanda_pedido foreign key (pedido_id)
    references public.pedido (id) on delete restrict,
  constraint fk_comanda_creado_por foreign key (creado_por)
    references public.perfil_usuario (id) on delete restrict,
  constraint fk_comanda_primera_impresion_por foreign key (primera_impresion_por)
    references public.perfil_usuario (id) on delete restrict,
  constraint fk_comanda_ultima_impresion_por foreign key (ultima_impresion_por)
    references public.perfil_usuario (id) on delete restrict,
  constraint ck_comanda_numero_positivo check (numero > 0),
  constraint ck_comanda_lineas_no_vacias check (
    pg_catalog.jsonb_typeof(lineas) = 'array' and pg_catalog.jsonb_array_length(lineas) > 0
  ),
  constraint ck_comanda_impresiones_no_negativas check (impresiones >= 0),
  constraint ck_comanda_impresion_coherente check (
    (impresiones = 0 and primera_impresion_en is null and primera_impresion_por is null
      and ultima_impresion_en is null and ultima_impresion_por is null)
    or (impresiones > 0 and primera_impresion_en is not null and primera_impresion_por is not null
      and ultima_impresion_en is not null and ultima_impresion_por is not null)
  )
);

alter table public.comanda enable row level security;
revoke all on table public.comanda from public, anon, authenticated;

comment on table public.comanda is
  'E7-D12: documento inmutable de cocina generado en el envío que incluye líneas de cocina. Registra solicitudes de impresión, no salida física del papel.';
comment on column public.comanda.lineas is
  'E7-D12: snapshot documental [{detalle_id, producto_codigo, producto_nombre, cantidad, observacion}] sólo con líneas de cocina de ese envío.';
comment on column public.comanda.impresiones is
  'E7-R26/R27: cantidad de solicitudes de impresión registradas (primera + reimpresiones).';

-- Inmutabilidad (patrón E1 tgf_*_inmutable).
create function public.tgf_historial_detalle_pedido_inmutable()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $tgf_historial_detalle_pedido_inmutable$
begin
  raise exception using errcode = '42501',
    message = 'El historial de detalle de pedido es inmutable';
end;
$tgf_historial_detalle_pedido_inmutable$;

create trigger trg_historial_detalle_pedido_before_write_inmutable
before update or delete on public.historial_detalle_pedido
for each row execute function public.tgf_historial_detalle_pedido_inmutable();

create function public.tgf_comanda_contenido_inmutable()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $tgf_comanda_contenido_inmutable$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '42501', message = 'La comanda es inmutable';
  end if;
  if new.id is distinct from old.id
    or new.local_id is distinct from old.local_id
    or new.pedido_id is distinct from old.pedido_id
    or new.numero is distinct from old.numero
    or new.enviado_en is distinct from old.enviado_en
    or new.lineas is distinct from old.lineas
    or new.creado_por is distinct from old.creado_por
    or new.creado_en is distinct from old.creado_en then
    raise exception using errcode = '42501', message = 'El contenido de la comanda es inmutable';
  end if;
  return new;
end;
$tgf_comanda_contenido_inmutable$;

create trigger trg_comanda_before_write_inmutable
before update or delete on public.comanda
for each row execute function public.tgf_comanda_contenido_inmutable();

-- Historial automático de transiciones de estado de detalle.
create function public.tgf_detalle_pedido_historial_estado()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $tgf_detalle_pedido_historial_estado$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_creado_por uuid;
  v_operacion text;
begin
  select order_row.local_id, order_row.creado_por
  into strict v_local_id, v_creado_por
  from public.pedido as order_row
  where order_row.id = new.pedido_id;

  v_usuario_id := coalesce(v_usuario_id, v_creado_por);

  v_operacion := case
    when old.estado = 'ABIERTO' then 'ENVIO'
    when pg_catalog.current_setting('mikuyapp.operacion_detalle', true) = 'RECEPCION_COMPLETA'
      then 'RECEPCION_COMPLETA'
    else 'TRANSICION_COCINA'
  end;

  insert into public.historial_detalle_pedido (
    local_id, pedido_id, detalle_id, producto_id, operacion,
    estado_anterior, estado_nuevo, requiere_cocina, cantidad, precio_unitario,
    observacion, motivo, usuario_id
  ) values (
    v_local_id, new.pedido_id, new.id, new.producto_id, v_operacion,
    old.estado, new.estado, new.requiere_cocina, new.cantidad, new.precio_unitario,
    new.observacion, null, v_usuario_id
  );
  return null;
end;
$tgf_detalle_pedido_historial_estado$;

create trigger trg_detalle_pedido_after_update_historial_estado
after update of estado on public.detalle_pedido
for each row
when (old.estado is distinct from new.estado)
execute function public.tgf_detalle_pedido_historial_estado();

alter function public.tgf_historial_detalle_pedido_inmutable() owner to postgres;
alter function public.tgf_comanda_contenido_inmutable() owner to postgres;
alter function public.tgf_detalle_pedido_historial_estado() owner to postgres;
revoke all on function public.tgf_historial_detalle_pedido_inmutable() from public, anon, authenticated;
revoke all on function public.tgf_comanda_contenido_inmutable() from public, anon, authenticated;
revoke all on function public.tgf_detalle_pedido_historial_estado() from public, anon, authenticated;

comment on function public.tgf_detalle_pedido_historial_estado() is
  'E7-D11: registra cada cambio real de detalle_pedido.estado (ENVIO, TRANSICION_COCINA o RECEPCION_COMPLETA) con actor autenticado.';
comment on function public.tgf_historial_detalle_pedido_inmutable() is
  'E7-D11: rechaza UPDATE/DELETE sobre historial_detalle_pedido.';
comment on function public.tgf_comanda_contenido_inmutable() is
  'E7-D12: rechaza DELETE y cambios de contenido de comanda; sólo admite columnas de impresión.';

notify pgrst, 'reload schema';

commit;
