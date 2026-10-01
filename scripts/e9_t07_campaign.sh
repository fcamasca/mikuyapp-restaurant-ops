#!/usr/bin/env bash
# E9-T07 — Regresión técnica integral única (TP01–TP25, salvo TP22 con servidor Realtime real: ver
# scripts/e9_t06_local.ps1). PostgreSQL local efímero con wal_level=logical; nunca DEV/PROD.
# Uso: scripts/e9_t07_campaign.sh <ref_git_baseline_pre_e9>
#   ref_git_baseline_pre_e9: commit anterior a la construcción de E9 (p. ej. 313794a); de él se extraen las
#   versiones previas de los tests vigentes para demostrar contra la baseline la procedencia de cada fallo.
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); T=$REPO/supabase/tests; BASEREF=${1:?ref git de la baseline pre-E9}
PORT=${PGPORT:-54329}; TS=$(date +%s); OUT=${TMPDIR:-/tmp}/e9_t07_$TS; mkdir -p "$OUT"; FAILS=0
PG="psql -h /tmp -p $PORT -U postgres -X -v ON_ERROR_STOP=1 -q"
ok(){ echo "RESULT PASS $1"; }; ko(){ echo "RESULT FAIL $1"; FAILS=$((FAILS+1)); }
drop(){ dropdb -h /tmp -p $PORT -U postgres --if-exists --force "$1" 2>/dev/null; }
replay(){ bash "$REPO/scripts/e10_local_replay.sh" "$1" "$REPO" "$2" | tail -1; }

echo "== 1. Replay limpio total (TP25)"
E9=e9_t07_$TS; replay "$E9" all
BASE=e9_t07_base_$TS; replay "$BASE" 20260930000200

echo "== 2. TP02 precondición de la migración"
bash "$REPO/scripts/e9_t02_precondicion.sh" "$BASE" "$REPO" | grep -E "RESULT|fallos" || true

echo "== 3. Definiciones de funciones y políticas previas a E9 idénticas (DC-10)"
defs(){ $PG -d "$1" -At -c "select 'function ' || p.oid::regprocedure::text || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' union all select 'policy ' || tablename || '.' || policyname || '|' || md5(coalesce(qual, '') || coalesce(with_check, '') || cmd || roles::text) from pg_policies where schemaname = 'public' order by 1"; }
defs "$BASE" | sort >"$OUT/defs_base.txt"; defs "$E9" | sort >"$OUT/defs_e9.txt"
CHANGED=$(join -t'|' "$OUT/defs_base.txt" "$OUT/defs_e9.txt" | awk -F'|' '$2 != $3' | wc -l)
REMOVED=$(comm -23 <(cut -d'|' -f1 "$OUT/defs_base.txt") <(cut -d'|' -f1 "$OUT/defs_e9.txt") | wc -l)
ADDED=$(comm -13 <(cut -d'|' -f1 "$OUT/defs_base.txt") <(cut -d'|' -f1 "$OUT/defs_e9.txt") | paste -sd';')
echo "    funciones y políticas previas a E9: $(wc -l <"$OUT/defs_base.txt"); modificadas: $CHANGED; eliminadas: $REMOVED"
echo "    nuevas: $ADDED"
[[ $CHANGED -eq 0 && $REMOVED -eq 0 ]] && ok "ninguna función ni política previa a E9 fue modificada o eliminada" || ko "definiciones previas modificadas"

echo "== 4. Suite SQL vigente con E9 (tests homologados en el repositorio + E9)"
bash "$REPO/scripts/e10_local_sql_suite.sh" "$E9" "$T" >"$OUT/suite_e9.txt" 2>&1
echo "    PASS=$(grep -c 'RESULT PASS' "$OUT/suite_e9.txt") FAIL=$(grep -c 'RESULT FAIL' "$OUT/suite_e9.txt")"
grep -h "RACE " "$OUT/suite_e9.txt" | sed 's/^/    /'
echo "    E9: $(grep 'RESULT PASS e9_' "$OUT/suite_e9.txt" | sed 's/RESULT PASS //' | paste -sd' ')"
for t in e9_t02_modelo e9_t03_rpc e9_t06_integracion e9_t07_matriz_local_cerrado; do grep -q "RESULT PASS $t" "$OUT/suite_e9.txt" && ok "$t" || ko "$t"; done

