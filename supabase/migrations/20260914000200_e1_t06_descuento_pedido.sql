begin;

create table public.descuento_pedido (
  id uuid not null default gen_random_uuid(),
  pedido_id bigint not null,
  local_id uuid not null,
  tipo text not null,
  valor_solicitado numeric(14,4) not null,
  motivo text not null,
  estado text not null default 'PENDIENTE',
  solicitado_por uuid not null default auth.uid(),
  solicitado_en timestamptz not null default now(),
  solicitud_idempotency_key uuid not null,
  decidido_por uuid null,
  decidido_en timestamptz null,
  decision_idempotency_key uuid null,
  motivo_decision text null,
  subtotal_base numeric(14,2) null,
  importe_aplicado numeric(14,2) null,
  total_neto numeric(14,2) null,
  constraint pk_descuento_pedido primary key (id),
  constraint uq_descuento_pedido_pedido unique (pedido_id),
  constraint uq_descuento_pedido_solicitud unique (pedido_id, solicitado_por, solicitud_idempotency_key),
  constraint ck_descuento_pedido_tipo check (tipo in ('IMPORTE', 'PORCENTAJE')),
  constraint ck_descuento_pedido_valor check (
    valor_solicitado > 0 and valor_solicitado <> 'NaN'::numeric
      and valor_solicitado < 1000000000000
  ),
  constraint ck_descuento_pedido_motivo check (btrim(motivo) <> ''),
  constraint ck_descuento_pedido_estado check (estado in ('PENDIENTE', 'AUTORIZADO', 'RECHAZADO')),
  constraint ck_descuento_pedido_decision check (
    (estado = 'PENDIENTE' and decidido_por is null and decidido_en is null
      and decision_idempotency_key is null and motivo_decision is null
      and subtotal_base is null and importe_aplicado is null and total_neto is null)
    or
    (estado = 'AUTORIZADO' and decidido_por is not null and decidido_en is not null
      and decision_idempotency_key is not null
      and subtotal_base > 0 and importe_aplicado > 0
      and total_neto >= 0 and total_neto = subtotal_base - importe_aplicado)
    or
    (estado = 'RECHAZADO' and decidido_por is not null and decidido_en is not null
      and decision_idempotency_key is not null
      and motivo_decision is not null and btrim(motivo_decision) <> ''
      and subtotal_base is null and importe_aplicado is null and total_neto is null)
  ),
  constraint fk_descuento_pedido_pedido foreign key (pedido_id)
    references public.pedido (id) on delete restrict,
  constraint fk_descuento_pedido_local foreign key (local_id)
    references public.local (id) on delete restrict,
  constraint fk_descuento_pedido_solicitante foreign key (solicitado_por)
    references public.perfil_usuario (id) on delete restrict,
  constraint fk_descuento_pedido_decisor foreign key (decidido_por)
    references public.perfil_usuario (id) on delete restrict
);
create unique index uq_descuento_pedido_decision
  on public.descuento_pedido (pedido_id, decidido_por, decision_idempotency_key)
  where decision_idempotency_key is not null;
create index idx_descuento_pedido_local_estado
  on public.descuento_pedido (local_id, estado, solicitado_en desc);

create function public.tgf_descuento_pedido_historia()
returns trigger language plpgsql set search_path=pg_catalog as $$
begin
  if tg_op='DELETE' then
    raise exception using errcode='23514',message='El descuento no se elimina';
  end if;
  if old.estado<>'PENDIENTE' or new.estado not in ('AUTORIZADO','RECHAZADO')
    or row(new.id,new.pedido_id,new.local_id,new.tipo,new.valor_solicitado,new.motivo,
      new.solicitado_por,new.solicitado_en,new.solicitud_idempotency_key)
      is distinct from
      row(old.id,old.pedido_id,old.local_id,old.tipo,old.valor_solicitado,old.motivo,
      old.solicitado_por,old.solicitado_en,old.solicitud_idempotency_key) then
    raise exception using errcode='23514',message='El snapshot de descuento es inmutable';
  end if;
  return new;
