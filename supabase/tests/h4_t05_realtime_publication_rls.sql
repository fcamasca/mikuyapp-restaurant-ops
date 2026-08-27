begin;

create function pg_temp.h4_t05_set_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $h4_t05_set_user$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$h4_t05_set_user$;

do $h4_t05_metadata$
declare
  v_tables text[];
begin
  select pg_catalog.array_agg(
    publication_table.schemaname || '.' || publication_table.tablename
    order by publication_table.schemaname, publication_table.tablename
  )
  into v_tables
  from pg_catalog.pg_publication_tables as publication_table
  where publication_table.pubname = 'supabase_realtime';

  if v_tables is distinct from array[
    'public.detalle_pedido', 'public.mesa', 'public.pedido'
  ] then
    raise exception 'H4-T05 publicación inesperada: %', v_tables;
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies as policy_row
    where policy_row.schemaname = 'public'
      and policy_row.policyname in (
        'pedido_select_cocina_local',
        'detalle_pedido_select_cocina_local',
        'mesa_select_cocina_local'
      )
      and policy_row.cmd = 'SELECT'
      and policy_row.roles = array['authenticated']::name[]
  ) <> 3 then
    raise exception 'H4-T05 políticas SELECT de cocina incompletas';
  end if;

  if pg_catalog.has_column_privilege(
      'authenticated', 'public.detalle_pedido', 'estado', 'UPDATE'
    ) or pg_catalog.has_column_privilege(
      'authenticated', 'public.pedido', 'estado', 'UPDATE'
    ) or pg_catalog.has_column_privilege(
      'authenticated', 'public.mesa', 'estado', 'UPDATE'
    ) then
    raise exception 'H4-T05 amplió escrituras directas';
  end if;
end;
$h4_t05_metadata$;

do $h4_t05_fixtures$
declare
  v_kitchen_a uuid := '00000000-0000-0000-0000-00000000d451';
  v_kitchen_b uuid := '00000000-0000-0000-0000-00000000d452';
  v_cashier uuid := '00000000-0000-0000-0000-00000000d453';
  v_local_a uuid := '00000000-0000-0000-0000-00000000d454';
  v_local_b uuid := '00000000-0000-0000-0000-00000000d455';
  v_table_a uuid := '00000000-0000-0000-0000-00000000d456';
  v_table_b uuid := '00000000-0000-0000-0000-00000000d457';
  v_category_a uuid := '00000000-0000-0000-0000-00000000d458';
  v_category_b uuid := '00000000-0000-0000-0000-00000000d459';
  v_product_a uuid := '00000000-0000-0000-0000-00000000d45a';
  v_product_b uuid := '00000000-0000-0000-0000-00000000d45b';
  v_sent_at timestamptz := '2026-08-27 13:00:00-05';
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values
    (v_kitchen_a, 'authenticated', 'authenticated', 'h4-t05-kitchen-a@example.invalid', 'test'),
    (v_kitchen_b, 'authenticated', 'authenticated', 'h4-t05-kitchen-b@example.invalid', 'test'),
    (v_cashier, 'authenticated', 'authenticated', 'h4-t05-cashier@example.invalid', 'test');

  insert into public.local (id, codigo, nombre)
  values
    (v_local_a, 'H4-T05-A', 'Local H4 T05 A'),
    (v_local_b, 'H4-T05-B', 'Local H4 T05 B');

  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_kitchen_a, v_local_a, role_row.id, 'Cocina A'
  from public.rol as role_row where role_row.codigo = 'COCINA'
  union all
  select v_kitchen_b, v_local_b, role_row.id, 'Cocina B'
  from public.rol as role_row where role_row.codigo = 'COCINA'
  union all
  select v_cashier, v_local_a, role_row.id, 'Caja A'
  from public.rol as role_row where role_row.codigo = 'CAJA';

  insert into public.mesa (id, local_id, codigo, nombre, estado)
  values
    (v_table_a, v_local_a, 'RT-A', 'Mesa Realtime A', 'OCUPADA'),
    (v_table_b, v_local_b, 'RT-B', 'Mesa Realtime B', 'OCUPADA');

  insert into public.categoria (id, local_id, codigo, nombre)
  values
    (v_category_a, v_local_a, 'RT-A', 'Categoría A'),
    (v_category_b, v_local_b, 'RT-B', 'Categoría B');
  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio)
  values
    (v_product_a, v_local_a, v_category_a, 'RT-A', 'Producto A', 10),
    (v_product_b, v_local_b, v_category_b, 'RT-B', 'Producto B', 12);

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado, enviado_en)
  overriding system value
  values
    (-40501, v_local_a, v_table_a, v_kitchen_a, 'ENVIADO', v_sent_at),
    (-40502, v_local_b, v_table_b, v_kitchen_b, 'ENVIADO', v_sent_at);

  perform pg_temp.h4_t05_set_user(v_kitchen_a);
  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, estado, enviado_en
  ) overriding system value
  values
    (-40511, -40501, v_product_a, 1, 10, 'ENVIADO', v_sent_at),
    (-40512, -40501, v_product_a, 1, 10, 'ABIERTO', null),
    (-40513, -40502, v_product_b, 1, 12, 'ENVIADO', v_sent_at);
end;
$h4_t05_fixtures$;

set local role authenticated;

do $h4_t05_rls$
declare
  v_kitchen_a uuid := '00000000-0000-0000-0000-00000000d451';
  v_kitchen_b uuid := '00000000-0000-0000-0000-00000000d452';
  v_cashier uuid := '00000000-0000-0000-0000-00000000d453';
begin
  perform pg_temp.h4_t05_set_user(v_kitchen_a);
  if (select count(*) from public.pedido where id in (-40501, -40502)) <> 1
    or (select count(*) from public.mesa where id in (
      '00000000-0000-0000-0000-00000000d456',
      '00000000-0000-0000-0000-00000000d457'
    )) <> 1
    or (select count(*) from public.detalle_pedido where id in (-40511, -40512, -40513)) <> 1
    or not exists (select 1 from public.detalle_pedido where id = -40511) then
    raise exception 'H4-T05 RLS no aisló local A o expuso ABIERTO';
  end if;

  perform pg_temp.h4_t05_set_user(v_kitchen_b);
  if (select count(*) from public.detalle_pedido where id in (-40511, -40513)) <> 1
    or not exists (select 1 from public.detalle_pedido where id = -40513) then
    raise exception 'H4-T05 RLS no aisló local B';
  end if;

  perform pg_temp.h4_t05_set_user(v_cashier);
  if exists (select 1 from public.pedido where id in (-40501, -40502))
    or exists (select 1 from public.detalle_pedido where id in (-40511, -40513)) then
    raise exception 'H4-T05 expuso señales de cocina a CAJA';
  end if;
end;
$h4_t05_rls$;

reset role;
rollback;
