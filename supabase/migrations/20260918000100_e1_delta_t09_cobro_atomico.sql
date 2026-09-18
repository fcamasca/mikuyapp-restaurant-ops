begin;

create table public.cobro (
  id uuid not null default gen_random_uuid(),
  pedido_id bigint not null,
  sesion_caja_id uuid not null,
  local_id uuid not null,
  actor_id uuid not null,
  tipo text not null,
  total_aplicado numeric(14,2) not null,
  propina_total numeric(14,2) not null default 0,
  saldo_anterior numeric(14,2) not null,
  saldo_posterior numeric(14,2) not null,
  idempotency_key uuid not null,
  cobrado_en timestamptz not null default now(),
  constraint pk_cobro primary key(id),
  constraint uq_cobro_actor_idempotencia unique(sesion_caja_id,actor_id,idempotency_key),
  constraint ck_cobro_tipo check(tipo in('TOTAL','PARCIAL')),
  constraint ck_cobro_montos check(
    total_aplicado>0 and total_aplicado<1000000000000 and total_aplicado=round(total_aplicado,2)
    and propina_total>=0 and propina_total<100000000 and propina_total=round(propina_total,2)
    and saldo_anterior>0 and saldo_posterior>=0
    and saldo_posterior=saldo_anterior-total_aplicado
    and ((tipo='TOTAL' and saldo_posterior=0) or (tipo='PARCIAL' and saldo_posterior>0))
  ),
  constraint fk_cobro_pedido foreign key(pedido_id) references public.pedido(id) on delete restrict,
  constraint fk_cobro_sesion foreign key(sesion_caja_id) references public.sesion_caja(id) on delete restrict,
  constraint fk_cobro_local foreign key(local_id) references public.local(id) on delete restrict,
  constraint fk_cobro_actor foreign key(actor_id) references public.perfil_usuario(id) on delete restrict
);
create index idx_cobro_pedido_en on public.cobro(pedido_id,cobrado_en,id);
create index idx_cobro_sesion_en on public.cobro(sesion_caja_id,cobrado_en,id);

alter table public.pago
  add column cobro_id uuid null,
  add column orden smallint null,
  add constraint fk_pago_cobro foreign key(cobro_id) references public.cobro(id) on delete restrict,
  add constraint ck_pago_cobro_orden check(
    (cobro_id is null and orden is null) or (cobro_id is not null and orden>0)
  );
create unique index uq_pago_cobro_orden on public.pago(cobro_id,orden) where cobro_id is not null;
create index idx_pago_cobro on public.pago(cobro_id) where cobro_id is not null;

alter table public.auditoria_caja
  add column cobro_id uuid null,
  add column medios jsonb null,
  add constraint fk_auditoria_caja_cobro foreign key(cobro_id) references public.cobro(id) on delete restrict,
  add constraint ck_auditoria_caja_cobro_pago check(
    tipo<>'PAGO' or cobro_id is not null or medios is null
  ),
  add constraint ck_auditoria_caja_medios check(
    (tipo='PAGO' and cobro_id is null and medios is null)
    or (tipo='PAGO' and cobro_id is not null and medios is not null and jsonb_typeof(medios)='array' and jsonb_array_length(medios)>0)
    or (tipo<>'PAGO' and medios is null)
  );
create unique index uq_auditoria_caja_cobro on public.auditoria_caja(cobro_id) where cobro_id is not null;

alter table public.cobro enable row level security;
revoke all on public.cobro from public,anon,authenticated,service_role;
grant select on public.cobro to authenticated;
create policy pol_cobro_select_caja_local on public.cobro for select to authenticated using(
  exists(select 1 from public.obtener_contexto_autenticado() c
    where c.local_id=cobro.local_id and c.rol_codigo in('CAJA','ADMINISTRADOR'))
);

create function public.tgf_cobro_pago_inmutable() returns trigger
language plpgsql set search_path=pg_catalog as $$
begin
  raise exception using errcode='23514',message='Los cobros y medios confirmados son inmutables';
