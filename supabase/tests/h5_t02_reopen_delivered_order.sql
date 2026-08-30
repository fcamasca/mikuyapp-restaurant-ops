begin;

create function pg_temp.h5_reopen_user(p_id uuid) returns void language plpgsql set search_path=pg_catalog as $$
begin
 perform pg_catalog.set_config('request.jwt.claim.sub',p_id::text,true);
 perform pg_catalog.set_config('request.jwt.claim.role','authenticated',true);
end $$;

do $$
declare
 v_mozo uuid:='00000000-0000-0000-0000-00000000f801';
 v_cocina uuid:='00000000-0000-0000-0000-00000000f802';
 v_caja uuid:='00000000-0000-0000-0000-00000000f803';
 v_local uuid:='00000000-0000-0000-0000-00000000f804';
 v_cat uuid:='00000000-0000-0000-0000-00000000f805';
 v_old uuid:='00000000-0000-0000-0000-00000000f806';
 v_new uuid:='00000000-0000-0000-0000-00000000f807';
 v_table uuid:='00000000-0000-0000-0000-00000000f808';
 v_new_detail bigint;
begin
 insert into auth.users(id,aud,role,email,encrypted_password) values
 (v_mozo,'authenticated','authenticated','h5-reopen-w@example.invalid','test'),
 (v_cocina,'authenticated','authenticated','h5-reopen-k@example.invalid','test'),
 (v_caja,'authenticated','authenticated','h5-reopen-c@example.invalid','test');
 insert into public.local(id,codigo,nombre) values(v_local,'H5-REOPEN','H5 Reopen');
 insert into public.perfil_usuario(id,local_id,rol_id,nombre)
 select v_mozo,v_local,id,'Mozo' from public.rol where codigo='MOZO' union all
 select v_cocina,v_local,id,'Cocina' from public.rol where codigo='COCINA' union all
 select v_caja,v_local,id,'Caja' from public.rol where codigo='CAJA';
 insert into public.categoria(id,local_id,codigo,nombre) values(v_cat,v_local,'H5-REOPEN','Categoría');
 insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio) values
 (v_old,v_local,v_cat,'OLD','Anterior',10),(v_new,v_local,v_cat,'NEW','Nuevo',7);
 insert into public.mesa(id,local_id,codigo,nombre,estado) values(v_table,v_local,'H5-R','Mesa','PENDIENTE_PAGO');
 insert into public.pedido(id,local_id,mesa_id,creado_por,estado,enviado_en) overriding system value
 values(-50801,v_local,v_table,v_mozo,'ENTREGADO',now());
 perform pg_temp.h5_reopen_user(v_mozo);
 insert into public.detalle_pedido(id,pedido_id,producto_id,cantidad,precio_unitario,estado,enviado_en)
 overriding system value values(-50801,-50801,v_old,2,10,'LISTO',now());

 if (select pedido_estado from public.crear_o_recuperar_pedido_mesa(v_table)) <> 'ENTREGADO' then
  raise exception 'TA18 no recuperó ENTREGADO'; end if;
 select detalle_id into strict v_new_detail from public.agregar_detalle_pedido(-50801,v_new,1,null);
 if (select estado from public.detalle_pedido where id=v_new_detail)<>'ABIERTO'
  or (select estado from public.detalle_pedido where id=-50801)<>'LISTO'
  or (select estado from public.pedido where id=-50801)<>'ABIERTO'
  or (select estado from public.mesa where id=v_table)<>'OCUPADA' then
  raise exception 'TA18 reapertura incorrecta'; end if;

 perform public.enviar_pedido_cocina(-50801);
 perform pg_temp.h5_reopen_user(v_cocina);
 perform public.actualizar_estado_detalle_cocina(v_new_detail,'ENVIADO','RECIBIDO_COCINA');
 perform public.actualizar_estado_detalle_cocina(v_new_detail,'RECIBIDO_COCINA','EN_PREPARACION');
 perform public.actualizar_estado_detalle_cocina(v_new_detail,'EN_PREPARACION','LISTO');
 if (select estado from public.pedido where id=-50801)<>'LISTO'
  or (select estado from public.mesa where id=v_table)<>'PEDIDO_LISTO' then raise exception 'TA18 no volvió a LISTO'; end if;

 perform pg_temp.h5_reopen_user(v_mozo); perform public.entregar_pedido(-50801);
 if (select estado from public.mesa where id=v_table)<>'PENDIENTE_PAGO'
  or (select count(*) from public.detalle_pedido where pedido_id=-50801 and estado<>'LISTO')<>0
  or (select count(*) from public.historial_estado where pedido_id=-50801 and estado_anterior='LISTO' and estado_nuevo='ENTREGADO')<>1
 then raise exception 'TA18 segunda entrega incorrecta'; end if;

 perform pg_temp.h5_reopen_user(v_caja); perform public.registrar_pago_pedido(-50801,'EFECTIVO');
 if (select estado from public.pedido where id=-50801)<>'PAGADO' or (select estado from public.mesa where id=v_table)<>'LIBRE'
 then raise exception 'TA18 cobro final incorrecto'; end if;

 perform pg_temp.h5_reopen_user(v_mozo);
 begin perform public.agregar_detalle_pedido(-50801,v_new,1,null); raise exception 'TA13 alta postpago'; exception when sqlstate '42501' then null; end;
 begin perform public.enviar_pedido_cocina(-50801); raise exception 'TA13 envío postpago'; exception when sqlstate '42501' then null; end;
 begin perform public.entregar_pedido(-50801); raise exception 'TA13 entrega postpago'; exception when sqlstate '40001' then null; end;
 if (select count(*) from public.pago where pedido_id=-50801)<>1 then raise exception 'TA13 pago único roto'; end if;

 -- PAGADO no se recupera ni modifica. La mesa LIBRE sí puede iniciar otro pedido.
 if not exists (
   select 1 from public.crear_o_recuperar_pedido_mesa(v_table) opened
   where opened.pedido_id <> -50801 and opened.fue_creado
 ) then raise exception 'TA13 recuperó PAGADO en vez de crear un pedido nuevo'; end if;
end $$;

rollback;
