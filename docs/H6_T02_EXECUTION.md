# MikuyApp — Evidencia H6-T02

Fecha de reapertura: 2026-08-30.

## Estado

H6-T02 queda reabierta por el defecto detectado durante H6-TP17: la ruta protegida `/ventas` existía y funcionaba, pero `ADMINISTRADOR` y `CAJA` no tenían un acceso visible desde su flujo normal.

## Corrección

- Se reutilizó el menú de usuario existente; no se creó un sistema de navegación nuevo ni se rediseñaron pantallas.
- Se agregó la opción `Resumen diario` únicamente cuando el rol autenticado es `ADMINISTRADOR` o `CAJA`.
- Administración y Caja navegan a `/ventas` mediante el enrutamiento SPA existente.
- `MOZO` y `COCINA` no reciben la acción y la condición de rol del menú impide mostrarla.
- La autorización existente de `/ventas`, las RPC y el aislamiento por local no fueron modificados.

## Validación

| Verificación | Resultado |
|---|---|
| Ventas y acceso visible | 5/5 pruebas aprobadas |
| Rutas y autorización | 13/13 pruebas aprobadas |
| Regresión de Caja | 7/7 pruebas aprobadas |
| Typecheck | Aprobado |
| Build | Aprobado; genera `index-BhmtZEbO.js` y conserva únicamente el aviso conocido de bundle >500 kB |
| Acceso funcional publicado | Pendiente de desplegar el build corregido y comprobar la opción con usuarios `ADMINISTRADOR` y `CAJA` |

H6-T02 no se cierra mientras la validación funcional publicada permanezca pendiente. H6-TP17 continúa detenido y no debe reanudarse antes del despliegue de esta corrección.
