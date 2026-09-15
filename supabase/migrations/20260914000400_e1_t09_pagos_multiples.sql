begin;

alter table public.auditoria_caja
  add column pago_id bigint null,
  add column medio_pago text null,
  add column propina numeric(10,2) null,
  add column saldo_anterior numeric(14,2) null,
  add column saldo_nuevo numeric(14,2) null,
  add constraint fk_auditoria_caja_pago foreign key(pago_id) references public.pago(id) on delete restrict;
do $$ declare v_def text;begin
  select pg_get_constraintdef(oid) into v_def from pg_constraint
    where conrelid='public.auditoria_caja'::regclass and conname='ck_auditoria_caja_t07';
  v_def:=substring(v_def from 8 for length(v_def)-8);
  alter table public.auditoria_caja drop constraint ck_auditoria_caja_t07;
  execute 'alter table public.auditoria_caja add constraint ck_auditoria_caja_t09 check ('||v_def||
    ' or (tipo=''PAGO'' and pago_id is not null and pedido_id is not null and caja_id is not null'
    ||' and sesion_caja_id is not null and importe>0 and propina>=0'
    ||' and medio_pago in (''EFECTIVO'',''YAPE'',''PLIN'',''TARJETA'')'
    ||' and saldo_anterior>=importe and saldo_nuevo=saldo_anterior-importe))';
end $$;
create unique index uq_auditoria_caja_pago on public.auditoria_caja(pago_id) where pago_id is not null;

create function public.rpc_registrar_pago_pedido_v2(
  p_pedido_id bigint,p_sesion_caja_id uuid,p_importe_aplicar numeric,
  p_medio text,p_propina numeric,p_idempotency_key uuid
)
returns table(pago_id bigint,pedido_id bigint,pedido_estado text,mesa_id uuid,mesa_estado text,
  importe numeric,propina numeric,medio text,sesion_caja_id uuid,pagado_en timestamptz,
  subtotal numeric,descuento numeric,total_neto numeric,ya_pagado numeric,saldo numeric)
