begin;

-- T13: el trigger debe poder comprobar pagos aunque la operación legítima de
-- detalle se ejecute con privilegios columnarios mínimos de authenticated.
create or replace function public.tgf_bloquear_detalle_pedido_con_pago()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
declare v_pedido_id bigint:=coalesce(new.pedido_id,old.pedido_id);
begin
  if exists(select 1 from public.pago p where p.pedido_id=v_pedido_id) then
    raise exception using errcode='40001',message='Un pedido con pagos no admite mutaciones';
  end if;
  return coalesce(new,old);
end $$;
alter function public.tgf_bloquear_detalle_pedido_con_pago() owner to postgres;
revoke all on function public.tgf_bloquear_detalle_pedido_con_pago()
  from public,anon,authenticated,service_role;
comment on function public.tgf_bloquear_detalle_pedido_con_pago() is
  'Trigger endurecido: bloquea toda mutación de detalles tras el primer pago sin exponer lectura directa de pago al cliente.';

commit;
