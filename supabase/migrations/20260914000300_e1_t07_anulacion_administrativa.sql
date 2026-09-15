begin;

create table public.anulacion_pedido (
  id uuid not null default gen_random_uuid(),
  pedido_id bigint not null,
  local_id uuid not null,
  mesa_id uuid not null,
  actor_id uuid not null default auth.uid(),
  motivo text not null,
  estado_anterior text not null,
  estado_nuevo text not null,
  mesa_estado_anterior text not null,
  mesa_estado_nuevo text not null,
  anulado_en timestamptz not null default clock_timestamp(),
  idempotency_key uuid not null,
  constraint pk_anulacion_pedido primary key(id),
  constraint uq_anulacion_pedido_pedido unique(pedido_id),
  constraint uq_anulacion_pedido_idempotencia unique(pedido_id,actor_id,idempotency_key),
  constraint ck_anulacion_pedido_motivo check(btrim(motivo)<>''),
  constraint ck_anulacion_pedido_estados check(
    estado_anterior in ('ABIERTO','ENVIADO','RECIBIDO_COCINA','EN_PREPARACION','LISTO','ENTREGADO')
      and estado_nuevo='ANULADO'
      and mesa_estado_anterior in ('LIBRE','OCUPADA','PEDIDO_LISTO','PENDIENTE_PAGO')
      and mesa_estado_nuevo='LIBRE'
  ),
  constraint fk_anulacion_pedido_pedido foreign key(pedido_id) references public.pedido(id) on delete restrict,
  constraint fk_anulacion_pedido_local foreign key(local_id) references public.local(id) on delete restrict,
  constraint fk_anulacion_pedido_mesa foreign key(mesa_id,local_id) references public.mesa(id,local_id) on delete restrict,
  constraint fk_anulacion_pedido_actor foreign key(actor_id) references public.perfil_usuario(id) on delete restrict
);
create index idx_anulacion_pedido_local_fecha on public.anulacion_pedido(local_id,anulado_en desc);

create function public.tgf_anulacion_pedido_inmutable()
returns trigger language plpgsql set search_path=pg_catalog as $$
begin raise exception using errcode='23514',message='La anulación es inmutable';end $$;
alter function public.tgf_anulacion_pedido_inmutable() owner to postgres;
revoke all on function public.tgf_anulacion_pedido_inmutable() from public,anon,authenticated,service_role;
create trigger trg_anulacion_pedido_before_write before update or delete on public.anulacion_pedido
  for each row execute function public.tgf_anulacion_pedido_inmutable();

