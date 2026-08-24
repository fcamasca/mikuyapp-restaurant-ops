# MikuyApp — Hito H1: Evidencia de ejecución

## T-07 — Proyecto Supabase

| Campo | Valor |
|---|---|
| Fecha | 2026-08-23 |
| Responsable | Frankz Camasca |
| Servicio | Supabase |
| Proyecto | `mikuyapp` |
| Plan | Free |
| Estado | Healthy |
| Región | South America (São Paulo) |
| Código de región | `sa-east-1` |
| URL pública | <https://ibfrrifvhvtgcxfxuinf.supabase.co> |
| Migraciones actuales | Ninguna |

## Despliegue y validación de la migración H1

| Campo | Resultado |
|---|---|
| Fecha | 2026-08-23 |
| Responsable | Frankz Camasca |
| Commit HEAD | `443c5275467838c50fe787b9a200b781f975043e` |
| Supabase CLI | `2.115.0` |
| Proyecto | `mikuyapp` (`ibfrrifvhvtgcxfxuinf`) |
| Región | South America (São Paulo), `sa-east-1` |
| Migración | `20260823235106_h1_initial_schema.sql` |
| Dry-run | Correcto: una migración pendiente y `seeds: []` |
| Push | Correcto: una migración aplicada y `seeds: []` |
| Historial | Local `20260823235106`; remoto `20260823235106`; una versión H1 |
| TP-09 | Aprobada mediante `supabase/tests/tp09_tp11_schema.sql` |
| TP-11 | Aprobada mediante `supabase/tests/tp09_tp11_schema.sql` |
| Lint | Correcto: `No schema errors found` |
| Credenciales o secretos registrados | Ninguno |

## T-11 — Seed demo idempotente

| Campo | Resultado |
|---|---|
| Fecha | 2026-08-23 |
| Responsable | Frankz Camasca |
| Commit HEAD | `6984f4c495e39a470e5159f21358ac320612b550` |
| Proyecto | `mikuyapp` (`ibfrrifvhvtgcxfxuinf`) |
| Ejecución 1 del seed | Correcta mediante `supabase/seed.sql` |
| TP-12 | Aprobada mediante `supabase/tests/tp12_tp13_seed.sql` |
| Conteos tras ejecución 1 | 4 roles, 1 local, 6 mesas, 5 categorías y 10 productos |
| Ejecución 2 del seed | Correcta mediante `supabase/seed.sql` |
| Conteos tras ejecución 2 | 4 roles, 1 local, 6 mesas, 5 categorías y 10 productos |
| Comparación de identificadores | Huellas SHA-256 iguales sobre 26 pares ordenados de código e identificador |
| TP-13 | Aprobada: conteos, códigos e identificadores estables, sin duplicados |
| Usuarios y perfiles | 0 usuarios Auth y 0 perfiles |
| Datos transaccionales | 0 pedidos, 0 detalles, 0 historiales y 0 pagos |
| Credenciales, secretos o UUID registrados | Ninguno |

## T-12 — Cliente público y acceso anónimo

| Campo | Resultado |
|---|---|
| Fecha | 2026-08-23 |
| Responsable | Frankz Camasca |
| Commit HEAD | `f3045748dc4053f55829900e0fb9d952ce66e7e5` |
| Proyecto | `mikuyapp` (`ibfrrifvhvtgcxfxuinf`) |
| `@supabase/supabase-js` | `2.112.3` |
| Variables configuradas | `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY`, sin registrar valores |
| TP-14 — `local` | 1 fila activa legible |
| TP-14 — `mesa` | 6 filas activas legibles |
| TP-14 — `categoria` | 5 filas activas legibles |
| TP-14 — `producto` | 10 filas activas legibles |
| TP-14 — tabla privada | `pedido` rechazó `SELECT` por permisos/RLS |
| TP-17 — tablas públicas | `INSERT`, `UPDATE` y `DELETE` rechazados por permisos/RLS en las cuatro tablas |
| TP-17 — tabla transaccional | `INSERT`, `UPDATE` y `DELETE` rechazados por permisos/RLS en `pedido` |
| Comparación anterior/posterior | Conteos e identificadores sin cambios |
| Typecheck | Correcto mediante `npm run typecheck` |
| Build | Correcto mediante `npm run build` |
| TP-19 — alcance local | Variables locales ignoradas y plantilla sin valores; queda pendiente la revisión del despliegue en Cloudflare Pages |
| Revisión de secretos | Sin credenciales privadas en archivos versionables, build o reporte |
