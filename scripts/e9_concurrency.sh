#!/usr/bin/env bash
# E9 — Carreras reales con conexiones independientes (TP16, TP17; TP18 con "all").
# Uso: scripts/e9_concurrency.sh <db_plantilla_con_E9> [t03|all]
# Cada carrera usa una base efímera nueva creada desde la plantilla y la elimina al terminar:
# no requiere limpiezas (la jornada es inmutable por diseño). Nunca DEV ni PROD.
set -uo pipefail
TPL=$1; SCOPE=${2:-t03}; FAILS=0
PORT=${PGPORT:-54329}
P="psql -h /tmp -p $PORT -U postgres -X -q -v ON_ERROR_STOP=1"
ADMIN=00000000-0000-0000-0000-0000000e9c01; ADMIN2=00000000-0000-0000-0000-0000000e9c02
MOZO=00000000-0000-0000-0000-0000000e9c03;  CAJA=00000000-0000-0000-0000-0000000e9c04
LOCAL=00000000-0000-0000-0000-0000000e9c11; CAJAID=00000000-0000-0000-0000-0000000e9c12
M1=00000000-0000-0000-0000-0000000e9c21; M2=00000000-0000-0000-0000-0000000e9c22
PROD=00000000-0000-0000-0000-0000000e9c31
as(){ echo "select set_config('request.jwt.claim.sub','$1',true), set_config('request.jwt.claim.role','authenticated',true);"; }

FIXTURE="
insert into auth.users(id,aud,role,email,encrypted_password) select u,'authenticated','authenticated','e9c-'||u||'@example.invalid','t'
  from unnest(array['$ADMIN','$ADMIN2','$MOZO','$CAJA']::uuid[]) u;
insert into public.local(id,codigo,nombre) values('$LOCAL','E9-C','Local carreras');
insert into public.perfil_usuario(id,local_id,rol_id,nombre)
  select '$ADMIN'::uuid,'$LOCAL'::uuid,id,'Admin' from public.rol where codigo='ADMINISTRADOR'
  union all select '$ADMIN2'::uuid,'$LOCAL'::uuid,id,'Admin 2' from public.rol where codigo='ADMINISTRADOR'
  union all select '$MOZO'::uuid,'$LOCAL'::uuid,id,'Mozo' from public.rol where codigo='MOZO'
  union all select '$CAJA'::uuid,'$LOCAL'::uuid,id,'Caja' from public.rol where codigo='CAJA';
insert into public.mesa(id,local_id,codigo,nombre) values('$M1','$LOCAL','C1','Mesa 1'),('$M2','$LOCAL','C2','Mesa 2');
insert into public.categoria(id,local_id,codigo,nombre) values('00000000-0000-0000-0000-0000000e9c32','$LOCAL','C','Carta');
insert into public.producto(id,local_id,categoria_id,codigo,nombre,precio,requiere_cocina)
  values('$PROD','$LOCAL','00000000-0000-0000-0000-0000000e9c32','CHI','Chicha',10,false);
insert into public.caja(id,local_id,codigo,nombre) values('$CAJAID','$LOCAL','C','Caja C');"
OPEN_DAY="begin; $(as $ADMIN) select * from public.rpc_abrir_jornada_operativa(gen_random_uuid()); commit;"
DAY="(select id from public.jornada_operativa where local_id='$LOCAL' order by id desc limit 1)"

race(){ # name prep a b verify
  local name=$1 prep=$2 a=$3 b=$4 verify=$5 db=e9_race_$RANDOM oa ob
  dropdb -h /tmp -p $PORT -U postgres --if-exists --force $db 2>/dev/null
  createdb -h /tmp -p $PORT -U postgres -T "$TPL" $db || { echo "RESULT FAIL $name: plantilla"; FAILS=$((FAILS+1)); return; }
  if ! $P -d $db -c "begin; $FIXTURE commit;" -c "$prep" >/dev/null 2>/tmp/e9_prep.err; then
    echo "RESULT FAIL $name: preparación"; head -3 /tmp/e9_prep.err; FAILS=$((FAILS+1)); dropdb -h /tmp -p $PORT -U postgres --force $db; return
  fi
  oa=$(mktemp); ob=$(mktemp)
  (PGAPPNAME=e9_race $P -d $db -c "begin" -c "$a" -c "select pg_sleep(2)" -c "commit") >"$oa" 2>&1 & local pa=$!
  sleep 0.7
  (PGAPPNAME=e9_race $P -d $db -c "begin" -c "$b" -c "commit") >"$ob" 2>&1 & local pb=$!
  wait $pa; local ca=$?; wait $pb; local cb=$?
  local sa sb; sa=$(grep -o "ERROR:  .*" "$oa" | head -1); sb=$(grep -o "ERROR:  .*" "$ob" | head -1)
  echo "RACE $name: A exit=$ca ${sa:+[$sa]} | B exit=$cb ${sb:+[$sb]}"
  if grep -q "40001\|40P01\|deadlock" "$oa" "$ob"; then echo "RESULT FAIL $name: 40001/40P01"; FAILS=$((FAILS+1)); fi
  if $P -d $db -c "$verify" >/tmp/e9_verify.out 2>&1; then echo "RESULT PASS $name"; else echo "RESULT FAIL $name"; grep -m2 ERROR /tmp/e9_verify.out; FAILS=$((FAILS+1)); fi
  local residual; residual=$($P -d postgres -Atc "select count(*) from pg_stat_activity where application_name='e9_race'")
  [[ "$residual" != 0 ]] && { echo "RESULT FAIL $name: conexiones residuales"; FAILS=$((FAILS+1)); }
  rm -f "$oa" "$ob"; dropdb -h /tmp -p $PORT -U postgres --force $db
}
chk(){ echo "do \$v\$ begin if not ($1) then raise exception '$2'; end if; end \$v\$;"; }

