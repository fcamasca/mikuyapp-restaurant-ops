#!/usr/bin/env bash
# E7-T11 — Campaña SQL integral dentro del contenedor de base del stack Supabase LOCAL.
# Uso (lo invoca scripts/e7_t11_campaign.ps1):  bash /tmp/e7/scripts/e7_t11_sql_campaign.sh <fase>
#   fase = real      -> base `postgres` del stack (db reset): SQL E7, integración, privilegios, 40001, seguridad
#   fase = aislada   -> base efímera con replay completo (57 migraciones + seed): suite SQL completa y carreras históricas
#   fase = baseline  -> base efímera con replay sólo hasta 20260922000100 (pre-E7): reproducción HZ-01
#   fase = dbstd     -> base efímera con replay completo: prueba compensatoria histórica DBSTD-T09 (destructiva)
#   fase = drop <db> -> elimina una base efímera
# Nunca se conecta fuera del contenedor. Las bases efímeras se eliminan al terminar la campaña.
set -uo pipefail
DIR=/tmp/e7
T=$DIR/supabase/tests
PSQL="psql -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -U postgres"
FAILS=0

result() { # result <nombre> <archivo_salida> <exit>
  local name=$1 out=$2 code=$3
  if [[ $code -eq 0 ]]; then echo "RESULT PASS $name"; grep -h "NOTICE: \|NOTICE:  " "$out" | sed 's/^/    /' | head -3
  else echo "RESULT FAIL $name (exit $code)"; grep -v "^\s*$" "$out" | grep -i "error\|DETAIL\|CONTEXT\|HINT\|exception" | head -8 | sed 's/^/    /'; FAILS=$((FAILS+1)); fi
}
runf() { # runf <db> <archivo> [nombre]
  local db=$1 f=$2 name=${3:-$(basename "$2" .sql)} out; out=$(mktemp)
  (cd "$(dirname "$f")" && $PSQL -d "$db" -q -f "$(basename "$f")") >"$out" 2>&1; result "$name" "$out" $?; rm -f "$out"; }
q() { $PSQL -d "$1" -At -c "$2"; }

replay() { # replay <db> <hasta_migracion|all>
  local db=$1 until=$2 n=0 m
  createdb -U postgres --template=template0 "$db" || return 1
  pg_dump -U supabase_admin -d postgres --schema-only --exclude-schema=public | psql -X -q -U supabase_admin -d "$db" -v ON_ERROR_STOP=1 >/dev/null || { echo "REPLAY FAIL esquema de plataforma"; return 1; }
  for m in $(ls "$DIR/supabase/migrations" | grep '\.sql$' | sort); do
    $PSQL -d "$db" -q -f "$DIR/supabase/migrations/$m" >/tmp/e7/replay.out 2>&1 || { echo "REPLAY FAIL $m"; grep -i error /tmp/e7/replay.out | head -5; return 1; }
    n=$((n+1)); [[ "$until" != all && "$m" == "$until"* ]] && break
  done
  $PSQL -d "$db" -q -f "$DIR/supabase/seed.sql" >/dev/null 2>&1 || { echo "REPLAY FAIL seed"; return 1; }
  echo "REPLAY OK $db: $n migraciones (última $m) + seed"
}

# Carrera histórica genérica: A mantiene la transacción abierta; B se lanza mientras A retiene el lock.
race() { # race <db> <nombre> <setup> <callA> <callB> <verify|-> <cleanup>
  local db=$1 name=$2 setup=$3 a=$4 b=$5 verify=$6 cleanup=$7 oa ob
  oa=$(mktemp); ob=$(mktemp)
  runf "$db" "$T/$setup" "$name setup" >/dev/null
  (cd "$T" && PGAPPNAME=e7_t11_race $PSQL -d "$db" -q -c "begin" -f "$a" -c "select pg_sleep(2)" -c "commit") >"$oa" 2>&1 & local pa=$!
  sleep 0.7
  (cd "$T" && PGAPPNAME=e7_t11_race $PSQL -d "$db" -q -c "begin" -f "$b" -c "commit") >"$ob" 2>&1 & local pb=$!
  wait $pa; local ca=$?; wait $pb; local cb=$?
  local sa sb; sa=$(grep -o "ERROR:  [0-9A-Z]\{5\}" "$oa" | head -1 | awk '{print $2}'); sb=$(grep -o "ERROR:  [0-9A-Z]\{5\}" "$ob" | head -1 | awk '{print $2}')
  echo "RACE $name: A exit=$ca ${sa:+sqlstate=$sa} | B exit=$cb ${sb:+sqlstate=$sb}"
  [[ -n "$sb" ]] && grep -h "ERROR:" "$ob" | head -2 | sed 's/^/    B /'
  [[ -n "$sa" ]] && grep -h "ERROR:" "$oa" | head -2 | sed 's/^/    A /'
  if [[ "$sa$sb" == *40001* ]]; then echo "RESULT FAIL $name: aparece 40001"; FAILS=$((FAILS+1)); fi
  if [[ $ca -ne 0 && $cb -ne 0 ]]; then echo "RESULT FAIL $name: ambas sesiones fallaron"; FAILS=$((FAILS+1)); fi
  if [[ "$verify" != - ]]; then runf "$db" "$T/$verify" "$name verify"; else echo "RESULT PASS $name (una sesión confirmó)"; fi
  runf "$db" "$T/$cleanup" "$name cleanup"
  rm -f "$oa" "$ob"
}

