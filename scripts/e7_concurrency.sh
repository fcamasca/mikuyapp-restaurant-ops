#!/usr/bin/env bash
# E7 — Carreras reales con conexiones independientes (T04: TP10, T05: TP18, T05B: TP13).
# Uso: PSQL_CONN="-h <host> -p <port> -U postgres -d <db_local_aislada>" scripts/e7_concurrency.sh <t04|t05|t05b|all>
# Requiere una base LOCAL aislada con las migraciones E7 aplicadas. Nunca usar contra DEV/PROD compartidos.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
PSQL="psql -X -At -v ON_ERROR_STOP=1 ${PSQL_CONN:?definir PSQL_CONN}"
MOZO=00000000-0000-0000-0000-0000000e7c01; C1=00000000-0000-0000-0000-0000000e7c02; C2=00000000-0000-0000-0000-0000000e7c03
ADMIN=00000000-0000-0000-0000-0000000e7c04
CEV=00000000-0000-0000-0000-0000000e7c21; CHI=00000000-0000-0000-0000-0000000e7c22
FAILS=0; TMP=$(mktemp -d)

as_user() { echo "select set_config('request.jwt.claim.sub','$1',false), set_config('request.jwt.claim.role','authenticated',false);"; }
q() { $PSQL -c "$(as_user "$1")" -c "$2" | tail -n +2; }
mesa() { printf '00000000-0000-0000-0000-0000000e7d%02d' "$1"; }
check() { if [[ "$2" == "$3" ]]; then echo "  OK   $1 ($2)"; else echo "  FAIL $1: obtenido='$2' esperado='$3'"; FAILS=$((FAILS+1)); fi; }

# nuevo pedido en mesa N con K líneas de cocina (+ bebidas opcional); imprime pedido_id
new_order() { local m=$(mesa "$1") k=$2 extra=${3:-}
  local p; p=$(q $MOZO "select pedido_id from public.crear_o_recuperar_pedido_mesa('$m')")
  for i in $(seq 1 "$k"); do q $MOZO "select 1 from public.agregar_detalle_pedido($p,'$CEV',1,'obs $i')" >/dev/null; done
  [[ -n "$extra" ]] && q $MOZO "select 1 from public.agregar_detalle_pedido($p,'$CHI',1,null)" >/dev/null
  q $MOZO "select 1 from public.enviar_pedido_cocina($p)" >/dev/null; echo "$p"; }

# Sesión que mantiene la transacción abierta tras ejecutar la operación (para forzar la espera del otro lado)
hold() { local user=$1 sql=$2 out=$3
  $PSQL -c "$(as_user "$user")" -c "begin" -c "$sql" -c "select pg_sleep(2)" -c "commit" >"$out" 2>&1; }
run() { local user=$1 sql=$2 out=$3; $PSQL -c "$(as_user "$user")" -c "$sql" >"$out" 2>&1; echo "exit=$?" >>"$out"; }
waiting() { $PSQL -c "select count(*) from pg_stat_activity where datname=current_database() and wait_event_type='Lock'"; }
race() { # race <userA> <sqlA> <userB> <sqlB> -> deja salidas en $TMP/a $TMP/b y espera observada
  hold "$1" "$2" "$TMP/a" & local pa=$!; sleep 0.6
  run "$3" "$4" "$TMP/b" & local pb=$!; sleep 0.6
  WAITED=$(waiting); wait $pa $pb; }

setup() { $PSQL -f "$DIR/supabase/tests/e7_concurrency_cleanup.sql" >/dev/null; $PSQL -f "$DIR/supabase/tests/e7_concurrency_setup.sql" >/dev/null; }

