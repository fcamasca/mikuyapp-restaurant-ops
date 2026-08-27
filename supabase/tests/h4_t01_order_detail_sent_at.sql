begin;

set local enable_seqscan = off;

create function pg_temp.h4_t01_set_user(p_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog
as $h4_t01_set_user$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end;
$h4_t01_set_user$;

do $h4_t01_metadata$
declare
  v_type text;
  v_not_null boolean;
  v_default text;
  v_constraint text;
  v_index text;
  v_function text;
  v_plan json;
begin
  select
    pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod),
    attribute_row.attnotnull,
    pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid)
  into strict v_type, v_not_null, v_default
  from pg_catalog.pg_attribute as attribute_row
  left join pg_catalog.pg_attrdef as default_row
    on default_row.adrelid = attribute_row.attrelid
    and default_row.adnum = attribute_row.attnum
  where attribute_row.attrelid = 'public.detalle_pedido'::pg_catalog.regclass
    and attribute_row.attname = 'enviado_en'
    and attribute_row.attnum > 0
    and not attribute_row.attisdropped;

  if v_type <> 'timestamp with time zone' or v_not_null or v_default is not null then
    raise exception 'H4-T01 columna enviado_en inesperada: %/%/%', v_type, v_not_null, v_default;
  end if;

  select pg_catalog.pg_get_constraintdef(constraint_row.oid, true)
  into strict v_constraint
  from pg_catalog.pg_constraint as constraint_row
  where constraint_row.conrelid = 'public.detalle_pedido'::pg_catalog.regclass
    and constraint_row.conname = 'ck_detalle_pedido_envio_coherente'
    and constraint_row.contype = 'c'
    and constraint_row.convalidated;

  if v_constraint !~ 'ABIERTO'
    or v_constraint !~ 'ENVIADO'
    or v_constraint !~ 'RECIBIDO_COCINA'
    or v_constraint !~ 'EN_PREPARACION'
    or v_constraint !~ 'LISTO'
    or v_constraint !~ 'enviado_en IS NULL'
    or v_constraint !~ 'enviado_en IS NOT NULL' then
    raise exception 'H4-T01 constraint inesperado: %', v_constraint;
  end if;

  select pg_catalog.pg_get_indexdef(index_row.indexrelid)
  into strict v_index
  from pg_catalog.pg_index as index_row
  where index_row.indexrelid =
    'public.idx_detalle_pedido_cocina_enviado_en'::pg_catalog.regclass
    and index_row.indisvalid
    and index_row.indisready;

  if v_index !~ '\(enviado_en, pedido_id\)'
    or v_index !~ 'ENVIADO'
    or v_index !~ 'RECIBIDO_COCINA'
    or v_index !~ 'EN_PREPARACION'
    or v_index !~ 'LISTO' then
    raise exception 'H4-T01 índice inesperado: %', v_index;
  end if;

  execute $explain$
    explain (format json)
    select detail_row.id
    from public.detalle_pedido as detail_row
    where detail_row.estado in (
      'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO'
    )
    order by detail_row.enviado_en, detail_row.pedido_id
  $explain$
  into v_plan;

  if v_plan::text !~ 'idx_detalle_pedido_cocina_enviado_en' then
    raise exception 'H4-T01 la consulta prevista no utiliza el índice de cola: %', v_plan;
  end if;

  select pg_catalog.pg_get_functiondef(function_row.oid)
  into strict v_function
  from pg_catalog.pg_proc as function_row
  inner join pg_catalog.pg_namespace as function_schema
    on function_schema.oid = function_row.pronamespace
  where function_schema.nspname = 'public'
    and function_row.proname = 'enviar_pedido_cocina'
    and function_row.proargtypes = '20'::pg_catalog.oidvector;

  if v_function !~* 'clock_timestamp'
    or v_function !~* 'enviado_en = v_envio_detalles'
    or v_function !~* 'detail_row.estado = ''ABIERTO''' then
    raise exception 'H4-T01 función de envío no fija timestamp individual en servidor';
  end if;

  if pg_catalog.has_column_privilege(
    'authenticated', 'public.detalle_pedido', 'enviado_en', 'UPDATE'
  ) then
    raise exception 'H4-T01 authenticated puede actualizar enviado_en directamente';
  end if;

  if exists (
    select 1
    from public.detalle_pedido
    where (estado = 'ABIERTO' and enviado_en is not null)
      or (estado <> 'ABIERTO' and enviado_en is null)
  ) then
    raise exception 'H4-T01 quedaron datos históricos incompatibles';
  end if;
end;
$h4_t01_metadata$;

do $h4_t01_behaviour$
declare
  v_waiter_id uuid := '00000000-0000-0000-0000-00000000d401';
  v_local_id uuid := '00000000-0000-0000-0000-00000000d402';
  v_table_id uuid := '00000000-0000-0000-0000-00000000d403';
  v_category_id uuid := '00000000-0000-0000-0000-00000000d404';
  v_product_id uuid := '00000000-0000-0000-0000-00000000d405';
  v_order_id bigint := -40101;
  v_first_sent_at timestamptz;
  v_second_sent_at timestamptz;
  v_order_modified_at timestamptz;