end $$;
create trigger trg_cobro_inmutable before update or delete on public.cobro
for each row execute function public.tgf_cobro_pago_inmutable();

create function public.rpc_registrar_cobro_pedido(
  p_pedido_id bigint,p_sesion_caja_id uuid,p_tipo_cobro text,
  p_medios jsonb,p_idempotency_key uuid
)
returns table(
  cobro_id uuid,pedido_id bigint,pedido_estado text,mesa_id uuid,mesa_estado text,
  tipo_cobro text,total_aplicado numeric,propina_total numeric,sesion_caja_id uuid,
  cobrado_en timestamptz,subtotal numeric,descuento numeric,total_neto numeric,
  ya_pagado numeric,saldo_anterior numeric,saldo_posterior numeric,medios jsonb
)
language plpgsql security definer set search_path=pg_catalog as $$
declare
  v_actor uuid:=auth.uid();v_local uuid;v_rol text;v_sesion public.sesion_caja%rowtype;
  v_pedido public.pedido%rowtype;v_mesa public.mesa%rowtype;v_cobro public.cobro%rowtype;
  v_subtotal numeric;v_descuento numeric;v_neto numeric;v_pagado numeric;v_saldo numeric;
  v_total numeric:=0;v_propina_total numeric:=0;v_item jsonb;v_medio text;v_importe numeric;
  v_propina numeric;v_orden int:=0;v_medios_normalizados jsonb:='[]'::jsonb;
  v_medios_solicitados jsonb;v_primer_pago public.pago%rowtype;
  v_estado_pedido text;v_estado_mesa text;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'CAJA' then
    raise exception using errcode='42501',message='No autorizado para registrar cobros';
  end if;
  if p_pedido_id is null or p_sesion_caja_id is null or p_idempotency_key is null
    or p_tipo_cobro not in('TOTAL','PARCIAL') then
    raise exception using errcode='22023',message='Pedido, sesión, tipo y clave son obligatorios';
  end if;
  if p_medios is null or jsonb_typeof(p_medios)<>'array' or jsonb_array_length(p_medios)<1
    or jsonb_array_length(p_medios)>20 then
    raise exception using errcode='22023',message='La lista de medios es inválida';
  end if;

  -- Orden definitivo: sesión -> pedido -> mesa.
  select s.* into v_sesion from public.sesion_caja s
    where s.id=p_sesion_caja_id and s.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Sesión no disponible';end if;

  select c.* into v_cobro from public.cobro c
    where c.sesion_caja_id=v_sesion.id and c.actor_id=v_actor and c.idempotency_key=p_idempotency_key;
  if found then
    begin
      select jsonb_agg(jsonb_build_object('medio',x.value->>'medio','importe',(x.value->>'importe')::numeric,
        'propina',coalesce((x.value->>'propina')::numeric,0)) order by x.ord)
      into v_medios_solicitados from jsonb_array_elements(p_medios) with ordinality x(value,ord);
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception using errcode='22023',message='Clave reutilizada con otros datos';
    end;
    select coalesce(jsonb_agg(jsonb_build_object('pago_id',p.id,'orden',p.orden,'medio',p.medio,'importe',p.importe,'propina',p.propina) order by p.orden),'[]'::jsonb)
      into v_medios_normalizados from public.pago p where p.cobro_id=v_cobro.id;
    if v_cobro.pedido_id<>p_pedido_id or v_cobro.tipo<>p_tipo_cobro or v_medios_solicitados <>
      (select jsonb_agg(jsonb_build_object('medio',x->>'medio','importe',(x->>'importe')::numeric,
        'propina',(x->>'propina')::numeric) order by (x->>'orden')::int) from jsonb_array_elements(v_medios_normalizados)x) then
      raise exception using errcode='22023',message='Clave reutilizada con otros datos';
    end if;
    select p.* into strict v_pedido from public.pedido p where p.id=v_cobro.pedido_id;
    select m.* into strict v_mesa from public.mesa m where m.id=v_pedido.mesa_id;
    select r.subtotal,r.descuento,r.total_neto into v_subtotal,v_descuento,v_neto from public.fn_resolver_total_pedido(v_pedido.id)r;
    return query select v_cobro.id,v_cobro.pedido_id,v_pedido.estado,v_mesa.id,v_mesa.estado,v_cobro.tipo,
      v_cobro.total_aplicado,v_cobro.propina_total,v_cobro.sesion_caja_id,v_cobro.cobrado_en,
      v_subtotal,v_descuento,v_neto,v_neto-v_cobro.saldo_posterior,v_cobro.saldo_anterior,v_cobro.saldo_posterior,v_medios_normalizados;
    return;
  end if;

  if v_sesion.estado<>'ABIERTA' then raise exception using errcode='40001',message='La sesión ya no está abierta';end if;
  if not exists(select 1 from public.caja c where c.id=v_sesion.caja_id and c.local_id=v_local and c.activo) then
    raise exception using errcode='42501',message='Caja no disponible';
  end if;
  select p.* into v_pedido from public.pedido p where p.id=p_pedido_id and p.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Pedido no disponible';end if;
  select m.* into v_mesa from public.mesa m where m.id=v_pedido.mesa_id and m.local_id=v_local and m.activo for update;
  if not found then raise exception using errcode='42501',message='Mesa no disponible';end if;
  if v_pedido.estado<>'ENTREGADO' or v_mesa.estado<>'PENDIENTE_PAGO'
    or exists(select 1 from public.anulacion_pedido a where a.pedido_id=v_pedido.id) then
    raise exception using errcode='40001',message='Pedido no disponible para cobro';
  end if;
  select r.subtotal,r.descuento,r.total_neto into v_subtotal,v_descuento,v_neto from public.fn_resolver_total_pedido(v_pedido.id)r;
  select coalesce(sum(p.importe),0) into v_pagado from public.pago p where p.pedido_id=v_pedido.id;
  v_saldo:=v_neto-v_pagado;
  if v_saldo<=0 then raise exception using errcode='40001',message='El pedido ya no tiene saldo';end if;

  for v_item in select value from jsonb_array_elements(p_medios) loop
    if jsonb_typeof(v_item)<>'object' or (v_item-'medio'-'importe'-'propina')<>'{}'::jsonb then
      raise exception using errcode='22023',message='Línea de medio inválida';
    end if;
    begin
      v_medio:=v_item->>'medio';v_importe:=(v_item->>'importe')::numeric;
      v_propina:=coalesce((v_item->>'propina')::numeric,0);
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception using errcode='22023',message='Importe o propina inválidos';
    end;
    if v_medio not in('EFECTIVO','YAPE','PLIN','TARJETA') or v_importe is null or v_importe<=0
      or v_importe='NaN'::numeric or v_importe>=1000000000000 or v_importe<>round(v_importe,2)
      or v_propina<0 or v_propina='NaN'::numeric or v_propina>=100000000 or v_propina<>round(v_propina,2) then
      raise exception using errcode='22023',message='Medio, importe o propina inválidos';
    end if;
    v_total:=v_total+v_importe;v_propina_total:=v_propina_total+v_propina;
    v_medios_normalizados:=v_medios_normalizados||jsonb_build_array(jsonb_build_object(
      'orden',v_orden+1,'medio',v_medio,'importe',v_importe,'propina',v_propina));
    v_orden:=v_orden+1;
  end loop;
  if (p_tipo_cobro='TOTAL' and v_total<>v_saldo)
    or (p_tipo_cobro='PARCIAL' and (v_total<=0 or v_total>=v_saldo)) then
    raise exception using errcode='22023',message='La suma de medios no coincide con el tipo y saldo del cobro';
  end if;

  insert into public.cobro(pedido_id,sesion_caja_id,local_id,actor_id,tipo,total_aplicado,propina_total,
    saldo_anterior,saldo_posterior,idempotency_key)
  values(v_pedido.id,v_sesion.id,v_local,v_actor,p_tipo_cobro,v_total,v_propina_total,v_saldo,v_saldo-v_total,p_idempotency_key)
  returning * into v_cobro;
  v_orden:=0;v_medios_normalizados:='[]'::jsonb;
  for v_item in select value from jsonb_array_elements(p_medios) loop
    v_orden:=v_orden+1;v_medio:=v_item->>'medio';v_importe:=(v_item->>'importe')::numeric;v_propina:=coalesce((v_item->>'propina')::numeric,0);
    insert into public.pago(pedido_id,importe,medio,usuario_id,sesion_caja_id,propina,idempotency_key,cobro_id,orden)
    values(v_pedido.id,v_importe,v_medio,v_actor,v_sesion.id,v_propina,
      md5(v_cobro.id::text||':'||v_orden::text)::uuid,v_cobro.id,v_orden)
    returning * into v_primer_pago;
    v_medios_normalizados:=v_medios_normalizados||jsonb_build_array(jsonb_build_object(
      'pago_id',v_primer_pago.id,'orden',v_orden,'medio',v_medio,'importe',v_importe,'propina',v_propina));
  end loop;
  v_estado_pedido:='ENTREGADO';v_estado_mesa:='PENDIENTE_PAGO';
  if v_cobro.saldo_posterior=0 then
    update public.pedido set estado='PAGADO' where id=v_pedido.id;
    insert into public.historial_estado(pedido_id,estado_anterior,estado_nuevo,usuario_id)
      values(v_pedido.id,'ENTREGADO','PAGADO',v_actor);
    update public.mesa set estado='LIBRE' where id=v_mesa.id;
    v_estado_pedido:='PAGADO';v_estado_mesa:='LIBRE';
  end if;
  select p.* into v_primer_pago from public.pago p where p.cobro_id=v_cobro.id order by p.orden limit 1;
  insert into public.auditoria_caja(tipo,local_id,caja_id,sesion_caja_id,actor_id,creado_en,monto_inicial,
    pedido_id,pago_id,importe,propina,medio_pago,subtotal,descuento,total_neto,saldo_anterior,saldo_nuevo,
    estado_anterior,estado_nuevo,cobro_id,medios)
  values('PAGO',v_local,v_sesion.caja_id,v_sesion.id,v_actor,v_cobro.cobrado_en,null,v_pedido.id,
    v_primer_pago.id,v_total,v_propina_total,v_primer_pago.medio,v_subtotal,v_descuento,v_neto,v_saldo,
    v_cobro.saldo_posterior,'ENTREGADO',v_estado_pedido,v_cobro.id,v_medios_normalizados);
  return query select v_cobro.id,v_pedido.id,v_estado_pedido,v_mesa.id,v_estado_mesa,v_cobro.tipo,
    v_total,v_propina_total,v_sesion.id,v_cobro.cobrado_en,v_subtotal,v_descuento,v_neto,
    v_pagado+v_total,v_saldo,v_cobro.saldo_posterior,v_medios_normalizados;
