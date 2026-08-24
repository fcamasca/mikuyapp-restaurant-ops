do $test$
declare
  actual_count bigint;
  actual_codes text[];
begin
  select count(*), array_agg(codigo order by codigo)
  into actual_count, actual_codes
  from public.rol;
  if actual_count <> 4 or actual_codes <> array['ADMINISTRADOR', 'CAJA', 'COCINA', 'MOZO'] then
    raise exception 'Roles inválidos: conteo %, códigos %', actual_count, actual_codes;
  end if;

  select count(*) into actual_count
  from public.local
  where codigo = 'MIKUY-DEMO'
    and nombre = 'MikuyApp Demo'
    and activo = true;
  if actual_count <> 1 or (select count(*) from public.local) <> 1 then
    raise exception 'El local demo no es único, exacto y activo';
  end if;

  select count(*), array_agg(m.codigo order by m.codigo)
  into actual_count, actual_codes
  from public.mesa as m
  join public.local as l on l.id = m.local_id
  where l.codigo = 'MIKUY-DEMO'
    and m.activo = true
    and m.estado = 'LIBRE';
  if actual_count <> 6
     or actual_codes <> array['M01', 'M02', 'M03', 'M04', 'M05', 'M06']
     or (select count(*) from public.mesa) <> 6 then
    raise exception 'Mesas inválidas: conteo %, códigos %', actual_count, actual_codes;
  end if;

  select count(*) into actual_count
  from public.categoria as c
  join public.local as l on l.id = c.local_id
  where l.codigo = 'MIKUY-DEMO'
    and c.activo = true
    and (c.codigo, c.nombre, c.orden) in (
      ('CEVICHES', 'Ceviches', 1),
      ('CHICHARRONES', 'Chicharrones', 2),
      ('ARROCES', 'Arroces', 3),
      ('COMBOS', 'Combos', 4),
      ('BEBIDAS', 'Bebidas', 5)
    );
  if actual_count <> 5 or (select count(*) from public.categoria) <> 5 then
    raise exception 'Categorías inválidas: conteo exacto esperado 5, obtenido %', actual_count;
  end if;

  select count(*) into actual_count
  from public.producto as p
  join public.local as l on l.id = p.local_id
  join public.categoria as c on c.id = p.categoria_id and c.local_id = p.local_id
  where l.codigo = 'MIKUY-DEMO'
    and p.activo = true
    and p.precio >= 0
    and btrim(p.codigo) <> ''
    and btrim(p.nombre) <> ''
    and (c.codigo, p.codigo, p.nombre, p.precio) in (
      ('CEVICHES', 'CEVICHE_CLASICO', 'Ceviche clásico', 30.00),
      ('CEVICHES', 'CEVICHE_MIXTO', 'Ceviche mixto', 38.00),
      ('CHICHARRONES', 'CHICHARRON_PESCADO', 'Chicharrón de pescado', 28.00),
      ('CHICHARRONES', 'CHICHARRON_MIXTO', 'Chicharrón mixto', 35.00),
      ('ARROCES', 'ARROZ_MARISCOS', 'Arroz con mariscos', 34.00),
      ('ARROCES', 'CHAUFA_MARISCOS', 'Chaufa de mariscos', 32.00),
      ('COMBOS', 'COMBO_CEVICHE_CHICHARRON', 'Combo ceviche y chicharrón', 42.00),
      ('COMBOS', 'COMBO_FAMILIAR', 'Combo familiar', 75.00),
      ('BEBIDAS', 'CHICHA_MORADA', 'Chicha morada', 8.00),
      ('BEBIDAS', 'GASEOSA_PERSONAL', 'Gaseosa personal', 5.00)
    );
  if actual_count <> 10 or (select count(*) from public.producto) <> 10 then
    raise exception 'Productos inválidos: conteo exacto esperado 10, obtenido %', actual_count;
  end if;

  if exists (
    select 1
    from public.categoria as c
    left join public.producto as p on p.categoria_id = c.id and p.local_id = c.local_id
    group by c.id
    having count(p.id) <> 2
  ) then
    raise exception 'Cada categoría debe tener exactamente dos productos';
  end if;

  if exists (
    select 1 from public.rol where btrim(codigo) = '' or btrim(nombre) = ''
    union all
    select 1 from public.local where btrim(codigo) = '' or btrim(nombre) = ''
    union all
    select 1 from public.mesa where btrim(codigo) = '' or btrim(nombre) = ''
    union all
    select 1 from public.categoria where btrim(codigo) = '' or btrim(nombre) = ''
    union all
    select 1 from public.producto where btrim(codigo) = '' or btrim(nombre) = ''
  ) then
    raise exception 'Existen códigos o nombres vacíos';
  end if;

  if exists (
    select 1 from public.mesa as m left join public.local as l on l.id = m.local_id where l.id is null
    union all
    select 1 from public.categoria as c left join public.local as l on l.id = c.local_id where l.id is null
    union all
    select 1
    from public.producto as p
    left join public.local as l on l.id = p.local_id
    left join public.categoria as c on c.id = p.categoria_id and c.local_id = p.local_id
    where l.id is null or c.id is null
  ) then
    raise exception 'Existen referencias inválidas de local o categoría';
  end if;

  if (select count(*) from auth.users) <> 0 then
    raise exception 'auth.users debe permanecer vacío';
  end if;
  if (select count(*) from public.perfil_usuario) <> 0 then
    raise exception 'perfil_usuario debe permanecer vacío';
  end if;
  if (select count(*) from public.pedido) <> 0 then
    raise exception 'pedido debe permanecer vacío';
  end if;
  if (select count(*) from public.detalle_pedido) <> 0 then
    raise exception 'detalle_pedido debe permanecer vacío';
  end if;
  if (select count(*) from public.historial_estado) <> 0 then
    raise exception 'historial_estado debe permanecer vacío';
  end if;
  if (select count(*) from public.pago) <> 0 then
    raise exception 'pago debe permanecer vacío';
  end if;
end
$test$;

select
  (select count(*) from public.rol) as roles,
  (select count(*) from public.local) as locales,
  (select count(*) from public.mesa) as mesas,
  (select count(*) from public.categoria) as categorias,
  (select count(*) from public.producto) as productos,
  (select count(*) from auth.users) as usuarios_auth,
  (select count(*) from public.perfil_usuario) as perfiles,
  (select count(*) from public.pedido) as pedidos,
  (select count(*) from public.detalle_pedido) as detalles,
  (select count(*) from public.historial_estado) as historiales,
  (select count(*) from public.pago) as pagos;
