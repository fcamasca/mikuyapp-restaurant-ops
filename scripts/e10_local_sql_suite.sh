#!/usr/bin/env bash
# E10 — Suite SQL histórica local (misma selección, orden y carreras que scripts/e7_t11_sql_campaign.sh).
# Uso: scripts/e10_local_sql_suite.sh <db> <supabase/tests> [pre-e10]   (pre-e10 omite las pruebas e10_*)
set -uo pipefail
DB=$1; T=$2; PRE=${3:-}; FAILS=0
PSQL="psql -h /tmp -p ${PGPORT:-54329} -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -U postgres"
result(){ local name=$1 out=$2 code=$3; if [[ $code -eq 0 ]]; then echo "RESULT PASS $name"; else echo "RESULT FAIL $name (exit $code)"; grep -v "^\s*$" "$out" | grep -i "error\|exception" | head -3 | sed 's/^/    /'; FAILS=$((FAILS+1)); fi; }
runf(){ local db=$1 f=$2 name=${3:-$(basename "$2" .sql)} out; out=$(mktemp); (cd "$(dirname "$f")" && $PSQL -d "$db" -q -f "$(basename "$f")") >"$out" 2>&1; result "$name" "$out" $?; rm -f "$out"; }
race(){ local db=$1 name=$2 setup=$3 a=$4 b=$5 verify=$6 cleanup=$7 oa ob
  oa=$(mktemp); ob=$(mktemp); runf "$db" "$T/$setup" "$name setup" >/dev/null
  (cd "$T" && PGAPPNAME=e10_race $PSQL -d "$db" -q -c "begin" -f "$a" -c "select pg_sleep(2)" -c "commit") >"$oa" 2>&1 & local pa=$!
  sleep 0.7
  (cd "$T" && PGAPPNAME=e10_race $PSQL -d "$db" -q -c "begin" -f "$b" -c "commit") >"$ob" 2>&1 & local pb=$!
  wait $pa; local ca=$?; wait $pb; local cb=$?
  local sa sb; sa=$(grep -o "ERROR:  [0-9A-Z]\{5\}" "$oa" | head -1 | awk '{print $2}'); sb=$(grep -o "ERROR:  [0-9A-Z]\{5\}" "$ob" | head -1 | awk '{print $2}')
  echo "RACE $name: A exit=$ca ${sa:+sqlstate=$sa} | B exit=$cb ${sb:+sqlstate=$sb}"
  if [[ "$sa$sb" == *40001* ]]; then echo "RESULT FAIL $name: aparece 40001"; FAILS=$((FAILS+1)); fi
  if [[ $ca -ne 0 && $cb -ne 0 ]]; then echo "RESULT FAIL $name: ambas sesiones fallaron"; FAILS=$((FAILS+1)); fi
  if [[ "$verify" != - ]]; then runf "$db" "$T/$verify" "$name verify"; else echo "RESULT PASS $name (una sesión confirmó)"; fi
  runf "$db" "$T/$cleanup" "$name cleanup"; rm -f "$oa" "$ob"; }
echo "== B1 suite SQL (standalone, orden alfabético)"
for f in $(ls $T/*.sql | xargs -n1 basename | sort); do
  [[ -n "$PRE" && $f == e10_* ]] && continue
  case $f in *_setup.sql|*_call.sql|*_verify.sql|e10_concurrency_*|*_cleanup.sql|*_fixture.sql|*_add.sql|*_pay.sql|dbstd_t09_*|e7_t05b_hz01_*|e1_t03_caja_sesion.sql|e1_t04_apertura_sesion.sql|e1_t05_movimientos_cierre.sql|e1_t06_descuento_pedido.sql|e1_t07_anulacion_administrativa.sql|e1_t08_pago_sesion.sql) continue;; esac
  runf $DB "$T/$f"
done
echo "== B2 E1 con fixtures"
runf $DB "$T/e1_t03_fixture.sql"; runf $DB "$T/e1_t03_caja_sesion.sql"
runf $DB "$T/e1_t04_fixture.sql"; runf $DB "$T/e1_t04_apertura_sesion.sql"
runf $DB "$T/e1_t05_concurrency_setup.sql"; runf $DB "$T/e1_t05_movimientos_cierre.sql"
runf $DB "$T/e1_t06_concurrency_setup.sql"; runf $DB "$T/e1_t06_descuento_pedido.sql"
runf $DB "$T/e1_t07_concurrency_setup.sql"; runf $DB "$T/e1_t07_anulacion_administrativa.sql"
runf $DB "$T/e1_t08_concurrency_setup.sql"; runf $DB "$T/e1_t08_pago_sesion.sql"
echo "== B3 carreras históricas H4/H5"
race $DB "H4-T03 doble transición cocina" h4_t03_concurrency_setup.sql h4_t03_concurrency_call.sql h4_t03_concurrency_call.sql - h4_t03_concurrency_cleanup.sql
race $DB "H5-T02 doble entrega" h5_t02_concurrency_setup.sql h5_t02_concurrency_call.sql h5_t02_concurrency_call.sql h5_t02_concurrency_verify.sql h5_t02_concurrency_cleanup.sql
race $DB "H5-T02 reapertura vs pago" h5_t02_reopen_vs_payment_setup.sql h5_t02_reopen_vs_payment_add.sql h5_t02_reopen_vs_payment_pay.sql h5_t02_reopen_vs_payment_verify.sql h5_t02_reopen_vs_payment_cleanup.sql
race $DB "H5-T04 doble pago" h5_t04_concurrency_setup.sql h5_t04_concurrency_call.sql h5_t04_concurrency_call.sql h5_t04_concurrency_verify.sql h5_t04_concurrency_cleanup.sql
echo "== fallos: $FAILS"
