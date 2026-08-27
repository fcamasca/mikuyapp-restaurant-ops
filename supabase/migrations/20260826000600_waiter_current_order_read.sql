begin;

grant select on table public.pedido to authenticated;

create policy pedido_select_vigente_mozo_local
on public.pedido
for select
to authenticated
using (
  pedido.estado in (
    'ABIERTO',
    'ENVIADO',
    'RECIBIDO_COCINA',
    'EN_PREPARACION',
    'LISTO',
    'ENTREGADO'
  )
  and exists (
    select 1
    from public.obtener_contexto_autenticado() as auth_context
    where auth_context.local_id = pedido.local_id
      and auth_context.rol_codigo = 'MOZO'
  )
);

commit;
