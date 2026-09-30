#!/usr/bin/env bash
# E10 — Replay local de migraciones sobre PostgreSQL con emulación mínima de la plataforma Supabase.
# Uso: scripts/e10_local_replay.sh <db> <repo> [prefijo_hasta|all]
# Requiere un servidor PostgreSQL local (socket /tmp, puerto $PGPORT o 54329, usuario postgres).
# No se conecta a DEV ni a PROD. Ver specs/E10-AccountRequest/implementation.md §1.
set -uo pipefail
db=$1; repo=$2; until=${3:-all}
P="psql -h /tmp -p ${PGPORT:-54329} -U postgres -X -q -v ON_ERROR_STOP=1"
dropdb -h /tmp -p ${PGPORT:-54329} -U postgres --if-exists --force "$db" 2>/dev/null
createdb -h /tmp -p ${PGPORT:-54329} -U postgres -T template0 "$db" || exit 1
$P -d "$db" -f "$(dirname "$0")/e10_local_platform.sql" >/dev/null || { echo "REPLAY FAIL plataforma"; exit 1; }
n=0
for m in $(ls "$repo/supabase/migrations" | grep '\.sql$' | sort); do
  if ! $P -d "$db" -f "$repo/supabase/migrations/$m" >"${TMPDIR:-/tmp}/e10_replay.out" 2>&1; then echo "REPLAY FAIL $m"; grep -i -m5 "error" "${TMPDIR:-/tmp}/e10_replay.out"; exit 1; fi
  n=$((n+1)); last=$m
  [[ "$until" != all && "$m" == "$until"* ]] && break
done
$P -d "$db" -f "$repo/supabase/seed.sql" >"${TMPDIR:-/tmp}/e10_seed.out" 2>&1 || { echo "REPLAY FAIL seed"; grep -i -m5 error "${TMPDIR:-/tmp}/e10_seed.out"; exit 1; }
echo "REPLAY OK $db: $n migraciones (última $last) + seed"
