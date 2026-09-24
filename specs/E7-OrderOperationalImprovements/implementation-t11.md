# E7 — Evidencia de construcción: T11 (validación técnica integral)

Fecha: 23/09/2026. Rama `feature/E7-OrderOperationalImprovements`, desde `427d76f` (T10 técnicamente completa). No constituye aceptación. T12 **no iniciada**; no existe `acceptance.md`.

**Estado de T11: TÉCNICAMENTE COMPLETA** en el stack Supabase local real (desviación de ambiente aprobada en T10). Sin defectos E7 abiertos. DEV/Preview cloud: pendiente por PM-002, no ejecutado por riesgo sobre Production. Esta evidencia no sustituye la revalidación cloud previa a release/validación humana.

## 1. Ambiente y ejecución

| Componente | Versión |
|---|---|
| Node / npm (Windows, responsable) | 22.12.0 / 10.9.0 — suite repetida tras la corrección en Node 22.23.2 (Linux) |
| Docker Engine | 29.7.2 |
| Supabase CLI | 2.115.0 (`npx supabase`) |
| PostgreSQL | 17.6 (`supabase/postgres:17.6.1.155`) |
| PostgREST / Auth / Realtime / Kong | v14.5 / v2.196.0 / v2.129.0 / 2.8.1 |
| Imágenes | reutilizadas; ninguna descarga nueva |

Runners (sin `link`, `--linked` ni `db push`; registros `*.log` ignorados por git, sin claves):

| Runner | Contenido |
|---|---|
| `scripts/e7_t11_campaign.{cmd,ps1}` | Campaña única: `git diff --check`, `typecheck`, `build`, suite Node completa, replay 1 (`db reset`), fase real, R1–R15, fase aislada (replay 2 + suite SQL completa + carreras históricas), E1-T09, baseline HZ-01, DBSTD-T09, recorrido API/Realtime, residuos, replay 3 final, secretos, `supabase stop` |
| `scripts/e7_t11_sql_campaign.sh` | Fases SQL dentro del contenedor de base (`real`, `aislada`, `baseline`, `baselinesuite`, `homolog`, `dbstd`, `dbstdbase`, `drop`) |
| `scripts/e7_t11_followup.{cmd,ps1}` | Línea base pre-E7 de la suite SQL (clasificación) y dos repeticiones del recorrido API/Realtime |
| `scripts/e7_t11_homolog.{cmd,ps1}` | Suite histórica con homologaciones documentadas (§5.3) sobre pre-E7 y E7 |
| `scripts/e7_t11_complementos.{cmd,ps1}` | `supabase/tests/e7_t11_complementos.sql` (validaciones sin cobertura explícita previa) |

## 2. Replay limpio

| Replay | Resultado |
|---|---|
| 1 — `supabase db reset --local` (base `postgres` del stack) | 57 migraciones en orden (`20260823235106` … `20260924000800`) + seed, sin errores; orden verificado en `supabase_migrations.schema_migrations` |
| 2 — base aislada `e7_t11_*` (esquema de plataforma + 57 migraciones + seed, método de los runners E1) | OK |
| Pre-E7 — bases aisladas hasta `20260922000100` (49 migraciones + seed) | OK (líneas base para clasificar) |
| 3 — `db reset` final | OK; volumen local sin fixtures ni bases efímeras |

## 3. Frontend

| Verificación | Resultado |
|---|---|
| `npm run typecheck` | PASS |
| `npm run build` | PASS (guardia de ambiente OK; sólo el aviso de chunk > 500 kB ya conocido) |
| Suite Node completa (25 archivos) | Campaña: 385/386 — 1 fallo (§6, D-11). Tras la corrección: **386/386 PASS** |

## 4. Base real del stack (`postgres`, roles reales de Supabase)

