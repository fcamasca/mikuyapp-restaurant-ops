# MikuyApp — Aceptación del Hito H1

## Identificación

| Campo | Valor |
|---|---|
| Fecha | 2026-08-23 |
| Responsable de aceptación | Frankz Camasca |
| Producto | `mikuyapp` |
| Repositorio GitHub oficial | `fcamasca/mikuyapp-restaurant-ops` |
| Rama evaluada | `feature/h1-TechnicalBasis` |
| SHA evaluado | `a3f9949c01ec83ae2d56ddbff31d36bb748cd4e9` (`a3f9949`) |
| Preview evaluado | <https://1c1020bb.mikuyapp.pages.dev/> |

## Alcance aceptado

Se acepta el alcance aprobado de H1: repositorio y entorno reproducible; aplicación mínima Vite, React, TypeScript y Tailwind; modelo PostgreSQL de diez tablas; migración y seed demo idempotente; seguridad pública mínima; cliente de lectura Supabase; página técnica con estados controlados; y Preview en Cloudflare Pages.

H1 mantiene fuera de alcance autenticación funcional, autorización completa por rol, Realtime, operaciones de pedidos, cocina, caja, impresión, reportes y funciones de hitos posteriores.

## Evidencia de aceptación

- TP-01–TP-20 están aprobadas.
- La validación humana fue realizada por Frankz Camasca sobre el SHA y la URL indicados.
- La vista amplia fue aprobada.
- La vista móvil `390 × 844` fue aprobada sin desbordamiento horizontal crítico.
- La aplicación cargó y comunicó correctamente la conexión con Supabase.
- El local `MIKUY-DEMO`, 6 mesas, 5 categorías y 10 productos fueron visibles y legibles.
- La presentación general resultó comprensible.

## Seguridad

Se confirmó que la lectura anónima permanece limitada a los datos públicos requeridos, que las escrituras anónimas son rechazadas y que no existen credenciales privadas en los archivos versionados, el bundle, la configuración o la evidencia. La Publishable key pública del frontend es el único valor permitido en el artefacto compilado y no se registra aquí.

## Decisión

Frankz Camasca acepta H1 como técnicamente construido y validado dentro del alcance aprobado.

La rama `feature/h1-TechnicalBasis` fue integrada en `main` mediante fast-forward. El SHA funcional `03e75941349475562aa20d0e913abfbe418f4487` fue verificado en `main` mediante GitHub Actions y desplegado correctamente en <https://mikuyapp.pages.dev/> con HTTP 200, conexión Supabase correcta y datos demo 6/5/10 sin alteraciones.

Con la integración y la producción verificadas, H1 queda cerrado. Se conservan sin cambios los criterios históricos, la aceptación humana y la evidencia TP-01–TP-20.
