#!/usr/bin/env bash
# E9-T06 — Integración técnica local: migraciones E9 incrementales sobre la línea base, recorrido SQL
# integrado (TP23) y señal Realtime de jornada_operativa (TP22, parte local): publicación, cambios
# decodificados del WAL y visibilidad RLS de la fila nueva para cada rol (autorización de postgres_changes).
# Uso: scripts/e9_t06_integracion.sh   (PostgreSQL local con wal_level=logical; nunca DEV/PROD)
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); T=$REPO/supabase/tests; FAILS=0; TS=$(date +%s)
PORT=${PGPORT:-54329}
PG="psql -h /tmp -p $PORT -U postgres -X -v ON_ERROR_STOP=1 -q"
ok(){ echo "RESULT PASS $1"; }; ko(){ echo "RESULT FAIL $1"; FAILS=$((FAILS+1)); }

echo "== 1. Migraciones E9 incrementales sobre la línea base (59 migraciones + seed)"
BASE=e9_t06_base_$TS
bash "$REPO/scripts/e10_local_replay.sh" "$BASE" "$REPO" 20260930000200 | tail -1
for m in $(ls "$REPO/supabase/migrations" | grep '^20261001.*_e9_' | sort); do
  $PG -d "$BASE" -f "$REPO/supabase/migrations/$m" >/dev/null 2>&1 && ok "incremental $m" || ko "incremental $m"
done
$PG -d "$BASE" -f "$T/e9_t06_integracion.sql" 2>&1 | grep -q "E9-T06 recorrido integrado: PASS" && ok "TP23 recorrido integrado (base incremental)" || ko "TP23 recorrido integrado (base incremental)"
dropdb -h /tmp -p $PORT -U postgres --force "$BASE"

echo "== 2. TP22 (local): señal Realtime de jornada_operativa"
DB=e9_t06_wal_$TS; SLOT=e9_t06_$TS
bash "$REPO/scripts/e10_local_replay.sh" "$DB" "$REPO" all | tail -1
PUB=$($PG -d "$DB" -At -c "select string_agg(tablename, ',' order by tablename) from pg_publication_tables where pubname = 'supabase_realtime'")
echo "PUBLICACION $PUB"
[[ "$PUB" == "detalle_pedido,jornada_operativa,mesa,pedido,solicitud_cuenta" ]] && ok "publicación incluye jornada_operativa" || ko "publicación inesperada"
A=00000000-0000-0000-0000-0000000e96a1; M=00000000-0000-0000-0000-0000000e96a2; K=00000000-0000-0000-0000-0000000e96a3
C=00000000-0000-0000-0000-0000000e96a4; AB=00000000-0000-0000-0000-0000000e96a5; L=00000000-0000-0000-0000-0000000e96b1
LB=00000000-0000-0000-0000-0000000e96b2; MESA=00000000-0000-0000-0000-0000000e96c1
as(){ echo "select set_config('request.jwt.claim.sub','$1',false), set_config('request.jwt.claim.role','authenticated',false);"; }
$PG -d "$DB" >/dev/null <<SQL
insert into auth.users(id,aud,role,email,encrypted_password) select u,'authenticated','authenticated','e9t06-'||u||'@example.invalid','t'
  from unnest(array['$A','$M','$K','$C','$AB']::uuid[]) u;
insert into public.local(id,codigo,nombre) values('$L','E9-T06W','Local señal'),('$LB','E9-T06B','Otro');
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
  select '$A'::uuid,'$L'::uuid,id,'Admin' from public.rol where codigo='ADMINISTRADOR'
  union all select '$M'::uuid,'$L'::uuid,id,'Mozo' from public.rol where codigo='MOZO'
  union all select '$K'::uuid,'$L'::uuid,id,'Cocina' from public.rol where codigo='COCINA'
  union all select '$C'::uuid,'$L'::uuid,id,'Caja' from public.rol where codigo='CAJA'
  union all select '$AB'::uuid,'$LB'::uuid,id,'Admin B' from public.rol where codigo='ADMINISTRADOR';
