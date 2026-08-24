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

## T-13 — Página técnica y estados

| Campo | Resultado |
|---|---|
| Fecha | 2026-08-23 |
| Responsable | Frankz Camasca |
| Commit HEAD | `ec357c0a64bcf2a7cd095532b5c8cc343e16ad5f` |
| Implementación | Página técnica React conectada exclusivamente a `demoCatalogService` |
| Estados implementados | `loading`, `success`, `empty`, `configuration-error` y `connection-error` |
| TP-05 | Aprobada: HTTP 200, página técnica visible, sin módulos operativos ni errores de consola |
| TP-15 — loading | Observado con mensaje de conexión y `aria-busy` |
| TP-15 — success | Observado con local `MikuyApp Demo`, código `MIKUY-DEMO` y datos remotos |
| TP-15 — empty | Observado mediante carga controlada sin modificar Supabase |
| TP-16 — configuración | Observada con variables ausentes controladas; mensaje accionable sin valores ni error crudo |
| TP-16 — conexión | Observada mediante fallo controlado; reintento recuperó el estado `success` |
| Conteos visibles | 6 mesas, 5 categorías y 10 productos activos |
| Responsive estrecho | 390 px: una columna, contenido legible y sin desbordamiento horizontal |
| Responsive amplio | 1280 px: resúmenes en tres columnas, secciones principales en dos y productos en tres; sin desbordamiento horizontal |
| Typecheck | Correcto mediante `npm run typecheck` |
| Build | Correcto mediante `npm run build` |
| Acceso anónimo | `npm run verify:anon` conserva TP-14 y TP-17 aprobadas; datos sin cambios |
| Pruebas controladas | `App.tsx` restaurado al SHA-256 original después de observar los estados |
| Revisión de secretos | Sin credenciales privadas en archivos versionables, bundle o logs; `.env.local` permanece ignorado |
| Defectos | Sin defectos funcionales pendientes; el escenario temporal de reintento se ajustó para React Strict Mode y fue retirado |

## T-14 — Despliegue Preview en Cloudflare Pages

| Campo | Resultado |
|---|---|
| Fecha | 2026-08-23 |
| Responsable | Frankz Camasca |
| Commit candidato | `c57cdf06ad83c5775a78eaf2f7029db854caaa98` (`c57cdf0`) |
| Producto y proyecto Pages | `mikuyapp` |
| Repositorio GitHub oficial | `fcamasca/mikuyapp-restaurant-ops` |
| Aclaración de ejecución | El nombre lógico y el proyecto Pages son `mikuyapp`; el slug real del repositorio es `fcamasca/mikuyapp-restaurant-ops`. No constituye un cambio de arquitectura. |
| Plan e integración | Cloudflare Pages Free conectado mediante GitHub |
| Rama de producción | `main` |
| Rama Preview | `feature/h1-TechnicalBasis`, configurada como rama personalizada |
| Configuración de build | React (Vite); `npm run build`; salida `dist`; Node.js `22.12.0` |
| Variables públicas | `NODE_VERSION`, `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY`, sin registrar valores |
| Despliegue inicial de producción | `main@4eb75d9` falló por ausencia de `package.json`; intento separado del candidato H1 y sin despliegue de producción |
| Despliegue Preview | Correcto para `feature/h1-TechnicalBasis@c57cdf0`; build, carga de tres activos y publicación completados |
| URL Preview validada | <https://c3cb696e.mikuyapp.pages.dev> |
| TP-18 | Aprobada: URL accesible, aplicación cargada, conexión comprensible, local demo y conteos 6 mesas, 5 categorías y 10 productos visibles; recarga correcta y sin errores propios de MikuyApp en consola |
| TP-19 | Aprobada: solo las tres variables públicas aprobadas en Preview; sin credenciales privadas en configuración, build o evidencia |
| Datos | Sin mutaciones: el despliegue realizó únicamente consultas públicas de lectura |
| Regresiones finales | `npm run typecheck`, `npm run build` y `npm run verify:anon` correctos; TP-14 y TP-17 permanecen aprobadas y los datos no cambiaron |
| Activación del candidato | Se usó un deploy hook temporal para construir el HEAD ya publicado sin commit ni push adicionales; el hook fue eliminado después del despliegue |
| Estado de producción | Sin despliegue de producción; no se fusionó ni convirtió la rama feature en producción |
| TP-20 | Pendiente de validación humana H1; las pruebas completas en dispositivos corresponden a H6 |

## T-15 — Consolidación técnica previa a TP-20

