select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-00000000e294',
  false
);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', false);
select * from public.entregar_pedido(-50291);
