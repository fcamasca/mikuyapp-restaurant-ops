# MikuyApp — Evidencia H6-T02

Fecha de reapertura: 2026-08-30.

## Estado

H6-T02 queda reabierta por el defecto detectado durante H6-TP17: la ruta protegida `/ventas` existía y funcionaba, pero `ADMINISTRADOR` y `CAJA` no tenían un acceso visible desde su flujo normal.

## Corrección

- Se agregó navegación funcional visible `Resumen diario` en los encabezados existentes de Administración y Caja; no se creó un sistema de navegación nuevo ni se rediseñaron pantallas.
- El menú del avatar conserva únicamente identidad, rol y `Cerrar sesión`; no contiene navegación funcional.
- Administración y Caja navegan a `/ventas` mediante el enrutamiento SPA existente.
- `/ventas` ofrece retorno visible a `Cobros pendientes` para `CAJA` y al catálogo para `ADMINISTRADOR`, usando el mismo enrutamiento.
- `MOZO` y `COCINA` no reciben la acción porque sus pantallas no incorporan este control funcional.
- La autorización existente de `/ventas`, las RPC y el aislamiento por local no fueron modificados.

## Validación

| Verificación | Resultado |
|---|---|
| Ventas y navegación visible de ida/retorno | 5/5 pruebas aprobadas |
| Rutas y autorización | 13/13 pruebas aprobadas |
| Regresión de Caja | 7/7 pruebas aprobadas |
| Regresión de Administración | 28/28 pruebas aprobadas |
| Interfaz responsive | 14/14 pruebas aprobadas |
| Typecheck | Aprobado |
| Build | Aprobado; genera `index-5vrb77kv.js` y conserva únicamente el aviso conocido de bundle >500 kB |
| Acceso funcional publicado | Pendiente de desplegar el build corregido y comprobar la opción con usuarios `ADMINISTRADOR` y `CAJA` |

H6-T02 no se cierra mientras la validación funcional publicada permanezca pendiente. H6-TP17 continúa detenido y no debe reanudarse antes del despliegue de esta corrección.
