-- MikuyApp H2 / T05: asociación administrativa de usuarios Auth y perfiles.
-- Copiar esta plantilla al SQL Editor de Supabase Dashboard.
-- Sustituir los cuatro NULL únicamente dentro del editor y nunca guardar la copia rellenada.
-- Ejemplo de sustitución conceptual: UUID_AUTH_ADMINISTRADOR, sin incluir valores reales aquí.

begin;

do $h2_profiles$
declare
  v_administrador_uuid uuid := null;
  v_mozo_uuid uuid := null;
  v_cocina_uuid uuid := null;
  v_caja_uuid uuid := null;
  v_local_id uuid;
  v_user_ids uuid[];
  v_role_count integer;
  v_auth_user_count integer;
  v_profile_count integer;
  v_distinct_role_count integer;
  v_distinct_local_count integer;
  v_all_profiles_active boolean;
begin
  if v_administrador_uuid is null
    or v_mozo_uuid is null
    or v_cocina_uuid is null
    or v_caja_uuid is null then
    raise exception
      'Plantilla bloqueada: sustituye los cuatro UUID Auth exclusivamente en una copia temporal dentro de Supabase SQL Editor.';
  end if;

  v_user_ids := array[
    v_administrador_uuid,
    v_mozo_uuid,
    v_cocina_uuid,
    v_caja_uuid
  ];

  if (
    select count(distinct auth_id)
    from unnest(v_user_ids) as requested_users(auth_id)
  ) <> 4 then
    raise exception 'Los cuatro usuarios Auth deben tener UUID diferentes.';
  end if;

  select local_demo.id
  into v_local_id
  from public.local as local_demo
  where local_demo.codigo = 'MIKUY-DEMO'
    and local_demo.activo = true;

  if v_local_id is null then
    raise exception 'No existe un local activo con el código MIKUY-DEMO.';
  end if;

  select count(*)
  into v_role_count
  from public.rol as available_role
  where available_role.codigo in ('ADMINISTRADOR', 'MOZO', 'COCINA', 'CAJA')
    and available_role.activo = true;

  if v_role_count <> 4 then
    raise exception 'Deben existir activos los cuatro roles ADMINISTRADOR, MOZO, COCINA y CAJA.';
  end if;

  select count(*)
  into v_auth_user_count
  from auth.users as auth_user
  where auth_user.id = any(v_user_ids);

  if v_auth_user_count <> 4 then
    raise exception 'Los cuatro UUID deben corresponder a cuentas existentes en Authentication → Users.';
  end if;

  insert into public.perfil_usuario (
    id,
    local_id,
    rol_id,
    nombre,
    activo
  )
  select
    requested_profile.user_id,
    v_local_id,
    available_role.id,
    requested_profile.display_name,
    true
  from (
    values
      (v_administrador_uuid, 'ADMINISTRADOR', 'Administrador de prueba'),
      (v_mozo_uuid, 'MOZO', 'Mozo de prueba'),
      (v_cocina_uuid, 'COCINA', 'Cocina de prueba'),
      (v_caja_uuid, 'CAJA', 'Caja de prueba')
  ) as requested_profile(user_id, role_code, display_name)
  inner join public.rol as available_role
    on available_role.codigo = requested_profile.role_code
   and available_role.activo = true
  on conflict (id) do update
  set local_id = excluded.local_id,
      rol_id = excluded.rol_id,
      nombre = excluded.nombre,
      activo = true;

  select
    count(*),
    count(distinct linked_profile.rol_id),
    count(distinct linked_profile.local_id),
    coalesce(bool_and(linked_profile.activo), false)
  into
    v_profile_count,
    v_distinct_role_count,
    v_distinct_local_count,
    v_all_profiles_active
  from public.perfil_usuario as linked_profile
  where linked_profile.id = any(v_user_ids)
    and linked_profile.local_id = v_local_id;

  if v_profile_count <> 4
    or v_distinct_role_count <> 4
    or v_distinct_local_count <> 1
    or not v_all_profiles_active then
    raise exception
      'La asociación no produjo cuatro perfiles activos, cuatro roles diferentes y un único local.';
  end if;

  raise notice
    'Verificación correcta: cuatro perfiles activos, cuatro roles diferentes y un único local MIKUY-DEMO.';
end
$h2_profiles$;

commit;
