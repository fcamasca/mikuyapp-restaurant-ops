begin;

grant select on table public.detalle_pedido to authenticated;
grant update (cantidad, observacion)
on table public.detalle_pedido to authenticated;
grant delete on table public.detalle_pedido to authenticated;

create policy detalle_pedido_select_mozo_local
on public.detalle_pedido
for select
to authenticated
using (
  exists (
    select 1
    from public.pedido as order_row
    cross join public.obtener_contexto_autenticado() as auth_context
    where order_row.id = detalle_pedido.pedido_id
      and order_row.local_id = auth_context.local_id
      and auth_context.rol_codigo = 'MOZO'
      and order_row.estado in (
        'ABIERTO',
        'ENVIADO',
        'RECIBIDO_COCINA',
        'EN_PREPARACION',
        'LISTO',
        'ENTREGADO'
      )
  )
);

create policy detalle_pedido_update_abierto_mozo
on public.detalle_pedido
for update
to authenticated
using (
  detalle_pedido.estado = 'ABIERTO'
  and exists (
    select 1
    from public.pedido as order_row
    cross join public.obtener_contexto_autenticado() as auth_context
    where order_row.id = detalle_pedido.pedido_id
      and order_row.local_id = auth_context.local_id
      and auth_context.rol_codigo = 'MOZO'
      and order_row.estado in (
        'ABIERTO',
        'ENVIADO',
        'RECIBIDO_COCINA',
        'EN_PREPARACION',
        'LISTO',
        'ENTREGADO'
      )
  )
)
with check (
  detalle_pedido.estado = 'ABIERTO'
  and exists (
    select 1
    from public.pedido as order_row
    cross join public.obtener_contexto_autenticado() as auth_context
    where order_row.id = detalle_pedido.pedido_id
      and order_row.local_id = auth_context.local_id
      and auth_context.rol_codigo = 'MOZO'
      and order_row.estado in (
        'ABIERTO',
        'ENVIADO',
        'RECIBIDO_COCINA',
        'EN_PREPARACION',
        'LISTO',
        'ENTREGADO'
      )
  )
);

create policy detalle_pedido_delete_abierto_mozo
on public.detalle_pedido
for delete
to authenticated
using (
  detalle_pedido.estado = 'ABIERTO'
  and exists (
    select 1
    from public.pedido as order_row
    cross join public.obtener_contexto_autenticado() as auth_context
    where order_row.id = detalle_pedido.pedido_id
      and order_row.local_id = auth_context.local_id
      and auth_context.rol_codigo = 'MOZO'
      and order_row.estado in (
        'ABIERTO',
        'ENVIADO',
        'RECIBIDO_COCINA',
        'EN_PREPARACION',
        'LISTO',
        'ENTREGADO'
      )
  )
);

commit;