begin
  insert into auth.users (id, aud, role, email, encrypted_password)
  values (v_waiter_id, 'authenticated', 'authenticated', 'h4-t01-waiter@example.invalid', 'test');

  insert into public.local (id, codigo, nombre)
  values (v_local_id, 'H4-T01', 'Local H4 T01');

  insert into public.perfil_usuario (id, local_id, rol_id, nombre)
  select v_waiter_id, v_local_id, role_row.id, 'Mozo H4 T01'
  from public.rol as role_row
  where role_row.codigo = 'MOZO';

  insert into public.mesa (id, local_id, codigo, nombre, estado)
  values (v_table_id, v_local_id, 'H4-T01', 'Mesa H4 T01', 'OCUPADA');

  insert into public.categoria (id, local_id, codigo, nombre)
  values (v_category_id, v_local_id, 'H4-T01', 'Categoría H4 T01');

  insert into public.producto (
    id, local_id, categoria_id, codigo, nombre, precio
  ) values (
    v_product_id, v_local_id, v_category_id, 'H4-T01', 'Producto H4 T01', 15.00
  );

  insert into public.pedido (id, local_id, mesa_id, creado_por, estado)
  overriding system value
  values (v_order_id, v_local_id, v_table_id, v_waiter_id, 'ABIERTO');

  perform pg_temp.h4_t01_set_user(v_waiter_id);

  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, estado
  ) overriding system value
  values
    (-40111, v_order_id, v_product_id, 1, 15.00, 'ABIERTO'),
    (-40112, v_order_id, v_product_id, 2, 15.00, 'ABIERTO');

  if exists (
    select 1 from public.detalle_pedido
    where pedido_id = v_order_id and enviado_en is not null
  ) then
    raise exception 'H4-T01 un detalle ABIERTO nació con timestamp';
  end if;

  select modificado_en into strict v_order_modified_at
  from public.pedido where id = v_order_id;

  perform public.enviar_pedido_cocina(v_order_id);

  select enviado_en into strict v_first_sent_at
  from public.detalle_pedido where id = -40111;

  if v_first_sent_at is null
    or (select enviado_en from public.detalle_pedido where id = -40112)
       is distinct from v_first_sent_at
    or (select enviado_en from public.pedido where id = v_order_id)
       is distinct from v_first_sent_at
    or (select modificado_en from public.pedido where id = v_order_id)
       is distinct from v_order_modified_at
    or exists (
      select 1 from public.detalle_pedido
      where pedido_id = v_order_id
        and (estado <> 'ENVIADO' or enviado_en is null)
    ) then
    raise exception 'H4-T01 primer envío o auditoría inconsistentes';
  end if;

  perform pg_catalog.pg_sleep(0.01);

  insert into public.detalle_pedido (
    id, pedido_id, producto_id, cantidad, precio_unitario, estado
  ) overriding system value
  values (-40113, v_order_id, v_product_id, 1, 15.00, 'ABIERTO');

  perform public.enviar_pedido_cocina(v_order_id);

  select enviado_en into strict v_second_sent_at
  from public.detalle_pedido where id = -40113;

  if v_second_sent_at is null or v_second_sent_at <= v_first_sent_at
    or (select enviado_en from public.detalle_pedido where id = -40111)
       is distinct from v_first_sent_at then
    raise exception 'H4-T01 agregado posterior no recibió timestamp individual posterior';
  end if;

  perform public.enviar_pedido_cocina(v_order_id);

  if (select enviado_en from public.detalle_pedido where id = -40113)
       is distinct from v_second_sent_at then
    raise exception 'H4-T01 reenvío sobrescribió timestamp';
  end if;

  update public.detalle_pedido
  set estado = 'RECIBIDO_COCINA'
  where id = -40111;

  if (select enviado_en from public.detalle_pedido where id = -40111)
       is distinct from v_first_sent_at then
    raise exception 'H4-T01 transición posterior sobrescribió timestamp';
  end if;

  begin
    update public.detalle_pedido
    set enviado_en = v_first_sent_at + interval '1 second'
    where id = -40111;
    raise exception 'H4-T01 permitió alterar timestamp establecido';
  exception when sqlstate '22000' then
    null;
  end;

  begin
    insert into public.detalle_pedido (
      id, pedido_id, producto_id, cantidad, precio_unitario, estado, enviado_en
    ) overriding system value
    values (-40114, v_order_id, v_product_id, 1, 15.00, 'ABIERTO', pg_catalog.now());
    raise exception 'H4-T01 permitió ABIERTO con timestamp';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.detalle_pedido (
      id, pedido_id, producto_id, cantidad, precio_unitario, estado
    ) overriding system value
    values (-40115, v_order_id, v_product_id, 1, 15.00, 'ENVIADO');
    raise exception 'H4-T01 permitió ENVIADO sin timestamp';
  exception when check_violation then
    null;
  end;
end;
$h4_t01_behaviour$;

rollback;