echo "== TP16 apertura vs apertura"
race "TP16 dos ADMIN abren a la vez" "select 1" \
  "$(as $ADMIN) select * from public.rpc_abrir_jornada_operativa(gen_random_uuid());" \
  "$(as $ADMIN2) select * from public.rpc_abrir_jornada_operativa(gen_random_uuid());" \
  "$(chk "(select count(*) from public.jornada_operativa where local_id='$LOCAL')=1 and (select numero from public.jornada_operativa where local_id='$LOCAL')=1" 'TP16: más de una jornada o numeración')"
race "TP16 doble envío con la misma clave" "select 1" \
  "$(as $ADMIN) select * from public.rpc_abrir_jornada_operativa('00000000-0000-0000-0000-0000000e9cff');" \
  "$(as $ADMIN) create temp table r as select * from public.rpc_abrir_jornada_operativa('00000000-0000-0000-0000-0000000e9cff'); $(chk "(select ya_existia from r)" 'TP16: el segundo envío no devolvió la existente')" \
  "$(chk "(select count(*) from public.jornada_operativa where local_id='$LOCAL')=1" 'TP16: duplicado con la misma clave')"

echo "== TP17 cierre vs creación y cierre vs cierre"
race "TP17 cierre gana a crear pedido" "$OPEN_DAY" \
  "$(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY);" \
  "$(as $MOZO) select * from public.crear_o_recuperar_pedido_mesa('$M1');" \
  "$(chk "(select estado from public.jornada_operativa where local_id='$LOCAL')='CERRADA' and not exists(select 1 from public.pedido) and (select estado from public.mesa where id='$M1')='LIBRE'" 'TP17: jornada cerrada con pedido o residuos')"
race "TP17 crear pedido gana al cierre" "$OPEN_DAY" \
  "$(as $MOZO) select * from public.crear_o_recuperar_pedido_mesa('$M1');" \
  "$(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY);" \
  "$(chk "(select estado from public.jornada_operativa where local_id='$LOCAL')='ABIERTA' and (select count(*) from public.pedido where jornada_operativa_id=$DAY)=1" 'TP17: cierre con pedido vigente')"
race "TP17 cierre gana a abrir caja" "$OPEN_DAY" \
  "$(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY);" \
  "$(as $CAJA) select public.rpc_abrir_sesion_caja('$CAJAID',0,gen_random_uuid());" \
  "$(chk "(select estado from public.jornada_operativa where local_id='$LOCAL')='CERRADA' and not exists(select 1 from public.sesion_caja) and not exists(select 1 from public.solicitud_apertura_caja) and not exists(select 1 from public.auditoria_caja)" 'TP17: jornada cerrada con sesión o residuos')"
race "TP17 abrir caja gana al cierre" "$OPEN_DAY" \
  "$(as $CAJA) select public.rpc_abrir_sesion_caja('$CAJAID',0,gen_random_uuid());" \
  "$(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY);" \
  "$(chk "(select estado from public.jornada_operativa where local_id='$LOCAL')='ABIERTA' and (select count(*) from public.sesion_caja where jornada_operativa_id=$DAY and estado='ABIERTA')=1" 'TP17: cierre con sesión abierta')"
race "TP17 cierre vs cierre" "$OPEN_DAY" \
  "$(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY);" \
  "$(as $ADMIN2) create temp table r as select * from public.rpc_cerrar_jornada_operativa($DAY); $(chk "(select ya_estaba_cerrada from r) and (select cerrada_por from r)='$ADMIN'" 'TP17: el segundo cierre no fue idempotente')" \
  "$(chk "(select cerrada_por from public.jornada_operativa where local_id='$LOCAL')='$ADMIN'" 'TP17: actor de cierre')"

