begin;

do $dbstd_tp16_column_comments$
declare
  v_expected record;
  v_actual text;
begin
  for v_expected in
    select * from (values
      ('pedido', 'estado', 'Estado actual de la cabecera del pedido. Durante el flujo operativo se sincroniza a partir de los estados de sus detalles; un pedido ENTREGADO sin nuevos detalles conserva su estado. PAGADO y ANULADO son estados terminales.'),
      ('pedido', 'enviado_en', 'Instante del primer envío del pedido a cocina. Los envíos posteriores de nuevos detalles no reemplazan este valor.'),
      ('pedido', 'modificado_en', 'Comportamiento actual: se inicializa con creado_en y se actualiza al insertar o eliminar detalles, o al modificar cantidad, observacion, pedido_id o producto_id de un detalle. No cambia por una transición aislada de estado del detalle. Su semántica definitiva permanece pendiente de decisión.'),
      ('pedido', 'modificado_por', 'Comportamiento actual: se inicializa con creado_por y se actualiza con el actor que inserta o elimina detalles, o modifica cantidad, observacion, pedido_id o producto_id de un detalle. No cambia por una transición aislada de estado del detalle. Su semántica definitiva permanece pendiente de decisión.'),
      ('detalle_pedido', 'estado', 'Estado operativo individual del detalle. El conjunto de estados de los detalles se utiliza para derivar los estados operativos del pedido y de la mesa.'),
      ('detalle_pedido', 'precio_unitario', 'Snapshot del precio unitario aplicado al crear el detalle; no depende de cambios posteriores en producto.precio.'),
      ('detalle_pedido', 'enviado_en', 'Instante del primer envío individual del detalle a cocina. Solo puede establecerse en la transición ABIERTO a ENVIADO y, una vez fijado, es inmutable.'),
      ('pago', 'importe', 'Snapshot del importe registrado al cobrar el pedido; constituye el valor persistido utilizado por los reportes de ventas.')
    ) as expected_comment(table_name, column_name, comment_text)
  loop
    select pg_catalog.col_description(attribute_metadata.attrelid, attribute_metadata.attnum)
    into strict v_actual
    from pg_catalog.pg_attribute as attribute_metadata
    inner join pg_catalog.pg_class as table_metadata
      on table_metadata.oid = attribute_metadata.attrelid
    inner join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = table_metadata.relnamespace
    where table_schema.nspname = 'public'
      and table_metadata.relname = v_expected.table_name
      and attribute_metadata.attname = v_expected.column_name
      and not attribute_metadata.attisdropped;

    if v_actual is distinct from v_expected.comment_text then
      raise exception 'DBSTD-TP16 comentario inesperado: public.%.%',
        v_expected.table_name,
        v_expected.column_name;
    end if;
  end loop;
end;
$dbstd_tp16_column_comments$;

do $dbstd_tp16_function_comments$
declare
  v_expected record;
  v_actual text;
begin
  for v_expected in
    select * from (values
      ('obtener_contexto_autenticado', '', 'Devuelve el local y rol del usuario autenticado únicamente cuando perfil, rol y local están activos y el rol pertenece al conjunto autorizado; en otro caso no devuelve filas.'),
      ('sincronizar_estado_operativo_pedido', 'p_pedido_id bigint, p_usuario_id uuid', 'Deriva y sincroniza los estados operativos del pedido y de su mesa a partir de los estados de sus detalles, y registra en historial_estado los cambios de estado de la cabecera.'),
      ('registrar_auditoria_detalle_pedido', '', 'Mantiene la auditoría de detalle_pedido, protege sus campos de creación, valida la asignación e inmutabilidad de enviado_en y propaga a pedido únicamente las modificaciones de contenido definidas por el comportamiento actual.'),
      ('exportar_productos_local', '', 'Devuelve al ADMINISTRADOR los productos de su local autenticado, incluidos activos e inactivos, ordenados por categoría y producto; rechaza contextos inexistentes o inválidos.'),
      ('exportar_ventas_hoy', '', 'Devuelve al ADMINISTRADOR las ventas PAGADO de su local correspondientes al día en America/Lima, ordenadas por fecha de pago; rechaza contextos inexistentes o inválidos.'),
      ('obtener_resumen_ventas_hoy', '', 'Agrupa por medio de pago las ventas PAGADO del día en America/Lima para ADMINISTRADOR y CAJA de su local autenticado; rechaza contextos inexistentes o inválidos.'),
      ('obtener_creadores_pedidos_vigentes', 'p_pedido_ids bigint[]', 'Devuelve al MOZO los nombres de los creadores de los pedidos solicitados que permanecen vigentes y pertenecen a su local autenticado.')
    ) as expected_comment(function_name, identity_arguments, comment_text)
  loop
    select pg_catalog.obj_description(function_metadata.oid, 'pg_proc')
    into strict v_actual
    from pg_catalog.pg_proc as function_metadata
    inner join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function_metadata.pronamespace
    where function_schema.nspname = 'public'
      and function_metadata.proname = v_expected.function_name
      and pg_catalog.pg_get_function_identity_arguments(function_metadata.oid)
        = v_expected.identity_arguments;

    if v_actual is distinct from v_expected.comment_text then
      raise exception 'DBSTD-TP16 comentario inesperado: public.%(%)',
        v_expected.function_name,
        v_expected.identity_arguments;
    end if;
  end loop;
