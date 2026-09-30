#!/usr/bin/env bash
# E10-T07 — Campaña SQL integral única sobre PostgreSQL local (ver specs/E10-AccountRequest/implementation.md §1).
# Uso: scripts/e10_t07_campaign.sh   Salida: resultados por bloque; bases efímeras eliminadas al final.
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); T=$REPO/supabase/tests; TS=$(date +%s); FAILS=0; OUT=${TMPDIR:-/tmp}/e10_t07_$TS
mkdir -p "$OUT"
PORT=${PGPORT:-54329}; PG="psql -h /tmp -p $PORT -U postgres -X -v ON_ERROR_STOP=1 -q"
q(){ $PG -d "$1" -At -c "$2"; }
drop(){ dropdb -h /tmp -p $PORT -U postgres --force "$1" 2>/dev/null; }

echo "== 1. Replay limpio total"
E10=e10_t07_e10_$TS; BASE=e10_t07_base_$TS
bash "$REPO/scripts/e10_local_replay.sh" "$E10" "$REPO" all | tail -1 || FAILS=$((FAILS+1))
echo "MIGRACIONES $(ls "$REPO/supabase/migrations" | grep -c '\.sql$') en disco; orden estricto: $(ls "$REPO/supabase/migrations" | grep '\.sql$' | sort -c && echo si)"
bash "$REPO/scripts/e10_local_replay.sh" "$BASE" "$REPO" 20260924000800 | tail -1

echo "== 2. SQL E10"
for f in e10_t02_modelo e10_t03_solicitud e10_t06_integracion e10_t07_complementos; do
  if (cd "$T" && $PG -d "$E10" -f "$f.sql") >"$OUT/$f.out" 2>&1; then echo "RESULT PASS $f"; grep -h "NOTICE" "$OUT/$f.out" | sed 's/.*NOTICE:  /    /'; else echo "RESULT FAIL $f"; grep -h ERROR "$OUT/$f.out" | head -3; FAILS=$((FAILS+1)); fi
done

echo "== 3. Suite SQL histórica sin homologar: línea base vs E10"
bash "$REPO/scripts/e10_local_sql_suite.sh" "$BASE" "$T" pre-e10 >"$OUT/suite_base.txt" 2>&1
bash "$REPO/scripts/e10_local_replay.sh" "${BASE}b" "$REPO" 20260924000800 >/dev/null; drop "$BASE"; BASE=${BASE}b
bash "$REPO/scripts/e10_local_replay.sh" "${E10}s" "$REPO" all >/dev/null
bash "$REPO/scripts/e10_local_sql_suite.sh" "${E10}s" "$T" >"$OUT/suite_e10.txt" 2>&1; drop "${E10}s"
for s in base e10; do echo "SUITE $s: PASS=$(grep -c 'RESULT PASS' "$OUT/suite_$s.txt") FAIL=$(grep -c 'RESULT FAIL' "$OUT/suite_$s.txt")"; done
grep -h "RACE " "$OUT/suite_e10.txt" | sed 's/^/    e10 /'
diff <(grep "RESULT FAIL" "$OUT/suite_base.txt" | sed 's/ (exit.*//' | sort) <(grep "RESULT FAIL" "$OUT/suite_e10.txt" | sed 's/ (exit.*//' | sort) >"$OUT/diff_fail.txt"
if [[ -s "$OUT/diff_fail.txt" ]]; then echo "DIFERENCIAS sin homologar (clasificar; ver bloque 4):"; cat "$OUT/diff_fail.txt"; else echo "RESULT PASS mismos fallos preexistentes en ambas bases (sin regresiones)"; fi
echo "    E10 nuevas en suite: $(grep 'RESULT PASS e10_' "$OUT/suite_e10.txt" | sed 's/RESULT PASS //' | paste -sd' ')"