alter table public.auditoria_caja
  drop constraint ck_auditoria_caja_t06,
  add column anulacion_pedido_id uuid null,
  add column mesa_estado_anterior text null,
  add column mesa_estado_nuevo text null,
  add constraint fk_auditoria_caja_anulacion foreign key(anulacion_pedido_id)
    references public.anulacion_pedido(id) on delete restrict,
  add constraint ck_auditoria_caja_t07 check (
    (tipo='APERTURA' and caja_id is not null and sesion_caja_id is not null
      and movimiento_caja_id is null and monto_inicial is not null
      and monto_inicial>=0 and monto_inicial<>'NaN'::numeric and importe is null
      and tipo_movimiento is null and efectivo_esperado is null and efectivo_contado is null
      and diferencia is null and motivo is null and estado_anterior is null and estado_nuevo='ABIERTA'
      and pedido_id is null and descuento_pedido_id is null and anulacion_pedido_id is null)
    or
    (tipo in ('ENTRADA','SALIDA') and caja_id is not null and sesion_caja_id is not null
      and movimiento_caja_id is not null and monto_inicial is null
      and importe>0 and tipo_movimiento=tipo and efectivo_esperado is null and efectivo_contado is null
      and diferencia is null and motivo is not null and btrim(motivo)<>''
      and estado_anterior='ABIERTA' and estado_nuevo='ABIERTA'
      and pedido_id is null and descuento_pedido_id is null and anulacion_pedido_id is null)
    or
    (tipo in ('CIERRE','CIERRE_SUPERVISOR') and caja_id is not null and sesion_caja_id is not null
      and movimiento_caja_id is null and monto_inicial is null
      and importe is null and tipo_movimiento is null and efectivo_esperado is not null
      and efectivo_contado is not null and diferencia=efectivo_contado-efectivo_esperado
      and (diferencia=0 or (motivo is not null and btrim(motivo)<>''))
      and (tipo<>'CIERRE_SUPERVISOR' or (motivo is not null and btrim(motivo)<>''))
      and estado_anterior='ABIERTA' and estado_nuevo='CERRADA'
      and pedido_id is null and descuento_pedido_id is null and anulacion_pedido_id is null)
    or
    (tipo='SOLICITUD_DESCUENTO' and caja_id is null and sesion_caja_id is null
      and pedido_id is not null and descuento_pedido_id is not null and anulacion_pedido_id is null
      and solicitante_id=actor_id and autorizador_id is null and tipo_descuento in ('IMPORTE','PORCENTAJE')
      and valor_solicitado>0 and motivo is not null and btrim(motivo)<>''
      and subtotal is null and descuento is null and total_neto is null
      and estado_anterior is null and estado_nuevo='PENDIENTE')
    or
    (tipo='AUTORIZACION_DESCUENTO' and caja_id is null and sesion_caja_id is null
      and pedido_id is not null and descuento_pedido_id is not null and anulacion_pedido_id is null
      and solicitante_id is not null and autorizador_id=actor_id
      and tipo_descuento in ('IMPORTE','PORCENTAJE') and valor_solicitado>0
      and subtotal>0 and descuento>0 and total_neto=subtotal-descuento
      and estado_anterior='PENDIENTE' and estado_nuevo='AUTORIZADO')
    or
    (tipo='RECHAZO_DESCUENTO' and caja_id is null and sesion_caja_id is null
      and pedido_id is not null and descuento_pedido_id is not null and anulacion_pedido_id is null
      and solicitante_id is not null and autorizador_id=actor_id
      and tipo_descuento in ('IMPORTE','PORCENTAJE') and valor_solicitado>0
      and motivo is not null and btrim(motivo)<>''
      and subtotal is null and descuento is null and total_neto is null
      and estado_anterior='PENDIENTE' and estado_nuevo='RECHAZADO')
    or
    (tipo='ANULACION' and caja_id is null and sesion_caja_id is null
      and pedido_id is not null and descuento_pedido_id is null and anulacion_pedido_id is not null
      and solicitante_id is null and autorizador_id is null
      and motivo is not null and btrim(motivo)<>''
      and estado_anterior in ('ABIERTO','ENVIADO','RECIBIDO_COCINA','EN_PREPARACION','LISTO','ENTREGADO')
      and estado_nuevo='ANULADO' and mesa_estado_anterior is not null and mesa_estado_nuevo='LIBRE')
  );
create unique index uq_auditoria_caja_anulacion
  on public.auditoria_caja(anulacion_pedido_id) where anulacion_pedido_id is not null;