language plpgsql security definer set search_path=pg_catalog as $$
declare
  v_actor uuid:=auth.uid();v_local uuid;v_rol text;v_sesion public.sesion_caja%rowtype;
  v_pedido public.pedido%rowtype;v_mesa public.mesa%rowtype;v_pago public.pago%rowtype;
  v_subtotal numeric;v_descuento numeric;v_neto numeric;v_pagado numeric;v_saldo numeric;
  v_estado_pedido text;v_estado_mesa text;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then raise exception using errcode='42501',message='No autorizado para registrar pagos';end if;
  if p_pedido_id is null or p_sesion_caja_id is null or p_idempotency_key is null then raise exception using errcode='22023',message='Pedido, sesión y clave son obligatorios';end if;
  if p_importe_aplicar is null or p_importe_aplicar<=0 or p_importe_aplicar='NaN'::numeric
    or p_importe_aplicar>=1000000000000 or p_importe_aplicar<>round(p_importe_aplicar,2) then raise exception using errcode='22023',message='Importe aplicado inválido';end if;
  if p_medio is null or p_medio not in ('EFECTIVO','YAPE','PLIN','TARJETA') then raise exception using errcode='22023',message='Medio inválido';end if;
  if p_propina is null or p_propina<0 or p_propina='NaN'::numeric or p_propina>=100000000 or p_propina<>round(p_propina,2) then raise exception using errcode='22023',message='Propina inválida';end if;

  -- Orden definitivo T09: sesión -> pedido -> mesa.
  select s.* into v_sesion from public.sesion_caja s where s.id=p_sesion_caja_id and s.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Sesión no disponible';end if;
  select p.* into v_pago from public.pago p where p.sesion_caja_id=v_sesion.id and p.usuario_id=v_actor and p.idempotency_key=p_idempotency_key for update;
  if found then
    if v_pago.pedido_id<>p_pedido_id or v_pago.importe<>p_importe_aplicar or v_pago.medio<>p_medio or v_pago.propina<>p_propina then raise exception using errcode='22023',message='Clave reutilizada con otros datos';end if;
    select p.* into strict v_pedido from public.pedido p where p.id=v_pago.pedido_id;
    select m.* into strict v_mesa from public.mesa m where m.id=v_pedido.mesa_id;
    select r.subtotal,r.descuento,r.total_neto into v_subtotal,v_descuento,v_neto from public.fn_resolver_total_pedido(v_pedido.id) r;
    select coalesce(sum(p.importe),0) into v_pagado from public.pago p where p.pedido_id=v_pedido.id;
    return query select v_pago.id,v_pago.pedido_id,v_pedido.estado,v_mesa.id,v_mesa.estado,v_pago.importe,v_pago.propina,v_pago.medio,v_pago.sesion_caja_id,v_pago.pagado_en,v_subtotal,v_descuento,v_neto,v_pagado,v_neto-v_pagado;return;
  end if;
  if v_sesion.estado<>'ABIERTA' then raise exception using errcode='40001',message='La sesión ya no está abierta';end if;
  if not exists(select 1 from public.caja c where c.id=v_sesion.caja_id and c.local_id=v_local and c.activo) then raise exception using errcode='42501',message='Caja no disponible';end if;
  select p.* into v_pedido from public.pedido p where p.id=p_pedido_id and p.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Pedido no disponible';end if;
  select m.* into v_mesa from public.mesa m where m.id=v_pedido.mesa_id and m.local_id=v_local and m.activo for update;
  if not found then raise exception using errcode='42501',message='Mesa no disponible';end if;
  if v_pedido.estado<>'ENTREGADO' or v_mesa.estado<>'PENDIENTE_PAGO' or exists(select 1 from public.anulacion_pedido a where a.pedido_id=v_pedido.id) then raise exception using errcode='40001',message='Pedido no disponible para cobro';end if;
  select r.subtotal,r.descuento,r.total_neto into v_subtotal,v_descuento,v_neto from public.fn_resolver_total_pedido(v_pedido.id) r;
  select coalesce(sum(p.importe),0) into v_pagado from public.pago p where p.pedido_id=v_pedido.id;
  v_saldo:=v_neto-v_pagado;
  if v_saldo<=0 or p_importe_aplicar>v_saldo then raise exception using errcode='22023',message='Importe excede el saldo';end if;
  insert into public.pago(pedido_id,importe,medio,usuario_id,sesion_caja_id,propina,idempotency_key)
    values(v_pedido.id,p_importe_aplicar,p_medio,v_actor,v_sesion.id,p_propina,p_idempotency_key) returning * into v_pago;
  v_saldo:=v_saldo-p_importe_aplicar;v_pagado:=v_pagado+p_importe_aplicar;
  v_estado_pedido:='ENTREGADO';v_estado_mesa:='PENDIENTE_PAGO';
  if v_saldo=0 then
    update public.pedido set estado='PAGADO' where id=v_pedido.id;
    insert into public.historial_estado(pedido_id,estado_anterior,estado_nuevo,usuario_id) values(v_pedido.id,'ENTREGADO','PAGADO',v_actor);
    update public.mesa set estado='LIBRE' where id=v_mesa.id;
    v_estado_pedido:='PAGADO';v_estado_mesa:='LIBRE';
  end if;
  insert into public.auditoria_caja(tipo,local_id,caja_id,sesion_caja_id,actor_id,creado_en,monto_inicial,
    pedido_id,pago_id,importe,propina,medio_pago,subtotal,descuento,total_neto,saldo_anterior,saldo_nuevo,estado_anterior,estado_nuevo)
  values('PAGO',v_local,v_sesion.caja_id,v_sesion.id,v_actor,v_pago.pagado_en,null,v_pedido.id,v_pago.id,v_pago.importe,
    v_pago.propina,v_pago.medio,v_subtotal,v_descuento,v_neto,v_saldo+v_pago.importe,v_saldo,'ENTREGADO',v_estado_pedido);
  return query select v_pago.id,v_pedido.id,v_estado_pedido,v_mesa.id,v_estado_mesa,v_pago.importe,v_pago.propina,v_pago.medio,v_pago.sesion_caja_id,v_pago.pagado_en,v_subtotal,v_descuento,v_neto,v_pagado,v_saldo;
end $$;