t04() {
  echo "== T04 / E7-TP10 — recepción completa"
  local p; p=$(new_order 1 3)
  race $C1 "select detalles_recibidos from public.rpc_recibir_pedido_cocina($p)" $C2 "select detalles_recibidos from public.rpc_recibir_pedido_cocina($p)"
  check "R1 dos cocinas: sesión B esperó lock" "$WAITED" "1"
  check "R1 sesión A recibió" "$(grep -E '^[0-9]+$' $TMP/a | tail -1)" "3"
  check "R1 sesión B recibió (sin error)" "$(grep -E '^[0-9]+$' $TMP/b | head -1)/$(grep exit $TMP/b)" "0/exit=0"
  check "R1 historial RECEPCION_COMPLETA" "$(q $C1 "select count(*) from public.historial_detalle_pedido where pedido_id=$p and operacion='RECEPCION_COMPLETA'")" "3"

  p=$(new_order 2 2); local d; d=$(q $C1 "select min(id) from public.detalle_pedido where pedido_id=$p")
  race $C1 "select detalles_recibidos from public.rpc_recibir_pedido_cocina($p)" $C2 "select 1 from public.actualizar_estado_detalle_cocina($d,'ENVIADO','RECIBIDO_COCINA')"
  check "R2 completa vs individual: individual esperó" "$WAITED" "1"
  check "R2 individual perdedora PT409" "$(grep -c 'fue actualizado por otra sesión' $TMP/b)" "1"
  check "R2 una sola transición del detalle" "$(q $C1 "select count(*) from public.historial_detalle_pedido where detalle_id=$d")" "2"

  p=$(new_order 3 2); d=$(q $C1 "select min(id) from public.detalle_pedido where pedido_id=$p")
  race $C2 "select 1 from public.actualizar_estado_detalle_cocina($d,'ENVIADO','RECIBIDO_COCINA')" $C1 "select detalles_recibidos from public.rpc_recibir_pedido_cocina($p)"
  check "R3 individual vs completa: completa esperó" "$WAITED" "1"
  check "R3 completa omitió el detalle ya recibido" "$(grep -E '^[0-9]+$' $TMP/b | head -1)" "1"
  check "R3 historial por detalle sin duplicados" "$(q $C1 "select count(*) from public.historial_detalle_pedido where pedido_id=$p and operacion<>'ENVIO'")" "2"

  p=$(new_order 4 1); local m; m=$(mesa 4)
  q $MOZO "select 1 from public.agregar_detalle_pedido($p,'$CEV',2,'nuevo')" >/dev/null
  race $MOZO "select detalles_enviados from public.enviar_pedido_cocina($p)" $C1 "select detalles_recibidos from public.rpc_recibir_pedido_cocina($p)"
  check "R4 envío vs completa: completa esperó" "$WAITED" "1"
  check "R4 completa recibió también lo enviado antes" "$(grep -E '^[0-9]+$' $TMP/b | head -1)" "2"
  check "R4 ningún ENVIADO residual" "$(q $C1 "select count(*) from public.detalle_pedido where pedido_id=$p and estado='ENVIADO'")" "0"

  p=$(new_order 5 1)
  q $MOZO "select 1 from public.agregar_detalle_pedido($p,'$CEV',2,'nuevo')" >/dev/null
  race $C1 "select detalles_recibidos from public.rpc_recibir_pedido_cocina($p)" $MOZO "select detalles_enviados from public.enviar_pedido_cocina($p)"
  check "R5 completa vs envío: envío esperó" "$WAITED" "1"
  check "R5 detalle nuevo queda ENVIADO para cocina" "$(q $C1 "select string_agg(estado,',' order by id) from public.detalle_pedido where pedido_id=$p")" "RECIBIDO_COCINA,ENVIADO"
  check "R5 comandas 1 y 2" "$(q $C1 "select string_agg(numero::text,',' order by numero) from public.comanda where pedido_id=$p")" "1,2"
}