| Verificación | Resultado |
|---|---|
| SQL E7 T02, T03, T04, T05, T05B, T09 | 6/6 PASS |
| `e7_t10_integracion.sql` | PASS (13 eventos de detalle, 2 comandas, total caja 114) |
| `e7_t11_complementos.sql` | PASS (ejecución aparte, mismo stack) |
| Carreras R1–R15 (`e7_concurrency.sh all`) | 0 fallos; sin `40001`, sin `40P01`, sin deadlocks; 0 conexiones residuales |
| Publicación Realtime | `detalle_pedido, mesa, pedido` |
| `service_role` (revalidación `…800`) | Sin `SELECT`/`TRUNCATE` sobre `historial_detalle_pedido` y `comanda`; sin `EXECUTE` en triggers ni RPC E7 |
| RPC E7 | `EXECUTE` sólo `authenticated` (7/7) |
| `40001` manual en funciones vigentes de `public` | **0** |
| `SECURITY DEFINER` con owner ≠ `postgres` o `search_path` ≠ `pg_catalog` | 0 |
| Tablas de `public` sin RLS / con escritura de `anon` | 0 / 0 |
| `detalle_pedido`: `UPDATE`/`DELETE` de `authenticated`, políticas eliminadas por E7-D15 | `false` / `false` / 0 |
| `producto.requiere_cocina` | `INSERT`/`UPDATE` por columna a `authenticated` (RLS ADMIN del local); `anon` sin privilegio |
| Funciones de `public` ejecutables por `anon` | 1: `h3_abrir_o_recuperar_pedido(uuid)` — preexistente de E1-T18, fuera de E7 (§7) |

## 5. Suite SQL del repositorio, carreras históricas y clasificación

### 5.1 Método

Toda la suite `supabase/tests/` (43 pruebas independientes + E1 con fixtures en el orden de sus runners + 4 carreras H4/H5 con conexiones reales) se ejecutó **tres veces con los mismos archivos**: sobre E7 (campaña), sobre la baseline pre-E7 y con homologaciones documentadas en copias temporales (§5.3). Un fallo es **preexistente** si ocurre igual en la baseline pre-E7; **superado por E7** si sólo ocurre con E7 y la causa es un cambio aprobado del Spec; **regresión** si sólo ocurre con E7 sin causa aprobada. Ningún archivo histórico del repositorio se modificó.

### 5.2 Resultado sin homologación (archivos originales)

| Bloque | E7 | Pre-E7 |
|---|---|---|
| Independientes (43) | 31 PASS / 12 FAIL | 33 PASS / 10 FAIL (sin las pruebas E7) |
| E1 con fixtures (12 pasos) | 6 / 6 | 6 / 6 |
| Carreras H4/H5 (verify + cleanup) | H4-T03, H5-T02 ×2 correctas; H5-T04 falla; cleanup H4-T03 falla | H4-T03, H5-T02 ×2 correctas; H5-T04 falla |
| `testE1T09Concurrency.mjs` | Falla en la aserción `/22023\|40001/` (la perdedora recibe `PT409`) | igual (E1-T18) |
| `dbstd_t09_compensating_rollback.sql` | Falla (en `order_audit_trail`) | Falla (en `dbstd_t03`) |

### 5.3 Homologaciones (sólo en copias temporales)

- **H1 — E1-T18/D17:** `'40001'` → `'PT409'` en 11 pruebas históricas (conflictos funcionales migrados por E1-T18, anterior a E7). Aplicada en ambas bases.
- **H2 — sólo E7:** se omite la comprobación del cuerpo exacto de `registrar_auditoria_detalle_pedido()` (`order_audit_trail`, TP21 histórico) y se usa el comentario vigente de esa función en `dbstd_t04` (ambos cambiados por E7-T03, E7-D05/D-1).

| Bloque | E7 homologado | Pre-E7 homologado |
|---|---|---|
| Independientes | 36 PASS / 7 FAIL | 33 PASS / 3 FAIL |
| E1 con fixtures | 10 / 2 | 10 / 2 |
| Carreras H4/H5 | H4-T03 y H5-T02 ×2 correctas; H5-T04 falla; cleanup H4-T03 falla | H4-T03 y H5-T02 ×2 correctas; H5-T04 falla |

