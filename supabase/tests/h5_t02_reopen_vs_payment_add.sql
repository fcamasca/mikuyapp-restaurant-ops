select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000f821',false);
select set_config('request.jwt.claim.role','authenticated',false);
select * from public.agregar_detalle_pedido(-50821,'00000000-0000-0000-0000-00000000f826',1,null);
