begin;

alter function public.h2_auth_context()
  rename to obtener_contexto_autenticado;

alter function public.h3_abrir_o_recuperar_pedido(uuid)
  rename to crear_o_recuperar_pedido_mesa;

create or replace function public.crear_o_recuperar_pedido_mesa(
  p_mesa_id uuid
)
returns table (
  pedido_id bigint,
  pedido_estado text,
  creado_en timestamptz,
  enviado_en timestamptz,
  fue_creado boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $crear_o_recuperar_pedido_mesa$
declare
  v_usuario_id uuid := auth.uid();
  v_local_id uuid;
  v_rol_codigo text;
  v_mesa_estado text;
  v_pedido public.pedido%rowtype;
begin
  if p_mesa_id is null or v_usuario_id is null then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para abrir pedidos';
  end if;

  select auth_context.local_id, auth_context.rol_codigo
  into v_local_id, v_rol_codigo
  from public.obtener_contexto_autenticado() as auth_context;

  if v_local_id is null or v_rol_codigo is distinct from 'MOZO' then
    raise exception using
      errcode = '42501',
      message = 'No autorizado para abrir pedidos';
  end if;

  select table_row.estado
  into v_mesa_estado
  from public.mesa as table_row
  where table_row.id = p_mesa_id
    and table_row.local_id = v_local_id
    and table_row.activo = true
  for update;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Mesa no disponible para el usuario autenticado';
  end if;

  select order_row.*
  into v_pedido
  from public.pedido as order_row
  where order_row.mesa_id = p_mesa_id
    and order_row.local_id = v_local_id
    and order_row.estado in (
      'ABIERTO',
      'ENVIADO',
      'RECIBIDO_COCINA',
      'EN_PREPARACION',
      'LISTO',
      'ENTREGADO'
    );

  if found then
    return query
    select
      v_pedido.id,
      v_pedido.estado,
      v_pedido.creado_en,
      v_pedido.enviado_en,
      false;
    return;
  end if;

  if v_mesa_estado <> 'LIBRE' then
    raise exception using
      errcode = '55000',
      message = 'La mesa no está libre y no tiene un pedido vigente recuperable';
  end if;

  insert into public.pedido (local_id, mesa_id, creado_por, estado)
  values (v_local_id, p_mesa_id, v_usuario_id, 'ABIERTO')
  returning * into v_pedido;

  insert into public.historial_estado (
    pedido_id,
    estado_anterior,
    estado_nuevo,
    usuario_id
  )
  values (v_pedido.id, null, 'ABIERTO', v_usuario_id);

  update public.mesa as table_row
  set estado = 'OCUPADA'
  where table_row.id = p_mesa_id
    and table_row.local_id = v_local_id
    and table_row.activo = true
    and table_row.estado = 'LIBRE';

  if not found then
    raise exception using
      errcode = '40001',
      message = 'La mesa cambió durante la apertura del pedido';
  end if;

  return query
  select
    v_pedido.id,
    v_pedido.estado,
    v_pedido.creado_en,
    v_pedido.enviado_en,
    true;
end;
$crear_o_recuperar_pedido_mesa$;

alter policy h2_select_own_profile
  on public.perfil_usuario rename to perfil_usuario_select_propio;
alter policy h2_select_context_role
  on public.rol rename to rol_select_contexto_autenticado;
alter policy h2_select_context_local
  on public.local rename to local_select_contexto_autenticado;
alter policy h2_select_local_categories
  on public.categoria rename to categoria_select_local;
alter policy h2_insert_admin_categories
  on public.categoria rename to categoria_insert_administrador;
alter policy h2_update_admin_categories
  on public.categoria rename to categoria_update_administrador;
alter policy h2_delete_admin_categories
  on public.categoria rename to categoria_delete_administrador;
alter policy h2_select_local_products
  on public.producto rename to producto_select_local;
alter policy h2_insert_admin_products
  on public.producto rename to producto_insert_administrador;
alter policy h2_update_admin_products
  on public.producto rename to producto_update_administrador;
alter policy h2_delete_admin_products
  on public.producto rename to producto_delete_administrador;
alter policy h2_select_local_tables
  on public.mesa rename to mesa_select_local;
alter policy h2_insert_admin_tables
  on public.mesa rename to mesa_insert_administrador;
alter policy h2_update_admin_tables
  on public.mesa rename to mesa_update_administrador;
alter policy h2_delete_admin_tables
  on public.mesa rename to mesa_delete_administrador;

do $verify_domain_object_names$
begin
  if exists (
    select 1
    from pg_catalog.pg_proc as function_metadata
    inner join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function_metadata.pronamespace
    where function_schema.nspname = 'public'
      and function_metadata.proname ~* '^h[0-9]+_'
  ) then
    raise exception 'Persisten funciones públicas con prefijo de hito';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policy as policy_metadata
    inner join pg_catalog.pg_class as table_metadata
      on table_metadata.oid = policy_metadata.polrelid
    inner join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public'
      and policy_metadata.polname ~* '^h[0-9]+_'
  ) then
    raise exception 'Persisten policies públicas con prefijo de hito';
  end if;

  if pg_catalog.has_function_privilege(
      'anon', 'public.obtener_contexto_autenticado()', 'EXECUTE'
    )
    or not pg_catalog.has_function_privilege(
      'authenticated', 'public.obtener_contexto_autenticado()', 'EXECUTE'
    )
    or pg_catalog.has_function_privilege(
      'anon', 'public.crear_o_recuperar_pedido_mesa(uuid)', 'EXECUTE'
    )
    or not pg_catalog.has_function_privilege(
      'authenticated', 'public.crear_o_recuperar_pedido_mesa(uuid)', 'EXECUTE'
    ) then
    raise exception 'Los privilegios de las funciones renombradas cambiaron';
  end if;
end;
$verify_domain_object_names$;

notify pgrst, 'reload schema';

commit;
