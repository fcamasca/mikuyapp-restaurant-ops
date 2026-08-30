begin;

create function pg_temp.h6_set_user(p_id uuid) returns void language plpgsql set search_path=pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub',p_id::text,true);
  perform pg_catalog.set_config('request.jwt.claim.role','authenticated',true);
end $$;

do $metadata$
declare v_name text;
begin
  foreach v_name in array array['obtener_resumen_ventas_hoy','exportar_ventas_hoy','exportar_productos_local'] loop
    if not exists (
      select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_name and pg_catalog.pg_get_function_identity_arguments(p.oid)=''
        and p.prosecdef and p.proowner=(select oid from pg_catalog.pg_roles where rolname='postgres')
        and p.proconfig=array['search_path=pg_catalog']
    ) or pg_catalog.has_function_privilege('anon',('public.'||v_name||'()')::regprocedure,'EXECUTE')
      or not pg_catalog.has_function_privilege('authenticated',('public.'||v_name||'()')::regprocedure,'EXECUTE') then
      raise exception 'H6-T02 contrato de seguridad inesperado: %',v_name;
    end if;
  end loop;
end $metadata$;

do $behaviour$
declare
  v_admin_a uuid:='00000000-0000-0000-0000-000000006201';
  v_cashier_a uuid:='00000000-0000-0000-0000-000000006202';
  v_waiter_a uuid:='00000000-0000-0000-0000-000000006203';
  v_kitchen_a uuid:='00000000-0000-0000-0000-000000006204';
  v_admin_b uuid:='00000000-0000-0000-0000-000000006205';
  v_local_a uuid:='00000000-0000-0000-0000-000000006211';
  v_local_b uuid:='00000000-0000-0000-0000-000000006212';
  v_table_a uuid:='00000000-0000-0000-0000-000000006221';
  v_table_b uuid:='00000000-0000-0000-0000-000000006222';
  v_cat_a uuid:='00000000-0000-0000-0000-000000006231';
  v_cat_b uuid:='00000000-0000-0000-0000-000000006232';
  v_product_a uuid:='00000000-0000-0000-0000-000000006241';
  v_product_b uuid:='00000000-0000-0000-0000-000000006242';
  v_today date:=(pg_catalog.now() at time zone 'America/Lima')::date;
  v_count bigint; v_amount numeric;
