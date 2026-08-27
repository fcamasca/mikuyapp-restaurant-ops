begin;

do $h3_t05_concurrency_setup$
declare
  v_waiter_id uuid;
  v_local_id uuid;
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

  select user_profile.id, user_profile.local_id
  into strict v_waiter_id, v_local_id
  from public.perfil_usuario as user_profile
  inner join public.rol as role_row on role_row.id = user_profile.rol_id
  where role_row.codigo = 'MOZO'
    and user_profile.activo = true
    and role_row.activo = true
  order by user_profile.creado_en
  limit 1;

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
