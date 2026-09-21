# E1 — Entrega de construcción: T15

Fecha de validación: 2026-09-21. No constituye aceptación de E1.

E1-T15 queda **COMPLETADA técnicamente en PostgreSQL local aislado y frontend**. T14 y TP62–TP64 permanecen pendientes de validación humana.

## Diseño implementado

- `notificacion_caja` representa únicamente eventos internos `APERTURA`/`CIERRE`, referencia de forma única a `auditoria_caja` y conserva sólo tipo, prioridad y vínculos; no duplica importes ni snapshots financieros.
- `notificacion_caja_destinatario` materializa una entrega por cada `ADMINISTRADOR` activo del mismo local y conserva `leida_en` individual.
- Un trigger restringido a auditorías `APERTURA`, `CIERRE` y `CIERRE_SUPERVISOR` genera notificación y destinatarios dentro de la misma transacción financiera. Recuperar una sesión, reintentar o fallar no produce duplicados ni huérfanos.
- `rpc_obtener_notificaciones_caja()` compone caja, actor legible e importes desde auditoría y snapshots existentes. El nombre del actor se resuelve dentro de la RPC sin ampliar el acceso directo a `perfil_usuario`.
- `rpc_marcar_notificacion_caja_leida(uuid)` sólo actualiza la entrega propia del administrador autenticado y es idempotente.
- La interfaz administrativa incorpora campana, contador, lista reciente y estilos informativo/alerta. Caja advierte antes de confirmar un cierre con diferencia; no existe aprobación/rechazo.

## Migración

Nueva migración aditiva, pendiente de aplicación manual en DEV:

`supabase/migrations/20260921000100_e1_t15_notificaciones_caja.sql`

No se editaron migraciones históricas ni se aplicaron cambios remotos.

## Validación SQL

- Replay limpio: **45 migraciones + seed**, PostgreSQL local, base aislada `e1_t15_951aac247c5345e1a8943b4d7a78209e`.
- T15 SQL: TP02, TP06, TP10, TP17, TP18, TP51, TP52, TP54, TP55, TP59 y TP60 aprobados.
- Destinatarios: dos administradores activos locales recibieron una entrega cada uno; administrador inactivo y administrador de otro local recibieron cero.
- Idempotencia: apertura/cierre reintentados conservaron una notificación y una entrega por destinatario.
- Atomicidad: fallo inducido en destinatarios revirtió apertura, auditoría y notificación.
- Seguridad: CAJA/MOZO/COCINA/anon/otro local rechazados; tablas sin privilegio cliente; actor legible sólo por RPC.
- Regresiones afectadas aprobadas: `e1_t04_apertura_sesion`, `e1_t05_movimientos_cierre`, `e1_t11_auditoria_financiera`.

## Validación frontend

- **58/58** pruebas Node/React afectadas aprobadas: notificaciones, Caja y Administración.
- `npm run typecheck`: aprobado.
- `npm run build`: aprobado.
- Warning no bloqueante: Vite informó un chunk minificado mayor de 500 kB.

## Límites preservados

No se modificaron reglas financieras, PM-002, PROD ni DEV remoto. No se creó framework genérico, aprobación de diferencias, notificaciones para otros eventos, deploy ni `acceptance.md`. TP62 permanece abierto.
