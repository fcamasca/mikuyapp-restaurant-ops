begin;

do $verify_domain_object_names$
declare
  invalid_objects text[];
  expected_policies text[] := array[
    'categoria_delete_administrador',
    'categoria_insert_administrador',
    'categoria_select_local',
    'categoria_update_administrador',
    'local_select_contexto_autenticado',
    'mesa_delete_administrador',
    'mesa_insert_administrador',
    'mesa_select_local',
    'mesa_update_administrador',
    'perfil_usuario_select_propio',
    'producto_delete_administrador',
    'producto_insert_administrador',
    'producto_select_local',
    'producto_update_administrador',
    'rol_select_contexto_autenticado'
  ];
  actual_policies text[];
begin
  select pg_catalog.array_agg(object_name order by object_name)
  into invalid_objects
  from (
    select 'relation:' || relation_metadata.relname as object_name
    from pg_catalog.pg_class as relation_metadata
    inner join pg_catalog.pg_namespace as relation_schema
      on relation_schema.oid = relation_metadata.relnamespace
    where relation_schema.nspname = 'public'
      and relation_metadata.relkind in ('r', 'p', 'v', 'm', 'i', 'S')
      and relation_metadata.relname ~* '^h[0-9]+_'
    union all
    select 'column:' || table_metadata.relname || '.' || column_metadata.attname
    from pg_catalog.pg_attribute as column_metadata
    inner join pg_catalog.pg_class as table_metadata
      on table_metadata.oid = column_metadata.attrelid
    inner join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public'
      and column_metadata.attnum > 0
      and not column_metadata.attisdropped
      and column_metadata.attname ~* '^h[0-9]+_'
    union all
    select 'constraint:' || constraint_metadata.conname
    from pg_catalog.pg_constraint as constraint_metadata
    inner join pg_catalog.pg_namespace as constraint_schema
      on constraint_schema.oid = constraint_metadata.connamespace
    where constraint_schema.nspname = 'public'
      and constraint_metadata.conname ~* '^h[0-9]+_'
    union all
    select 'function:' || function_metadata.proname
    from pg_catalog.pg_proc as function_metadata
    inner join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function_metadata.pronamespace
    where function_schema.nspname = 'public'
      and function_metadata.proname ~* '^h[0-9]+_'
    union all
    select 'policy:' || policy_metadata.polname
    from pg_catalog.pg_policy as policy_metadata
    inner join pg_catalog.pg_class as table_metadata
      on table_metadata.oid = policy_metadata.polrelid
    inner join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public'
      and policy_metadata.polname ~* '^h[0-9]+_'
    union all
    select 'trigger:' || trigger_metadata.tgname
    from pg_catalog.pg_trigger as trigger_metadata
    inner join pg_catalog.pg_class as table_metadata
      on table_metadata.oid = trigger_metadata.tgrelid
    inner join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public'
      and not trigger_metadata.tgisinternal
      and trigger_metadata.tgname ~* '^h[0-9]+_'
  ) as milestone_objects;

  if invalid_objects is not null then
    raise exception 'Objetos permanentes con prefijo de hito: %', invalid_objects;
  end if;

  if to_regprocedure('public.h2_auth_context()') is not null
    or to_regprocedure('public.h3_abrir_o_recuperar_pedido(uuid)') is not null
    or to_regprocedure('public.obtener_contexto_autenticado()') is null
    or to_regprocedure('public.crear_o_recuperar_pedido_mesa(uuid)') is null then
    raise exception 'Funciones permanentes antiguas o nuevas inconsistentes';
  end if;

  select pg_catalog.array_agg(policy_metadata.polname order by policy_metadata.polname)
  into actual_policies
  from pg_catalog.pg_policy as policy_metadata
  inner join pg_catalog.pg_class as table_metadata
    on table_metadata.oid = policy_metadata.polrelid
  inner join pg_catalog.pg_namespace as table_schema
    on table_schema.oid = table_metadata.relnamespace
  where table_schema.nspname = 'public'
    and table_metadata.relname in (
      'perfil_usuario', 'rol', 'local', 'categoria', 'producto', 'mesa'
    )
    and policy_metadata.polroles = array[
      (select role_metadata.oid from pg_catalog.pg_roles as role_metadata
       where role_metadata.rolname = 'authenticated')
    ];

  if actual_policies <> expected_policies then
    raise exception 'Policies funcionales inesperadas: %', actual_policies;
  end if;
end;
$verify_domain_object_names$;

rollback;
