begin;

create or replace function public.h2_auth_context()
returns table (
  local_id uuid,
  rol_id smallint,
  rol_codigo text
)
language sql
stable
security definer
set search_path = pg_catalog
as $h2_auth_context$
  select
    user_profile.local_id as local_id,
    user_profile.rol_id as rol_id,
    user_role.codigo as rol_codigo
  from public.perfil_usuario as user_profile
  inner join public.rol as user_role
    on user_role.id = user_profile.rol_id
  inner join public.local as user_local
    on user_local.id = user_profile.local_id
  where user_profile.id = auth.uid()
    and user_profile.activo = true
    and user_role.activo = true
    and user_role.codigo in ('ADMINISTRADOR', 'MOZO', 'COCINA', 'CAJA')
    and user_local.activo = true;
$h2_auth_context$;

alter function public.h2_auth_context() owner to postgres;

revoke all on function public.h2_auth_context() from public;
revoke all on function public.h2_auth_context() from anon;
grant execute on function public.h2_auth_context() to authenticated;

commit;