echo "== 5. Procedencia de cada fallo: misma prueba en la baseline pre-E9 (versión del test en $BASEREF)"
BT=$OUT/tests_base; mkdir -p "$BT"; git -C "$REPO" archive "$BASEREF" supabase/tests | tar -x -C "$OUT" && cp "$OUT"/supabase/tests/*.sql "$BT"/
drop "$BASE"; replay "$BASE" 20260930000200 >/dev/null
bash "$REPO/scripts/e10_local_sql_suite.sh" "$BASE" "$BT" >"$OUT/suite_base.txt" 2>&1
key(){ grep -A1 "RESULT FAIL" "$1" | sed 's/ (exit [0-9]*)//' | sed 's/psql:[^:]*:[0-9]*: //' ; }
while read -r line; do
  name=${line#RESULT FAIL }; name=${name% (exit*}
  e9err=$(grep -A1 -F "RESULT FAIL $name" "$OUT/suite_e9.txt" | sed -n 2p | sed 's/psql:[^:]*:[0-9]*: //' | sed 's/^ *//')
  if grep -q -F "RESULT FAIL $name" "$OUT/suite_base.txt"; then
    berr=$(grep -A1 -F "RESULT FAIL $name" "$OUT/suite_base.txt" | sed -n 2p | sed 's/psql:[^:]*:[0-9]*: //' | sed 's/^ *//')
    if [[ "$e9err" == "$berr" ]]; then echo "    PREEXISTENTE (mismo error en la baseline): $name :: $e9err"
    else echo "    PREEXISTENTE (falla en la baseline; el valor del error difiere): $name :: E9 [$e9err] | baseline [$berr]"; fi
  else echo "    NUEVO CON E9: $name :: $e9err"; ko "fallo nuevo con E9: $name"; fi
done < <(grep "RESULT FAIL" "$OUT/suite_e9.txt")

