begin;
create function pg_temp.t07_user(p uuid) returns void language plpgsql set search_path=pg_catalog as $$
begin perform set_config('request.jwt.claim.sub',coalesce(p::text,''),true);perform set_config('request.jwt.claim.role','authenticated',true);end $$;

do $t$
declare
  admin uuid:='e1070000-0000-0000-0000-000000000101';admin_other uuid:='e1070000-0000-0000-0000-000000000102';
  caja uuid:='e1070000-0000-0000-0000-000000000103';mozo uuid:='e1070000-0000-0000-0000-000000000104';
  local_a uuid:='e1070000-0000-0000-0000-000000000201';local_b uuid:='e1070000-0000-0000-0000-000000000202';
  box_id uuid:='e1070000-0000-0000-0000-000000000301';session_id uuid:='e1070000-0000-0000-0000-000000000401';
  category_id uuid:='e1070000-0000-0000-0000-000000000501';product_id uuid:='e1070000-0000-0000-0000-000000000502';
  states text[]:=array['ABIERTO','ENVIADO','RECIBIDO_COCINA','EN_PREPARACION','LISTO','ENTREGADO'];
  st text;idx int:=0;pid bigint;mid uuid;mesa_st text;r jsonb;aid uuid;checks int:=0;before_detail text;
begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='anulacion_pedido'
    and column_name in ('solicitante_id','autorizador_id')) then raise exception 'flujo solicitante/autorizador no permitido';end if;
  if has_function_privilege('anon','public.anular_pedido_supervisado(bigint,text,uuid)','EXECUTE')
    or not has_function_privilege('authenticated','public.anular_pedido_supervisado(bigint,text,uuid)','EXECUTE')
    or has_table_privilege('authenticated','public.anulacion_pedido','INSERT,UPDATE,DELETE') then raise exception 'grants T07 inválidos';end if;
  checks:=checks+1;
  insert into auth.users(id,aud,role,email,encrypted_password) values
   (admin,'authenticated','authenticated','t07-a@example.invalid','x'),(admin_other,'authenticated','authenticated','t07-o@example.invalid','x'),
   (caja,'authenticated','authenticated','t07-c@example.invalid','x'),(mozo,'authenticated','authenticated','t07-m@example.invalid','x');
  insert into public.local(id,codigo,nombre) values(local_a,'T07-A','Local A'),(local_b,'T07-B','Local B');
  insert into public.perfil_usuario(id,local_id,rol_id,nombre)
   select admin,local_a,id,'Admin' from public.rol where codigo='ADMINISTRADOR' union all
   select admin_other,local_b,id,'Admin otro' from public.rol where codigo='ADMINISTRADOR' union all
   select caja,local_a,id,'Caja' from public.rol where codigo='CAJA' union all
   select mozo,local_a,id,'Mozo' from public.rol where codigo='MOZO';
  insert into public.caja(id,local_id,codigo,nombre) values(box_id,local_a,'T07','Caja');
  insert into public.sesion_caja(id,caja_id,local_id,abierta_por,monto_inicial,idempotency_key)
   values(session_id,box_id,local_a,caja,0,'e1070000-0000-0000-0000-000000000601');
  insert into public.categoria(id,local_id,codigo,nombre) values(category_id,local_a,'T07','Categoría');
  insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values(product_id,local_a,category_id,'T07','Producto',10);

  perform pg_temp.t07_user(admin);
  foreach st in array states loop
    idx:=idx+1;pid:=-11700-idx;mid:=('e1070000-0000-0000-0000-'||lpad((700+idx)::text,12,'0'))::uuid;
    mesa_st:=case when st='LISTO' then 'PEDIDO_LISTO' when st='ENTREGADO' then 'PENDIENTE_PAGO' else 'OCUPADA' end;
    insert into public.mesa(id,local_id,codigo,nombre,estado) values(mid,local_a,'T'||idx,'Mesa',mesa_st);
    insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values(pid,local_a,mid,mozo,st);
    insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en) overriding system value
      values(pid,pid,product_id,2,10,case when st='ABIERTO' then 'ABIERTO' else 'LISTO' end,case when st='ABIERTO' then null else now() end);
    select concat_ws('|',id,pedido_id,producto_id,cantidad,precio_unitario,coalesce(observacion,''),estado,coalesce(enviado_en::text,'')) into before_detail
      from public.detalle_pedido where pedido_id=pid;
    r:=public.anular_pedido_supervisado(pid,'Motivo '||st,('e1070000-0000-0000-0000-'||lpad((800+idx)::text,12,'0'))::uuid);aid:=(r->>'id')::uuid;
    if r->>'estado_anterior'<>st or r->>'estado_nuevo'<>'ANULADO' or r->>'mesa_estado_anterior'<>mesa_st
      or r->>'mesa_estado_nuevo'<>'LIBRE' or (r->>'actor_id')::uuid<>admin or r->>'anulado_en' is null
      or (select estado from public.pedido where id=pid)<>'ANULADO' or (select estado from public.mesa where id=mid)<>'LIBRE'
      or (select count(*) from public.historial_estado where pedido_id=pid and estado_anterior=st and estado_nuevo='ANULADO' and usuario_id=admin)<>1
      or (select count(*) from public.auditoria_caja where anulacion_pedido_id=aid and tipo='ANULACION' and actor_id=admin and autorizador_id is null and solicitante_id is null)<>1
      or (select concat_ws('|',id,pedido_id,producto_id,cantidad,precio_unitario,coalesce(observacion,''),estado,coalesce(enviado_en::text,'')) from public.detalle_pedido where pedido_id=pid)<>before_detail
      then raise exception 'TP26/TP27 inconsistente para %: %',st,r;end if;
  end loop;
  checks:=checks+1;

  -- Reintento exacto de ENTREGADO; no duplica historial ni auditoría.
  r:=public.anular_pedido_supervisado(-11706,'Motivo ENTREGADO','e1070000-0000-0000-0000-000000000806');
  if (select count(*) from public.anulacion_pedido where pedido_id=-11706)<>1
    or (select count(*) from public.historial_estado where pedido_id=-11706 and estado_nuevo='ANULADO')<>1
    or (select count(*) from public.auditoria_caja where pedido_id=-11706 and tipo='ANULACION')<>1 then raise exception 'idempotencia T07';end if;
  begin perform public.anular_pedido_supervisado(-11706,'Otro motivo',gen_random_uuid());raise exception 'segunda anulación permitida';exception when sqlstate '40001' then null;end;
  checks:=checks+1;
  begin perform public.anular_pedido_supervisado(-11701,' ',gen_random_uuid());raise exception 'motivo vacío permitido';exception when sqlstate '22023' then null;end;
  perform pg_temp.t07_user(caja);begin perform public.anular_pedido_supervisado(-11701,'x',gen_random_uuid());raise exception 'CAJA anuló';exception when sqlstate '42501' then null;end;
  perform pg_temp.t07_user(mozo);begin perform public.anular_pedido_supervisado(-11701,'x',gen_random_uuid());raise exception 'MOZO anuló';exception when sqlstate '42501' then null;end;
  perform pg_temp.t07_user(admin_other);begin perform public.anular_pedido_supervisado(-11701,'x',gen_random_uuid());raise exception 'otro local anuló';exception when sqlstate '42501' then null;end;
  checks:=checks+1;

  -- Pedido ENTREGADO con pago confirmado permanece completamente intacto.
  mid:='e1070000-0000-0000-0000-000000000707';
  insert into public.mesa(id,local_id,codigo,nombre,estado) values(mid,local_a,'TP28','Mesa pago','PENDIENTE_PAGO');
  insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values(-11707,local_a,mid,mozo,'ENTREGADO');
  insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en) overriding system value values(-11707,-11707,product_id,2,10,'LISTO',now());
  insert into public.pago(pedido_id,importe,medio,usuario_id,sesion_caja_id,propina,idempotency_key) values(-11707,1,'YAPE',caja,session_id,0,'e1070000-0000-0000-0000-000000000607');
  perform pg_temp.t07_user(admin);
  begin perform public.anular_pedido_supervisado(-11707,'No debe',gen_random_uuid());raise exception 'pedido con pago anulado';exception when sqlstate '40001' then null;end;
  if (select estado from public.pedido where id=-11707)<>'ENTREGADO' or (select estado from public.mesa where id=mid)<>'PENDIENTE_PAGO'
    or (select count(*) from public.pago where pedido_id=-11707)<>1 or exists(select 1 from public.auditoria_caja where pedido_id=-11707 and tipo='ANULACION') then raise exception 'TP28 alteró pedido con pago';end if;
  checks:=checks+1;

  -- Estados terminales bloqueados aun sin snapshot T07 previo.
  insert into public.mesa(id,local_id,codigo,nombre,estado) values
    ('e1070000-0000-0000-0000-000000000708',local_a,'PAG','Pagada','LIBRE'),
    ('e1070000-0000-0000-0000-000000000709',local_a,'ANU','Anulada','LIBRE');
  insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values
    (-11708,local_a,'e1070000-0000-0000-0000-000000000708',mozo,'PAGADO'),
    (-11709,local_a,'e1070000-0000-0000-0000-000000000709',mozo,'ANULADO');
  begin perform public.anular_pedido_supervisado(-11708,'x',gen_random_uuid());raise exception 'PAGADO anulable';exception when sqlstate '40001' then null;end;
  begin perform public.anular_pedido_supervisado(-11709,'x',gen_random_uuid());raise exception 'ANULADO anulable';exception when sqlstate '40001' then null;end;
  checks:=checks+1;

  -- TP30: H3 agregar y H5 entregar/cobrar no mutan terminales.
  perform pg_temp.t07_user(mozo);
  begin perform public.agregar_detalle_pedido(-11708,product_id,1,null);raise exception 'H3 mutó PAGADO';exception when sqlstate '42501' then null;end;
  begin perform public.agregar_detalle_pedido(-11709,product_id,1,null);raise exception 'H3 mutó ANULADO';exception when sqlstate '42501' then null;end;
  begin perform public.entregar_pedido(-11708);raise exception 'H5 entregó PAGADO';exception when sqlstate '40001' then null;end;
  begin perform public.entregar_pedido(-11709);raise exception 'H5 entregó ANULADO';exception when sqlstate '40001' then null;end;
  perform pg_temp.t07_user(caja);
  begin perform public.rpc_registrar_pago_total_pedido(-11708,session_id,'EFECTIVO',0,gen_random_uuid());raise exception 'H5 cobró PAGADO';exception when sqlstate '40001' then null;end;
  begin perform public.rpc_registrar_pago_total_pedido(-11709,session_id,'EFECTIVO',0,gen_random_uuid());raise exception 'H5 cobró ANULADO';exception when sqlstate '40001' then null;end;
  if exists(select 1 from public.detalle_pedido where pedido_id in(-11708,-11709)) then raise exception 'TP30 creó detalles';end if;
  checks:=checks+1;
  begin update public.anulacion_pedido set motivo='editado' where pedido_id=-11701;raise exception 'anulación editable';exception when sqlstate '23514' then null;end;
  begin delete from public.anulacion_pedido where pedido_id=-11701;raise exception 'anulación eliminable';exception when sqlstate '23514' then null;end;
  checks:=checks+1;
  raise notice 'E1-T07 grupos aprobados: %',checks;
end $t$;
select 'E1-T07 SQL: 8 grupos de comprobación aprobados';
rollback;