suite() { # suite <db> [pre-e7]: B1 standalone, B2 E1 con fixtures, B3 carreras históricas
  local DB=$1 pre=${2:-}
    echo "== B1 suite SQL vigente (standalone, orden alfabético)"
    for f in $(ls $T/*.sql | xargs -n1 basename | sort); do
      [[ -n "$pre" && $f == e7_* ]] && continue
      case $f in *_setup.sql|*_call.sql|*_verify.sql|*_cleanup.sql|*_fixture.sql|*_add.sql|*_pay.sql|dbstd_t09_*|e7_t05b_hz01_*|e1_t03_caja_sesion.sql|e1_t04_apertura_sesion.sql|e1_t05_movimientos_cierre.sql|e1_t06_descuento_pedido.sql|e1_t07_anulacion_administrativa.sql|e1_t08_pago_sesion.sql) continue;; esac
      runf $DB "$T/$f"
    done
    echo "== B2 E1 con fixtures (orden de los runners E1)"
    runf $DB "$T/e1_t03_fixture.sql"; runf $DB "$T/e1_t03_caja_sesion.sql"
    runf $DB "$T/e1_t04_fixture.sql"; runf $DB "$T/e1_t04_apertura_sesion.sql"
    runf $DB "$T/e1_t05_concurrency_setup.sql"; runf $DB "$T/e1_t05_movimientos_cierre.sql"
    runf $DB "$T/e1_t06_concurrency_setup.sql"; runf $DB "$T/e1_t06_descuento_pedido.sql"
    runf $DB "$T/e1_t07_concurrency_setup.sql"; runf $DB "$T/e1_t07_anulacion_administrativa.sql"
    runf $DB "$T/e1_t08_concurrency_setup.sql"; runf $DB "$T/e1_t08_pago_sesion.sql"
    echo "== B3 carreras históricas H4/H5 (conexiones independientes)"
    race $DB "H4-T03 doble transición cocina" h4_t03_concurrency_setup.sql h4_t03_concurrency_call.sql h4_t03_concurrency_call.sql - h4_t03_concurrency_cleanup.sql
    race $DB "H5-T02 doble entrega" h5_t02_concurrency_setup.sql h5_t02_concurrency_call.sql h5_t02_concurrency_call.sql h5_t02_concurrency_verify.sql h5_t02_concurrency_cleanup.sql
    race $DB "H5-T02 reapertura vs pago" h5_t02_reopen_vs_payment_setup.sql h5_t02_reopen_vs_payment_add.sql h5_t02_reopen_vs_payment_pay.sql h5_t02_reopen_vs_payment_verify.sql h5_t02_reopen_vs_payment_cleanup.sql
    race $DB "H5-T04 doble pago" h5_t04_concurrency_setup.sql h5_t04_concurrency_call.sql h5_t04_concurrency_call.sql h5_t04_concurrency_verify.sql h5_t04_concurrency_cleanup.sql
}

security_catalog() { # security_catalog <db>
  local db=$1
  echo "== 40001 manual en funciones vigentes de public"
  echo "SEC funciones_con_40001=$(q "$db" "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc like '%40001%'")"
  q "$db" "select '    '||p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc like '%40001%' order by 1"
  echo "== SECURITY DEFINER inseguros (owner distinto de postgres o search_path distinto de pg_catalog)"
  echo "SEC definer_inseguras=$(q "$db" "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and (pg_get_userbyid(p.proowner)<>'postgres' or coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=pg_catalog%')")"
  q "$db" "select '    '||p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and (pg_get_userbyid(p.proowner)<>'postgres' or coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=pg_catalog%') order by 1"
  echo "== funciones de public ejecutables por anon"
  echo "SEC funciones_anon=$(q "$db" "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and has_function_privilege('anon',p.oid,'execute')")"
  q "$db" "select '    '||p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and has_function_privilege('anon',p.oid,'execute') order by 1"
  echo "== tablas de public sin RLS"
  echo "SEC tablas_sin_rls=$(q "$db" "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity")"
  echo "== escritura de anon sobre tablas de public"
  echo "SEC tablas_escritura_anon=$(q "$db" "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and (has_table_privilege('anon',c.oid,'insert') or has_table_privilege('anon',c.oid,'update') or has_table_privilege('anon',c.oid,'delete'))")"
  echo "== detalle_pedido: UPDATE/DELETE directo de authenticated y políticas eliminadas por E7-D15"
  echo "SEC detalle_update_auth=$(q "$db" "select has_table_privilege('authenticated','public.detalle_pedido','update')") detalle_delete_auth=$(q "$db" "select has_table_privilege('authenticated','public.detalle_pedido','delete')") politicas_mutacion=$(q "$db" "select count(*) from pg_policies where tablename='detalle_pedido' and policyname in ('detalle_pedido_update_abierto_mozo','detalle_pedido_delete_abierto_mozo')")"
  echo "== columnas de detalle_pedido actualizables por authenticated"
  q "$db" "select '    '||attname from pg_attribute where attrelid='public.detalle_pedido'::regclass and attnum>0 and not attisdropped and has_column_privilege('authenticated','public.detalle_pedido',attname,'update') order by 1"
  echo "== requiere_cocina de producto: privilegio de columna por rol"
  echo "SEC producto_requiere_cocina insert_auth=$(q "$db" "select has_column_privilege('authenticated','public.producto','requiere_cocina','insert')") update_auth=$(q "$db" "select has_column_privilege('authenticated','public.producto','requiere_cocina','update')") update_anon=$(q "$db" "select has_column_privilege('anon','public.producto','requiere_cocina','update')")"
}

case "${1:-}" in
  real)
    DB=postgres
    echo "== versiones"; q $DB "select version()"; q $DB "select count(*)||' migraciones; primera '||min(version)||'; última '||max(version) from supabase_migrations.schema_migrations"
    echo "ORDEN migraciones_ordenadas=$(q $DB "select bool_and(ok) from (select version > lag(version) over (order by version) or lag(version) over (order by version) is null as ok from supabase_migrations.schema_migrations) s")"
    echo "== publicación Realtime"; q $DB "select string_agg(tablename, ',' order by tablename) from pg_publication_tables where pubname='supabase_realtime'"
    echo "== privilegios E7 con roles reales (service_role/authenticated/anon)"
    q $DB "select 'tabla '||t||' service_role='||has_table_privilege('service_role',t,'select')||' authenticated='||has_table_privilege('authenticated',t,'select')||' anon='||has_table_privilege('anon',t,'select') from unnest(array['public.historial_detalle_pedido','public.comanda']) t"
    q $DB "select 'truncate service_role '||t||'='||has_table_privilege('service_role',t,'truncate') from unnest(array['public.historial_detalle_pedido','public.comanda']) t"
    q $DB "select 'funcion '||p.oid::regprocedure||' service_role='||has_function_privilege('service_role',p.oid,'execute')||' authenticated='||has_function_privilege('authenticated',p.oid,'execute')||' anon='||has_function_privilege('anon',p.oid,'execute') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like 'rpc\_%' and p.proname in ('rpc_obtener_tablero_cocina','rpc_recibir_pedido_cocina','rpc_cancelar_detalle_pedido','rpc_obtener_cancelaciones_pedido','rpc_modificar_detalle_pedido','rpc_retirar_detalle_pedido','rpc_registrar_impresion_comanda') or p.proname like 'tgf\_%comanda%' or p.proname like 'tgf\_%historial\_detalle%' or p.proname = 'tgf_detalle_pedido_historial_estado') order by 1"
    for f in e7_t02_modelo e7_t03_envio e7_t04_recepcion_tablero e7_t05_cancelacion e7_t05b_edicion_retiro e7_t09_impresion_comanda e7_t10_integracion; do runf $DB "$T/$f.sql"; done
    security_catalog $DB
    ;;
  aislada)
    DB=e7_t11_$(date +%s); echo "DB=$DB"
    replay $DB all || { echo "== fallos: replay"; exit 1; }
    suite $DB
    security_catalog $DB
    echo "$DB" > $DIR/t11_db
    ;;
  homolog)
    # Suite histórica con homologaciones documentadas en copias temporales (el repositorio no se modifica):
    #  H1) E1-T18/D17: conflictos funcionales '40001' -> 'PT409' (todas las pruebas históricas, ambas bases).
    #  H2) sólo base E7: TP21 del cuerpo de registrar_auditoria_detalle_pedido (E7-D05, D-1) y su comentario DBSTD-TP16.
    # Se ejecuta sobre la baseline pre-E7 (pre) y sobre el esquema completo (e7) para comparar resultados.
    mode=${2:?pre|e7}; H=$DIR/hom_$mode; rm -rf $H; cp -r $T $H
    for f in $H/*.sql; do case $(basename $f) in e7_*) ;; *) sed -i "s/'40001'/'PT409'/g" "$f";; esac; done
    if [[ $mode == e7 ]]; then
      sed -i "s/raise exception 'TP21 cambió el cuerpo de registrar_auditoria_detalle_pedido()';/null; -- E7-T11 homologación: cuerpo reemplazado por E7-T03 (E7-D05, D-1)/" $H/order_audit_trail.sql
      sed -i "s/Mantiene la auditoría de detalle_pedido, protege sus campos de creación, valida la asignación e inmutabilidad de enviado_en y propaga a pedido únicamente las modificaciones de contenido definidas por el comportamiento actual\./Mantiene la auditoría de detalle_pedido, protege sus campos de creación, valida la asignación e inmutabilidad de enviado_en (ABIERTO -> ENVIADO, o ABIERTO -> LISTO sin cocina según E7-D05) y propaga a pedido únicamente las modificaciones de contenido./" $H/dbstd_t04_catalog_comments.sql
    fi
    echo "HOMOLOGACION $mode: 40001->PT409 en $(grep -l "'PT409'" $H/*.sql | grep -v '/e7_' | wc -l) archivos históricos; E7: $(grep -c 'E7-T11 homologación' $H/order_audit_trail.sql) cambio(s) en order_audit_trail, $(grep -c 'E7-D05' $H/dbstd_t04_catalog_comments.sql) en dbstd_t04"
    DB=e7_t11_hom_${mode}_$(date +%s); echo "DB=$DB"
    if [[ $mode == e7 ]]; then replay $DB all || exit 1; else replay $DB 20260922000100 || exit 1; fi
    T=$H; suite $DB $([[ $mode == pre ]] && echo pre-e7)
    dropdb -U postgres --force $DB && echo "DROP $DB"; rm -rf $H
    ;;
  baselinesuite)
    DB=e7_t11_presuite_$(date +%s); echo "DB=$DB"
    replay $DB 20260922000100 || { echo "== fallos: replay baseline"; exit 1; }
    suite $DB pre-e7
    security_catalog $DB
    dropdb -U postgres --force $DB && echo "DROP $DB"
    ;;
  baseline)
    DB=e7_t11_base_$(date +%s); echo "DB=$DB"
    replay $DB 20260922000100 || { echo "== fallos: replay baseline"; exit 1; }
    runf $DB "$T/e7_t05b_hz01_reproduccion_baseline.sql"
    dropdb -U postgres --force $DB && echo "DROP $DB"
    ;;
  dbstdbase)
    DB=e7_t11_dbstdpre_$(date +%s); echo "DB=$DB"
    replay $DB 20260922000100 || { echo "== fallos: replay baseline"; exit 1; }
    runf $DB "$T/dbstd_t09_compensating_rollback.sql"
    dropdb -U postgres --force $DB && echo "DROP $DB"
    ;;
  dbstd)
    DB=e7_t11_dbstd_$(date +%s); echo "DB=$DB"
    replay $DB all || { echo "== fallos: replay dbstd"; exit 1; }
    runf $DB "$T/dbstd_t09_compensating_rollback.sql"
    dropdb -U postgres --force $DB && echo "DROP $DB"
    ;;
  drop)
    echo "RESIDUO conexiones_campaña=$(q postgres "select count(*) from pg_stat_activity where application_name like 'e7_t11%' or application_name like 't09_%' or application_name='e7_concurrency'")"
    dropdb -U postgres --force "$2" && echo "DROP $2"
    echo "RESIDUO bases_efimeras=$(q postgres "select count(*) from pg_database where datname like 'e7_t11%' or datname like 'e1_t%'")"
    ;;
  *) echo "fase desconocida"; exit 2;;
esac
echo "== fallos: $FAILS"
exit $((FAILS>0))