echo "== 6. Diagnóstico complementario (no es criterio de éxito ni se versiona): correcciones H1/H2 de E10 en copias en ambos lados"
for side in base e9; do
  D=$OUT/diag_$side; mkdir -p "$D"; if [[ $side == base ]]; then cp "$BT"/*.sql "$D"/; else cp "$T"/*.sql "$D"/; fi
  for f in "$D"/*.sql; do case $(basename "$f") in e7_*|e10_*|e9_*) ;; *) sed -i "s/'40001'/'PT409'/g" "$f";; esac; done
  sed -i "s/raise exception 'TP21 cambió el cuerpo de registrar_auditoria_detalle_pedido()';/null;/" "$D/order_audit_trail.sql"
  sed -i "s/valida la asignación e inmutabilidad de enviado_en y propaga a pedido únicamente las modificaciones de contenido definidas por el comportamiento actual\./valida la asignación e inmutabilidad de enviado_en (ABIERTO -> ENVIADO, o ABIERTO -> LISTO sin cocina según E7-D05) y propaga a pedido únicamente las modificaciones de contenido./" "$D/dbstd_t04_catalog_comments.sql"
done
for f in h4_t05_realtime_publication_rls h5_t06_realtime_cashier_signal; do sed -i "s/'public.detalle_pedido', 'public.mesa', 'public.pedido'$/'public.detalle_pedido', 'public.mesa', 'public.pedido', 'public.solicitud_cuenta'/" "$OUT/diag_base/$f.sql"; done
DB=e9_t07_db_$TS; drop "$DB"; replay "$DB" 20260930000200 >/dev/null; bash "$REPO/scripts/e10_local_sql_suite.sh" "$DB" "$OUT/diag_base" >"$OUT/diag_base.txt" 2>&1; drop "$DB"
DE=e9_t07_de_$TS; drop "$DE"; replay "$DE" all >/dev/null; bash "$REPO/scripts/e10_local_sql_suite.sh" "$DE" "$OUT/diag_e9" >"$OUT/diag_e9.txt" 2>&1; drop "$DE"
for s in base e9; do echo "    DIAGNÓSTICO $s: PASS=$(grep -c 'RESULT PASS' "$OUT/diag_$s.txt") FAIL=$(grep -c 'RESULT FAIL' "$OUT/diag_$s.txt")"; done
NEWD=$(comm -13 <(grep "RESULT FAIL" "$OUT/diag_base.txt" | sed 's/ (exit.*//' | sort) <(grep "RESULT FAIL" "$OUT/diag_e9.txt" | sed 's/ (exit.*//' | sort))
[[ -z "$NEWD" ]] && echo "    diagnóstico: ningún fallo adicional con E9 detrás de los fallos preexistentes" || { echo "    diagnóstico: fallos adicionales con E9:"; echo "$NEWD" | sed 's/^/      /'; ko "diagnóstico con fallos adicionales"; }

echo "== 7. Carreras reales (TP16–TP18 de E9; E7 y E10 vigentes)"
TPL=e9_t07_tpl_$TS; replay "$TPL" all >/dev/null
bash "$REPO/scripts/e9_concurrency.sh" "$TPL" all >"$OUT/conc_e9.txt" 2>&1; grep -E "RACE|RESULT|fallos" "$OUT/conc_e9.txt" | sed 's/^/    /'
grep -q "== fallos: 0" "$OUT/conc_e9.txt" && ok "carreras E9 TP16–TP18" || ko "carreras E9"
C7=e9_t07_c7_$TS; replay "$C7" all >/dev/null
PSQL_CONN="-h /tmp -p $PORT -U postgres -d $C7" bash "$REPO/scripts/e7_concurrency.sh" all >"$OUT/conc_e7.txt" 2>&1
echo "    E7: OK=$(grep -c '^  OK' "$OUT/conc_e7.txt") $(grep '== fallos' "$OUT/conc_e7.txt")"; grep -q "== fallos: 0" "$OUT/conc_e7.txt" && ok "carreras E7 vigentes" || ko "carreras E7"
bash "$REPO/scripts/e10_concurrency.sh" all >"$OUT/conc_e10.txt" 2>&1
echo "    E10: PASS=$(grep -c 'RESULT PASS' "$OUT/conc_e10.txt") $(grep '== fallos' "$OUT/conc_e10.txt")"; grep -q "== fallos: 0" "$OUT/conc_e10.txt" && ok "carreras E10 vigentes" || ko "carreras E10"
drop "$TPL"; drop "$C7"

echo "== 8. Integración técnica y señal Realtime local (T06)"
bash "$REPO/scripts/e9_t06_integracion.sh" >"$OUT/t06.txt" 2>&1; grep -E "RESULT|WAL|RESIDUO" "$OUT/t06.txt" | sed 's/^/    /'
grep -q "== fallos: 0" "$OUT/t06.txt" && ok "integración T06" || ko "integración T06"

echo "== 9. Node completo y typecheck"
(cd "$REPO" && node --experimental-strip-types --test tests/*.test.mjs) >"$OUT/node.txt" 2>&1
echo "    $(grep -E '^# (tests|pass|fail)' "$OUT/node.txt" | paste -sd' ')"; grep -q "^# fail 0" "$OUT/node.txt" && ok "suite Node completa" || ko "suite Node"
(cd "$REPO" && node node_modules/typescript/bin/tsc --noEmit) >"$OUT/tsc.txt" 2>&1 && ok "typecheck" || { ko "typecheck"; head -5 "$OUT/tsc.txt"; }

drop "$E9"; drop "$BASE"
echo "RESIDUO slots=$($PG -d postgres -At -c "select count(*) from pg_replication_slots") conexiones=$($PG -d postgres -At -c "select count(*) from pg_stat_activity where application_name like 'e%_race'") bases=$($PG -d postgres -At -c "select count(*) from pg_database where datname like 'e9_t07_%' or datname like 'e9_race_%'")"
echo "Salida detallada: $OUT"
echo "== fallos: $FAILS"; exit $((FAILS>0))
