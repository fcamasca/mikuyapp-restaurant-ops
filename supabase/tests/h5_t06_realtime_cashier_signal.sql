begin;

do $h5_t06_metadata$
declare
  v_tables text[];
  v_policy text;
begin
  select pg_catalog.array_agg(
    publication_table.schemaname || '.' || publication_table.tablename
    order by publication_table.schemaname, publication_table.tablename
  ) into v_tables
  from pg_catalog.pg_publication_tables publication_table
  where publication_table.pubname = 'supabase_realtime';

  -- Contrato actualizado: E10 publica solicitud_cuenta (E10-D07) y E9 publica jornada_operativa (E9-D12).
  if v_tables is distinct from array[
    'public.detalle_pedido', 'public.jornada_operativa', 'public.mesa', 'public.pedido', 'public.solicitud_cuenta'
  ] or 'public.pago' = any(coalesce(v_tables, array[]::text[])) then
    raise exception 'H5-T06 publicación Realtime inesperada: %', v_tables;
  end if;

  select policy_row.qual into strict v_policy
  from pg_catalog.pg_policies policy_row
  where policy_row.schemaname = 'public'
    and policy_row.tablename = 'pedido'
    and policy_row.policyname = 'pedido_select_caja_local_cobro'
    and policy_row.cmd = 'SELECT'
    and policy_row.roles = array['authenticated']::name[];

  if v_policy !~ '''ENTREGADO'''
    or v_policy !~ '''PAGADO'''
    or v_policy !~ '''CAJA'''
    or v_policy !~ 'local_id' then
    raise exception 'H5-T06 política de señal de caja inesperada: %', v_policy;
  end if;

  if not pg_catalog.has_table_privilege('authenticated', 'public.pedido', 'SELECT') then
    raise exception 'H5-T06 authenticated no puede recibir señales SELECT de pedido';
  end if;
end;
$h5_t06_metadata$;

create function pg_temp.h5_t06_set_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$$;

do $h5_t06_fixtures$
declare
  v_cashier_a uuid := '00000000-0000-0000-0000-00000000f601';
  v_cashier_b uuid := '00000000-0000-0000-0000-00000000f602';
  v_local_a uuid := '00000000-0000-0000-0000-00000000f603';
  v_local_b uuid := '00000000-0000-0000-0000-00000000f604';
begin
  insert into auth.users(id,aud,role,email,encrypted_password) values
    (v_cashier_a,'authenticated','authenticated','h5-t06-a@example.invalid','test'),
    (v_cashier_b,'authenticated','authenticated','h5-t06-b@example.invalid','test');
  insert into public.local(id,codigo,nombre) values
    (v_local_a,'H5-T06-A','Local H5 T06 A'),
    (v_local_b,'H5-T06-B','Local H5 T06 B');
  insert into public.perfil_usuario(id,local_id,rol_id,nombre)
  select v_cashier_a,v_local_a,id,'Caja A' from public.rol where codigo='CAJA'
  union all
  select v_cashier_b,v_local_b,id,'Caja B' from public.rol where codigo='CAJA';
  -- E9 (homologación mínima): precondición global de E9 — jornada operativa ABIERTA válida para los locales del fixture.
  insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
  select l.id, (now() at time zone 'America/Lima')::date,
    1 + coalesce((select max(j.numero) from public.jornada_operativa j where j.local_id = l.id and j.fecha_operativa = (now() at time zone 'America/Lima')::date), 0),
    (select p.id from public.perfil_usuario p where p.local_id = l.id order by p.id limit 1), now(), gen_random_uuid()
  from public.local l
  where l.id in (v_local_a, v_local_b)
    and exists (select 1 from public.perfil_usuario p where p.local_id = l.id)
    and not exists (select 1 from public.jornada_operativa j where j.local_id = l.id and j.estado = 'ABIERTA');
  insert into public.mesa(id,local_id,codigo,nombre,estado) values
    ('00000000-0000-0000-0000-00000000f611',v_local_a,'F611','Entregada','PENDIENTE_PAGO'),
    ('00000000-0000-0000-0000-00000000f612',v_local_a,'F612','Pagada','LIBRE'),
    ('00000000-0000-0000-0000-00000000f613',v_local_a,'F613','Lista','PEDIDO_LISTO'),
    ('00000000-0000-0000-0000-00000000f614',v_local_b,'F614','Otro local','PENDIENTE_PAGO');
  insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values
    (-50601,v_local_a,'00000000-0000-0000-0000-00000000f611',v_cashier_a,'ENTREGADO'),
    (-50602,v_local_a,'00000000-0000-0000-0000-00000000f612',v_cashier_a,'PAGADO'),
    (-50603,v_local_a,'00000000-0000-0000-0000-00000000f613',v_cashier_a,'LISTO'),
    (-50604,v_local_b,'00000000-0000-0000-0000-00000000f614',v_cashier_b,'ENTREGADO');
end;
$h5_t06_fixtures$;

set local role authenticated;

do $h5_t06_rls$
begin
  perform pg_temp.h5_t06_set_user('00000000-0000-0000-0000-00000000f601');
  if (select pg_catalog.array_agg(id order by id) from public.pedido where id between -50604 and -50601)
      is distinct from array[-50602::bigint,-50601::bigint] then
    raise exception 'H5-T06 CAJA A no quedó limitada a ENTREGADO/PAGADO de su local';
  end if;

  perform pg_temp.h5_t06_set_user('00000000-0000-0000-0000-00000000f602');
  if (select pg_catalog.array_agg(id order by id) from public.pedido where id between -50604 and -50601)
      is distinct from array[-50604::bigint] then
    raise exception 'H5-T06 CAJA B no quedó aislada en su local';
  end if;
end;
$h5_t06_rls$;

reset role;

rollback;
