begin;

revoke all privileges
on table
  public.perfil_usuario,
  public.rol,
  public.local,
  public.categoria,
  public.producto,
  public.mesa,
  public.pedido,
  public.detalle_pedido,
  public.historial_estado,
  public.pago
from authenticated;

revoke insert, update, delete, truncate, references, trigger
on table
  public.perfil_usuario,
  public.rol,
  public.local,
  public.categoria,
  public.producto,
  public.mesa,
  public.pedido,
  public.detalle_pedido,
  public.historial_estado,
  public.pago
from public, anon;

revoke all privileges on all sequences in schema public
from public, anon, authenticated;

grant select on table
  public.perfil_usuario,
  public.rol,
  public.local,
  public.categoria,
  public.producto,
  public.mesa
to authenticated;

grant delete on table
  public.categoria,
  public.producto,
  public.mesa
to authenticated;

grant insert (local_id, codigo, nombre, orden, activo)
on table public.categoria
to authenticated;

grant update (codigo, nombre, orden, activo)
on table public.categoria
to authenticated;

grant insert (local_id, categoria_id, codigo, nombre, precio, activo)
on table public.producto
to authenticated;

grant update (codigo, nombre, precio, categoria_id, activo)
on table public.producto
to authenticated;

grant insert (local_id, codigo, nombre, activo)
on table public.mesa
to authenticated;

grant update (codigo, nombre, activo)
on table public.mesa
to authenticated;

do $h2_privilege_checks$
declare
  h2_table_name text;
  h2_table_reference text;
  h2_column_name text;
  h2_sequence_reference text;
  h2_privilege_name text;
  h2_role_name text;
  h2_allowed_insert_columns text[];
  h2_allowed_update_columns text[];
  h2_tables constant text[] := array[
    'perfil_usuario',
    'rol',
    'local',
    'categoria',
    'producto',
    'mesa',
    'pedido',
    'detalle_pedido',
    'historial_estado',
    'pago'
  ];
  h2_authenticated_select_tables constant text[] := array[
    'perfil_usuario', 'rol', 'local', 'categoria', 'producto', 'mesa'
  ];
  h2_catalog_tables constant text[] := array[
    'categoria', 'producto', 'mesa'
  ];
  h2_anon_select_tables constant text[] := array[
    'local', 'mesa', 'categoria', 'producto'
  ];
  h2_write_privileges constant text[] := array[
    'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
  ];