create function public.anular_pedido_supervisado(
  p_pedido_id bigint,p_motivo text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare
  v_actor uuid:=auth.uid();v_local uuid;v_rol text;v_pedido public.pedido%rowtype;
  v_mesa public.mesa%rowtype;v_anulacion public.anulacion_pedido%rowtype;
  v_motivo text:=nullif(btrim(p_motivo),'');v_anulado_en timestamptz;
begin
  select c.local_id,c.rol_codigo into v_local,v_rol from public.obtener_contexto_autenticado() c;
  if v_actor is null or v_local is null or v_rol is distinct from 'ADMINISTRADOR' then
    raise exception using errcode='42501',message='No autorizado para anular pedidos';
  end if;
  if p_pedido_id is null or p_idempotency_key is null or v_motivo is null then
    raise exception using errcode='22023',message='Pedido, motivo y clave son obligatorios';
  end if;
  -- Orden T07: pedido -> mesa. No necesita ni bloquea sesión de caja.
  select p.* into v_pedido from public.pedido p
    where p.id=p_pedido_id and p.local_id=v_local for update;
  if not found then raise exception using errcode='42501',message='Pedido no disponible';end if;
  select m.* into v_mesa from public.mesa m
    where m.id=v_pedido.mesa_id and m.local_id=v_local and m.activo for update;
  if not found then raise exception using errcode='42501',message='Mesa no disponible';end if;
  select a.* into v_anulacion from public.anulacion_pedido a where a.pedido_id=v_pedido.id;
  if found then
    if v_anulacion.actor_id=v_actor and v_anulacion.idempotency_key=p_idempotency_key
      and v_anulacion.motivo=v_motivo then return to_jsonb(v_anulacion)-'idempotency_key';end if;
    raise exception using errcode='40001',message='El pedido ya fue anulado';
  end if;
  if exists(select 1 from public.pago p where p.pedido_id=v_pedido.id) then
    raise exception using errcode='40001',message='Un pedido con pagos no puede anularse';
  end if;
  if v_pedido.estado not in ('ABIERTO','ENVIADO','RECIBIDO_COCINA','EN_PREPARACION','LISTO','ENTREGADO') then
    raise exception using errcode='40001',message='El estado del pedido no admite anulación';
  end if;
  v_anulado_en:=clock_timestamp();
  update public.pedido p set estado='ANULADO' where p.id=v_pedido.id and p.estado=v_pedido.estado;
  if not found then raise exception using errcode='40001',message='El pedido cambió durante la anulación';end if;
  update public.mesa m set estado='LIBRE' where m.id=v_mesa.id and m.local_id=v_local;
  if not found then raise exception using errcode='40001',message='La mesa cambió durante la anulación';end if;
  insert into public.historial_estado(pedido_id,estado_anterior,estado_nuevo,usuario_id,creado_en)
  values(v_pedido.id,v_pedido.estado,'ANULADO',v_actor,v_anulado_en);
  insert into public.anulacion_pedido(pedido_id,local_id,mesa_id,actor_id,motivo,
    estado_anterior,estado_nuevo,mesa_estado_anterior,mesa_estado_nuevo,anulado_en,idempotency_key)
  values(v_pedido.id,v_local,v_mesa.id,v_actor,v_motivo,v_pedido.estado,'ANULADO',
    v_mesa.estado,'LIBRE',v_anulado_en,p_idempotency_key) returning * into v_anulacion;
  insert into public.auditoria_caja(tipo,local_id,caja_id,sesion_caja_id,actor_id,creado_en,
    monto_inicial,estado_anterior,estado_nuevo,pedido_id,anulacion_pedido_id,motivo,
    mesa_estado_anterior,mesa_estado_nuevo)
  values('ANULACION',v_local,null,null,v_actor,v_anulado_en,null,v_pedido.estado,'ANULADO',
    v_pedido.id,v_anulacion.id,v_motivo,v_mesa.estado,'LIBRE');
  return to_jsonb(v_anulacion)-'idempotency_key';
end $$;

alter function public.anular_pedido_supervisado(bigint,text,uuid) owner to postgres;
revoke all on function public.anular_pedido_supervisado(bigint,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.anular_pedido_supervisado(bigint,text,uuid) to authenticated;

alter table public.anulacion_pedido enable row level security;
revoke all on public.anulacion_pedido from public,anon,authenticated,service_role;
grant select on public.anulacion_pedido to authenticated;
create policy pol_anulacion_pedido_select_admin_local on public.anulacion_pedido
  for select to authenticated using(exists(select 1 from public.obtener_contexto_autenticado() c
    where c.local_id=anulacion_pedido.local_id and c.rol_codigo='ADMINISTRADOR'));

comment on table public.anulacion_pedido is 'Evento inmutable de anulación completa ejecutada directamente por ADMINISTRADOR; sin solicitante/autorizador, reverso ni cancelación por detalle.';
comment on function public.anular_pedido_supervisado(bigint,text,uuid) is 'ADMINISTRADOR del local anula directamente pedidos sin pagos en la matriz E1 aprobada; pedido, mesa, historial y auditoría son atómicos e idempotentes.';

notify pgrst,'reload schema';
commit;