t05() {
  echo "== T05 / E7-TP18 — cancelación vs cocina y vs anulación"
  local p d
  p=$(new_order 6 1); d=$(q $C1 "select min(id) from public.detalle_pedido where pedido_id=$p")
  q $C1 "select 1 from public.actualizar_estado_detalle_cocina($d,'ENVIADO','RECIBIDO_COCINA')" >/dev/null
  race $MOZO "select ya_cancelado from public.rpc_cancelar_detalle_pedido($d,'cliente se fue')" $C1 "select 1 from public.actualizar_estado_detalle_cocina($d,'RECIBIDO_COCINA','EN_PREPARACION')"
  check "R6 cancelación primero: cocina esperó" "$WAITED" "1"
  check "R6 cocina perdedora PT409 por cancelación" "$(grep -c 'fue cancelado por el mozo' $TMP/b)" "1"
  check "R6 detalle eliminado + un evento CANCELACION" "$(q $C1 "select (select count(*) from public.detalle_pedido where id=$d)||'/'||(select count(*) from public.historial_detalle_pedido where detalle_id=$d and operacion='CANCELACION')")" "0/1"
  check "R6 pedido vacío ABIERTO y mesa OCUPADA" "$(q $C1 "select p.estado||'/'||m.estado from public.pedido p join public.mesa m on m.id=p.mesa_id where p.id=$p")" "ABIERTO/OCUPADA"

  p=$(new_order 7 1); d=$(q $C1 "select min(id) from public.detalle_pedido where pedido_id=$p")
  q $C1 "select 1 from public.actualizar_estado_detalle_cocina($d,'ENVIADO','RECIBIDO_COCINA')" >/dev/null
  race $C1 "select 1 from public.actualizar_estado_detalle_cocina($d,'RECIBIDO_COCINA','EN_PREPARACION')" $MOZO "select ya_cancelado from public.rpc_cancelar_detalle_pedido($d,'cliente se fue')"
  check "R7 cocina primero: cancelación esperó" "$WAITED" "1"
  check "R7 cancelación perdedora PT409 (preparación iniciada)" "$(grep -c 'La preparación ya inició' $TMP/b)" "1"
  check "R7 detalle EN_PREPARACION sin evento CANCELACION" "$(q $C1 "select (select estado from public.detalle_pedido where id=$d)||'/'||(select count(*) from public.historial_detalle_pedido where detalle_id=$d and operacion='CANCELACION')")" "EN_PREPARACION/0"

  p=$(new_order 8 1); d=$(q $C1 "select min(id) from public.detalle_pedido where pedido_id=$p")
  race $MOZO "select ya_cancelado from public.rpc_cancelar_detalle_pedido($d,'duplicado A')" $MOZO "select ya_cancelado from public.rpc_cancelar_detalle_pedido($d,'duplicado B')"
  check "R8 doble cancelación concurrente: B esperó" "$WAITED" "1"
  check "R8 A cancela / B idempotente" "$(grep -E '^[tf]$' $TMP/a | tail -1)/$(grep -E '^[tf]$' $TMP/b | head -1)" "f/t"
  check "R8 un solo evento CANCELACION" "$(q $C1 "select count(*) from public.historial_detalle_pedido where detalle_id=$d and operacion='CANCELACION'")" "1"

  p=$(new_order 9 2); d=$(q $C1 "select min(id) from public.detalle_pedido where pedido_id=$p")
  race $ADMIN "select (public.anular_pedido_supervisado($p,'anulación de prueba',gen_random_uuid()))->>'pedido_id'" $MOZO "select ya_cancelado from public.rpc_cancelar_detalle_pedido($d,'tarde')"
  check "R9 anulación ADMIN primero: cancelación esperó" "$WAITED" "1"
  check "R9 cancelación perdedora PT409 (pedido anulado)" "$(grep -c 'ya no admite cancelaciones' $TMP/b)" "1"
  check "R9 pedido ANULADO, detalle intacto, sin CANCELACION" "$(q $C1 "select (select estado from public.pedido where id=$p)||'/'||(select count(*) from public.detalle_pedido where id=$d)||'/'||(select count(*) from public.historial_detalle_pedido where pedido_id=$p and operacion='CANCELACION')")" "ANULADO/1/0"
  check "R6–R9 ningún 40001" "$(cat $TMP/a $TMP/b | grep -c 40001)" "0"
}

open_order() { # pedido con 1 detalle enviado + 1 detalle ABIERTO; imprime "pedido detalle_abierto"
  local m=$(mesa "$1") p d
  p=$(q $MOZO "select pedido_id from public.crear_o_recuperar_pedido_mesa('$m')")
  q $MOZO "select 1 from public.agregar_detalle_pedido($p,'$CEV',1,'enviado')" >/dev/null
  q $MOZO "select 1 from public.enviar_pedido_cocina($p)" >/dev/null
  d=$(q $MOZO "select detalle_id from public.agregar_detalle_pedido($p,'$CEV',1,'borrador')"); echo "$p $d"; }

