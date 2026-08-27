-- T19: ejecutar manualmente en una copia temporal dentro de Supabase SQL Editor.
-- No contiene ni requiere correos, contraseñas, UUID Auth o service_role.

begin;

create temporary table h2_t19_fixture_ids (
  history_product_id uuid not null,
  ordered_table_id uuid not null,
  other_local_id uuid not null,
  other_category_id uuid not null
) on commit drop;

do $h2_t19_setup$
declare
  v_demo_local_id uuid;
  v_admin_profile_id uuid;
  v_other_local_id uuid;
  v_other_category_id uuid;
  v_demo_category_id uuid;
  v_product_id uuid;
  v_table_id uuid;
  v_order_id bigint;
  v_admin_count integer;
begin
  select l.id
    into strict v_demo_local_id
  from public.local as l
  where l.codigo = 'MIKUY-DEMO'
    and l.activo = true;

  select count(*), min(p.id::text)::uuid
    into v_admin_count, v_admin_profile_id
  from public.perfil_usuario as p
  join public.rol as r on r.id = p.rol_id
  where p.local_id = v_demo_local_id
    and p.activo = true
    and r.codigo = 'ADMINISTRADOR'
    and r.activo = true;

  if v_admin_count <> 1 then
    raise exception 'T19 requiere exactamente un perfil ADMINISTRADOR activo en MIKUY-DEMO.';
  end if;

  insert into public.local (codigo, nombre, activo)
  values ('H2T19-FIX-LOCAL-OTHER', 'H2T19-FIX-Local secundario', true)
  on conflict (codigo) do update
    set nombre = excluded.nombre,
        activo = true
  returning id into v_other_local_id;

  insert into public.categoria (local_id, codigo, nombre, orden, activo)
  values (v_other_local_id, 'H2T19-FIX-CAT-OTHER', 'H2T19-FIX-Categoría externa', 990, true)
  on conflict (local_id, codigo) do update
    set nombre = excluded.nombre,
        orden = excluded.orden,
        activo = true
  returning id into v_other_category_id;

  insert into public.categoria (local_id, codigo, nombre, orden, activo)
  values (v_demo_local_id, 'H2T19-FIX-CAT-HISTORY', 'H2T19-FIX-Categoría historial', 991, true)
  on conflict (local_id, codigo) do update
    set nombre = excluded.nombre,
        orden = excluded.orden,
        activo = true
  returning id into v_demo_category_id;

  insert into public.producto (local_id, categoria_id, codigo, nombre, precio, activo)
  values (
    v_demo_local_id,
    v_demo_category_id,
    'H2T19-FIX-PRODUCT-HISTORY',
    'H2T19-FIX-Producto con historial',
    1.00,
    true
  )
  on conflict (local_id, codigo) do update
    set categoria_id = excluded.categoria_id,
        nombre = excluded.nombre,
        precio = excluded.precio,
        activo = true
  returning id into v_product_id;

  insert into public.mesa (local_id, codigo, nombre, estado, activo)
  values (
    v_demo_local_id,
    'H2T19-FIX-TABLE-ORDERED',
    'H2T19-FIX-Mesa con pedido',
    'OCUPADA',
    true
  )
  on conflict (local_id, codigo) do update
    set nombre = excluded.nombre,
        estado = 'OCUPADA',
        activo = true
  returning id into v_table_id;

  select p.id
    into v_order_id
  from public.pedido as p
  where p.local_id = v_demo_local_id
    and p.mesa_id = v_table_id
    and p.creado_por = v_admin_profile_id
  order by p.id
  limit 1;

  if v_order_id is null then
    insert into public.pedido (local_id, mesa_id, creado_por, estado)
    values (v_demo_local_id, v_table_id, v_admin_profile_id, 'ABIERTO')
    returning id into v_order_id;
  end if;

  if not exists (
    select 1
    from public.detalle_pedido as d
    where d.pedido_id = v_order_id
      and d.producto_id = v_product_id
  ) then
    insert into public.detalle_pedido (
      pedido_id,
      producto_id,
      cantidad,
      precio_unitario,
      observacion
    )
    values (v_order_id, v_product_id, 1, 1.00, 'H2T19-FIX-Detalle controlado');
  end if;

  truncate table h2_t19_fixture_ids;
  insert into h2_t19_fixture_ids (
    history_product_id,
    ordered_table_id,
    other_local_id,
    other_category_id
  )
  values (v_product_id, v_table_id, v_other_local_id, v_other_category_id);
end
$h2_t19_setup$;

select
  ids.history_product_id as "H2_HISTORY_PRODUCT_ID",
  ids.ordered_table_id as "H2_ORDERED_TABLE_ID",
  ids.other_local_id as "H2_OTHER_LOCAL_ID",
  ids.other_category_id as "H2_OTHER_CATEGORY_ID"
from h2_t19_fixture_ids as ids;

commit;