| Campo | Resultado |
|---|---|
| Fecha | 2026-08-23 |
| Responsable | Frankz Camasca |
| Commit HEAD auditado | `cbc1b3e` (`feat: t14`) |
| Rama y remoto | `feature/h1-TechnicalBasis`, sincronizada con `origin/feature/h1-TechnicalBasis` antes de los cambios T-15 |
| Aclaración de nombres | Producto y proyecto Cloudflare Pages: `mikuyapp`; repositorio GitHub oficial: `fcamasca/mikuyapp-restaurant-ops`. Es una corrección de nomenclatura, no de arquitectura. |
| TP-10 dinámica | Aprobada mediante `supabase/tests/tp10_constraints.sql`, ejecutada por `supabase db query --linked` dentro de `BEGIN`/`ROLLBACK` |
| Rechazos TP-10 | Rol, mesa, pedido, historial y medio de pago inválidos; cantidad fraccionaria (`22P02`), cero y negativa; precios negativos; importes cero y negativo; código duplicado y FK inexistente |
| Catálogos TP-10 | 9 UNIQUE exactos y 12 índices adicionales exactos de D-08 |
| Snapshot anterior | 4 roles, 1 local, 6 mesas, 5 categorías, 10 productos; 0 perfiles, pedidos, detalles, historiales, pagos y usuarios Auth |
| Snapshot posterior | Conteos idénticos al snapshot anterior |
| Huella demo | 26 pares ordenados; SHA-256 `d670493ae6c47501ad886a939daea69ab62c7c4fd785d7dc1d3c61c443cee12e` antes y después |
| Historial de migraciones | Local y remoto: única versión `20260823235106`; sin cambios |
| Entorno | Node.js `22.12.0`; npm `10.9.0`; Supabase CLI `2.115.0` |
| Lockfile | SHA-256 `4D802301CF095FFAC5B55F578512F234F4288B4B728E2962C5E9D988B1EFC66E` antes y después de `npm ci` |
| Regresiones | `npm ci`, `npm run typecheck`, `npm run build` y `npm run verify:anon` correctos |
| Base de datos | `supabase db lint --linked`: `No schema errors found`; TP-09/TP-11 y TP-12 ejecutadas por consultas SQL sin reaplicar migración ni seed |
| Preview revisado | <https://c3cb696e.mikuyapp.pages.dev/>: HTTP 200, React y Supabase comprensibles, local demo y conteos 6/5/10 visibles, 0 errores propios de MikuyApp |
| Auditoría de secretos | 41 archivos versionados/build revisados; `.env.local` no versionado; 0 credenciales privadas; una Publishable key en el bundle, permitida y sin registrar su valor |
| Estado de T-15 | En progreso; pendiente exclusivamente de TP-20 y aceptación humana |

### Matriz consolidada TP-01–TP-20

| Prueba | Estado | Evidencia actual | Fecha/entorno |
|---|---|---|---|
| TP-01 | Aprobada | Git, remoto `fcamasca/mikuyapp-restaurant-ops`, rama feature y archivos ignorados verificados | 2026-08-23 / Git local y GitHub |
| TP-02 | Aprobada | `npm ci` finalizó sin errores y el lockfile no cambió | 2026-08-23 / Windows x64 |
| TP-03 | Aprobada | Node `22.12.0`, npm `10.9.0`, `.nvmrc`, `engines` y lockfile consistentes | 2026-08-23 / Windows x64 |
| TP-04 | Aprobada | `npm run typecheck` terminó con código 0 | 2026-08-23 / local |
| TP-05 | Aprobada | Evidencia T-13 de arranque local y página técnica; Preview vigente carga React | 2026-08-23 / local y Preview |
| TP-06 | Aprobada | 4 roles, 4 estados de mesa, 8 de pedido, 4 medios y flujo declarativo exactos | 2026-08-23 / fuentes TypeScript y D-06 |
| TP-07 | Aprobada | Estructura D-02 presente; sin router, Realtime, Auth funcional ni módulos operativos | 2026-08-23 / árbol versionado |
| TP-08 | Aprobada | Build Vite correcto; CSS contiene utilidades Tailwind y breakpoints `sm`/`lg` | 2026-08-23 / `dist` local |
| TP-09 | Aprobada | Una migración aplicada y única versión local/remota `20260823235106` | 2026-08-23 / Supabase vinculado |
| TP-10 | Aprobada | Prueba dinámica transaccional: SQLSTATE/restricciones esperados, 9 UNIQUE y 12 índices; `ROLLBACK` | 2026-08-23 / Supabase vinculado |
| TP-11 | Aprobada | `tp09_tp11_schema.sql` confirmó tablas, columnas, PK, FK, nulabilidad, identity, ON DELETE y RLS | 2026-08-23 / Supabase vinculado |
| TP-12 | Aprobada | Consulta actual: 4 roles, 1 local, 6 mesas, 5 categorías y 10 productos; cero filas no permitidas | 2026-08-23 / Supabase vinculado |
| TP-13 | Aprobada | Evidencia de dos seeds conservada; huella actual de los mismos 26 identificadores permanece estable | 2026-08-23 / Supabase vinculado |
| TP-14 | Aprobada | Lectura anónima 1/6/5/10 y tabla `pedido` rechazada | 2026-08-23 / API pública Supabase |
| TP-15 | Aprobada | Evidencia T-13 de `loading`, `success` y `empty` controlado | 2026-08-23 / local |
| TP-16 | Aprobada | Evidencia T-13 de configuración ausente y fallo de conexión controlados, sin credenciales | 2026-08-23 / local |
| TP-17 | Aprobada | `INSERT`, `UPDATE` y `DELETE` anónimos rechazados; comparación anterior/posterior sin cambios | 2026-08-23 / API pública Supabase |
| TP-18 | Aprobada | Preview HTTP 200, React/Supabase correctos y datos demo 6/5/10 visibles | 2026-08-23 / Cloudflare Pages Preview |
| TP-19 | Aprobada | Git, build, configuración y evidencia sin secretos privados; solo variables públicas aprobadas | 2026-08-23 / local y Cloudflare Pages |
| TP-20 | Pendiente humana | Debe ejecutarse sobre la URL Preview final posterior al commit autorizado de T-15 | Pendiente / usuario |