begin
  foreach h2_table_name in array h2_tables loop
    h2_table_reference := pg_catalog.format('public.%I', h2_table_name);

    if pg_catalog.has_table_privilege(
      'authenticated', h2_table_reference, 'SELECT'
    ) <> (h2_table_name = any(h2_authenticated_select_tables)) then
      raise exception 'Privilegio SELECT authenticated inesperado: %', h2_table_name;
    end if;

    if pg_catalog.has_table_privilege(
      'authenticated', h2_table_reference, 'DELETE'
    ) <> (h2_table_name = any(h2_catalog_tables)) then
      raise exception 'Privilegio DELETE authenticated inesperado: %', h2_table_name;
    end if;

    if pg_catalog.has_table_privilege('authenticated', h2_table_reference, 'INSERT')
      or pg_catalog.has_table_privilege('authenticated', h2_table_reference, 'UPDATE')
      or pg_catalog.has_table_privilege('authenticated', h2_table_reference, 'TRUNCATE')
      or pg_catalog.has_table_privilege('authenticated', h2_table_reference, 'REFERENCES')
      or pg_catalog.has_table_privilege('authenticated', h2_table_reference, 'TRIGGER') then
      raise exception 'Privilegio amplio authenticated inesperado: %', h2_table_name;
    end if;

    if pg_catalog.has_table_privilege('anon', h2_table_reference, 'SELECT')
      <> (h2_table_name = any(h2_anon_select_tables)) then
      raise exception 'Lectura anonima H1 inesperada: %', h2_table_name;
    end if;

    foreach h2_privilege_name in array h2_write_privileges loop
      if pg_catalog.has_table_privilege(
        'anon', h2_table_reference, h2_privilege_name
      ) then
        raise exception 'Escritura anonima inesperada: % %',
          h2_table_name, h2_privilege_name;
      end if;
    end loop;

    if exists (
      select 1
      from pg_catalog.pg_class as table_metadata
      inner join pg_catalog.pg_namespace as table_schema
        on table_schema.oid = table_metadata.relnamespace
      cross join lateral pg_catalog.aclexplode(
        coalesce(
          table_metadata.relacl,
          pg_catalog.acldefault('r', table_metadata.relowner)
        )
      ) as table_acl
      where table_schema.nspname = 'public'
        and table_metadata.relname = h2_table_name
        and table_acl.grantee = 0
        and table_acl.privilege_type = any(h2_write_privileges)
    ) then
      raise exception 'Escritura PUBLIC inesperada: %', h2_table_name;
    end if;

    h2_allowed_insert_columns := case h2_table_name
      when 'categoria' then array['local_id', 'codigo', 'nombre', 'orden', 'activo']
      when 'producto' then array[
        'local_id', 'categoria_id', 'codigo', 'nombre', 'precio', 'activo'
      ]
      when 'mesa' then array['local_id', 'codigo', 'nombre', 'activo']
      else array[]::text[]
    end;

    h2_allowed_update_columns := case h2_table_name
      when 'categoria' then array['codigo', 'nombre', 'orden', 'activo']
      when 'producto' then array['codigo', 'nombre', 'precio', 'categoria_id', 'activo']
      when 'mesa' then array['codigo', 'nombre', 'activo']
      else array[]::text[]
    end;

    for h2_column_name in
      select column_metadata.attname
      from pg_catalog.pg_attribute as column_metadata
      where column_metadata.attrelid = h2_table_reference::pg_catalog.regclass
        and column_metadata.attnum > 0
        and not column_metadata.attisdropped
    loop
      if pg_catalog.has_column_privilege(
        'authenticated', h2_table_reference, h2_column_name, 'INSERT'
      ) <> (h2_column_name = any(h2_allowed_insert_columns)) then
        raise exception 'Privilegio INSERT de columna inesperado: %.%',
          h2_table_name, h2_column_name;
      end if;

      if pg_catalog.has_column_privilege(
        'authenticated', h2_table_reference, h2_column_name, 'UPDATE'
      ) <> (h2_column_name = any(h2_allowed_update_columns)) then
        raise exception 'Privilegio UPDATE de columna inesperado: %.%',
          h2_table_name, h2_column_name;
      end if;

      if pg_catalog.has_column_privilege('anon', h2_table_reference, h2_column_name, 'INSERT')
        or pg_catalog.has_column_privilege('anon', h2_table_reference, h2_column_name, 'UPDATE')
        or pg_catalog.has_column_privilege('anon', h2_table_reference, h2_column_name, 'REFERENCES') then
        raise exception 'Privilegio anonimo de columna inesperado: %.%',
          h2_table_name, h2_column_name;
      end if;
    end loop;
  end loop;

  for h2_sequence_reference in
    select pg_catalog.format('%I.%I', sequence_schema.nspname, sequence_metadata.relname)
    from pg_catalog.pg_class as sequence_metadata
    inner join pg_catalog.pg_namespace as sequence_schema
      on sequence_schema.oid = sequence_metadata.relnamespace
    where sequence_schema.nspname = 'public'
      and sequence_metadata.relkind = 'S'
  loop
    foreach h2_role_name in array array['anon', 'authenticated'] loop
      if pg_catalog.has_sequence_privilege(h2_role_name, h2_sequence_reference, 'USAGE')
        or pg_catalog.has_sequence_privilege(h2_role_name, h2_sequence_reference, 'SELECT')
        or pg_catalog.has_sequence_privilege(h2_role_name, h2_sequence_reference, 'UPDATE') then
        raise exception 'Privilegio de secuencia inesperado: % %',
          h2_role_name, h2_sequence_reference;
      end if;
    end loop;
  end loop;
end;
$h2_privilege_checks$;

commit;