create or replace function public.rpc_registrar_pago_total_pedido(p_pedido_id bigint,p_sesion_caja_id uuid,p_medio text,p_propina numeric,p_idempotency_key uuid)
returns table(pago_id bigint,pedido_id bigint,pedido_estado text,mesa_id uuid,mesa_estado text,importe numeric,propina numeric,medio text,sesion_caja_id uuid,pagado_en timestamptz)
language plpgsql security definer set search_path=pg_catalog as $$
declare v_total numeric;v_pagado numeric;v_saldo numeric;v_retry_importe numeric;
  v_actor uuid:=auth.uid();v_local uuid;v_rol text;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode='42501',message='No autorizado para registrar pagos';
  end if;
  if p_pedido_id is null or p_sesion_caja_id is null or p_idempotency_key is null then
    raise exception using errcode='22023',message='Pedido, sesión y clave son obligatorios';
  end if;
  if p_medio is null or p_medio not in ('EFECTIVO','YAPE','PLIN','TARJETA') then
    raise exception using errcode='22023',message='Medio inválido';
  end if;
  if p_propina is null or p_propina<0 or p_propina='NaN'::numeric or p_propina>=100000000
    or p_propina<>round(p_propina,2) then
    raise exception using errcode='22023',message='Propina inválida';
  end if;
  if not exists(select 1 from public.sesion_caja s where s.id=p_sesion_caja_id and s.local_id=v_local) then
    raise exception using errcode='42501',message='Sesión no disponible';
  end if;
  select p.importe into v_retry_importe from public.pago p
    where p.sesion_caja_id=p_sesion_caja_id and p.usuario_id=v_actor
      and p.idempotency_key=p_idempotency_key;
  if found then
    v_saldo:=v_retry_importe;
  else
    select r.total_neto into v_total from public.fn_resolver_total_pedido(p_pedido_id) r;
    select coalesce(sum(p.importe),0) into v_pagado from public.pago p where p.pedido_id=p_pedido_id;
    v_saldo:=v_total-v_pagado;
    if v_saldo is null or v_saldo<=0 then
      raise exception using errcode='40001',message='El pedido ya no está disponible para cobro';
    end if;
  end if;
  return query select r.pago_id,r.pedido_id,r.pedido_estado,r.mesa_id,r.mesa_estado,r.importe,r.propina,r.medio,r.sesion_caja_id,r.pagado_en
    from public.rpc_registrar_pago_pedido_v2(p_pedido_id,p_sesion_caja_id,v_saldo,p_medio,p_propina,p_idempotency_key) r;
end $$;

create function public.tgf_bloquear_detalle_pedido_con_pago() returns trigger language plpgsql set search_path=pg_catalog as $$
declare v_pedido_id bigint:=coalesce(new.pedido_id,old.pedido_id);begin
 if exists(select 1 from public.pago p where p.pedido_id=v_pedido_id) then raise exception using errcode='40001',message='Un pedido con pagos no admite mutaciones';end if;return coalesce(new,old);end $$;
create trigger trg_detalle_pedido_bloquear_con_pago before insert or update or delete on public.detalle_pedido for each row execute function public.tgf_bloquear_detalle_pedido_con_pago();

alter function public.rpc_registrar_pago_pedido_v2(bigint,uuid,numeric,text,numeric,uuid) owner to postgres;
alter function public.rpc_registrar_pago_total_pedido(bigint,uuid,text,numeric,uuid) owner to postgres;
alter function public.tgf_bloquear_detalle_pedido_con_pago() owner to postgres;
revoke all on function public.rpc_registrar_pago_pedido_v2(bigint,uuid,numeric,text,numeric,uuid),public.tgf_bloquear_detalle_pedido_con_pago() from public,anon,authenticated,service_role;
grant execute on function public.rpc_registrar_pago_pedido_v2(bigint,uuid,numeric,text,numeric,uuid) to authenticated;
comment on function public.rpc_registrar_pago_pedido_v2(bigint,uuid,numeric,text,numeric,uuid) is 'T09: N pagos autoritativos con locks sesión-pedido-mesa, saldo, propina e idempotencia.';
notify pgrst,'reload schema';
commit;