end $$;

-- Compatibilidad: todas las vías históricas escriben a través del nuevo acto de cobro.
create or replace function public.rpc_registrar_pago_pedido_v2(
  p_pedido_id bigint,p_sesion_caja_id uuid,p_importe_aplicar numeric,
  p_medio text,p_propina numeric,p_idempotency_key uuid
)
returns table(pago_id bigint,pedido_id bigint,pedido_estado text,mesa_id uuid,mesa_estado text,
  importe numeric,propina numeric,medio text,sesion_caja_id uuid,pagado_en timestamptz,
  subtotal numeric,descuento numeric,total_neto numeric,ya_pagado numeric,saldo numeric)
language plpgsql security definer set search_path=pg_catalog as $$
declare v_saldo numeric;v_tipo text;v_result record;v_linea jsonb;
begin
  select c.tipo into v_tipo from public.cobro c where c.sesion_caja_id=p_sesion_caja_id
    and c.actor_id=auth.uid() and c.idempotency_key=p_idempotency_key;
  select r.total_neto-coalesce((select sum(p.importe) from public.pago p where p.pedido_id=p_pedido_id),0)
    into v_saldo from public.fn_resolver_total_pedido(p_pedido_id)r;
  if v_tipo is null then v_tipo:=case when p_importe_aplicar=v_saldo then 'TOTAL' else 'PARCIAL' end;end if;
  select * into v_result from public.rpc_registrar_cobro_pedido(p_pedido_id,p_sesion_caja_id,v_tipo,
    jsonb_build_array(jsonb_build_object('medio',p_medio,'importe',p_importe_aplicar,'propina',p_propina)),p_idempotency_key);
  v_linea:=v_result.medios->0;
  return query select (v_linea->>'pago_id')::bigint,v_result.pedido_id,v_result.pedido_estado,v_result.mesa_id,
    v_result.mesa_estado,(v_linea->>'importe')::numeric,(v_linea->>'propina')::numeric,v_linea->>'medio',
    v_result.sesion_caja_id,v_result.cobrado_en,v_result.subtotal,v_result.descuento,v_result.total_neto,
    v_result.ya_pagado,v_result.saldo_posterior;
