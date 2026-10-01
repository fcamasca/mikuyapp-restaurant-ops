begin;

do $h3_t05_concurrency_setup$
declare
  v_waiter_id uuid := '00000000-0000-0000-0000-00000000f5c4';
  v_local_id uuid := '00000000-0000-0000-0000-00000000f5c5';
  v_category_id uuid := '00000000-0000-0000-0000-00000000f5c1';
  v_product_id uuid := '00000000-0000-0000-0000-00000000f5c2';
  v_table_id uuid := '00000000-0000-0000-0000-00000000f5c3';
begin
  delete from public.historial_estado where pedido_id = -95501;
  delete from public.detalle_pedido where pedido_id = -95501;
  delete from public.pedido where id = -95501;
  delete from public.mesa where id = v_table_id;
  delete from public.producto where id = v_product_id;
  delete from public.categoria where id = v_category_id;
  -- E9 (homologación mínima): la jornada es inmutable y no se borra; se cierra con la transición permitida ABIERTA -> CERRADA.
  update public.jornada_operativa set estado = 'CERRADA', cerrada_por = abierta_por, cerrada_en = greatest(now(), abierta_en)
  where local_id in (v_local_id) and estado = 'ABIERTA';
  delete from public.perfil_usuario where (id = v_waiter_id) and id not in (select abierta_por from public.jornada_operativa union all select cerrada_por from public.jornada_operativa where cerrada_por is not null); -- E9 (homologación mínima): el perfil que abre/cierra una jornada no se borra
  delete from auth.users where (id = v_waiter_id) and id not in (select id from public.perfil_usuario); -- E9 (homologación mínima): se conserva el usuario de un perfil conservado
  delete from public.local where (id = v_local_id) and id not in (select local_id from public.jornada_operativa); -- E9 (homologación mínima): el local con jornadas (inmutables) se conserva

  insert into auth.users (id, aud, role, email, encrypted_password)
  values (
    v_waiter_id,
    'authenticated',
    'authenticated',
    'h3-t05-concurrency@example.invalid',
    'test'
  )
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;

  insert into public.local (id, codigo, nombre)
  values (v_local_id, 'H3-T05-CONC', 'Local concurrencia H3 T05')
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;

  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_waiter_id, v_local_id, role_row.id, 'Mozo concurrencia H3 T05'
  from public.rol as role_row
  where role_row.codigo = 'MOZO'
  on conflict (id) do nothing /* E9 (homologación mínima): el fixture puede persistir por la jornada inmutable */;
  -- E9 (homologación mínima): precondición global de E9 — jornada operativa ABIERTA válida para los locales del fixture.
  insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
  select l.id, (now() at time zone 'America/Lima')::date,
    1 + coalesce((select max(j.numero) from public.jornada_operativa j where j.local_id = l.id and j.fecha_operativa = (now() at time zone 'America/Lima')::date), 0),
    (select p.id from public.perfil_usuario p where p.local_id = l.id order by p.id limit 1), now(), gen_random_uuid()
  from public.local l
  where l.id in (v_local_id)
    and exists (select 1 from public.perfil_usuario p where p.local_id = l.id)
    and not exists (select 1 from public.jornada_operativa j where j.local_id = l.id and j.estado = 'ABIERTA');

  insert into public.categoria (id, local_id, codigo, nombre)
  values (v_category_id, v_local_id, 'T05-CONC', 'Fixture concurrencia T05');

  insert into public.producto (
    id, local_id, categoria_id, codigo, nombre, precio
  )
  values (
    v_product_id, v_local_id, v_category_id,
    'T05-CONC', 'Producto concurrencia T05', 1.00
  );

  insert into public.mesa (id, local_id, codigo, nombre, estado)
  values (v_table_id, v_local_id, 'T05-CONC', 'Mesa concurrencia T05', 'OCUPADA');

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado)
  overriding system value
  values (-95501, v_local_id, v_table_id, v_waiter_id, 'ABIERTO');

  insert into public.historial_estado (
    pedido_id, estado_anterior, estado_nuevo, usuario_id
  )
  values (-95501, null, 'ABIERTO', v_waiter_id);

  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, estado
  ) overriding system value
  values (-95511, -95501, v_product_id, 1, 1.00, 'ABIERTO');
end;
$h3_t05_concurrency_setup$;

commit;
