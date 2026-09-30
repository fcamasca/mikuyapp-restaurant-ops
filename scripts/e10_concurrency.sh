#!/usr/bin/env bash
# E10 — Carreras reales con conexiones independientes sobre una base local efímera.
# Uso: scripts/e10_concurrency.sh <t03|t07|all>   (PostgreSQL local, ver specs/E10-AccountRequest/implementation.md §1)
# A abre transacción, ejecuta su operación, retiene locks 2 s y confirma; B se lanza 0,7 s después.
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); T=$REPO/supabase/tests; DB=e10_cc_$(date +%s); FAILS=0
PSQL="psql -h /tmp -p ${PGPORT:-54329} -U postgres -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -d $DB"
M1=00000000-0000-0000-0000-00000e10cc01; M2=00000000-0000-0000-0000-00000e10cc02
C1=00000000-0000-0000-0000-00000e10cc03; C2=00000000-0000-0000-0000-00000e10cc04; AD=00000000-0000-0000-0000-00000e10cc05
call(){ echo "-v op=$1 -v usuario=$2 -v mesa=$3"; }
race(){ # race <nombre> <mesa> <opA> <userA> <opB> <userB> <esperado> <sqlstate_B_esperado|->
  local name=$1 mesa=$2 oa ob; oa=$(mktemp); ob=$(mktemp)
  (PGAPPNAME=e10_race $PSQL -q $(call $3 $4 $mesa) -c "begin" -f "$T/e10_concurrency_call.sql" -c "select pg_sleep(2)" -c "commit") >"$oa" 2>&1 & local pa=$!
  sleep 0.7
  (PGAPPNAME=e10_race $PSQL -q $(call $5 $6 $mesa) -c "begin" -f "$T/e10_concurrency_call.sql" -c "commit") >"$ob" 2>&1 & local pb=$!
  wait $pa; local ca=$?; wait $pb; local cb=$?
  local sa sb; sa=$(grep -o "ERROR:  [0-9A-Z]\{5\}" "$oa" | head -1 | awk '{print $2}'); sb=$(grep -o "ERROR:  [0-9A-Z]\{5\}" "$ob" | head -1 | awk '{print $2}')
  echo "RACE $name: A=$3 exit=$ca${sa:+ sqlstate=$sa} | B=$5 exit=$cb${sb:+ sqlstate=$sb}"
  grep -h "E10-RACE\|ERROR:" "$oa" "$ob" | sed 's/^/    /'
  if grep -q "40001\|40P01\|deadlock" "$oa" "$ob"; then echo "RESULT FAIL $name: 40001/40P01/deadlock"; FAILS=$((FAILS+1)); fi
  if [[ $ca -ne 0 ]]; then echo "RESULT FAIL $name: A falló"; FAILS=$((FAILS+1)); fi
  if [[ "$8" == - && $cb -ne 0 ]]; then echo "RESULT FAIL $name: B falló"; FAILS=$((FAILS+1)); fi
  if [[ "$8" != - && "$sb" != "$8" ]]; then echo "RESULT FAIL $name: B debía fallar con $8"; FAILS=$((FAILS+1)); fi
  if $PSQL -q -v mesa=$mesa -v esperado="$7" -f "$T/e10_concurrency_verify.sql" >"$oa" 2>&1; then echo "RESULT PASS $name ($7)"; else echo "RESULT FAIL $name verify"; grep -h ERROR "$oa" | sed 's/^/    /'; FAILS=$((FAILS+1)); fi
  rm -f "$oa" "$ob"; }
bash "$REPO/scripts/e10_local_replay.sh" "$DB" "$REPO" all | tail -1
$PSQL -q -f "$T/e10_concurrency_setup.sql" >/dev/null || { echo "SETUP FAIL"; exit 1; }
if [[ ${1:-all} == t03 || ${1:-all} == all ]]; then
  echo "== T03: TP05 solicitud vs solicitud; TP10 solicitud vs cobro final (ambos órdenes)"
  race "TP05 dos mozos" 1 solicitar $M1 solicitar $M2 "ENTREGADO:PENDIENTE" -
  race "TP10 solicitud antes que cobro" 2 solicitar $M1 cobro_total $C1 "PAGADO:ATENDIDA" -
  race "TP10 cobro antes que solicitud" 3 cobro_total $C1 solicitar $M1 "PAGADO:-" PT409
fi
if [[ ${1:-all} == t07 || ${1:-all} == all ]]; then
  echo "== T07: TP11 solicitud vs reapertura/anulación (ambos órdenes) y dos cajas"
  race "TP11 solicitud antes que reapertura" 4 solicitar $M1 reapertura $M2 "ABIERTO:SIN_EFECTO/REAPERTURA" -
  race "TP11 reapertura antes que solicitud" 5 reapertura $M2 solicitar $M1 "ABIERTO:-" PT409
  race "TP11 solicitud antes que anulación" 6 solicitar $M1 anulacion $AD "ANULADO:SIN_EFECTO/ANULACION" -
  race "TP11 anulación antes que solicitud" 7 anulacion $AD solicitar $M1 "ANULADO:-" PT409
  $PSQL -q $(call solicitar $M1 8) -f "$T/e10_concurrency_call.sql" >/dev/null 2>&1
  race "TP11 dos cajas con solicitud" 8 cobro_total $C1 cobro_total $C2 "PAGADO:ATENDIDA" PT409
fi
echo "RESIDUO conexiones=$(psql -h /tmp -p ${PGPORT:-54329} -U postgres -At -c "select count(*) from pg_stat_activity where application_name='e10_race'")"
dropdb -h /tmp -p ${PGPORT:-54329} -U postgres --force "$DB" && echo "DROP $DB"
echo "== fallos: $FAILS"; exit $((FAILS>0))