insert into public.mesa(id,local_id,codigo,nombre) values('$MESA','$L','W1','Mesa');
SQL
$PG -d "$DB" -At -c "select 1 from pg_create_logical_replication_slot('$SLOT', 'test_decoding')" >/dev/null
run(){ $PG -d "$DB" -c "$(as $1)" -c "$2" >/dev/null 2>&1; }
run $A "select * from public.rpc_abrir_jornada_operativa('$K')"                       # apertura: INSERT
run $A "select * from public.rpc_abrir_jornada_operativa(gen_random_uuid())"           # idempotente: sin escritura
run $M "select * from public.crear_o_recuperar_pedido_mesa('$MESA')"
run $A "select * from public.rpc_cerrar_jornada_operativa((select id from public.jornada_operativa where local_id='$L'))"  # rechazado: sin escritura
run $M "select public.liberar_mesa_pedido_vacio((select id from public.pedido where mesa_id='$MESA'))"
run $A "select * from public.rpc_cerrar_jornada_operativa((select id from public.jornada_operativa where local_id='$L'))"  # cierre: UPDATE
run $A "select * from public.rpc_cerrar_jornada_operativa((select id from public.jornada_operativa where local_id='$L' order by id limit 1))"  # repetición: sin escritura
run $A "select * from public.rpc_abrir_jornada_operativa(gen_random_uuid())"           # nueva jornada: INSERT
CHANGES=$($PG -d "$DB" -At -c "select data from pg_logical_slot_get_changes('$SLOT', null, null) where data like 'table public.jornada_operativa:%'")
INS=$(grep -c "INSERT" <<<"$CHANGES"); UPD=$(grep -c "UPDATE" <<<"$CHANGES"); DEL=$(grep -c "DELETE" <<<"$CHANGES")
echo "WAL jornada_operativa INSERT=$INS UPDATE=$UPD DELETE=$DEL"
grep -o "estado\[text\]:'[A-Z]*'" <<<"$CHANGES" | paste -sd' ' | sed 's/^/    /'
[[ $INS -eq 2 && $UPD -eq 1 && $DEL -eq 0 ]] && ok "2 aperturas y 1 cierre emitidos; idempotencias y cierre rechazado no emiten" || ko "cambios decodificados inesperados"
$PG -d "$DB" -At -c "select pg_drop_replication_slot('$SLOT')" >/dev/null
# Autorización Realtime = RLS de SELECT sobre la versión nueva de la fila (ABIERTA y CERRADA).
vis(){ $PG -d "$DB" -At -c "begin" -c "$(as $1)" -c "set local role authenticated" -c "select 'VIS=' || coalesce(string_agg(estado, ',' order by id), 'NINGUNA') from public.jornada_operativa" -c "rollback" 2>&1 | grep -o "VIS=.*" | cut -c5-; }
for u in $A $M $K $C; do
  V=$(vis $u); [[ "$V" == "CERRADA,ABIERTA" ]] && ok "RLS: rol $u del local ve ABIERTA y CERRADA (recibe apertura y cierre)" || ko "RLS rol $u: '$V'"
done
V=$(vis $AB); [[ "$V" == "NINGUNA" ]] && ok "RLS: ADMIN de otro local no ve las jornadas" || ko "RLS otro local: '$V'"
ANON=$($PG -d "$DB" -At -c "begin" -c "set local role anon" -c "select count(*) from public.jornada_operativa" -c "rollback" 2>&1 | grep -c "permission denied")
[[ "$ANON" -ge 1 ]] && ok "anon sin acceso a jornada_operativa" || ko "anon con acceso"
dropdb -h /tmp -p $PORT -U postgres --force "$DB"
echo "RESIDUO slots=$($PG -d postgres -At -c "select count(*) from pg_replication_slots where slot_name like 'e9_%'") bases=$($PG -d postgres -At -c "select count(*) from pg_database where datname like 'e9_t06_%'")"
echo "== fallos: $FAILS"; exit $((FAILS>0))