Con H1, `h4_t03_kitchen_detail_state_transition`, `h5_t02_reopen_delivered_order`, `e1_delta_t09`, `e1_t09`, `e1_t04`–`e1_t07` y el comportamiento completo de H4 (transiciones de cocina) pasan también sobre E7.

### 5.4 Clasificación de cada fallo

| Prueba | Clasificación | Causa / evidencia |
|---|---|---|
| `h3_t04_open_order_detail_mutations` | **Superada por E7** (E7-D15, DH-01) | Matriz de privilegios de mutación directa (`UPDATE`/`DELETE`) retirada a propósito. Previsto en TP29. Equivalente vigente: `e7_t05b_edicion_retiro` (TP11/TP12: edición/retiro vía RPC, `UPDATE`/`DELETE` directos denegados, auditoría igual a H3, HZ-01), R10–R14 y §4 |
| `order_audit_trail` | **Superada por E7** (E7-D05/D-1 y E7-D15) | Sin homologar: cambió el cuerpo de la función de auditoría (admite `ABIERTO → LISTO` sin cocina). Con H2: se detiene en un `UPDATE` directo de `authenticated` (`42501`, E7-D15). Equivalente: `e7_t05b` (“auditoría distinta de H3”), `e7_t03` (TP05 `enviado_en` sin cocina), `e7_t02` (TP20) |
| `dbstd_t04_catalog_comments` | **Superada por E7** | Comentario de `registrar_auditoria_detalle_pedido()` actualizado en `…200`; con H2 falla por el total de comentarios (27): E7 comenta sus objetos nuevos. Pasa en pre-E7 |
| `h5_t02_safe_order_delivery` (con H1) | **Superada por E7** (E7-D15) | Último bloque: espera 0 filas por RLS en `UPDATE`/`DELETE` de un detalle `ENTREGADO`; ahora el privilegio no existe (`42501`), restricción más fuerte. Todo el comportamiento H5-T02 anterior pasa |
| Cleanup de la carrera H4-T03 | **Superada por E7** (arnés) | El cleanup histórico no conoce `historial_detalle_pedido` (FK `RESTRICT`); la carrera en sí es correcta (una confirma, la otra `PT409`). La base efímera se eliminó; sin residuos |
| `tp09_tp11_schema` | Preexistente (H1) | Espera exactamente 10 tablas: 23 en pre-E7 (E1), 25 con E7 |
| `dbstd_t03_function_metadata` | Preexistente (E1) | Hash de grants distinto ya en pre-E7 (cambia también con E7) |
| `domain_object_names` | Preexistente (E1-T18) | Objeto con prefijo de hito `h3_abrir_o_recuperar_pedido` (§7) |
| `e1_delta_t09`, `e1_t09`, `h4_t03_kitchen…`, `h5_t02_reopen…`, `e1_t04`–`e1_t07` (sin H1) | Preexistente (E1-T18) | Esperan `40001`; pasan con H1 en ambas bases |
| `e1_t03_caja_sesion`, `e1_t08_pago_sesion` | Preexistente | Dependen del replay parcial de sus runners E1 (esquema de su época); fallan igual en pre-E7 |
| `h5_t04_transactional_payment` y carrera H5-T04 | Preexistente (E1) | El cobro H5 exige sesión de caja desde E1 (“Debe abrir una sesión de caja…”) |
| `testE1T09Concurrency.mjs` | Preexistente (E1-T18) | La perdedora devuelve `PT409` (contrato vigente), no `40001` |
| `dbstd_t09_compensating_rollback` | Preexistente | Falla en pre-E7 (`dbstd_t03`); con E7 se detiene antes, en `order_audit_trail` (superada) |
| `e7_t05b_hz01_reproduccion_baseline` (baseline) | PASS esperado | HZ-01 se reproduce en pre-E7; con E7 queda corregido (TP12) |

**Regresiones reales: ninguna.** Los runners E1 que reconstruyen su propia base hasta una migración objetivo (`testE1T03`–`T08`, `T09Replay`, `T11`, `T13`, `T15`, `T16`) validan contratos de su época y no se ejecutaron. Su SQL se ejecutó sobre el esquema vigente (arriba).

