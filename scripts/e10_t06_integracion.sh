#!/usr/bin/env bash
# E10-T06 — Integración local: migraciones E10 incrementales sobre la línea base, recorrido SQL integrado
# y verificación de la señal Realtime a nivel de WAL (decodificación lógica) sobre bases efímeras.
# Uso: scripts/e10_t06_integracion.sh   (PostgreSQL local con wal_level=logical; nunca DEV/PROD)
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); T=$REPO/supabase/tests; FAILS=0; TS=$(date +%s)
PG="psql -h /tmp -p ${PGPORT:-54329} -U postgres -X -v ON_ERROR_STOP=1 -q"
ok(){ echo "RESULT PASS $1"; }; ko(){ echo "RESULT FAIL $1"; FAILS=$((FAILS+1)); }

echo "== 1. Migraciones E10 incrementales sobre la línea base (57 migraciones + seed)"
BASE=e10_t06_base_$TS
bash "$REPO/scripts/e10_local_replay.sh" "$BASE" "$REPO" 20260924000800 | tail -1
for m in $(ls "$REPO/supabase/migrations" | grep '^20260930.*_e10_' | sort); do
  $PG -d "$BASE" -f "$REPO/supabase/migrations/$m" >/dev/null 2>&1 && ok "incremental $m" || ko "incremental $m"
done
$PG -d "$BASE" -f "$T/e10_t06_integracion.sql" 2>&1 | grep -q "E10-T06 recorrido integrado: PASS" && ok "recorrido integrado (base incremental)" || ko "recorrido integrado (base incremental)"
dropdb -h /tmp -p ${PGPORT:-54329} -U postgres --force "$BASE"

echo "== 2. Señal Realtime: publicación + cambios decodificados de solicitud_cuenta (test_decoding)"
DB=e10_t06_wal_$TS; SLOT=e10_t06_$TS
bash "$REPO/scripts/e10_local_replay.sh" "$DB" "$REPO" all | tail -1
echo "PUBLICACION $($PG -d "$DB" -At -c "select string_agg(tablename, ',' order by tablename) from pg_publication_tables where pubname = 'supabase_realtime'")"
$PG -d "$DB" -f "$T/e10_concurrency_setup.sql" >/dev/null
$PG -d "$DB" -At -c "select 1 from pg_create_logical_replication_slot('$SLOT', 'test_decoding')" >/dev/null
call(){ $PG -d "$DB" -v op=$1 -v usuario=$2 -v mesa=$3 -f "$T/e10_concurrency_call.sql" >/dev/null 2>&1; }
M1=00000000-0000-0000-0000-00000e10cc01; C1=00000000-0000-0000-0000-00000e10cc03; AD=00000000-0000-0000-0000-00000e10cc05
call solicitar $M1 1; call solicitar $M1 1; call cobro_total $C1 1      # nueva, repetición (sin escritura), cierre ATENDIDA
call solicitar $M1 2; call reapertura $M1 2                              # nueva, cierre SIN_EFECTO/REAPERTURA
call solicitar $M1 3; call anulacion $AD 3                               # nueva, cierre SIN_EFECTO/ANULACION
call cobro_total $C1 4                                                   # cobro sin solicitud: sin cambios en la tabla
CHANGES=$($PG -d "$DB" -At -c "select data from pg_logical_slot_get_changes('$SLOT', null, null) where data like 'table public.solicitud_cuenta:%'")
INS=$(grep -c "INSERT" <<<"$CHANGES"); UPD=$(grep -c "UPDATE" <<<"$CHANGES"); DEL=$(grep -c "DELETE" <<<"$CHANGES")
echo "WAL solicitud_cuenta INSERT=$INS UPDATE=$UPD DELETE=$DEL"
grep -o "estado\[text\]:'[A-Z_]*'\|motivo_sin_efecto\[text\]:[^ ]*" <<<"$CHANGES" | paste -sd' ' | sed 's/^/    /'
[[ $INS -eq 3 && $UPD -eq 3 && $DEL -eq 0 ]] && ok "3 altas y 3 cierres emitidos; repetición y cobro sin solicitud no emiten" || ko "cambios decodificados inesperados"
$PG -d "$DB" -At -c "select pg_drop_replication_slot('$SLOT')" >/dev/null
dropdb -h /tmp -p ${PGPORT:-54329} -U postgres --force "$DB"
echo "RESIDUO slots=$($PG -d postgres -At -c "select count(*) from pg_replication_slots where slot_name like 'e10_%'") bases=$($PG -d postgres -At -c "select count(*) from pg_database where datname like 'e10_t06_%'")"
echo "== fallos: $FAILS"; exit $((FAILS>0))
