# E1 — Entrega parcial de construcción: T13

Fecha de revalidación delta: 2026-09-18. No constituye aceptación de E1.

E1-T13 queda **COMPLETADA técnicamente en PostgreSQL local aislado y frontend**. TP62–TP64 y T14 permanecen pendientes de validación humana.

## Replay, regresión y seguridad

- Replay limpio final del delta: 43 migraciones ordenadas y `supabase/seed.sql`, sobre `mikuyapp-e1-t09-validation-20260914/e1_t13_afcb03139d6247569824d3443ca43a36` (PostgreSQL 17, red `none`, sin bind mounts).
- Migraciones históricas: intactas. Las correcciones se añadieron como `20260917000300_e1_t13_trigger_pago_security.sql` y `20260917000400_e1_t13_auditoria_orden.sql`.
- Regresión SQL: H1–H6/PM-001 y E1 T03–T12 aprobadas sobre el contrato correspondiente; T03 se comprobó además con su runner histórico aislado.
- Seguridad final: cero funciones `SECURITY DEFINER` públicas con owner/search path inseguro; cero ejecuciones financieras concedidas a `anon`; RLS, grants, FKs y atomicidad aprobados; cero conexiones T13 residuales.
- Aplicación: 311/311 pruebas Node/React; `npm run typecheck` y `npm run build` aprobados. El build sólo advirtió sobre tamaño de chunk. No existe script/dependencia de lint.

## Carreras reales

- Doble apertura: tres variantes aprobadas; ambas llamadas observaron el mismo ID, una sesión `ABIERTA`, una auditoría y cero conexiones residuales.
- Doble cierre, cierre-vs-movimiento y cierre-vs-cobro: bloqueo real; ganador atómico y perdedor `40001` sin efectos parciales.
- Descuento-vs-cobro: el cobro esperó y aplicó el neto autorizado de 80.
- Anulación-vs-cobro: la anulación ganó; el cobro esperó y falló `40001`, sin pago inconsistente.
- Pagos T09: doble saldo final, parciales incompatibles, cobro-vs-cierre y cobro-vs-anulación aprobaron sin sobrepago, huérfanos ni conexiones residuales.

## Matriz TP01–TP61

| TP | Estado | Evidencia principal |
|---|---|---|
| TP01 | Aprobada | Modelo/constraint de caja y replay final |
| TP02 | Aprobada | SQL T03/T04: apertura y auditoría |
| TP03 | Aprobada | T04 secuencial: recupera snapshot sin duplicar |
| TP04 | Aprobada | Tres carreras de doble apertura |
| TP05 | Aprobada | Continuidad por Cajero B |
| TP06 | Aprobada | Idempotencia de apertura |
| TP07 | Aprobada | Autorización por local/caja |
| TP08 | Aprobada | Unicidad e histórico de sesión |
| TP09 | Aprobada | Actor por operación y aislamiento |
| TP10 | Aprobada | Rechazos sesión/caja/local |
| TP11 | Aprobada | Lectura de sesión autorizada |
| TP12 | Aprobada | Grants/RLS de apertura e histórico |
| TP13 | Aprobada | Entrada inmutable positiva |
| TP14 | Aprobada | Salida inmutable positiva |
| TP15 | Aprobada | Validaciones de movimiento |
| TP16 | Aprobada | Idempotencia y carrera movimiento/cierre |
| TP17 | Aprobada | Cierre, diferencia y actores |
| TP18 | Aprobada | Doble cierre y cierre-vs-cobro |
| TP19 | Aprobada | Descuento IMPORTE y snapshot 100/20/80 |
| TP20 | Aprobada | PORCENTAJE y redondeo PostgreSQL |
| TP21 | Aprobada | Separación CAJA/ADMINISTRADOR |
| TP22 | Aprobada | Entradas de descuento inválidas |
| TP23 | Aprobada | Inmutabilidad tras decisión/pago |
| TP24 | Aprobada | Carrera descuento-vs-cobro |
| TP25 | Aprobada | Resolver subtotal/descuento/neto |
| TP26 | Aprobada | Anulación atómica, mesa e historial |
| TP27 | Aprobada | Matriz completa de estados |
| TP28 | Aprobada | Pago confirmado bloquea anulación |
| TP29 | Aprobada | Carrera anulación-vs-cobro |
| TP30 | Aprobada | Terminalidad PAGADO/ANULADO |
| TP31 | Aprobada | Compatibilidad legacy de pago |
| TP32 | Aprobada | Pago total único |
| TP33 | Aprobada | Dos medios distintos |
| TP34 | Aprobada | TARJETA + TARJETA |
| TP35 | Aprobada | Calculadora UI sin persistencia por líneas |
| TP36 | Aprobada | Cuatro pagos repetidos/distintos |
| TP37 | Aprobada | Importe inválido y sobrepago |
| TP38 | Aprobada | Carrera doble saldo final |
| TP39 | Aprobada | Carrera parciales incompatibles |
| TP40 | Aprobada | Idempotencia/reintento de pago |
| TP41 | Aprobada | Reapertura previa al primer pago |
| TP42 | Aprobada | Mutaciones bloqueadas tras parcial |
| TP43 | Aprobada | Sesión/caja/local/actor de pago |
| TP44 | Aprobada | Carrera cobro-vs-cierre |
| TP45 | Aprobada | Propina separada |
| TP46 | Aprobada | Propina inválida rechazada |
| TP47 | Aprobada | Propina efectivo en esperado |
| TP48 | Aprobada | Recibo parcial/ticket consolidado interno |
| TP49 | Aprobada | Reconstrucción ordenada de sesión compartida |
| TP50 | Aprobada | Snapshots anterior/nuevo coherentes |
| TP51 | Aprobada | Auditoría sin escritura directa |
| TP52 | Aprobada | Aislamiento por local e IDs |
| TP53 | Aprobada | FKs RESTRICT |
| TP54 | Aprobada | Rollback dominio + auditoría |
| TP55 | Aprobada | SECURITY DEFINER/owner/search path/grants/RLS |
| TP56 | Aprobada | Reporte de sesión conciliado |
| TP57 | Aprobada | Resumen diario con parciales |
| TP58 | Aprobada | Lima, dos locales y CSV |
| TP59 | Aprobada | Estados UI y reintento |
| TP60 | Aprobada | Doble envío, respuesta obsoleta y Realtime |
| TP61 | Aprobada | Regresión integral, SQL, seguridad, concurrencia, Node, typecheck y build |

## Defectos detectados y corregidos

1. El trigger que protege detalles tras un pago consultaba `pago` con privilegios del invocador y podía producir `42501`. Se convirtió en `SECURITY DEFINER`, owner `postgres`, `search_path=pg_catalog` y sin `EXECUTE` cliente.
2. Eventos de auditoría creados en una misma transacción compartían timestamp y podían leerse en orden no determinista. La RPC de lectura aplica precedencia estable de eventos sin cambiar los eventos ni sus timestamps.
3. La adaptación T10 había perdido la suscripción Realtime de Caja. Se restauró usando la infraestructura H4/H5 y descartando respuestas tardías tras cleanup.
4. Pruebas históricas con inventarios exactos o regex dependientes del formateo se homologaron a los contratos aditivos aprobados, sin reducir invariantes.

No se inició T14, no se ejecutaron TP62–TP64, no se modificaron `PLAN_MVP.md`, PM-002 ni ambientes alojados, y no hubo commit, push o merge.
