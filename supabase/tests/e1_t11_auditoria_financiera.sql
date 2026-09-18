begin;
create function pg_temp.t11_user(p uuid) returns void language plpgsql set search_path=pg_catalog as $$
begin perform set_config('request.jwt.claim.sub',coalesce(p::text,''),true);perform set_config('request.jwt.claim.role','authenticated',true);end $$;

do $t$
declare
  a uuid:='e1110000-0000-0000-0000-000000000101';b uuid:='e1110000-0000-0000-0000-000000000102';admin uuid:='e1110000-0000-0000-0000-000000000103';other uuid:='e1110000-0000-0000-0000-000000000104';waiter uuid:='e1110000-0000-0000-0000-000000000105';
  la uuid:='e1110000-0000-0000-0000-000000000201';lb uuid:='e1110000-0000-0000-0000-000000000202';box uuid:='e1110000-0000-0000-0000-000000000301';boxb uuid:='e1110000-0000-0000-0000-000000000302';s uuid:='e1110000-0000-0000-0000-000000000401';sb uuid:='e1110000-0000-0000-0000-000000000402';m uuid:='e1110000-0000-0000-0000-000000000501';cat uuid:='e1110000-0000-0000-0000-000000000502';prod uuid:='e1110000-0000-0000-0000-000000000503';pid bigint:=-11101;before_count bigint;defs text;checks int:=0;
