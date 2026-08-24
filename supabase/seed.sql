begin;

insert into public.rol (codigo, nombre, activo)
values
  ('ADMINISTRADOR', 'Administrador', true),
  ('MOZO', 'Mozo', true),
  ('COCINA', 'Cocina', true),
  ('CAJA', 'Caja', true)
on conflict (codigo) do update
set nombre = excluded.nombre,
    activo = excluded.activo;

insert into public.local (codigo, nombre, activo)
values ('MIKUY-DEMO', 'MikuyApp Demo', true)
on conflict (codigo) do update
set nombre = excluded.nombre,
    activo = excluded.activo;

insert into public.mesa (local_id, codigo, nombre, estado, activo)
select local_demo.id, mesa_demo.codigo, mesa_demo.nombre, 'LIBRE', true
from public.local as local_demo
cross join (
  values
    ('M01', 'Mesa 1'),
    ('M02', 'Mesa 2'),
    ('M03', 'Mesa 3'),
    ('M04', 'Mesa 4'),
    ('M05', 'Mesa 5'),
    ('M06', 'Mesa 6')
) as mesa_demo (codigo, nombre)
where local_demo.codigo = 'MIKUY-DEMO'
on conflict (local_id, codigo) do update
set nombre = excluded.nombre,
    estado = excluded.estado,
    activo = excluded.activo;

insert into public.categoria (local_id, codigo, nombre, orden, activo)
select local_demo.id, categoria_demo.codigo, categoria_demo.nombre, categoria_demo.orden, true
from public.local as local_demo
cross join (
  values
    ('CEVICHES', 'Ceviches', 1),
    ('CHICHARRONES', 'Chicharrones', 2),
    ('ARROCES', 'Arroces', 3),
    ('COMBOS', 'Combos', 4),
    ('BEBIDAS', 'Bebidas', 5)
) as categoria_demo (codigo, nombre, orden)
where local_demo.codigo = 'MIKUY-DEMO'
on conflict (local_id, codigo) do update
set nombre = excluded.nombre,
    orden = excluded.orden,
    activo = excluded.activo;

insert into public.producto (local_id, categoria_id, codigo, nombre, precio, activo)
select
  local_demo.id,
  categoria_demo.id,
  producto_demo.codigo,
  producto_demo.nombre,
  producto_demo.precio,
  true
from public.local as local_demo
join public.categoria as categoria_demo
  on categoria_demo.local_id = local_demo.id
join (
  values
    ('CEVICHES', 'CEVICHE_CLASICO', 'Ceviche clásico', 30.00::numeric(10,2)),
    ('CEVICHES', 'CEVICHE_MIXTO', 'Ceviche mixto', 38.00::numeric(10,2)),
    ('CHICHARRONES', 'CHICHARRON_PESCADO', 'Chicharrón de pescado', 28.00::numeric(10,2)),
    ('CHICHARRONES', 'CHICHARRON_MIXTO', 'Chicharrón mixto', 35.00::numeric(10,2)),
    ('ARROCES', 'ARROZ_MARISCOS', 'Arroz con mariscos', 34.00::numeric(10,2)),
    ('ARROCES', 'CHAUFA_MARISCOS', 'Chaufa de mariscos', 32.00::numeric(10,2)),
    ('COMBOS', 'COMBO_CEVICHE_CHICHARRON', 'Combo ceviche y chicharrón', 42.00::numeric(10,2)),
    ('COMBOS', 'COMBO_FAMILIAR', 'Combo familiar', 75.00::numeric(10,2)),
    ('BEBIDAS', 'CHICHA_MORADA', 'Chicha morada', 8.00::numeric(10,2)),
    ('BEBIDAS', 'GASEOSA_PERSONAL', 'Gaseosa personal', 5.00::numeric(10,2))
) as producto_demo (categoria_codigo, codigo, nombre, precio)
  on producto_demo.categoria_codigo = categoria_demo.codigo
where local_demo.codigo = 'MIKUY-DEMO'
on conflict (local_id, codigo) do update
set categoria_id = excluded.categoria_id,
    nombre = excluded.nombre,
    precio = excluded.precio,
    activo = excluded.activo;

commit;