if [[ "$SCOPE" == all ]]; then
  echo "== TP18 otras carreras"
  ENTREGADO="$OPEN_DAY begin; $(as $CAJA) select public.rpc_abrir_sesion_caja('$CAJAID',0,'00000000-0000-0000-0000-0000000e9c41'); $(as $MOZO)
    select * from public.crear_o_recuperar_pedido_mesa('$M1');
    select public.agregar_detalle_pedido((select id from public.pedido), '$PROD', 1, null);
    select public.enviar_pedido_cocina((select id from public.pedido)); select public.entregar_pedido((select id from public.pedido)); commit;"
  SES="(select id from public.sesion_caja where estado='ABIERTA')"
  race "TP18 cobro final en curso vs cierre (sesión abierta)" "$ENTREGADO" \
    "$(as $CAJA) select * from public.rpc_registrar_cobro_pedido((select id from public.pedido), $SES, 'TOTAL', '[{\"medio\":\"EFECTIVO\",\"importe\":10,\"propina\":0}]'::jsonb, gen_random_uuid());" \
    "$(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY);" \
    "$(chk "(select estado from public.jornada_operativa where local_id='$LOCAL')='ABIERTA' and (select estado from public.pedido)='PAGADO'" 'TP18: estado tras cobro vs cierre')"
  PAGADO="$ENTREGADO begin; $(as $CAJA) select * from public.rpc_registrar_cobro_pedido((select id from public.pedido), $SES, 'TOTAL', '[{\"medio\":\"EFECTIVO\",\"importe\":10,\"propina\":0}]'::jsonb, gen_random_uuid()); commit;"
  race "TP18 cierre de caja en curso vs cierre de jornada" "$PAGADO" \
    "$(as $CAJA) select public.fn_cerrar_sesion_caja($SES, 10, null, gen_random_uuid(), false);" \
    "$(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY);" \
    "$(chk "(select estado from public.jornada_operativa where local_id='$LOCAL')='ABIERTA'" 'TP18: cierre de jornada con caja aún abierta al obtener el lock'); begin; $(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY); commit; $(chk "(select estado from public.jornada_operativa where local_id='$LOCAL')='CERRADA'" 'TP18: el reintento no cerró')"
  race "TP18 cierre de jornada vs cierre de caja (jornada primero)" "$PAGADO" \
    "$(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY);" \
    "$(as $CAJA) select public.fn_cerrar_sesion_caja($SES, 10, null, gen_random_uuid(), false);" \
    "$(chk "(select estado from public.jornada_operativa where local_id='$LOCAL')='ABIERTA' and (select estado from public.sesion_caja)='CERRADA'" 'TP18: estado tras cierre vs cierre de caja')"
  ANUL="$ENTREGADO begin; $(as $CAJA) select public.fn_cerrar_sesion_caja($SES, 0, null, gen_random_uuid(), false); commit;"
  race "TP18 anulación en curso vs cierre" "$ANUL" \
    "$(as $ADMIN2) select public.anular_pedido_supervisado((select id from public.pedido), 'Carrera', gen_random_uuid());" \
    "$(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY);" \
    "$(chk "(select estado from public.jornada_operativa where local_id='$LOCAL')='ABIERTA' and (select estado from public.pedido)='ANULADO'" 'TP18: cierre admitido con anulación sin confirmar'); begin; $(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY); commit; $(chk "(select estado from public.jornada_operativa where local_id='$LOCAL')='CERRADA'" 'TP18: el reintento no cerró')"
  VACIO="$OPEN_DAY begin; $(as $MOZO) select * from public.crear_o_recuperar_pedido_mesa('$M1'); commit;"
  race "TP18 liberación de mesa vacía en curso vs cierre" "$VACIO" \
    "$(as $MOZO) select public.liberar_mesa_pedido_vacio((select id from public.pedido));" \
    "$(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY);" \
    "$(chk "(select estado from public.jornada_operativa where local_id='$LOCAL')='ABIERTA' and (select estado from public.pedido)='ANULADO'" 'TP18: cierre admitido con liberación sin confirmar'); begin; $(as $ADMIN) select * from public.rpc_cerrar_jornada_operativa($DAY); commit; $(chk "(select estado from public.jornada_operativa where local_id='$LOCAL')='CERRADA'" 'TP18: el reintento no cerró')"
  race "TP18 apertura en curso vs crear pedido" "select 1" \
    "$(as $ADMIN) select * from public.rpc_abrir_jornada_operativa(gen_random_uuid());" \
    "$(as $MOZO) select * from public.crear_o_recuperar_pedido_mesa('$M1');" \
    "$(chk "not exists(select 1 from public.pedido) and (select count(*) from public.jornada_operativa where estado='ABIERTA')=1" 'TP18: pedido creado sin apertura confirmada'); begin; $(as $MOZO) select * from public.crear_o_recuperar_pedido_mesa('$M1'); commit; $(chk "(select count(*) from public.pedido where jornada_operativa_id=$DAY)=1" 'TP18: tras la apertura no se pudo crear')"
fi
echo "== fallos: $FAILS"; exit $FAILS
