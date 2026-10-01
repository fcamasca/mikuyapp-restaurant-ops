-- E10 — Fixture comprometida para carreras reales (TP05, TP10, TP11). Usar sólo en una base local
-- efímera: la inmutabilidad de solicitud_cuenta impide limpiarla; la base se elimina al terminar.
begin;
insert into auth.users (id, aud, role, email, encrypted_password)
select u, 'authenticated', 'authenticated', 'e10-cc-' || u || '@example.invalid', 't'
from unnest(array['00000000-0000-0000-0000-00000e10cc01','00000000-0000-0000-0000-00000e10cc02',
  '00000000-0000-0000-0000-00000e10cc03','00000000-0000-0000-0000-00000e10cc04','00000000-0000-0000-0000-00000e10cc05']::uuid[]) u;
insert into public.local (id, codigo, nombre) values ('00000000-0000-0000-0000-00000e10cc10', 'E10-CC', 'Local carreras E10');
insert into public.perfil_usuario (id, local_id, rol_id, nombre)
select '00000000-0000-0000-0000-00000e10cc01'::uuid, '00000000-0000-0000-0000-00000e10cc10'::uuid, id, 'Mozo Uno' from public.rol where codigo = 'MOZO'
union all select '00000000-0000-0000-0000-00000e10cc02', '00000000-0000-0000-0000-00000e10cc10', id, 'Mozo Dos' from public.rol where codigo = 'MOZO'
union all select '00000000-0000-0000-0000-00000e10cc03', '00000000-0000-0000-0000-00000e10cc10', id, 'Caja Uno' from public.rol where codigo = 'CAJA'
union all select '00000000-0000-0000-0000-00000e10cc04', '00000000-0000-0000-0000-00000e10cc10', id, 'Caja Dos' from public.rol where codigo = 'CAJA'
union all select '00000000-0000-0000-0000-00000e10cc05', '00000000-0000-0000-0000-00000e10cc10', id, 'Admin' from public.rol where codigo = 'ADMINISTRADOR';
-- E9 (homologación mínima): precondición global de E9 — jornada operativa ABIERTA válida para los locales del fixture.
insert into public.jornada_operativa (local_id, fecha_operativa, numero, abierta_por, abierta_en, idempotency_key)
select l.id, (now() at time zone 'America/Lima')::date,
  1 + coalesce((select max(j.numero) from public.jornada_operativa j where j.local_id = l.id and j.fecha_operativa = (now() at time zone 'America/Lima')::date), 0),
  (select p.id from public.perfil_usuario p where p.local_id = l.id order by p.id limit 1), now(), gen_random_uuid()
from public.local l
where l.id in ('00000000-0000-0000-0000-00000e10cc10'::uuid)
  and exists (select 1 from public.perfil_usuario p where p.local_id = l.id)
  and not exists (select 1 from public.jornada_operativa j where j.local_id = l.id and j.estado = 'ABIERTA');
insert into public.mesa (id, local_id, codigo, nombre)
select ('00000000-0000-0000-0000-00000e10cc' || (20 + g))::uuid, '00000000-0000-0000-0000-00000e10cc10', 'CC-' || g, 'Mesa ' || g
from generate_series(1, 9) g;
insert into public.categoria (id, local_id, codigo, nombre) values ('00000000-0000-0000-0000-00000e10cc11', '00000000-0000-0000-0000-00000e10cc10', 'CC', 'Carta');
insert into public.producto (id, local_id, categoria_id, codigo, nombre, precio, requiere_cocina) values
  ('00000000-0000-0000-0000-00000e10cc12', '00000000-0000-0000-0000-00000e10cc10', '00000000-0000-0000-0000-00000e10cc11', 'CHI', 'Chicha', 8, false),
  ('00000000-0000-0000-0000-00000e10cc13', '00000000-0000-0000-0000-00000e10cc10', '00000000-0000-0000-0000-00000e10cc11', 'PAN', 'Pan', 5, false);
insert into public.caja (id, local_id, codigo, nombre) values ('00000000-0000-0000-0000-00000e10cc14', '00000000-0000-0000-0000-00000e10cc10', 'CC', 'Caja CC');
insert into public.sesion_caja (id, caja_id, local_id, abierta_por, monto_inicial, idempotency_key)
values ('00000000-0000-0000-0000-00000e10cc15', '00000000-0000-0000-0000-00000e10cc14', '00000000-0000-0000-0000-00000e10cc10',
  '00000000-0000-0000-0000-00000e10cc03', 0, '00000000-0000-0000-0000-00000e10cc16');
-- Nueve pedidos ENTREGADO (Chicha x1 = 8) en las mesas CC-1 … CC-9
select pg_catalog.set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000e10cc01', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
do $cc$
declare v_pedido bigint; g int;
begin
  for g in 1..9 loop
    select pedido_id into strict v_pedido from public.crear_o_recuperar_pedido_mesa(('00000000-0000-0000-0000-00000e10cc' || (20 + g))::uuid);
    perform public.agregar_detalle_pedido(v_pedido, '00000000-0000-0000-0000-00000e10cc12', 1, null);
    perform public.enviar_pedido_cocina(v_pedido);
    perform public.entregar_pedido(v_pedido);
  end loop;
end $cc$;
commit;
