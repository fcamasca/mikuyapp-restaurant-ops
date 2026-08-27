begin;

alter table public.detalle_pedido
  add column estado text not null default 'ABIERTO';

alter table public.detalle_pedido
  add constraint ck_detalle_pedido_estado_valido check (
    estado in (
      'ABIERTO',
      'ENVIADO',
      'RECIBIDO_COCINA',
      'EN_PREPARACION',
      'LISTO'
    )
  );

create index idx_detalle_pedido_pedido_id_estado
  on public.detalle_pedido (pedido_id, estado);

do $h3_t01_existing_orders$
begin
  if exists (
    select 1
    from public.pedido
    where estado in (
      'ABIERTO',
      'ENVIADO',
      'RECIBIDO_COCINA',
      'EN_PREPARACION',
      'LISTO',
      'ENTREGADO'
    )
    group by mesa_id
    having count(*) > 1
  ) then
    raise exception using
      errcode = '23505',
      message = 'No se puede garantizar un pedido vigente por mesa: existen mesas con pedidos vigentes duplicados';
  end if;
end;
$h3_t01_existing_orders$;

create unique index uq_pedido_mesa_id_vigente
  on public.pedido (mesa_id)
  where estado in (
    'ABIERTO',
    'ENVIADO',
    'RECIBIDO_COCINA',
    'EN_PREPARACION',
    'LISTO',
    'ENTREGADO'
  );

commit;