t05b() {
  echo "== T05B / E7-TP13 — edición/retiro ABIERTO vs envío"
  local p d
  read p d < <(open_order 10)
  race $MOZO "select pedido_estado from public.rpc_retirar_detalle_pedido($d)" $MOZO "select detalles_enviados from public.enviar_pedido_cocina($p)"
  check "R10 retiro primero: envío esperó" "$WAITED" "1"
  check "R10 envío procesa estado resultante (0 enviados)" "$(grep -E '^[0-9]+$' $TMP/b | head -1)/$(grep exit $TMP/b)" "0/exit=0"
  check "R10 pedido derivado ENVIADO" "$(q $MOZO "select estado from public.pedido where id=$p")" "ENVIADO"

  read p d < <(open_order 11)
  race $MOZO "select detalles_enviados from public.enviar_pedido_cocina($p)" $MOZO "select pedido_estado from public.rpc_retirar_detalle_pedido($d)"
  check "R11 envío primero: retiro esperó" "$WAITED" "1"
  check "R11 retiro perdedor PT409" "$(grep -c 'ya fue enviado' $TMP/b)" "1"
  check "R11 detalle enviado intacto" "$(q $MOZO "select estado from public.detalle_pedido where id=$d")" "ENVIADO"

  read p d < <(open_order 12)
  race $MOZO "select 1 from public.enviar_pedido_cocina($p)" $MOZO "select cantidad from public.rpc_modificar_detalle_pedido($d,5,'borrador',1,'borrador')"
  check "R12 envío primero: edición esperó" "$WAITED" "1"
  check "R12 edición perdedora PT409" "$(grep -c 'ya fue enviado' $TMP/b)" "1"
  check "R12 cantidad sin cambios" "$(q $MOZO "select cantidad from public.detalle_pedido where id=$d")" "1"

  $PSQL -f "$DIR/supabase/tests/e7_concurrency_cleanup.sql" >/dev/null; $PSQL -f "$DIR/supabase/tests/e7_concurrency_setup.sql" >/dev/null
  read p d < <(open_order 1)
  race $MOZO "select cantidad from public.rpc_modificar_detalle_pedido($d,5,'borrador',1,'borrador')" $MOZO "select detalles_enviados from public.enviar_pedido_cocina($p)"
  check "R13 edición primero: envío esperó" "$WAITED" "1"
  check "R13 envío con la cantidad editada" "$(q $MOZO "select estado||'/'||cantidad from public.detalle_pedido where id=$d")" "ENVIADO/5"
  # R14: observación esperada NULL real; otra sesión la modifica; snapshot antiguo => PT409
  p=$(q $MOZO "select pedido_id from public.crear_o_recuperar_pedido_mesa('$(mesa 2)')")
  d=$(q $MOZO "select detalle_id from public.agregar_detalle_pedido($p,'$CEV',1,null)")
  race $MOZO "select observacion from public.rpc_modificar_detalle_pedido($d,1,'Poco picante',1,null)" $MOZO "select cantidad from public.rpc_modificar_detalle_pedido($d,4,null,1,null)"
  check "R14 esperado NULL: B esperó" "$WAITED" "1"
  check "R14 B con snapshot antiguo (1, NULL) pierde PT409" "$(grep -c 'El producto cambió o ya fue enviado' $TMP/b)" "1"
  check "R14 detalle conserva la edición ganadora" "$(q $MOZO "select cantidad||'/'||observacion from public.detalle_pedido where id=$d")" "1/Poco picante"
  check "R10–R14 sin interbloqueos (40P01) ni 40001" "$(cat $TMP/a $TMP/b | grep -cE '40P01|40001|deadlock')" "0"
  check "R10–R14 sin deadlocks registrados" "$($PSQL -c "select deadlocks from pg_stat_database where datname=current_database()")" "0"
}

case "${1:-all}" in
  t04) setup; t04 ;;
  t05) setup; t05 ;;
  t05b) setup; t05b ;;
  all) setup; t04; t05; t05b ;;
  *) echo "escenario desconocido"; exit 2 ;;
esac
$PSQL -f "$DIR/supabase/tests/e7_concurrency_cleanup.sql" >/dev/null
check "sin conexiones residuales" "$($PSQL -c "select count(*) from pg_stat_activity where datname=current_database() and pid<>pg_backend_pid() and backend_type='client backend'")" "0"
rm -rf "$TMP"; echo "== fallos: $FAILS"; exit $((FAILS>0))
