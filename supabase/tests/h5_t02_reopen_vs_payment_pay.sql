select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000f822',false);
select set_config('request.jwt.claim.role','authenticated',false);
select * from public.registrar_pago_pedido(-50821,'EFECTIVO');