end $$;
alter function public.tgf_descuento_pedido_historia() owner to postgres;
revoke all on function public.tgf_descuento_pedido_historia() from public,anon,authenticated,service_role;
create trigger trg_descuento_pedido_before_write
  before update or delete on public.descuento_pedido
  for each row execute function public.tgf_descuento_pedido_historia();

-- Amplía únicamente el catálogo de auditoría requerido por T06.
alter table public.auditoria_caja
  drop constraint ck_auditoria_caja_t05,
  alter column caja_id drop not null,
  alter column sesion_caja_id drop not null,
  add column pedido_id bigint null,
  add column descuento_pedido_id uuid null,
  add column solicitante_id uuid null,
  add column autorizador_id uuid null,
  add column tipo_descuento text null,
  add column valor_solicitado numeric(14,4) null,
  add column subtotal numeric(14,2) null,
  add column descuento numeric(14,2) null,
  add column total_neto numeric(14,2) null,
  add constraint fk_auditoria_caja_pedido foreign key (pedido_id)
    references public.pedido(id) on delete restrict,
  add constraint fk_auditoria_caja_descuento foreign key (descuento_pedido_id)
    references public.descuento_pedido(id) on delete restrict,
  add constraint fk_auditoria_caja_solicitante foreign key (solicitante_id)
    references public.perfil_usuario(id) on delete restrict,
  add constraint fk_auditoria_caja_autorizador foreign key (autorizador_id)
    references public.perfil_usuario(id) on delete restrict,
  add constraint ck_auditoria_caja_t06 check (
    (tipo='APERTURA' and caja_id is not null and sesion_caja_id is not null
      and movimiento_caja_id is null and monto_inicial is not null
      and monto_inicial>=0 and monto_inicial<>'NaN'::numeric and importe is null
      and tipo_movimiento is null and efectivo_esperado is null and efectivo_contado is null
      and diferencia is null and motivo is null and estado_anterior is null and estado_nuevo='ABIERTA'
      and pedido_id is null and descuento_pedido_id is null)
    or
    (tipo in ('ENTRADA','SALIDA') and caja_id is not null and sesion_caja_id is not null
      and movimiento_caja_id is not null and monto_inicial is null
      and importe>0 and tipo_movimiento=tipo and efectivo_esperado is null and efectivo_contado is null
      and diferencia is null and motivo is not null and btrim(motivo)<>''
      and estado_anterior='ABIERTA' and estado_nuevo='ABIERTA'
      and pedido_id is null and descuento_pedido_id is null)
    or
    (tipo in ('CIERRE','CIERRE_SUPERVISOR') and caja_id is not null and sesion_caja_id is not null
      and movimiento_caja_id is null and monto_inicial is null
      and importe is null and tipo_movimiento is null and efectivo_esperado is not null
      and efectivo_contado is not null and diferencia=efectivo_contado-efectivo_esperado
      and (diferencia=0 or (motivo is not null and btrim(motivo)<>''))
      and (tipo<>'CIERRE_SUPERVISOR' or (motivo is not null and btrim(motivo)<>''))
      and estado_anterior='ABIERTA' and estado_nuevo='CERRADA'
      and pedido_id is null and descuento_pedido_id is null)
    or
    (tipo='SOLICITUD_DESCUENTO' and caja_id is null and sesion_caja_id is null
      and pedido_id is not null and descuento_pedido_id is not null
      and solicitante_id=actor_id and autorizador_id is null and tipo_descuento in ('IMPORTE','PORCENTAJE')
      and valor_solicitado>0 and motivo is not null and btrim(motivo)<>''
      and subtotal is null and descuento is null and total_neto is null
      and estado_anterior is null and estado_nuevo='PENDIENTE')
    or
    (tipo='AUTORIZACION_DESCUENTO' and caja_id is null and sesion_caja_id is null
      and pedido_id is not null and descuento_pedido_id is not null
      and solicitante_id is not null and autorizador_id=actor_id
      and tipo_descuento in ('IMPORTE','PORCENTAJE') and valor_solicitado>0
      and subtotal>0 and descuento>0 and total_neto=subtotal-descuento
      and estado_anterior='PENDIENTE' and estado_nuevo='AUTORIZADO')
    or
    (tipo='RECHAZO_DESCUENTO' and caja_id is null and sesion_caja_id is null
      and pedido_id is not null and descuento_pedido_id is not null
      and solicitante_id is not null and autorizador_id=actor_id
      and tipo_descuento in ('IMPORTE','PORCENTAJE') and valor_solicitado>0
      and motivo is not null and btrim(motivo)<>''
      and subtotal is null and descuento is null and total_neto is null
      and estado_anterior='PENDIENTE' and estado_nuevo='RECHAZADO')
  );
