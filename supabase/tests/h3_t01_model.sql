begin;

do $h3_t01_metadata$
declare
  actual_default text;
  actual_definition text;
  actual_predicate text;
  actual_type text;
  is_not_null boolean;
begin
  select
    pg_catalog.format_type(attribute_metadata.atttypid, attribute_metadata.atttypmod),
    attribute_metadata.attnotnull,
    pg_catalog.pg_get_expr(default_metadata.adbin, default_metadata.adrelid)
  into strict actual_type, is_not_null, actual_default
  from pg_catalog.pg_attribute as attribute_metadata
  inner join pg_catalog.pg_class as table_metadata
    on table_metadata.oid = attribute_metadata.attrelid
  inner join pg_catalog.pg_namespace as table_schema
    on table_schema.oid = table_metadata.relnamespace
  left join pg_catalog.pg_attrdef as default_metadata
    on default_metadata.adrelid = attribute_metadata.attrelid
    and default_metadata.adnum = attribute_metadata.attnum
  where table_schema.nspname = 'public'
    and table_metadata.relname = 'detalle_pedido'
    and attribute_metadata.attname = 'estado'
    and attribute_metadata.attnum > 0
    and not attribute_metadata.attisdropped;

  if actual_type <> 'text'
    or not is_not_null
    or actual_default <> '''ABIERTO''::text' then
    raise exception 'H3-T01 columna estado inesperada: tipo %, not null %, default %',
      actual_type, is_not_null, actual_default;
  end if;

  select pg_catalog.pg_get_constraintdef(constraint_metadata.oid, true)
  into strict actual_definition
  from pg_catalog.pg_constraint as constraint_metadata
  where constraint_metadata.conrelid = 'public.detalle_pedido'::pg_catalog.regclass
    and constraint_metadata.conname = 'ck_detalle_pedido_estado_valido'
    and constraint_metadata.contype = 'c';

  if actual_definition !~ 'ABIERTO'
    or actual_definition !~ 'ENVIADO'
    or actual_definition !~ 'RECIBIDO_COCINA'
    or actual_definition !~ 'EN_PREPARACION'
    or actual_definition !~ 'LISTO'
    or actual_definition ~ 'ANULADO'
    or actual_definition ~ 'PENDIENTE' then
    raise exception 'H3-T01 check de detalle inesperado: %', actual_definition;
  end if;

  select pg_catalog.pg_get_indexdef(index_metadata.indexrelid)
  into strict actual_definition
  from pg_catalog.pg_index as index_metadata
  where index_metadata.indexrelid =
    'public.idx_detalle_pedido_pedido_id_estado'::pg_catalog.regclass;

  if actual_definition !~ '\(pedido_id, estado\)'
    or actual_definition ~ 'UNIQUE' then
    raise exception 'H3-T01 índice de detalle inesperado: %', actual_definition;
  end if;

  select
    pg_catalog.pg_get_indexdef(index_metadata.indexrelid),
    pg_catalog.pg_get_expr(index_metadata.indpred, index_metadata.indrelid)
  into strict actual_definition, actual_predicate
  from pg_catalog.pg_index as index_metadata
  where index_metadata.indexrelid =
    'public.uq_pedido_mesa_id_vigente'::pg_catalog.regclass
    and index_metadata.indisunique;

  if actual_definition !~ 'UNIQUE INDEX'
    or actual_definition !~ '\(mesa_id\)'
    or actual_predicate !~ 'ABIERTO'
    or actual_predicate !~ 'ENVIADO'
    or actual_predicate !~ 'RECIBIDO_COCINA'
    or actual_predicate !~ 'EN_PREPARACION'
    or actual_predicate !~ 'LISTO'
    or actual_predicate !~ 'ENTREGADO'
    or actual_predicate ~ 'PAGADO'
    or actual_predicate ~ 'ANULADO'
    or actual_predicate ~ 'PENDIENTE' then
    raise exception 'H3-T01 índice parcial inesperado: % / %',
      actual_definition, actual_predicate;
  end if;
end;
$h3_t01_metadata$;

do $h3_t01_behaviour$
declare
  actual_constraint text;
  actual_state text;
  test_local_id uuid := '00000000-0000-0000-0000-00000000b301';
  test_table_id uuid := '00000000-0000-0000-0000-00000000b302';
  test_user_id uuid := '00000000-0000-0000-0000-00000000b303';
  test_product_id uuid := '00000000-0000-0000-0000-00000000b304';
  test_category_id uuid := '00000000-0000-0000-0000-00000000b305';
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values (test_user_id, 'authenticated', 'authenticated', 'h3-t01@example.invalid', 'test');

  insert into public.local (id, codigo, nombre)
  values (test_local_id, 'H3-T01', 'Local H3 T01');

  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select test_user_id, test_local_id, rol_metadata.id, 'Mozo H3 T01'
  from public.rol as rol_metadata
  where rol_metadata.codigo = 'MOZO';

  insert into public.mesa (id, local_id, codigo, nombre)
  values (test_table_id, test_local_id, 'H3-M01', 'Mesa H3 T01');

  insert into public.categoria (id, local_id, codigo, nombre)
  values (test_category_id, test_local_id, 'H3-C01', 'Categoría H3 T01');

  insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio)
  values (test_product_id, test_local_id, test_category_id, 'H3-P01', 'Producto H3 T01', 10.00);

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado)
  overriding system value
  values (-93001, test_local_id, test_table_id, test_user_id, 'ABIERTO');

  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario
  ) overriding system value
  values (-93001, -93001, test_product_id, 1, 10.00);

  if (select estado from public.detalle_pedido where id = -93001) <> 'ABIERTO' then
    raise exception 'H3-T01 el default ABIERTO no se aplicó';
  end if;

  begin
    update public.detalle_pedido set estado = 'ANULADO' where id = -93001;
    raise exception using errcode = 'P0001', message = 'H3-T01 aceptó ANULADO en detalle';
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate,
      actual_constraint = constraint_name;
    if actual_state <> '23514'
      or actual_constraint <> 'ck_detalle_pedido_estado_valido' then
      raise exception 'H3-T01 estado inválido: se esperaba 23514/check, se obtuvo %/%',
        actual_state, actual_constraint;
    end if;
  end;

  begin
    insert into public.pedido (id, local_id, mesa_id, creado_por, estado)
    overriding system value
    values (-93002, test_local_id, test_table_id, test_user_id, 'ENTREGADO');
    raise exception using errcode = 'P0001', message = 'H3-T01 aceptó dos pedidos vigentes';
  exception when unique_violation then
    get stacked diagnostics actual_constraint = constraint_name;
    if actual_constraint <> 'uq_pedido_mesa_id_vigente' then
      raise exception 'H3-T01 unicidad falló por índice inesperado: %', actual_constraint;
    end if;
  end;

  update public.pedido set estado = 'PAGADO' where id = -93001;

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado)
  overriding system value
  values (-93003, test_local_id, test_table_id, test_user_id, 'ABIERTO');

  update public.pedido set estado = 'ANULADO' where id = -93003;

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado)
  overriding system value
  values (-93004, test_local_id, test_table_id, test_user_id, 'ABIERTO');
end;
$h3_t01_behaviour$;

rollback;
