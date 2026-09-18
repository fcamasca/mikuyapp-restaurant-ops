# E1 — Entrega parcial de construcción: T12

Fecha: 2026-09-17. No constituye aceptación de E1.

E1-T12 queda **COMPLETADA técnicamente en PostgreSQL local aislado y frontend**. La migración `20260917000200_e1_t12_reportes_caja.sql` añade lecturas autoritativas de reporte por sesión y resumen diario sin modificar reglas financieras T03–T11 ni crear contabilidad o conciliación bancaria.

## Contratos finales

- `rpc_obtener_reportes_sesion_caja(uuid default null)`: CAJA/ADMINISTRADOR del local. Devuelve caja, sesión, actores y fechas, monto inicial, ventas y propinas por medio, entradas/salidas, esperado, contado, diferencia, descuentos, anulaciones, cantidad de pagos/parciales y pedidos completados.
- `rpc_obtener_resumen_diario_caja()`: CAJA/ADMINISTRADOR del local. Usa corte `America/Lima` y devuelve total vendido, ventas/propinas por medio, descuentos, anulaciones, pagos, parciales y pedidos completados sin duplicarlos por N pagos.

La vista existente `/ventas` evolucionó a reportes operativos: muestra resumen diario, selector/reporte de sesión y exportación CSV de ambos snapshots. JavaScript sólo transforma nombres/tipos para presentación y CSV; no suma ni reconstruye importes financieros.

## Validación

- TP56–TP58 SQL: aprobados.
- Regresión H6 de reportes/exportaciones: aprobada.
- Pruebas Node/React afectadas: 35/35 aprobadas.
- Pruebas focalizadas finales de reportes: 9/9 aprobadas.
- `npm run typecheck`: aprobado.
- `npm run build`: aprobado, con advertencia no bloqueante de tamaño de chunk.

Entorno: contenedor local aislado `mikuyapp-e1-t09-validation-20260914`, base `e1_t11_validation_20260917`, previamente validada hasta T11. Se aplicó T12 una vez; no se repitieron replay integral, suites SQL T03–T11, regresión integral T13 ni TP62–TP64.

No se iniciaron T13–T14, no se modificaron `PLAN_MVP.md`, PM-002 ni ambientes alojados, y no hubo commit, push o merge.