## 6. Defectos encontrados y correcciones

| ID | Defecto | Clasificación | Corrección | Repetición |
|---|---|---|---|---|
| D-11 | `tests/catalogSecurity.test.mjs` (H2) exigía que el alta de producto enviara exactamente las columnas de la concesión H2; E7-D02 agrega `requiere_cocina` (concesión aditiva en `…100`) | Expectativa histórica superada por E7 | La prueba calcula las columnas efectivas = concesión H2 + concesiones aditivas de E7, y verifica `requiere_cocina = true` en el alta. La prueba T07 de la concesión H2 exacta no cambió | `catalogSecurity` 22/22; suite Node completa 386/386 |
| D-12 | Recorrido API/Realtime: en la campaña, la señal de envío no llegó a la cocina en 15 s (y el script cortó por falta de comanda en el snapshot local) | No reproducido | El script ahora registra un diagnóstico y continúa con el snapshot autoritativo si falta la señal; el paso Realtime sigue marcándose FAIL. Causa probable no verificada: el recorrido corrió justo después de tres reconstrucciones de base en el mismo clúster (gran volumen de WAL que Realtime debe decodificar) | 2 repeticiones con el stack recién iniciado: **19/19 y 19/19**, Realtime en 416–545 ms. T10: 19/19 |

Ninguna migración nueva; ninguna migración comprometida modificada.

## 7. Hallazgo fuera del alcance de E7

`20260922000100_e1_delta_t18…` recrea con `create or replace` la función `public.h3_abrir_o_recuperar_pedido(uuid)`, renombrada en 2026-08 a `crear_o_recuperar_pedido_mesa`. Al no existir, se crea como objeto nuevo con los privilegios por defecto de Supabase (`EXECUTE` a `anon`, sin `revoke`). Es `SECURITY DEFINER`, rechaza a `anon` con `42501` en su primera instrucción y para `authenticated` falla porque invoca `h2_auth_context()` (ya renombrada). No es explotable, pero viola la convención (“cero `SECURITY DEFINER` ejecutables por `anon`”) y también existe en DEV/Production. No se corrige en E7: requiere una decisión y una migración correctiva aparte (p. ej. `drop function`).

## 8. Matriz TP01–TP31

