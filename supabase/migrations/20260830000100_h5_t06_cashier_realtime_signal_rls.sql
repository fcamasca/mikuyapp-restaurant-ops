begin;

create policy pedido_select_caja_local_cobro
on public.pedido
for select
to authenticated
using (
  pedido.estado in ('ENTREGADO', 'PAGADO')
  and exists (
    select 1
    from public.obtener_contexto_autenticado() as auth_context
    where auth_context.local_id = pedido.local_id
      and auth_context.rol_codigo = 'CAJA'
  )
);

commit;