begin
  insert into auth.users(id,aud,role,email,encrypted_password) values
    (v_admin_a,'authenticated','authenticated','h6t02-admin-a@example.invalid','test'),
    (v_cashier_a,'authenticated','authenticated','h6t02-cashier-a@example.invalid','test'),
    (v_waiter_a,'authenticated','authenticated','h6t02-waiter-a@example.invalid','test'),
    (v_kitchen_a,'authenticated','authenticated','h6t02-kitchen-a@example.invalid','test'),
    (v_admin_b,'authenticated','authenticated','h6t02-admin-b@example.invalid','test');
  insert into public.local(id,codigo,nombre) values(v_local_a,'H6T02-A','H6 T02 A'),(v_local_b,'H6T02-B','H6 T02 B');
  insert into public.perfil_usuario(id,local_id,rol_id,nombre)
  select v_admin_a,v_local_a,id,'Admin A' from public.rol where codigo='ADMINISTRADOR' union all
  select v_cashier_a,v_local_a,id,'Caja A' from public.rol where codigo='CAJA' union all
  select v_waiter_a,v_local_a,id,'Mozo A' from public.rol where codigo='MOZO' union all
  select v_kitchen_a,v_local_a,id,'Cocina A' from public.rol where codigo='COCINA' union all
  select v_admin_b,v_local_b,id,'Admin B' from public.rol where codigo='ADMINISTRADOR';
  insert into public.mesa(id,local_id,codigo,nombre) values(v_table_a,v_local_a,'H6-A','Mesa A'),(v_table_b,v_local_b,'H6-B','Mesa B');
  insert into public.categoria(id,local_id,codigo,nombre) values(v_cat_a,v_local_a,'H6-CA','Categoría A'),(v_cat_b,v_local_b,'H6-CB','Categoría B');
  insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio,activo) values
    (v_product_a,v_local_a,v_cat_a,'H6-PA','Producto A',12.50,true),(v_product_b,v_local_b,v_cat_b,'H6-PB','Producto B',99,false);
  insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values
    (-6201,v_local_a,v_table_a,v_waiter_a,'PAGADO'),(-6202,v_local_a,v_table_a,v_waiter_a,'PAGADO'),
    (-6203,v_local_a,v_table_a,v_waiter_a,'PAGADO'),(-6204,v_local_a,v_table_a,v_waiter_a,'ENTREGADO'),
    (-6211,v_local_b,v_table_b,v_admin_b,'PAGADO');
  insert into public.pago(pedido_id,importe,medio,usuario_id,pagado_en) values
    (-6201,10,'EFECTIVO',v_cashier_a,(v_today+time '12:00') at time zone 'America/Lima'),
    (-6202,20.50,'YAPE',v_cashier_a,(v_today+time '23:30') at time zone 'America/Lima'),
    (-6203,777,'TARJETA',v_cashier_a,((v_today-1)+time '12:00') at time zone 'America/Lima'),
    (-6204,888,'PLIN',v_cashier_a,(v_today+time '13:00') at time zone 'America/Lima'),
    (-6211,99,'TARJETA',v_admin_b,(v_today+time '14:00') at time zone 'America/Lima');

  perform pg_temp.h6_set_user(v_admin_a);
  select coalesce(sum(r.pedidos_pagados),0),coalesce(sum(r.importe),0) into v_count,v_amount from public.obtener_resumen_ventas_hoy() r;
  if v_count<>2 or v_amount<>30.50 then raise exception 'TP01 resumen admin A incorrecto: %, %',v_count,v_amount; end if;
  if (select count(*) from public.obtener_resumen_ventas_hoy() where medio='EFECTIVO' and pedidos_pagados=1 and importe=10)<>1
    or (select count(*) from public.obtener_resumen_ventas_hoy() where medio='YAPE' and pedidos_pagados=1 and importe=20.50)<>1 then raise exception 'TP02 medios incorrectos'; end if;
  if (select count(*) from public.exportar_ventas_hoy() where pedido_id=-6202)<>1 then raise exception 'TP03 cruce UTC/Lima excluido'; end if;
  if (select count(*) from public.exportar_ventas_hoy())<>2 or exists(select 1 from public.exportar_ventas_hoy() where pedido_id in(-6203,-6204,-6211)) then raise exception 'TP05 ventas exportadas incorrectas'; end if;
  if (select count(*) from public.exportar_productos_local())<>1 or not exists(select 1 from public.exportar_productos_local() where codigo_producto='H6-PA' and precio=12.50 and activo) then raise exception 'TP06 productos A incorrectos'; end if;

  perform pg_temp.h6_set_user(v_cashier_a);
  select coalesce(sum(r.pedidos_pagados),0),coalesce(sum(r.importe),0) into v_count,v_amount from public.obtener_resumen_ventas_hoy() r;
  if v_count<>2 or v_amount<>30.50 then raise exception 'TP04 resumen caja incorrecto'; end if;
  begin perform public.exportar_ventas_hoy(); raise exception 'TP04 caja exportó ventas'; exception when sqlstate '42501' then null; end;
  begin perform public.exportar_productos_local(); raise exception 'TP04 caja exportó productos'; exception when sqlstate '42501' then null; end;
  perform pg_temp.h6_set_user(v_waiter_a); begin perform public.obtener_resumen_ventas_hoy(); raise exception 'TP04 mozo autorizado'; exception when sqlstate '42501' then null; end;
  perform pg_temp.h6_set_user(v_kitchen_a); begin perform public.obtener_resumen_ventas_hoy(); raise exception 'TP04 cocina autorizada'; exception when sqlstate '42501' then null; end;

  perform pg_temp.h6_set_user(v_admin_b);
  select coalesce(sum(r.pedidos_pagados),0),coalesce(sum(r.importe),0) into v_count,v_amount from public.obtener_resumen_ventas_hoy() r;
  if v_count<>1 or v_amount<>99 then raise exception 'TP07 resumen B filtró incorrectamente'; end if;
  if (select count(*) from public.exportar_ventas_hoy())<>1 or not exists(select 1 from public.exportar_ventas_hoy() where pedido_id=-6211)
    or (select count(*) from public.exportar_productos_local())<>1 or not exists(select 1 from public.exportar_productos_local() where codigo_producto='H6-PB' and not activo) then raise exception 'TP07 exportación B incorrecta'; end if;
  if exists(select 1 from public.exportar_ventas_hoy() where pedido_id in(-6201,-6202)) or exists(select 1 from public.exportar_productos_local() where codigo_producto='H6-PA') then raise exception 'TP07 fuga entre locales'; end if;
end $behaviour$;

select 'H6-TP01..TP07 OK' as resultado;
rollback;