end $$;

create or replace function public.rpc_registrar_pago_total_pedido(
  p_pedido_id bigint,p_sesion_caja_id uuid,p_medio text,p_propina numeric,p_idempotency_key uuid
)
returns table(pago_id bigint,pedido_id bigint,pedido_estado text,mesa_id uuid,mesa_estado text,
  importe numeric,propina numeric,medio text,sesion_caja_id uuid,pagado_en timestamptz)
language sql security definer set search_path=pg_catalog as $$
  select r.pago_id,r.pedido_id,r.pedido_estado,r.mesa_id,r.mesa_estado,r.importe,r.propina,r.medio,r.sesion_caja_id,r.pagado_en
  from public.rpc_registrar_pago_pedido_v2(p_pedido_id,p_sesion_caja_id,
    (select x.total_neto-coalesce((select sum(p.importe) from public.pago p where p.pedido_id=p_pedido_id),0)
      from public.fn_resolver_total_pedido(p_pedido_id)x),p_medio,p_propina,p_idempotency_key)r
$$;

alter function public.rpc_registrar_cobro_pedido(bigint,uuid,text,jsonb,uuid) owner to postgres;
alter function public.rpc_registrar_pago_pedido_v2(bigint,uuid,numeric,text,numeric,uuid) owner to postgres;
alter function public.rpc_registrar_pago_total_pedido(bigint,uuid,text,numeric,uuid) owner to postgres;
alter function public.tgf_cobro_pago_inmutable() owner to postgres;
revoke all on function public.rpc_registrar_cobro_pedido(bigint,uuid,text,jsonb,uuid),
  public.rpc_registrar_pago_pedido_v2(bigint,uuid,numeric,text,numeric,uuid),
  public.rpc_registrar_pago_total_pedido(bigint,uuid,text,numeric,uuid),
  public.tgf_cobro_pago_inmutable() from public,anon,authenticated,service_role;
grant execute on function public.rpc_registrar_cobro_pedido(bigint,uuid,text,jsonb,uuid),
  public.rpc_registrar_pago_pedido_v2(bigint,uuid,numeric,text,numeric,uuid),
  public.rpc_registrar_pago_total_pedido(bigint,uuid,text,numeric,uuid) to authenticated;

comment on table public.cobro is 'E1 DT-02: acto atómico e idempotente que agrupa uno o más medios en pago; legacy no se backfillea.';
comment on function public.rpc_registrar_cobro_pedido(bigint,uuid,text,jsonb,uuid) is 'Registra TOTAL/PARCIAL con N medios en una transacción y locks sesión-pedido-mesa.';
notify pgrst,'reload schema';
commit;
