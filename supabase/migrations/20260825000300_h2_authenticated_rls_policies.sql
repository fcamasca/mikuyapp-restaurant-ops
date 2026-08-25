begin;

create policy h2_select_own_profile
on public.perfil_usuario
for select
to authenticated
using (public.perfil_usuario.id = auth.uid());

create policy h2_select_context_role
on public.rol
for select
to authenticated
using (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.rol_id = public.rol.id
  )
);

create policy h2_select_context_local
on public.local
for select
to authenticated
using (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.local.id
  )
);

create policy h2_select_local_categories
on public.categoria
for select
to authenticated
using (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.categoria.local_id
      and (
        auth_context.rol_codigo = 'ADMINISTRADOR'
        or public.categoria.activo = true
      )
  )
);

create policy h2_insert_admin_categories
on public.categoria
for insert
to authenticated
with check (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.categoria.local_id
      and auth_context.rol_codigo = 'ADMINISTRADOR'
  )
);

create policy h2_update_admin_categories
on public.categoria
for update
to authenticated
using (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.categoria.local_id
      and auth_context.rol_codigo = 'ADMINISTRADOR'
  )
)
with check (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.categoria.local_id
      and auth_context.rol_codigo = 'ADMINISTRADOR'
  )
);

create policy h2_delete_admin_categories
on public.categoria
for delete
to authenticated
using (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.categoria.local_id
      and auth_context.rol_codigo = 'ADMINISTRADOR'
  )
);

create policy h2_select_local_products
on public.producto
for select
to authenticated
using (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.producto.local_id
      and (
        auth_context.rol_codigo = 'ADMINISTRADOR'
        or (
          public.producto.activo = true
          and exists (
            select 1
            from public.categoria as product_category
            where product_category.id = public.producto.categoria_id
              and product_category.local_id = public.producto.local_id
              and product_category.activo = true
          )
        )
      )
  )
);

create policy h2_insert_admin_products
on public.producto
for insert
to authenticated
with check (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.producto.local_id
      and auth_context.rol_codigo = 'ADMINISTRADOR'
  )
  and exists (
    select 1
    from public.categoria as product_category
    where product_category.id = public.producto.categoria_id
      and product_category.local_id = public.producto.local_id
  )
);

create policy h2_update_admin_products
on public.producto
for update
to authenticated
using (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.producto.local_id
      and auth_context.rol_codigo = 'ADMINISTRADOR'
  )
)
with check (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.producto.local_id
      and auth_context.rol_codigo = 'ADMINISTRADOR'
  )
  and exists (
    select 1
    from public.categoria as product_category
    where product_category.id = public.producto.categoria_id
      and product_category.local_id = public.producto.local_id
  )
);

create policy h2_delete_admin_products
on public.producto
for delete
to authenticated
using (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.producto.local_id
      and auth_context.rol_codigo = 'ADMINISTRADOR'
  )
);

create policy h2_select_local_tables
on public.mesa
for select
to authenticated
using (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.mesa.local_id
      and (
        auth_context.rol_codigo = 'ADMINISTRADOR'
        or (
          auth_context.rol_codigo = 'MOZO'
          and public.mesa.activo = true
        )
      )
  )
);

create policy h2_insert_admin_tables
on public.mesa
for insert
to authenticated
with check (
  public.mesa.estado = 'LIBRE'
  and exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.mesa.local_id
      and auth_context.rol_codigo = 'ADMINISTRADOR'
  )
);

create policy h2_update_admin_tables
on public.mesa
for update
to authenticated
using (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.mesa.local_id
      and auth_context.rol_codigo = 'ADMINISTRADOR'
  )
)
with check (
  (
    public.mesa.activo = true
    or public.mesa.estado = 'LIBRE'
  )
  and exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.mesa.local_id
      and auth_context.rol_codigo = 'ADMINISTRADOR'
  )
);

