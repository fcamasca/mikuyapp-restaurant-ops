begin;

create function pg_temp.h5_t04_set_user(p_user_id uuid)
returns void language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

do $metadata$
declare v_definition text;
begin
  select pg_catalog.pg_get_functiondef(p.oid) into strict v_definition
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'registrar_pago_pedido'
    and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_pedido_id bigint, p_medio text'
    and p.prosecdef and p.proowner = (select oid from pg_catalog.pg_roles where rolname = 'postgres')
    and p.proconfig = array['search_path=pg_catalog'];

  if v_definition !~* 'auth\.uid' or v_definition !~* 'obtener_contexto_autenticado'
    or v_definition !~* '''CAJA''' or v_definition !~* 'for update'
    or v_definition !~* 'sum\(detail_row\.cantidad \* detail_row\.precio_unitario\)'
    or v_definition !~* 'insert into public\.pago'
    or v_definition !~* '''ENTREGADO'', ''PAGADO'''
    or pg_catalog.has_function_privilege('anon', 'public.registrar_pago_pedido(bigint,text)', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.registrar_pago_pedido(bigint,text)', 'EXECUTE')
    or not exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.pago'::regclass and conname = 'uq_pago_pedido_id' and contype = 'u') then
    raise exception 'H5-T04 contrato, seguridad o unicidad inesperados';
  end if;
end $metadata$;

do $behaviour$
declare
  v_cashier uuid := '00000000-0000-0000-0000-00000000e401';
  v_other_cashier uuid := '00000000-0000-0000-0000-00000000e402';
  v_waiter uuid := '00000000-0000-0000-0000-00000000e403';
  v_kitchen uuid := '00000000-0000-0000-0000-00000000e404';
  v_admin uuid := '00000000-0000-0000-0000-00000000e405';
  v_local uuid := '00000000-0000-0000-0000-00000000e406';
  v_other_local uuid := '00000000-0000-0000-0000-00000000e407';
  v_category uuid := '00000000-0000-0000-0000-00000000e408';
  v_product uuid := '00000000-0000-0000-0000-00000000e409';
  v_medium text;
  v_order bigint;
begin
  insert into auth.users (id,aud,role,email,encrypted_password) values
    (v_cashier,'authenticated','authenticated','h5t04-c@example.invalid','test'),
    (v_other_cashier,'authenticated','authenticated','h5t04-c2@example.invalid','test'),
    (v_waiter,'authenticated','authenticated','h5t04-w@example.invalid','test'),
    (v_kitchen,'authenticated','authenticated','h5t04-k@example.invalid','test'),
    (v_admin,'authenticated','authenticated','h5t04-a@example.invalid','test');
  insert into public.local(id,codigo,nombre) values (v_local,'H5-T04-A','H5 T04 A'),(v_other_local,'H5-T04-B','H5 T04 B');
  insert into public.perfil_usuario(id,local_id,rol_id,nombre)
  select v_cashier,v_local,id,'Caja' from public.rol where codigo='CAJA' union all
  select v_other_cashier,v_other_local,id,'Caja B' from public.rol where codigo='CAJA' union all
  select v_waiter,v_local,id,'Mozo' from public.rol where codigo='MOZO' union all
  select v_kitchen,v_local,id,'Cocina' from public.rol where codigo='COCINA' union all
  select v_admin,v_local,id,'Admin' from public.rol where codigo='ADMINISTRADOR';
  insert into public.categoria(id,local_id,codigo,nombre) values(v_category,v_local,'H5-T04','Categoría');
  insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values(v_product,v_local,v_category,'H5-T04','Producto',999);

  for v_order, v_medium in select * from (values (-50401::bigint,'EFECTIVO'),(-50402,'YAPE'),(-50403,'PLIN'),(-50404,'TARJETA')) x(id,medio) loop
    insert into public.mesa(id,local_id,codigo,nombre,estado) values(('00000000-0000-0000-0000-' || lpad(abs(v_order)::text,12,'0'))::uuid,v_local,'T'||abs(v_order),'Mesa','PENDIENTE_PAGO');
    insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values(v_order,v_local,('00000000-0000-0000-0000-' || lpad(abs(v_order)::text,12,'0'))::uuid,v_waiter,'ENTREGADO');
    insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en) overriding system value values(v_order,v_order,v_product,3,12.50,'LISTO',now());
    perform pg_temp.h5_t04_set_user(v_cashier);
    perform public.registrar_pago_pedido(v_order,v_medium);
    if (select count(*) from public.pago where pedido_id=v_order and importe=37.50 and medio=v_medium and usuario_id=v_cashier) <> 1
      or (select estado from public.pedido where id=v_order) <> 'PAGADO'
      or (select estado from public.mesa where id=('00000000-0000-0000-0000-' || lpad(abs(v_order)::text,12,'0'))::uuid) <> 'LIBRE'
      or (select estado from public.detalle_pedido where id=v_order) <> 'LISTO'
      or (select count(*) from public.historial_estado where pedido_id=v_order and estado_anterior='ENTREGADO' and estado_nuevo='PAGADO' and usuario_id=v_cashier) <> 1 then
      raise exception 'H5-T04 cobro % incorrecto', v_medium;
    end if;
  end loop;

  begin perform public.registrar_pago_pedido(-50401,'EFECTIVO'); raise exception 'doble cobro permitido'; exception when sqlstate '40001' then null; end;
  begin perform public.registrar_pago_pedido(-50402,'BITCOIN'); raise exception 'medio inválido permitido'; exception when sqlstate '22023' then null; end;
  perform pg_temp.h5_t04_set_user(v_other_cashier);
  begin perform public.registrar_pago_pedido(-50401,'EFECTIVO'); raise exception 'otro local permitido'; exception when sqlstate '42501' then null; end;
  perform pg_temp.h5_t04_set_user(v_waiter);
  begin perform public.registrar_pago_pedido(-50401,'EFECTIVO'); raise exception 'MOZO permitido'; exception when sqlstate '42501' then null; end;
  perform pg_temp.h5_t04_set_user(v_kitchen);
  begin perform public.registrar_pago_pedido(-50401,'EFECTIVO'); raise exception 'COCINA permitido'; exception when sqlstate '42501' then null; end;
  perform pg_temp.h5_t04_set_user(v_admin);
  begin perform public.registrar_pago_pedido(-50401,'EFECTIVO'); raise exception 'ADMINISTRADOR permitido'; exception when sqlstate '42501' then null; end;

  insert into public.mesa(id,local_id,codigo,nombre,estado) values('00000000-0000-0000-0000-000000050490',v_local,'T50490','Rollback','PENDIENTE_PAGO');
  insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values(-50490,v_local,'00000000-0000-0000-0000-000000050490',v_waiter,'ENTREGADO');
  insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en) overriding system value values(-50490,-50490,v_product,2,7,'LISTO',now());
  perform pg_temp.h5_t04_set_user(v_cashier);
end $behaviour$;

create function pg_temp.h5_t04_fail_history() returns trigger language plpgsql as $$ begin raise exception 'fallo inducido H5-T04'; end $$;
create trigger h5_t04_fail_history before insert on public.historial_estado for each row when (new.pedido_id = -50490) execute function pg_temp.h5_t04_fail_history();
do $rollback_test$
begin
  begin perform public.registrar_pago_pedido(-50490,'EFECTIVO'); exception when raise_exception then null; end;
  if exists(select 1 from public.pago where pedido_id=-50490)
    or (select estado from public.pedido where id=-50490) <> 'ENTREGADO'
    or (select estado from public.mesa where id='00000000-0000-0000-0000-000000050490') <> 'PENDIENTE_PAGO'
    or exists(select 1 from public.historial_estado where pedido_id=-50490 and estado_nuevo='PAGADO') then
    raise exception 'H5-T04 rollback incompleto';
  end if;
end $rollback_test$;

rollback;
