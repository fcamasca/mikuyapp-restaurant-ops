do $$
declare
  mismatch_count integer;
  actual_count integer;
  actual_names text[];
begin
  select count(*)
    into actual_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind in ('r', 'p');

  select array_agg(c.relname order by c.relname)
    into actual_names
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind in ('r', 'p');

  if actual_count <> 10 or actual_names <> array[
    'categoria', 'detalle_pedido', 'historial_estado', 'local', 'mesa',
    'pago', 'pedido', 'perfil_usuario', 'producto', 'rol'
  ]::text[] then
    raise exception 'TP-09: expected 10 exact public tables, found %: %', actual_count, actual_names;
  end if;

  with expected (
    table_name,
    column_name,
    formatted_type,
    not_null,
    default_expr,
    identity_kind
  ) as (
    values
      ('local', 'id', 'uuid', true, 'gen_random_uuid()', ''),
      ('local', 'codigo', 'text', true, null, ''),
      ('local', 'nombre', 'text', true, null, ''),
      ('local', 'activo', 'boolean', true, 'true', ''),
      ('local', 'creado_en', 'timestamp with time zone', true, 'now()', ''),
      ('rol', 'id', 'smallint', true, null, 'd'),
      ('rol', 'codigo', 'text', true, null, ''),
      ('rol', 'nombre', 'text', true, null, ''),
      ('rol', 'activo', 'boolean', true, 'true', ''),
      ('perfil_usuario', 'id', 'uuid', true, null, ''),
      ('perfil_usuario', 'local_id', 'uuid', true, null, ''),
      ('perfil_usuario', 'rol_id', 'smallint', true, null, ''),
      ('perfil_usuario', 'nombre', 'text', true, null, ''),
      ('perfil_usuario', 'activo', 'boolean', true, 'true', ''),
      ('perfil_usuario', 'creado_en', 'timestamp with time zone', true, 'now()', ''),
      ('mesa', 'id', 'uuid', true, 'gen_random_uuid()', ''),
      ('mesa', 'local_id', 'uuid', true, null, ''),
      ('mesa', 'codigo', 'text', true, null, ''),
      ('mesa', 'nombre', 'text', true, null, ''),
      ('mesa', 'estado', 'text', true, '''LIBRE''::text', ''),
      ('mesa', 'activo', 'boolean', true, 'true', ''),
      ('mesa', 'creado_en', 'timestamp with time zone', true, 'now()', ''),
      ('categoria', 'id', 'uuid', true, 'gen_random_uuid()', ''),
      ('categoria', 'local_id', 'uuid', true, null, ''),
      ('categoria', 'codigo', 'text', true, null, ''),
      ('categoria', 'nombre', 'text', true, null, ''),
      ('categoria', 'orden', 'integer', true, '0', ''),
      ('categoria', 'activo', 'boolean', true, 'true', ''),
      ('categoria', 'creado_en', 'timestamp with time zone', true, 'now()', ''),
      ('producto', 'id', 'uuid', true, 'gen_random_uuid()', ''),
      ('producto', 'local_id', 'uuid', true, null, ''),
      ('producto', 'categoria_id', 'uuid', true, null, ''),
      ('producto', 'codigo', 'text', true, null, ''),
      ('producto', 'nombre', 'text', true, null, ''),
      ('producto', 'precio', 'numeric(10,2)', true, null, ''),
      ('producto', 'activo', 'boolean', true, 'true', ''),
      ('producto', 'creado_en', 'timestamp with time zone', true, 'now()', ''),
      ('pedido', 'id', 'bigint', true, null, 'a'),
      ('pedido', 'local_id', 'uuid', true, null, ''),
      ('pedido', 'mesa_id', 'uuid', true, null, ''),
      ('pedido', 'creado_por', 'uuid', true, null, ''),
      ('pedido', 'estado', 'text', true, '''ABIERTO''::text', ''),
      ('pedido', 'creado_en', 'timestamp with time zone', true, 'now()', ''),
      ('pedido', 'enviado_en', 'timestamp with time zone', false, null, ''),
      ('pedido', 'modificado_por', 'uuid', true, null, ''),
      ('pedido', 'modificado_en', 'timestamp with time zone', true, null, ''),
      ('detalle_pedido', 'id', 'bigint', true, null, 'a'),
      ('detalle_pedido', 'pedido_id', 'bigint', true, null, ''),
      ('detalle_pedido', 'producto_id', 'uuid', true, null, ''),
      ('detalle_pedido', 'cantidad', 'integer', true, null, ''),
      ('detalle_pedido', 'precio_unitario', 'numeric(10,2)', true, null, ''),
      ('detalle_pedido', 'observacion', 'text', false, null, ''),
      ('detalle_pedido', 'estado', 'text', true, '''ABIERTO''::text', ''),
      ('detalle_pedido', 'creado_por', 'uuid', true, null, ''),
      ('detalle_pedido', 'creado_en', 'timestamp with time zone', true, 'now()', ''),
      ('detalle_pedido', 'modificado_por', 'uuid', true, null, ''),
      ('detalle_pedido', 'modificado_en', 'timestamp with time zone', true, 'now()', ''),
      ('detalle_pedido', 'enviado_en', 'timestamp with time zone', false, null, ''),
      ('historial_estado', 'id', 'bigint', true, null, 'a'),
      ('historial_estado', 'pedido_id', 'bigint', true, null, ''),
      ('historial_estado', 'estado_anterior', 'text', false, null, ''),
      ('historial_estado', 'estado_nuevo', 'text', true, null, ''),
      ('historial_estado', 'usuario_id', 'uuid', true, null, ''),
      ('historial_estado', 'creado_en', 'timestamp with time zone', true, 'now()', ''),
      ('pago', 'id', 'bigint', true, null, 'a'),
      ('pago', 'pedido_id', 'bigint', true, null, ''),
      ('pago', 'importe', 'numeric(10,2)', true, null, ''),
      ('pago', 'medio', 'text', true, null, ''),
      ('pago', 'usuario_id', 'uuid', true, null, ''),
      ('pago', 'pagado_en', 'timestamp with time zone', true, 'now()', '')
  ),
  actual as (
    select
      c.relname::text as table_name,
      a.attname::text as column_name,
      format_type(a.atttypid, a.atttypmod) as formatted_type,
      a.attnotnull as not_null,
      pg_get_expr(d.adbin, d.adrelid) as default_expr,
      a.attidentity::text as identity_kind
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace n on n.oid = c.relnamespace
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where n.nspname = 'public'
      and c.relname in (
        'local', 'rol', 'perfil_usuario', 'mesa', 'categoria',
        'producto', 'pedido', 'detalle_pedido', 'historial_estado', 'pago'
      )
      and c.relkind in ('r', 'p')
      and a.attnum > 0
      and not a.attisdropped
  )
  select count(*)
    into mismatch_count
  from expected e
  full join actual a using (table_name, column_name)
  where e.table_name is null
     or a.table_name is null
     or e.formatted_type <> a.formatted_type
     or e.not_null <> a.not_null
     or coalesce(e.default_expr, '') <> coalesce(a.default_expr, '')
     or e.identity_kind <> a.identity_kind;

  if mismatch_count <> 0 then
    raise exception 'TP-11: column definitions differ in % places', mismatch_count;
  end if;

  select count(*) into actual_count
  from pg_constraint con
  join pg_namespace n on n.oid = con.connamespace
  where n.nspname = 'public' and con.contype = 'p';
  if actual_count <> 10 then
    raise exception 'TP-11: expected 10 PK, found %', actual_count;
  end if;

  select count(*) into actual_count
  from pg_constraint con
  join pg_namespace n on n.oid = con.connamespace
  where n.nspname = 'public' and con.contype = 'f';
  if actual_count <> 19 then
    raise exception 'TP-11: expected 19 FK, found %', actual_count;
  end if;

  select count(*) into actual_count
  from pg_constraint con
  join pg_namespace n on n.oid = con.connamespace
  where n.nspname = 'public' and con.contype = 'f' and con.confdeltype = 'r';
  if actual_count <> 19 then
    raise exception 'TP-11: expected 19 FK ON DELETE RESTRICT, found %', actual_count;
  end if;

  select count(*) into actual_count
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and a.attidentity in ('a', 'd');
  if actual_count <> 5 then
    raise exception 'TP-11: expected 5 identity columns, found %', actual_count;
  end if;

  select count(*) into mismatch_count
  from (
    values
      ('rol', 'id', 'd'),
      ('pedido', 'id', 'a'),
      ('detalle_pedido', 'id', 'a'),
      ('historial_estado', 'id', 'a'),
      ('pago', 'id', 'a')
  ) as e(table_name, column_name, identity_kind)
  left join pg_class c on c.relname = e.table_name
  left join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
  left join pg_attribute a
    on a.attrelid = c.oid and a.attname = e.column_name
  where n.oid is null or a.attidentity::text <> e.identity_kind;
  if mismatch_count <> 0 then
    raise exception 'TP-11: identity modality mismatch';
  end if;

  select count(*) into actual_count
  from pg_constraint con
  join pg_namespace n on n.oid = con.connamespace
  where n.nspname = 'public' and con.contype = 'u';
  if actual_count <> 9 then
    raise exception 'TP-11: expected 9 UNIQUE constraints, found %', actual_count;
  end if;

  select count(*) into actual_count
  from pg_constraint con
  join pg_namespace n on n.oid = con.connamespace
  where n.nspname = 'public' and con.contype = 'c';
  if actual_count <> 25 then
    raise exception 'TP-11: expected 25 CHECK constraints, found %', actual_count;
  end if;

  select count(*), array_agg(index_name order by index_name)
    into actual_count, actual_names
  from (
    select index_class.relname::text as index_name
    from pg_index i
    join pg_class table_class on table_class.oid = i.indrelid
    join pg_namespace n on n.oid = table_class.relnamespace
    join pg_class index_class on index_class.oid = i.indexrelid
    left join pg_constraint con on con.conindid = i.indexrelid
    where n.nspname = 'public'
      and con.oid is null
      and table_class.relname in (
        'local', 'rol', 'perfil_usuario', 'mesa', 'categoria',
        'producto', 'pedido', 'detalle_pedido', 'historial_estado', 'pago'
      )
  ) indexes;
  if actual_count <> 15 or actual_names <> array[
    'idx_categoria_local_id_activo_orden',
    'idx_detalle_pedido_cocina_enviado_en',
    'idx_detalle_pedido_pedido_id',
    'idx_detalle_pedido_pedido_id_estado',
    'idx_detalle_pedido_producto_id',
    'idx_historial_estado_pedido_id_creado_en',
    'idx_mesa_local_id_estado',
    'idx_pago_pagado_en',
    'idx_pedido_local_id_estado_creado_en',
    'idx_pedido_mesa_id_estado',
    'idx_perfil_usuario_local_id',
    'idx_perfil_usuario_rol_id',
    'idx_producto_categoria_id_activo',
    'idx_producto_local_id_activo',
    'uq_pedido_mesa_id_vigente'
  ]::text[] then
    raise exception 'TP-11: expected 15 exact additional indexes, found %: %', actual_count, actual_names;
  end if;

  select count(*) into actual_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (
      'local', 'rol', 'perfil_usuario', 'mesa', 'categoria',
      'producto', 'pedido', 'detalle_pedido', 'historial_estado', 'pago'
    )
    and c.relrowsecurity;
  if actual_count <> 10 then
    raise exception 'TP-11: expected RLS on 10 tables, found %', actual_count;
  end if;

  select count(*) into actual_count
  from pg_policies
  where schemaname = 'public'
    and tablename in ('local', 'mesa', 'categoria', 'producto')
    and cmd = 'SELECT'
    and roles = array['anon']::name[]
    and regexp_replace(qual, '[()[:space:]]', '', 'g') = 'activo=true';
  if actual_count <> 4 then
    raise exception 'TP-11: expected 4 active-row anon SELECT policies, found %', actual_count;
  end if;

  select count(*) into actual_count
  from pg_policies
  where schemaname = 'public' and 'anon' = any(roles);
  if actual_count <> 4 then
    raise exception 'TP-11: unexpected anon policies found: %', actual_count;
  end if;

  select count(*) into mismatch_count
  from (
    values
      ('local', true),
      ('rol', false),
      ('perfil_usuario', false),
      ('mesa', true),
      ('categoria', true),
      ('producto', true),
      ('pedido', false),
      ('detalle_pedido', false),
      ('historial_estado', false),
      ('pago', false)
  ) as expected(table_name, can_select)
  where has_table_privilege(
    'anon',
    format('public.%I', expected.table_name),
    'SELECT'
  ) <> expected.can_select;
  if mismatch_count <> 0 then
    raise exception 'TP-11: anon SELECT privilege matrix differs in % tables', mismatch_count;
  end if;

  select count(*) into actual_count
  from (
    values
      ('local'), ('rol'), ('perfil_usuario'), ('mesa'), ('categoria'),
      ('producto'), ('pedido'), ('detalle_pedido'), ('historial_estado'), ('pago')
  ) as tables(table_name)
  cross join (
    values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')
  ) as privileges(privilege_name)
  where has_table_privilege(
    'anon',
    format('public.%I', tables.table_name),
    privileges.privilege_name
  );
  if actual_count <> 0 then
    raise exception 'TP-11: anon has % forbidden table privileges', actual_count;
  end if;

  select count(*) into actual_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'S'
    and (
      has_sequence_privilege('anon', c.oid, 'USAGE')
      or has_sequence_privilege('anon', c.oid, 'SELECT')
      or has_sequence_privilege('anon', c.oid, 'UPDATE')
    );
  if actual_count <> 0 then
    raise exception 'TP-11: anon has privileges on % public sequences', actual_count;
  end if;

  raise notice 'TP-09/TP-11 passed: schema and anon access match H1';
end;
$$;