end;
$dbstd_tp16_function_comments$;

do $dbstd_tp16_trigger_comment$
declare
  v_actual text;
  v_expected constant text := 'Trigger BEFORE INSERT, UPDATE o DELETE que ejecuta registrar_auditoria_detalle_pedido() para mantener auditoría, validar enviado_en y propagar al pedido las modificaciones de contenido definidas por el comportamiento actual.';
begin
  select pg_catalog.obj_description(trigger_metadata.oid, 'pg_trigger')
  into strict v_actual
  from pg_catalog.pg_trigger as trigger_metadata
  inner join pg_catalog.pg_class as table_metadata
    on table_metadata.oid = trigger_metadata.tgrelid
  inner join pg_catalog.pg_namespace as table_schema
    on table_schema.oid = table_metadata.relnamespace
  where table_schema.nspname = 'public'
    and table_metadata.relname = 'detalle_pedido'
    and trigger_metadata.tgname = 'detalle_pedido_registrar_auditoria'
    and not trigger_metadata.tgisinternal;

  if v_actual is distinct from v_expected then
    raise exception 'DBSTD-TP16 comentario inesperado: detalle_pedido_registrar_auditoria';
  end if;
end;
$dbstd_tp16_trigger_comment$;

do $dbstd_tp17_rls_unchanged$
declare
  v_policy_count integer;
  v_policy_fingerprint text;
  v_rls_fingerprint text;
begin
  select
    pg_catalog.count(*)::integer,
    pg_catalog.md5(pg_catalog.string_agg(
      pg_catalog.concat_ws(
        '|',
        table_schema.nspname,
        table_metadata.relname,
        policy_metadata.polname,
        policy_metadata.polcmd,
        policy_metadata.polpermissive::text,
        policy_metadata.polroles::text,
        coalesce(pg_catalog.pg_get_expr(policy_metadata.polqual, policy_metadata.polrelid), ''),
        coalesce(pg_catalog.pg_get_expr(policy_metadata.polwithcheck, policy_metadata.polrelid), '')
      ),
      E'\n' order by table_metadata.relname, policy_metadata.polname
    ))
  into v_policy_count, v_policy_fingerprint
  from pg_catalog.pg_policy as policy_metadata
  inner join pg_catalog.pg_class as table_metadata
    on table_metadata.oid = policy_metadata.polrelid
  inner join pg_catalog.pg_namespace as table_schema
    on table_schema.oid = table_metadata.relnamespace
  where table_schema.nspname = 'public';

  select pg_catalog.md5(pg_catalog.string_agg(
    pg_catalog.concat_ws(
      '|',
      table_metadata.relname,
      table_metadata.relrowsecurity::text,
      table_metadata.relforcerowsecurity::text
    ),
    E'\n' order by table_metadata.relname
  ))
  into v_rls_fingerprint
  from pg_catalog.pg_class as table_metadata
  inner join pg_catalog.pg_namespace as table_schema
    on table_schema.oid = table_metadata.relnamespace
  where table_schema.nspname = 'public'
    and table_metadata.relkind = 'r';

  if v_policy_count <> 27
    or v_policy_fingerprint is distinct from 'd62980780a83fa9b9f456c5893d71712'
    or v_rls_fingerprint is distinct from 'd45e5fcf46a9a8e08185aee32a4a1c74' then
    raise exception 'DBSTD-TP17 policies o RLS cambiaron: %, %, %',
      v_policy_count,
      v_policy_fingerprint,
      v_rls_fingerprint;
  end if;
end;
$dbstd_tp17_rls_unchanged$;

select 'DBSTD-TP16..TP17 OK' as resultado;

rollback;