begin
  -- TP55: catálogo, RLS, grants, owner y search_path endurecidos.
  select pg_get_functiondef('public.rpc_obtener_auditoria_financiera(uuid,bigint,integer)'::regprocedure) into defs;
  if defs !~* 'security definer' or defs !~* 'set search_path to ''pg_catalog''' or
     (select rolname from pg_proc p join pg_roles r on r.oid=p.proowner where p.oid='public.rpc_obtener_auditoria_financiera(uuid,bigint,integer)'::regprocedure)<>'postgres' or
     has_function_privilege('anon','public.rpc_obtener_auditoria_financiera(uuid,bigint,integer)','EXECUTE') or
     not has_function_privilege('authenticated','public.rpc_obtener_auditoria_financiera(uuid,bigint,integer)','EXECUTE') or
     has_table_privilege('authenticated','public.auditoria_caja','INSERT,UPDATE,DELETE') or
     not (select relrowsecurity from pg_class where oid='public.auditoria_caja'::regclass) then raise exception 'TP55 metadata inválida';end if;
  if (select regexp_replace(pg_get_constraintdef(oid),'[[:space:]]','','g') from pg_constraint where conrelid='public.auditoria_caja'::regclass and conname='ck_auditoria_caja_catalogo_e1') ~ 'REVOC' then raise exception 'catálogo contiene revocación';end if;checks:=checks+1;

  insert into auth.users(id,aud,role,email,encrypted_password) values(a,'authenticated','authenticated','t11-a@example.invalid','x'),(b,'authenticated','authenticated','t11-b@example.invalid','x'),(admin,'authenticated','authenticated','t11-admin@example.invalid','x'),(other,'authenticated','authenticated','t11-other@example.invalid','x'),(waiter,'authenticated','authenticated','t11-w@example.invalid','x');
  insert into public.local(id,codigo,nombre) values(la,'T11-A','Local A'),(lb,'T11-B','Local B');
  insert into public.perfil_usuario(id,local_id,rol_id,nombre) select a,la,id,'Caja A' from public.rol where codigo='CAJA' union all select b,la,id,'Caja B' from public.rol where codigo='CAJA' union all select admin,la,id,'Admin' from public.rol where codigo='ADMINISTRADOR' union all select other,lb,id,'Caja otro' from public.rol where codigo='CAJA' union all select waiter,la,id,'Mozo' from public.rol where codigo='MOZO';
  insert into public.caja(id,local_id,codigo,nombre) values(box,la,'T11-A','Caja A'),(boxb,lb,'T11-B','Caja B');
  perform pg_temp.t11_user(a);perform public.rpc_abrir_sesion_caja(box,100,'e1110000-0000-0000-0000-000000000601');select id into s from public.sesion_caja where caja_id=box and estado='ABIERTA';
  perform pg_temp.t11_user(other);perform public.rpc_abrir_sesion_caja(boxb,10,'e1110000-0000-0000-0000-000000000602');select id into sb from public.sesion_caja where caja_id=boxb and estado='ABIERTA';
  perform pg_temp.t11_user(b);perform public.rpc_registrar_movimiento_caja(s,'ENTRADA',20,'Fondo adicional','e1110000-0000-0000-0000-000000000603');
  insert into public.mesa(id,local_id,codigo,nombre,estado) values(m,la,'T11-M','Mesa','PENDIENTE_PAGO');insert into public.categoria(id,local_id,codigo,nombre) values(cat,la,'T11','Categoría');insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values(prod,la,cat,'T11','Producto',100);insert into public.pedido(id,local_id,mesa_id,creado_por,estado) overriding system value values(pid,la,m,waiter,'ENTREGADO');insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en) overriding system value values(pid,pid,prod,1,100,'LISTO',now());
  perform public.rpc_solicitar_descuento_pedido(pid,10,null,'Cliente frecuente','e1110000-0000-0000-0000-000000000604');perform pg_temp.t11_user(admin);perform public.rpc_decidir_descuento_pedido(pid,'AUTORIZAR',null,'e1110000-0000-0000-0000-000000000605');perform pg_temp.t11_user(b);perform public.rpc_registrar_pago_pedido_v2(pid,s,90,'EFECTIVO',5,'e1110000-0000-0000-0000-000000000606');

  -- TP49/TP50: orden, actores y snapshots reconstruibles y coherentes.
  if (select string_agg(tipo,',' order by creado_en,
       case tipo when 'APERTURA' then 10 when 'ENTRADA' then 20 when 'SALIDA' then 20
         when 'SOLICITUD_DESCUENTO' then 30
         when 'AUTORIZACION_DESCUENTO' then 40 when 'RECHAZO_DESCUENTO' then 40
         when 'PAGO' then 50 when 'ANULACION' then 50
         when 'CIERRE' then 60 when 'CIERRE_SUPERVISOR' then 60 else 90 end,id)
      from public.rpc_obtener_auditoria_financiera(s,null,200))<>'APERTURA,ENTRADA,PAGO' or
     (select actor_id from public.rpc_obtener_auditoria_financiera(s,pid,200) where tipo='PAGO')<>b or
     (select count(*) from public.rpc_obtener_auditoria_financiera(null,pid,200) where tipo in('SOLICITUD_DESCUENTO','AUTORIZACION_DESCUENTO','PAGO'))<>3 or
     (select autorizador_id from public.rpc_obtener_auditoria_financiera(null,pid,200) where tipo='AUTORIZACION_DESCUENTO')<>admin or
     (select total_neto from public.rpc_obtener_auditoria_financiera(null,pid,200) where tipo='AUTORIZACION_DESCUENTO')<>90 or
     (select saldo_anterior from public.rpc_obtener_auditoria_financiera(null,pid,200) where tipo='PAGO')<>90 or
     (select saldo_nuevo from public.rpc_obtener_auditoria_financiera(null,pid,200) where tipo='PAGO')<>0 then
    raise exception 'TP49/TP50 reconstrucción inconsistente: sesión=%, pedido=%, actor=%, autorizador=%, neto=%, saldos=%/%',
      (select string_agg(tipo,',' order by creado_en,
        case tipo when 'APERTURA' then 10 when 'ENTRADA' then 20 when 'SALIDA' then 20
          when 'SOLICITUD_DESCUENTO' then 30
          when 'AUTORIZACION_DESCUENTO' then 40 when 'RECHAZO_DESCUENTO' then 40
          when 'PAGO' then 50 when 'ANULACION' then 50
          when 'CIERRE' then 60 when 'CIERRE_SUPERVISOR' then 60 else 90 end,id)
       from public.rpc_obtener_auditoria_financiera(s,null,200)),
      (select count(*) from public.rpc_obtener_auditoria_financiera(null,pid,200) where tipo in('SOLICITUD_DESCUENTO','AUTORIZACION_DESCUENTO','PAGO')),
      (select actor_id from public.rpc_obtener_auditoria_financiera(s,pid,200) where tipo='PAGO'),
      (select autorizador_id from public.rpc_obtener_auditoria_financiera(null,pid,200) where tipo='AUTORIZACION_DESCUENTO'),
      (select total_neto from public.rpc_obtener_auditoria_financiera(null,pid,200) where tipo='AUTORIZACION_DESCUENTO'),
      (select saldo_anterior from public.rpc_obtener_auditoria_financiera(null,pid,200) where tipo='PAGO'),
      (select saldo_nuevo from public.rpc_obtener_auditoria_financiera(null,pid,200) where tipo='PAGO');
  end if;checks:=checks+1;

  -- TP51: el cliente no escribe directamente.
  perform pg_temp.t11_user(a);execute 'set local role authenticated';
  begin insert into public.auditoria_caja(tipo,local_id,actor_id,estado_nuevo) values('APERTURA',la,a,'ABIERTA');raise exception 'INSERT directo permitido';exception when insufficient_privilege then null;end;
  begin update public.auditoria_caja set motivo='x' where local_id=la;raise exception 'UPDATE directo permitido';exception when insufficient_privilege then null;end;
  begin delete from public.auditoria_caja where local_id=la;raise exception 'DELETE directo permitido';exception when insufficient_privilege then null;end;reset role;checks:=checks+1;

  -- TP52: otra localidad no se filtra; rol no autorizado tampoco consulta.
  perform pg_temp.t11_user(a);if exists(select 1 from public.rpc_obtener_auditoria_financiera(sb,null,200)) then raise exception 'TP52 filtración cruzada';end if;
  perform pg_temp.t11_user(waiter);begin perform public.rpc_obtener_auditoria_financiera(s,null,200);raise exception 'MOZO leyó auditoría';exception when insufficient_privilege then null;end;checks:=checks+1;

  -- TP53: actores, caja, sesión y pedido referenciados no se eliminan.
  begin delete from public.perfil_usuario where id=b;raise exception 'actor eliminable';exception when foreign_key_violation then null;end;
  begin delete from public.caja where id=box;raise exception 'caja eliminable';exception when foreign_key_violation then null;end;
  begin delete from public.pedido where id=pid;raise exception 'pedido eliminable';exception when foreign_key_violation then null;end;checks:=checks+1;

  -- TP54: fallo inducido en auditoría revierte también el movimiento.
  select count(*) into before_count from public.movimiento_caja where sesion_caja_id=s;create function pg_temp.fail_t11_audit() returns trigger language plpgsql as $$begin raise exception 'fallo inducido';end$$;create trigger t11_fail before insert on public.auditoria_caja for each row when(new.tipo='SALIDA') execute function pg_temp.fail_t11_audit();perform pg_temp.t11_user(a);
  begin perform public.rpc_registrar_movimiento_caja(s,'SALIDA',1,'Debe revertir',gen_random_uuid());raise exception 'RPC no falló';exception when others then if sqlerrm<>'fallo inducido' then raise;end if;end;
  drop trigger t11_fail on public.auditoria_caja;if (select count(*) from public.movimiento_caja where sesion_caja_id=s)<>before_count or exists(select 1 from public.auditoria_caja where sesion_caja_id=s and tipo='SALIDA') then raise exception 'TP54 dejó efectos parciales';end if;checks:=checks+1;
  raise notice 'E1-T11 grupos aprobados: %',checks;
end $t$;
select 'E1-T11 SQL: TP49-TP55 aprobados';
rollback;
