select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-00000000d43f',
  false
);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', false);
select *
from public.actualizar_estado_detalle_cocina(
  -40391, 'ENVIADO', 'RECIBIDO_COCINA'
);