| TP | Resultado | Evidencia T11 |
|---|---|---|
| TP01 | Aprobada | `e7_t02` (default, grants); `e7_t11_complementos` (ADMIN edita/crea con default `true`; MOZO, COCINA, CAJA, ADMIN de otro local y `anon` rechazados sin cambios); Node T06; D-11 |
| TP02 | Aprobada | `e7_t02` (backfill, check validado, FKs/índices/triggers) |
| TP03 | Aprobada | `e7_t03` (snapshot, consolidación, snapshot de creación); `e7_t11_complementos` (cambio de catálogo con detalles `EN_PREPARACION`/`LISTO`, tablero y nuevos agregados con la condición vigente) |
| TP04 | Aprobada | `e7_t11_complementos` (dos productos individuales, comanda 1, `LISTO`/`PEDIDO_LISTO`, entrega, cobro E1, `PAGADO`/`LIBRE`); regresión H4/H5/E1 (§5) |
| TP05 | Aprobada | `e7_t03`, `e7_t04` (tablero nuevo/legado, transición rechazada); `e7_t11_complementos` (cobro `PAGADO`/`LIBRE`) |
| TP06 | Aprobada | `e7_t03`, `e7_t10_integracion`, recorrido API; Node T07 |
| TP07 | Aprobada | `e7_t10_integracion` (ceviche + bebida → comanda 2); `e7_t11_complementos` (sólo bebida → `LISTO`/`PEDIDO_LISTO`, sin comanda, nueva entrega) |
| TP08 | Aprobada | `e7_t04` |
| TP09 | Aprobada | `e7_t04` (reintento, `ENTREGADO`/`ANULADO`, rol/local); `e7_t11_complementos` (`PAGADO`); Node T08 (guard) |
| TP10 | Aprobada | R1–R5 |
| TP11 | Aprobada | `e7_t05b`; R12–R14 |
| TP12 | Aprobada | `e7_t05b` (HZ-01 corregido); baseline HZ-01 reproducido |
| TP13 | Aprobada | R10–R14 |
| TP14 | Aprobada | `e7_t05`; `e7_t10_integracion` (total caja 114) |
| TP15 | Aprobada | `e7_t05` |
| TP16 | Aprobada | `e7_t05` |
| TP17 | Aprobada | `e7_t05` |
| TP18 | Aprobada | R6–R9 |
| TP19 | Aprobada | `e7_t05`; Node T07/T08; recorrido API |
| TP20 | Aprobada | `e7_t02`, `e7_t03`, `e7_t05`, `e7_t10_integracion` |
| TP21 | Aprobada | `e7_t02`, `e7_t09`; §4 (privilegios con roles reales) |
| TP22 | Aprobada | `e7_t03`; `e7_t11_complementos` |
| TP23 | Aprobada | `e7_t09`; R15; recorrido API; Node `kitchenCommand` |
| TP24 | Aprobada (parte técnica) | `e7_t09` (estados idénticos); Node `kitchenCommand` (registro previo a `window.print()`, sin bloqueo). Impresora apagada/diálogo cancelado con dispositivo real: E7-TH05 (T12) |
| TP25 | Aprobada | `e7_t04`, `e7_t05`, `e7_t05b`, `e7_t09`; `e7_t11_complementos` (ADMINISTRADOR no recibe, cancela, imprime, lee tablero, edita ni retira; `anon` sin `EXECUTE`) |
| TP26 | Aprobada | Pruebas E7 de metadatos; catálogo de seguridad §4 (0 `40001`, 0 `SECURITY DEFINER` inseguros, RLS) |
| TP27 | Aprobada | Recorrido API/Realtime 19/19 (×2 en T11, ×1 en T10); `e7_t10_integracion` (visibilidad RLS de señales) |
| TP28 | Aprobada | Node `kitchenRealtimeService` (eventos repetidos/fuera de orden, resync en error y reconexión, respuestas tardías) y `waiterRealtime`; la cancelación usa la misma señal `UPDATE` de `pedido` (recorrido API) |
| TP29 | Aprobada | §5: H3/H4 sin regresiones; `h3_t04` y `order_audit_trail` superadas por E7 y documentadas |
| TP30 | Aprobada | §5: H5/E1 sin regresiones; Node caja/impresión/Inicio/Pedidos ADMIN en la suite completa |
| TP31 | Aprobada | Replay limpio, suite SQL, suite Node, `typecheck`, `build`, sin conexiones residuales |

## 9. Calidad del repositorio

| Verificación | Resultado |
|---|---|
| `git diff --check` (árbol y `main...HEAD`) | Sin errores |
| Secretos en archivos versionados (`sb_secret_`, JWT, `service_role`) | 0 coincidencias; registros `*.log` ignorados y sin claves |
| Fixtures/residuos | 0 locales/usuarios de validación, 0 bases efímeras, 0 conexiones de la campaña; volumen local reconstruido limpio |
| Stack | `supabase stop`; 0 contenedores `supabase_*` |
| Archivos temporales | Ninguno en el repositorio (copias homologadas sólo dentro del contenedor, eliminadas) |

## 10. Pendientes reales

1. **T12 — validación humana** (TH01–TH07), incluida la impresión física TH05 y la verificación de TP27 en dispositivos reales (atender la observación D-12).
2. **Revalidación cloud segura** (DEV/Preview) cuando PM-002 lo permita; T10/T11 no la sustituyen.
3. **Fuera de E7:** corrección de `h3_abrir_o_recuperar_pedido` (§7) y, opcionalmente, homologación formal de las pruebas históricas afectadas por E1-T18 (`40001` → `PT409`) y por E7 (`h3_t04`, `order_audit_trail`, `dbstd_t04`, cleanup H4-T03).