echo "== 4. Suite histórica homologada en copias temporales: H1/H2 de E7-T11 (ambas bases) y H3 de E10 (publicación, sólo E10)"
H=$OUT/hom; cp -r "$T" "$H"
for f in "$H"/*.sql; do case $(basename "$f") in e7_*|e10_*) ;; *) sed -i "s/'40001'/'PT409'/g" "$f";; esac; done
sed -i "s/raise exception 'TP21 cambió el cuerpo de registrar_auditoria_detalle_pedido()';/null; -- homologación E7-T11 (E7-D05)/" "$H/order_audit_trail.sql"
sed -i "s/Mantiene la auditoría de detalle_pedido, protege sus campos de creación, valida la asignación e inmutabilidad de enviado_en y propaga a pedido únicamente las modificaciones de contenido definidas por el comportamiento actual\./Mantiene la auditoría de detalle_pedido, protege sus campos de creación, valida la asignación e inmutabilidad de enviado_en (ABIERTO -> ENVIADO, o ABIERTO -> LISTO sin cocina según E7-D05) y propaga a pedido únicamente las modificaciones de contenido./" "$H/dbstd_t04_catalog_comments.sql"
bash "$REPO/scripts/e10_local_replay.sh" "${BASE}h" "$REPO" 20260924000800 >/dev/null
bash "$REPO/scripts/e10_local_sql_suite.sh" "${BASE}h" "$H" pre-e10 >"$OUT/hom_base.txt" 2>&1; drop "${BASE}h"
# H3 (sólo base E10, spec E10-D18/TP20): h4_t05 y h5_t06 fijan la publicación exacta de tres tablas; E10 agrega
# solicitud_cuenta (E10-D07). Se amplía sólo el arreglo esperado; el resto de sus aserciones se ejecuta intacto.
H10=$OUT/hom10; cp -r "$H" "$H10"
for f in h4_t05_realtime_publication_rls h5_t06_realtime_cashier_signal; do
  sed -i "s/'public.detalle_pedido', 'public.mesa', 'public.pedido'$/'public.detalle_pedido', 'public.mesa', 'public.pedido', 'public.solicitud_cuenta' -- homologación E10-D07/" "$H10/$f.sql"
  echo "HOMOLOGACION H3 $f: $(grep -c 'homologación E10-D07' "$H10/$f.sql") cambio(s)"
done
bash "$REPO/scripts/e10_local_replay.sh" "${E10}h" "$REPO" all >/dev/null
bash "$REPO/scripts/e10_local_sql_suite.sh" "${E10}h" "$H10" >"$OUT/hom_e10.txt" 2>&1; drop "${E10}h"
for s in base e10; do echo "HOMOLOGADA $s: PASS=$(grep -c 'RESULT PASS' "$OUT/hom_$s.txt") FAIL=$(grep -c 'RESULT FAIL' "$OUT/hom_$s.txt")"; grep "RESULT FAIL" "$OUT/hom_$s.txt" | sed 's/^/    /'; done
diff <(grep "RESULT FAIL" "$OUT/hom_base.txt" | sed 's/ (exit.*//' | sort) <(grep "RESULT FAIL" "$OUT/hom_e10.txt" | sed 's/ (exit.*//' | sort) >"$OUT/diff_hom.txt"
if [[ -s "$OUT/diff_hom.txt" ]]; then echo "REGRESION? diferencias homologadas:"; cat "$OUT/diff_hom.txt"; FAILS=$((FAILS+1)); else echo "RESULT PASS homologada: mismos fallos en ambas bases"; fi

echo "== 5. Seguridad y catálogo (base E10)"
echo "SEC funciones_con_40001=$(q $E10 "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc like '%40001%'")"
echo "SEC definer_inseguras=$(q $E10 "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and (pg_get_userbyid(p.proowner)<>'postgres' or coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=pg_catalog%')")"
echo "SEC funciones_anon=$(q $E10 "select coalesce(string_agg(p.oid::regprocedure::text, ', '), '-') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and has_function_privilege('anon',p.oid,'execute')")"
echo "SEC tablas_sin_rls=$(q $E10 "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity")"
echo "SEC tablas_escritura_anon=$(q $E10 "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and (has_table_privilege('anon',c.oid,'insert') or has_table_privilege('anon',c.oid,'update') or has_table_privilege('anon',c.oid,'delete'))")"
echo "SEC e10_objetos $(q $E10 "select string_agg(p.oid::regprocedure::text || ' auth=' || has_function_privilege('authenticated',p.oid,'execute') || ' anon=' || has_function_privilege('anon',p.oid,'execute') || ' service=' || has_function_privilege('service_role',p.oid,'execute'), '; ' order by 1) from pg_proc p where p.proname in ('rpc_solicitar_cuenta_pedido','obtener_pedidos_pendientes_pago_caja','tgf_solicitud_cuenta_inmutable','tgf_pedido_cerrar_solicitud_cuenta')")"
echo "SEC solicitud_cuenta authenticated=$(q $E10 "select string_agg(x, ',') from unnest(array['select','insert','update','delete','truncate']) x where has_table_privilege('authenticated','public.solicitud_cuenta',x)") anon=$(q $E10 "select coalesce(string_agg(x, ','),'-') from unnest(array['select','insert','update','delete','truncate']) x where has_table_privilege('anon','public.solicitud_cuenta',x)") service_role=$(q $E10 "select coalesce(string_agg(x, ','),'-') from unnest(array['select','insert','update','delete','truncate']) x where has_table_privilege('service_role','public.solicitud_cuenta',x)")"
echo "SEC publicacion=$(q $E10 "select string_agg(tablename, ',' order by tablename) from pg_publication_tables where pubname='supabase_realtime'")"
echo "SEC estados_pedido=$(q $E10 "select pg_get_constraintdef(oid) from pg_constraint where conname='ck_pedido_estado_valido'" | grep -o "'[A-Z_]*'" | paste -sd,)"
echo "SEC estados_mesa=$(q $E10 "select pg_get_constraintdef(oid) from pg_constraint where conrelid='public.mesa'::regclass and contype='c' and pg_get_constraintdef(oid) like '%PENDIENTE_PAGO%'" | grep -o "'[A-Z_]*'" | paste -sd,)"
echo "SEC estados_detalle=$(q $E10 "select pg_get_constraintdef(oid) from pg_constraint where conrelid='public.detalle_pedido'::regclass and contype='c' and pg_get_constraintdef(oid) like '%RECIBIDO_COCINA%' and pg_get_constraintdef(oid) not like '%requiere_cocina%'" | grep -o "'[A-Z_]*'" | sort -u | paste -sd,)"
drop "$E10"; drop "$BASE"

echo "== 6. Carreras reales (TP05, TP10, TP11)"
bash "$REPO/scripts/e10_concurrency.sh" all 2>&1 | grep "RACE\|RESULT\|RESIDUO\|fallos" || true
bash "$REPO/scripts/e10_concurrency.sh" all >/dev/null 2>&1 || FAILS=$((FAILS+1))

echo "== 7. Integración y señal WAL (T06)"
bash "$REPO/scripts/e10_t06_integracion.sh" 2>&1 | grep "RESULT\|WAL\|PUBLICACION\|RESIDUO" || true

echo "== 8. Residuos"
echo "RESIDUO bases=$(q postgres "select count(*) from pg_database where datname like 'e10_t07_%' or datname like 'e10_cc_%' or datname like 'e10_t06_%'") slots=$(q postgres "select count(*) from pg_replication_slots") conexiones=$(q postgres "select count(*) from pg_stat_activity where application_name like 'e10%'")"
echo "SALIDA $OUT"; echo "== fallos: $FAILS"; exit $((FAILS>0))