create unique index uq_auditoria_caja_descuento_tipo
  on public.auditoria_caja(descuento_pedido_id,tipo)
  where descuento_pedido_id is not null;

create function public.fn_resolver_total_pedido(p_pedido_id bigint)
returns table(subtotal numeric,descuento numeric,total_neto numeric)
language sql stable security definer set search_path=pg_catalog as $$
  with total as (
    select coalesce(sum(d.cantidad*d.precio_unitario),0)::numeric as subtotal
    from public.detalle_pedido d where d.pedido_id=p_pedido_id
  ), vigente as (
    select dp.importe_aplicado,dp.total_neto from public.descuento_pedido dp
    where dp.pedido_id=p_pedido_id and dp.estado='AUTORIZADO'
  )
  select total.subtotal,coalesce(vigente.importe_aplicado,0),
    coalesce(vigente.total_neto,total.subtotal)
  from total left join vigente on true;
$$;
alter function public.fn_resolver_total_pedido(bigint) owner to postgres;
revoke all on function public.fn_resolver_total_pedido(bigint) from public,anon,authenticated,service_role;

create function public.rpc_solicitar_descuento_pedido(
  p_pedido_id bigint,p_importe numeric,p_porcentaje numeric,p_motivo text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare
  v_actor uuid:=auth.uid();v_local uuid;v_rol text;v_pedido public.pedido%rowtype;
  v_descuento public.descuento_pedido%rowtype;v_tipo text;v_valor numeric;v_subtotal numeric;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode='42501',message='No autorizado para solicitar descuentos';
  end if;
  if p_pedido_id is null or p_idempotency_key is null or p_motivo is null or btrim(p_motivo)=''
    or (p_importe is null)=(p_porcentaje is null) then
    raise exception using errcode='22023',message='Solicitud de descuento inválida';
  end if;
  v_tipo:=case when p_importe is not null then 'IMPORTE' else 'PORCENTAJE' end;
  v_valor:=coalesce(p_importe,p_porcentaje);
  if v_valor<=0 or v_valor='NaN'::numeric or v_valor>=1000000000000
    or (v_tipo='IMPORTE' and v_valor<>round(v_valor,2))
    or (v_tipo='PORCENTAJE' and (v_valor>100 or v_valor<>round(v_valor,4))) then
    raise exception using errcode='22023',message='Valor de descuento inválido';
  end if;
  select p.* into v_pedido from public.pedido p
    where p.id=p_pedido_id and p.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Pedido no disponible';end if;
  select d.* into v_descuento from public.descuento_pedido d where d.pedido_id=v_pedido.id for update;
  if found then
    if v_descuento.solicitado_por=v_actor and v_descuento.solicitud_idempotency_key=p_idempotency_key
      and v_descuento.tipo=v_tipo and v_descuento.valor_solicitado=v_valor
      and v_descuento.motivo=btrim(p_motivo) then
      return to_jsonb(v_descuento)-'solicitud_idempotency_key'-'decision_idempotency_key';
    end if;
    raise exception using errcode='40001',message='El pedido ya tiene una solicitud de descuento';
  end if;
  if v_pedido.estado is distinct from 'ENTREGADO' or exists(select 1 from public.pago p where p.pedido_id=v_pedido.id) then
    raise exception using errcode='40001',message='El pedido no admite descuento';
  end if;
  select r.subtotal into v_subtotal from public.fn_resolver_total_pedido(v_pedido.id) r;
  if v_subtotal<=0 or (v_tipo='IMPORTE' and v_valor>v_subtotal) then
    raise exception using errcode='22023',message='El descuento excede el subtotal';
  end if;
  insert into public.descuento_pedido(pedido_id,local_id,tipo,valor_solicitado,motivo,
    solicitado_por,solicitud_idempotency_key)
  values(v_pedido.id,v_local,v_tipo,v_valor,btrim(p_motivo),v_actor,p_idempotency_key)
  returning * into v_descuento;
  insert into public.auditoria_caja(tipo,local_id,caja_id,sesion_caja_id,actor_id,creado_en,
    monto_inicial,estado_anterior,estado_nuevo,pedido_id,descuento_pedido_id,solicitante_id,
    tipo_descuento,valor_solicitado,motivo)
  values('SOLICITUD_DESCUENTO',v_local,null,null,v_actor,v_descuento.solicitado_en,
    null,null,'PENDIENTE',v_pedido.id,v_descuento.id,v_actor,v_tipo,v_valor,v_descuento.motivo
  );
  return to_jsonb(v_descuento)-'solicitud_idempotency_key'-'decision_idempotency_key';
end $$;

create function public.rpc_decidir_descuento_pedido(
  p_pedido_id bigint,p_decision text,p_motivo_decision text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare
  v_actor uuid:=auth.uid();v_local uuid;v_rol text;v_pedido public.pedido%rowtype;
  v_descuento public.descuento_pedido%rowtype;v_subtotal numeric;v_aplicado numeric;v_neto numeric;
  v_estado text;v_evento text;v_motivo text:=nullif(btrim(p_motivo_decision),'');
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then
    raise exception using errcode='42501',message='No autorizado para decidir descuentos';
  end if;
  if p_pedido_id is null or p_idempotency_key is null or p_decision not in ('AUTORIZAR','RECHAZAR')
    or (p_decision='RECHAZAR' and v_motivo is null) then
    raise exception using errcode='22023',message='Decisión de descuento inválida';
  end if;
  v_estado:=case when p_decision='AUTORIZAR' then 'AUTORIZADO' else 'RECHAZADO' end;
  v_evento:=case when p_decision='AUTORIZAR' then 'AUTORIZACION_DESCUENTO' else 'RECHAZO_DESCUENTO' end;
  select p.* into v_pedido from public.pedido p
    where p.id=p_pedido_id and p.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Pedido no disponible';end if;
  select d.* into v_descuento from public.descuento_pedido d
    where d.pedido_id=v_pedido.id and d.local_id=v_local for update;
  if not found then raise exception using errcode='40001',message='No existe solicitud de descuento';end if;
  if v_descuento.estado<>'PENDIENTE' then
    if v_descuento.estado=v_estado and v_descuento.decidido_por=v_actor
      and v_descuento.decision_idempotency_key=p_idempotency_key
      and v_descuento.motivo_decision is not distinct from v_motivo then
      return to_jsonb(v_descuento)-'solicitud_idempotency_key'-'decision_idempotency_key';
    end if;
    raise exception using errcode='40001',message='La solicitud ya fue decidida';
  end if;
  if v_pedido.estado is distinct from 'ENTREGADO' or exists(select 1 from public.pago p where p.pedido_id=v_pedido.id) then
    raise exception using errcode='40001',message='El pedido ya no admite descuento';
  end if;
  if p_decision='AUTORIZAR' then
    select r.subtotal into v_subtotal from public.fn_resolver_total_pedido(v_pedido.id) r;
    v_aplicado:=case when v_descuento.tipo='IMPORTE' then v_descuento.valor_solicitado
      else round(v_subtotal*v_descuento.valor_solicitado/100,2) end;
    if v_subtotal<=0 or v_aplicado<=0 or v_aplicado>v_subtotal then
      raise exception using errcode='22023',message='El descuento excede el subtotal';
    end if;
    v_neto:=v_subtotal-v_aplicado;
  end if;
  update public.descuento_pedido d set estado=v_estado,decidido_por=v_actor,
    decidido_en=clock_timestamp(),decision_idempotency_key=p_idempotency_key,
    motivo_decision=v_motivo,subtotal_base=v_subtotal,importe_aplicado=v_aplicado,total_neto=v_neto
  where d.id=v_descuento.id returning * into v_descuento;
  insert into public.auditoria_caja(tipo,local_id,caja_id,sesion_caja_id,actor_id,creado_en,
    monto_inicial,estado_anterior,estado_nuevo,pedido_id,descuento_pedido_id,solicitante_id,
    autorizador_id,tipo_descuento,valor_solicitado,subtotal,descuento,total_neto,motivo)
  values(v_evento,v_local,null,null,v_actor,v_descuento.decidido_en,null,'PENDIENTE',v_estado,
    v_pedido.id,v_descuento.id,v_descuento.solicitado_por,v_actor,v_descuento.tipo,
    v_descuento.valor_solicitado,v_subtotal,v_aplicado,v_neto,
    case when p_decision='RECHAZAR' then v_motivo else null end
  );
  return to_jsonb(v_descuento)-'solicitud_idempotency_key'-'decision_idempotency_key';
end $$;

-- T06 adapta sólo el importe total de la RPC provisional T08. Su orden actual
-- caja -> sesión -> pedido -> mesa se conserva; T09 debe adoptar definitivamente
-- sesión -> pedido -> mesa conforme al pendiente explícito de construcción.
create or replace function public.rpc_registrar_pago_total_pedido(
  p_pedido_id bigint,p_sesion_caja_id uuid,p_medio text,p_propina numeric,p_idempotency_key uuid
)
returns table(pago_id bigint,pedido_id bigint,pedido_estado text,mesa_id uuid,mesa_estado text,
  importe numeric,propina numeric,medio text,sesion_caja_id uuid,pagado_en timestamptz)
language plpgsql security definer set search_path=pg_catalog as $$
declare
  v_actor uuid:=auth.uid();v_local uuid;v_rol text;v_caja_id uuid;
  v_sesion public.sesion_caja%rowtype;v_pedido public.pedido%rowtype;v_mesa public.mesa%rowtype;
  v_importe public.pago.importe%type;v_pago public.pago%rowtype;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then raise exception using errcode='42501',message='No autorizado para registrar pagos';end if;
  if p_pedido_id is null or p_sesion_caja_id is null or p_idempotency_key is null then raise exception using errcode='22023',message='Pedido, sesión y clave de solicitud son obligatorios';end if;
  if p_medio is null or p_medio not in ('EFECTIVO','YAPE','PLIN','TARJETA') then raise exception using errcode='22023',message='Medio de pago inválido';end if;
  if p_propina is null or p_propina<0 or p_propina>=100000000 or p_propina<>round(p_propina,2) then raise exception using errcode='22023',message='Propina inválida';end if;
  select s.caja_id into v_caja_id from public.sesion_caja s where s.id=p_sesion_caja_id and s.local_id=v_local;
  if v_caja_id is null then raise exception using errcode='42501',message='Sesión no disponible para el usuario autenticado';end if;
  perform 1 from public.caja c where c.id=v_caja_id and c.local_id=v_local and c.activo for update;
  if not found then raise exception using errcode='42501',message='Caja no disponible para el usuario autenticado';end if;
  select s.* into strict v_sesion from public.sesion_caja s where s.id=p_sesion_caja_id and s.caja_id=v_caja_id and s.local_id=v_local for update;
  select p.* into v_pago from public.pago p where p.sesion_caja_id=v_sesion.id and p.usuario_id=v_actor and p.idempotency_key=p_idempotency_key for update;
  if found then
    if v_pago.pedido_id<>p_pedido_id or v_pago.medio<>p_medio or v_pago.propina<>p_propina then raise exception using errcode='22023',message='Clave de solicitud reutilizada con otros datos';end if;
    select p.* into strict v_pedido from public.pedido p where p.id=v_pago.pedido_id;
    return query select v_pago.id,v_pago.pedido_id,'PAGADO'::text,v_pedido.mesa_id,'LIBRE'::text,v_pago.importe,v_pago.propina,v_pago.medio,v_pago.sesion_caja_id,v_pago.pagado_en;return;
  end if;
  if v_sesion.estado is distinct from 'ABIERTA' then raise exception using errcode='40001',message='La sesión de caja ya no está abierta';end if;
  select p.* into v_pedido from public.pedido p where p.id=p_pedido_id and p.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Pedido no disponible para el usuario autenticado';end if;
  if v_pedido.estado is distinct from 'ENTREGADO' then raise exception using errcode='40001',message='El pedido ya no está disponible para cobro';end if;
  select m.* into v_mesa from public.mesa m where m.id=v_pedido.mesa_id and m.local_id=v_local and m.activo for update;
  if not found then raise exception using errcode='42501',message='Mesa no disponible para el usuario autenticado';end if;
  if v_mesa.estado is distinct from 'PENDIENTE_PAGO' then raise exception using errcode='40001',message='La mesa ya no está pendiente de pago';end if;
  select r.total_neto into v_importe from public.fn_resolver_total_pedido(v_pedido.id) r;
  if v_importe is null or v_importe<=0 then raise exception using errcode='55000',message='El pedido no tiene un importe positivo para cobrar';end if;
  insert into public.pago(pedido_id,importe,medio,usuario_id,sesion_caja_id,propina,idempotency_key)
  values(v_pedido.id,v_importe,p_medio,v_actor,v_sesion.id,p_propina,p_idempotency_key) returning * into strict v_pago;
  update public.pedido p set estado='PAGADO' where p.id=v_pedido.id and p.estado='ENTREGADO';
  if not found then raise exception using errcode='40001',message='El pedido cambió durante el cobro';end if;
  insert into public.historial_estado(pedido_id,estado_anterior,estado_nuevo,usuario_id) values(v_pedido.id,'ENTREGADO','PAGADO',v_actor);
  update public.mesa m set estado='LIBRE' where m.id=v_mesa.id and m.local_id=v_local and m.estado='PENDIENTE_PAGO';
  if not found then raise exception using errcode='40001',message='La mesa cambió durante el cobro';end if;
  return query select v_pago.id,v_pedido.id,'PAGADO'::text,v_mesa.id,'LIBRE'::text,v_pago.importe,v_pago.propina,v_pago.medio,v_pago.sesion_caja_id,v_pago.pagado_en;
end $$;

alter function public.rpc_solicitar_descuento_pedido(bigint,numeric,numeric,text,uuid) owner to postgres;
alter function public.rpc_decidir_descuento_pedido(bigint,text,text,uuid) owner to postgres;
alter function public.rpc_registrar_pago_total_pedido(bigint,uuid,text,numeric,uuid) owner to postgres;
revoke all on function public.rpc_solicitar_descuento_pedido(bigint,numeric,numeric,text,uuid),
  public.rpc_decidir_descuento_pedido(bigint,text,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.rpc_solicitar_descuento_pedido(bigint,numeric,numeric,text,uuid),
  public.rpc_decidir_descuento_pedido(bigint,text,text,uuid) to authenticated;

alter table public.descuento_pedido enable row level security;
revoke all on public.descuento_pedido from public,anon,authenticated,service_role;
grant select on public.descuento_pedido to authenticated;
create policy pol_descuento_pedido_select_local on public.descuento_pedido
  for select to authenticated using(exists(select 1 from public.obtener_contexto_autenticado() c
    where c.local_id=descuento_pedido.local_id and c.rol_codigo in ('CAJA','ADMINISTRADOR')));

comment on table public.descuento_pedido is 'Snapshot único autoritativo del descuento a nivel pedido; solicitud CAJA y decisión ADMINISTRADOR, sin infraestructura genérica.';
comment on function public.fn_resolver_total_pedido(bigint) is 'Autoridad DT-01: subtotal de detalles, descuento AUTORIZADO y total neto; pedido no duplica snapshots.';
comment on function public.rpc_solicitar_descuento_pedido(bigint,numeric,numeric,text,uuid) is 'CAJA solicita exactamente IMPORTE o PORCENTAJE sobre pedido ENTREGADO sin pagos, con motivo e idempotencia.';
comment on function public.rpc_decidir_descuento_pedido(bigint,text,text,uuid) is 'ADMINISTRADOR autoriza o rechaza; recalcula snapshot al decidir y bloquea pedido frente al cobro.';
comment on function public.rpc_registrar_pago_total_pedido(bigint,uuid,text,numeric,uuid) is 'T06: cobro total provisional consume DT-01 y mantiene el orden de locks T08; T09 debe adoptar sesión-pedido-mesa y pagos N/parciales.';

notify pgrst,'reload schema';
commit;
