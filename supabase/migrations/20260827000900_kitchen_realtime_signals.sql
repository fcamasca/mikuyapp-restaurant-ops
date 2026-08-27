begin;

do $configure_realtime_publication$
declare
  v_relation record;
begin
  if not exists (
    select 1 from pg_catalog.pg_publication
    where pubname = 'supabase_realtime'
  ) then
    create publication supabase_realtime;
  end if;

  for v_relation in
    select publication_table.schemaname, publication_table.tablename
    from pg_catalog.pg_publication_tables as publication_table
    where publication_table.pubname = 'supabase_realtime'
      and (
        publication_table.schemaname <> 'public'
        or publication_table.tablename not in ('detalle_pedido', 'pedido', 'mesa')
      )
  loop
    execute pg_catalog.format(
      'alter publication supabase_realtime drop table %I.%I',
      v_relation.schemaname,
      v_relation.tablename
    );
  end loop;

  if not exists (
    select 1 from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'detalle_pedido'
  ) then
    alter publication supabase_realtime add table public.detalle_pedido;
  end if;

  if not exists (
    select 1 from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pedido'
  ) then
    alter publication supabase_realtime add table public.pedido;
  end if;

  if not exists (
    select 1 from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'mesa'
  ) then
    alter publication supabase_realtime add table public.mesa;
  end if;
end;
$configure_realtime_publication$;

create policy pedido_select_cocina_local
on public.pedido
for select
to authenticated
using (
  pedido.estado in (
    'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
  )
  and exists (
    select 1
    from public.obtener_contexto_autenticado() as auth_context
    where auth_context.local_id = pedido.local_id
      and auth_context.rol_codigo = 'COCINA'
  )
);

create policy detalle_pedido_select_cocina_local
on public.detalle_pedido
for select
to authenticated
using (
  detalle_pedido.estado in (
    'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
  )
  and exists (
    select 1
    from public.pedido as order_row
    cross join public.obtener_contexto_autenticado() as auth_context
    where order_row.id = detalle_pedido.pedido_id
      and order_row.local_id = auth_context.local_id
      and auth_context.rol_codigo = 'COCINA'
      and order_row.estado in (
        'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
      )
  )
);

create policy mesa_select_cocina_local
on public.mesa
for select
to authenticated
using (
  mesa.activo = true
  and exists (
    select 1
    from public.obtener_contexto_autenticado() as auth_context
    where auth_context.local_id = mesa.local_id
      and auth_context.rol_codigo = 'COCINA'
  )
);

commit;