create policy h2_delete_admin_tables
on public.mesa
for delete
to authenticated
using (
  exists (
    select 1
    from public.h2_auth_context() as auth_context
    where auth_context.local_id = public.mesa.local_id
      and auth_context.rol_codigo = 'ADMINISTRADOR'
  )
);

do $h2_policy_checks$
declare
  h2_expected_policy record;
  h2_policy_metadata record;
  h2_authenticated_role oid;
  h2_anon_role oid;
  h2_profile_expression text;
  h2_category_expression text;
begin
  select role_metadata.oid
  into strict h2_authenticated_role
  from pg_catalog.pg_roles as role_metadata
  where role_metadata.rolname = 'authenticated';

  select role_metadata.oid
  into strict h2_anon_role
  from pg_catalog.pg_roles as role_metadata
  where role_metadata.rolname = 'anon';

  for h2_expected_policy in
    select *
    from (
      values
        ('perfil_usuario', 'h2_select_own_profile', 'r'),
        ('rol', 'h2_select_context_role', 'r'),
        ('local', 'h2_select_context_local', 'r'),
        ('categoria', 'h2_select_local_categories', 'r'),
        ('categoria', 'h2_insert_admin_categories', 'a'),
        ('categoria', 'h2_update_admin_categories', 'w'),
        ('categoria', 'h2_delete_admin_categories', 'd'),
        ('producto', 'h2_select_local_products', 'r'),
        ('producto', 'h2_insert_admin_products', 'a'),
        ('producto', 'h2_update_admin_products', 'w'),
        ('producto', 'h2_delete_admin_products', 'd'),
        ('mesa', 'h2_select_local_tables', 'r'),
        ('mesa', 'h2_insert_admin_tables', 'a'),
        ('mesa', 'h2_update_admin_tables', 'w'),
        ('mesa', 'h2_delete_admin_tables', 'd')
    ) as expected_policy(table_name, policy_name, command_name)
  loop
    select
      policy_metadata.polname,
      policy_metadata.polcmd,
      policy_metadata.polroles,
      pg_catalog.pg_get_expr(
        policy_metadata.polqual,
        policy_metadata.polrelid
      ) as using_expression,
      pg_catalog.pg_get_expr(
        policy_metadata.polwithcheck,
        policy_metadata.polrelid
      ) as check_expression
    into h2_policy_metadata
    from pg_catalog.pg_policy as policy_metadata
    inner join pg_catalog.pg_class as table_metadata
      on table_metadata.oid = policy_metadata.polrelid
    inner join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public'
      and table_metadata.relname = h2_expected_policy.table_name
      and policy_metadata.polname = h2_expected_policy.policy_name;

    if not found then
      raise exception 'Politica H2 ausente: %', h2_expected_policy.policy_name;
    end if;

    if h2_policy_metadata.polcmd::text <> h2_expected_policy.command_name then
      raise exception 'Operacion RLS inesperada: %', h2_expected_policy.policy_name;
    end if;

    if h2_policy_metadata.polroles <> array[h2_authenticated_role] then
      raise exception 'Rol RLS inesperado: %', h2_expected_policy.policy_name;
    end if;

    if h2_expected_policy.command_name = 'a'
      and (
        h2_policy_metadata.using_expression is not null
        or h2_policy_metadata.check_expression is null
      ) then
      raise exception 'INSERT sin WITH CHECK exclusivo: %',
        h2_expected_policy.policy_name;
    end if;

    if h2_expected_policy.command_name = 'w'
      and (
        h2_policy_metadata.using_expression is null
        or h2_policy_metadata.check_expression is null
      ) then
      raise exception 'UPDATE sin USING/WITH CHECK: %',
        h2_expected_policy.policy_name;
    end if;

    if h2_expected_policy.command_name in ('r', 'd')
      and (
        h2_policy_metadata.using_expression is null
        or h2_policy_metadata.check_expression is not null
      ) then
      raise exception 'SELECT/DELETE sin USING exclusivo: %',
        h2_expected_policy.policy_name;
    end if;

    if h2_expected_policy.table_name = 'perfil_usuario' then
      h2_profile_expression := h2_policy_metadata.using_expression;

      if h2_profile_expression ~* 'h2_auth_context'
        or h2_profile_expression !~* 'auth\.uid'
        or h2_profile_expression ~* '\mactivo\M' then
        raise exception 'Politica de perfil recursiva o restringida indebidamente';
      end if;
    elsif (
      coalesce(h2_policy_metadata.using_expression, '')
      || coalesce(h2_policy_metadata.check_expression, '')
    ) !~* 'h2_auth_context' then
      raise exception 'Politica H2 sin contexto autenticado: %',
        h2_expected_policy.policy_name;
    end if;

    if h2_expected_policy.table_name = 'categoria' then
      h2_category_expression :=
        coalesce(h2_policy_metadata.using_expression, '')
        || coalesce(h2_policy_metadata.check_expression, '');

      if h2_category_expression ~* '\mproducto\M' then
        raise exception 'Dependencia recursiva entre categoria y producto';
      end if;
    end if;
  end loop;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policy as policy_metadata
    inner join pg_catalog.pg_class as table_metadata
      on table_metadata.oid = policy_metadata.polrelid
    inner join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public'
      and policy_metadata.polname like 'h2\_%' escape '\'
  ) <> 15 then
    raise exception 'Cantidad inesperada de politicas H2';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policy as policy_metadata
    inner join pg_catalog.pg_class as table_metadata
      on table_metadata.oid = policy_metadata.polrelid
    inner join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public'
      and policy_metadata.polname = any(array[
        'anon_select_active_local',
        'anon_select_active_mesa',
        'anon_select_active_categoria',
        'anon_select_active_producto'
      ])
      and policy_metadata.polcmd = 'r'
      and policy_metadata.polroles = array[h2_anon_role]
  ) <> 4 then
    raise exception 'Las cuatro politicas anonimas H1 no fueron conservadas';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policy as policy_metadata
    inner join pg_catalog.pg_class as table_metadata
      on table_metadata.oid = policy_metadata.polrelid
    inner join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public'
      and table_metadata.relname = any(array[
        'pedido', 'detalle_pedido', 'historial_estado', 'pago'
      ])
      and policy_metadata.polname like 'h2\_%' escape '\'
  ) then
    raise exception 'Se detectaron politicas H2 sobre tablas transaccionales';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc as function_metadata
    inner join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function_metadata.pronamespace
    inner join pg_catalog.pg_roles as function_owner
      on function_owner.oid = function_metadata.proowner
    where function_schema.nspname = 'public'
      and function_metadata.proname = 'h2_auth_context'
      and function_metadata.pronargs = 0
      and function_metadata.prosecdef = true
      and function_owner.rolname = 'postgres'
  ) then
    raise exception 'La funcion de contexto no conserva SECURITY DEFINER postgres';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.categoria', 'INSERT')
    or pg_catalog.has_table_privilege('authenticated', 'public.categoria', 'UPDATE')
    or pg_catalog.has_table_privilege('authenticated', 'public.producto', 'INSERT')
    or pg_catalog.has_table_privilege('authenticated', 'public.producto', 'UPDATE')
    or pg_catalog.has_table_privilege('authenticated', 'public.mesa', 'INSERT')
    or pg_catalog.has_table_privilege('authenticated', 'public.mesa', 'UPDATE')
    or pg_catalog.has_column_privilege('authenticated', 'public.mesa', 'estado', 'INSERT')
    or pg_catalog.has_column_privilege('authenticated', 'public.mesa', 'estado', 'UPDATE') then
    raise exception 'Los privilegios protegidos T07 fueron alterados';
  end if;
end;
$h2_policy_checks$;

commit;
