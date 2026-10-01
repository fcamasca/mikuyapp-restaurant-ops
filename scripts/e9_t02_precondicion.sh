#!/usr/bin/env bash
# E9-TP02 — Precondición de la migración E9-T02 (DC-12): aborta con mensaje explícito si existen
# filas en pedido o sesion_caja y no deja objetos parciales; sobre la baseline vacía, aplica.
# Uso: scripts/e9_t02_precondicion.sh <db_baseline_pre_e9> <repo>
# Sólo bases locales efímeras (socket /tmp, puerto $PGPORT o 54329). Nunca DEV ni PROD.
set -uo pipefail
BASE=$1; REPO=$2; FAILS=0
P="psql -h /tmp -p ${PGPORT:-54329} -U postgres -X -q -v ON_ERROR_STOP=1"
MIG="$REPO/supabase/migrations/20261001000100_e9_t02_jornada_operativa.sql"
fresh(){ dropdb -h /tmp -p ${PGPORT:-54329} -U postgres --if-exists --force "$1" 2>/dev/null; createdb -h /tmp -p ${PGPORT:-54329} -U postgres -T "$BASE" "$1"; }
check(){ if [[ "$2" == "$3" ]]; then echo "RESULT PASS $1"; else echo "RESULT FAIL $1 (esperado '$3', obtenido '$2')"; FAILS=$((FAILS+1)); fi; }

seed_order(){ $P -d "$1" <<'SQL'
insert into auth.users(id,aud,role,email,encrypted_password) values('00000000-0000-0000-0000-0000000e9201','authenticated','authenticated','e9-tp02@example.invalid','t');
insert into public.local(id,codigo,nombre) values('00000000-0000-0000-0000-0000000e9202','E9-TP02','TP02');
insert into public.perfil_usuario(id,local_id,rol_id,nombre) select '00000000-0000-0000-0000-0000000e9201','00000000-0000-0000-0000-0000000e9202',id,'Mozo' from public.rol where codigo='MOZO';
insert into public.mesa(id,local_id,codigo,nombre) values('00000000-0000-0000-0000-0000000e9203','00000000-0000-0000-0000-0000000e9202','M','M');
insert into public.pedido(local_id,mesa_id,creado_por) values('00000000-0000-0000-0000-0000000e9202','00000000-0000-0000-0000-0000000e9203','00000000-0000-0000-0000-0000000e9201');
SQL
}
seed_session(){ $P -d "$1" <<'SQL'
insert into auth.users(id,aud,role,email,encrypted_password) values('00000000-0000-0000-0000-0000000e9211','authenticated','authenticated','e9-tp02c@example.invalid','t');
insert into public.local(id,codigo,nombre) values('00000000-0000-0000-0000-0000000e9212','E9-TP02C','TP02C');
insert into public.perfil_usuario(id,local_id,rol_id,nombre) select '00000000-0000-0000-0000-0000000e9211','00000000-0000-0000-0000-0000000e9212',id,'Caja' from public.rol where codigo='CAJA';
insert into public.caja(id,local_id,codigo,nombre) values('00000000-0000-0000-0000-0000000e9213','00000000-0000-0000-0000-0000000e9212','C','C');
insert into public.sesion_caja(caja_id,local_id,abierta_por,monto_inicial,idempotency_key) values('00000000-0000-0000-0000-0000000e9213','00000000-0000-0000-0000-0000000e9212','00000000-0000-0000-0000-0000000e9211',0,gen_random_uuid());
SQL
}
attempt(){ # db -> imprime "código|mensaje|tabla_creada|columnas|filas"
  local out; out=$($P -d "$1" -f "$MIG" 2>&1); local code=$?
  local msg; msg=$(grep -o "E9: la migración requiere[^\"]*" <<<"$out" | head -1)
  local t; t=$($P -d "$1" -Atc "select to_regclass('public.jornada_operativa') is not null")
  local c; c=$($P -d "$1" -Atc "select count(*) from information_schema.columns where table_schema='public' and column_name='jornada_operativa_id'")
  local r; r=$($P -d "$1" -Atc "select (select count(*) from public.pedido)||'/'||(select count(*) from public.sesion_caja)")
  echo "$code|$msg|$t|$c|$r"
}

fresh e9_tp02_a; seed_order e9_tp02_a
check "TP02 aborta con pedido existente" "$(attempt e9_tp02_a)" "3|E9: la migración requiere pedido y sesion_caja vacías (encontradas: 1 pedidos, 0 sesiones de caja)|f|0|1/0"
fresh e9_tp02_b; seed_session e9_tp02_b
check "TP02 aborta con sesión de caja existente" "$(attempt e9_tp02_b)" "3|E9: la migración requiere pedido y sesion_caja vacías (encontradas: 0 pedidos, 1 sesiones de caja)|f|0|0/1"
fresh e9_tp02_c
check "TP02 aplica sobre la baseline vacía" "$(attempt e9_tp02_c)" "0||t|2|0/0"
check "TP02 sin jornadas creadas" "$($P -d e9_tp02_c -Atc 'select count(*) from public.jornada_operativa')" "0"
for d in e9_tp02_a e9_tp02_b e9_tp02_c; do dropdb -h /tmp -p ${PGPORT:-54329} -U postgres --if-exists --force "$d"; done
echo "== TP02 fallos: $FAILS"; exit $FAILS
