# MikuyApp — Hito H2: Tareas

La estimación revisada es **540 minutos (9 horas)**. El plan original asignaba **240 minutos (4 horas)** a los días 3 y 4; la desviación es **+300 minutos (+5 horas)**. El MVP completo pasa de **24 a 29 horas**, sin recortar H3–H6 ni reducir seguridad, privilegios, integridad o pruebas. La construcción se ejecuta únicamente para las tareas autorizadas expresamente.

## Estado de ejecución

- [x] T01 — Alcance H2, base H1, variables públicas y acceso administrativo verificados.
- [x] T02 — Autenticación, login/logout, persistencia y ocho pruebas automatizadas verificadas.
- [x] T03 — Perfil, rol y local validados con pruebas automatizadas; pruebas reales con usuarios y RLS pendientes de T05–T08.
- [x] T04 — Rutas protegidas, guardas y destinos por rol verificados; validación real pendiente de T05–T08 y adaptación definitiva de `/tecnica` pendiente de T18.
- [x] T05 — Cuatro cuentas Auth asociadas a perfiles activos; roles ADMINISTRADOR, MOZO, COCINA y CAJA y local MIKUY-DEMO confirmados administrativamente.
- [x] T06 — Función `public.h2_auth_context()` implementada y aplicada; validación con usuarios autenticados pendiente hasta después de T08.
- [x] T07 — Privilegios PostgreSQL aplicados y verificados; INSERT y UPDATE limitados a columnas autorizadas, sin acceso a secuencias ni tablas transaccionales.
- [x] T08 — Políticas RLS por rol, local y operación aplicadas y verificadas; la validación real con los cuatro roles corresponde a T19.
- [x] T09 — Consultas administrativas y operativas de categorías/productos implementadas y verificadas; validaciones reales pendientes en T19 y validaciones visuales pendientes en T13, T17 y T21.
- [x] T10 — Administración completa de categorías implementada y verificada; creación, edición, activación, desactivación y eliminación confirmada disponibles.
- [x] T11 — Administración completa de productos implementada y verificada; creación, edición, activación, desactivación, reactivación y eliminación confirmada disponibles.
- [x] T12 — Administración completa de mesas implementada y verificada; altas en estado LIBRE, edición sin modificación de estado, activación, desactivación restringida y eliminación confirmada disponibles.

## Tareas planificadas

| ID | Min | Tarea | Dependencias | Resultado verificable | Pruebas asociadas |
|---|---:|---|---|---|---|
| T01 | 10 | Confirmar alcance actualizado, base H1, variables públicas y acceso administrativo | Autorización para construir | CRUD de tres catálogos y replanificación registrados | TP-25, TP-26, TP-27 |
| T02 | 25 | Integrar Auth, login/logout y sesión persistida | T01 | Inicio/cierre/restauración disponibles para cuatro roles | TP-01, TP-02, TP-03, TP-04, TP-05 |
| T03 | 25 | Consultar perfil propio y validar perfil, rol y local activos | T02 | Contextos inválidos y perfiles ajenos bloqueados | TP-05, TP-06, TP-07, TP-08, TP-23 |
| T04 | 20 | Configurar rutas protegidas, navegación y destinos por rol | T03 | Rutas autorizadas y `/tecnica` autenticada | TP-09, TP-10, TP-27 |
| T05 | 20 | Crear cuatro usuarios en Dashboard y asociar perfiles con SQL parametrizado | T01 | Cuatro perfiles sin secretos ni UUID versionados | TP-25, TP-26 |
| T06 | 30 | Implementar función de contexto `SECURITY DEFINER` sin recursión | T03, T05 | Contexto propio, activo y limitado a `authenticated` | TP-06, TP-07, TP-08, TP-20, TP-23 |
| T07 | 35 | Configurar privilegios PostgreSQL `INSERT` y `UPDATE` exclusivamente por columnas | T06 | INSERT/UPDATE por columnas aprobadas; `id`, `creado_en`, `mesa.estado` y local ajeno rechazados | TP-16, TP-21, TP-22, TP-43, TP-49, TP-50 |
| T08 | 40 | Aplicar políticas RLS SELECT/INSERT/UPDATE/DELETE por rol, local y estado de mesa | T06, T07 | Administrador muta solo su local; demás roles y anon rechazados | TP-19, TP-20, TP-21, TP-22, TP-23, TP-48, TP-49, TP-50 |
| T09 | 25 | Implementar consultas de carta y catálogos según estado, categoría y rol | T08 | Administrador ve activos/inactivos; carta operativa oculta categorías y productos inactivos | TP-11, TP-12, TP-13, TP-14, TP-52 |
| T10 | 40 | Implementar administración completa de categorías | T08, T09 | Crear, editar, activar/desactivar y eliminar sin dependencias | TP-31, TP-32, TP-33, TP-34, TP-35, TP-36, TP-51 |
| T11 | 40 | Implementar administración completa de productos | T08, T09, T10 | CRUD administrativo; reactivación, categoría del mismo local y eliminación restringida | TP-15, TP-37, TP-38, TP-39, TP-40, TP-41, TP-42, TP-49 |
| T12 | 35 | Implementar administración completa de mesas | T08 | CRUD administrativo; alta `LIBRE`, sin edición de estado | TP-43, TP-44, TP-45, TP-46, TP-47, TP-48 |
| T13 | 30 | Integrar carta agrupada y tablero operativo de mesas | T09, T10, T11, T12 | Carta filtrada y tablero del mozo solo con mesas activas | TP-11, TP-12, TP-17, TP-18, TP-19, TP-52 |
| T14 | 20 | Añadir validaciones de formularios, unicidad y valores inválidos | T10, T11, T12 | Obligatorios, código duplicado, precio/orden y categoría inválida controlados | TP-35, TP-36, TP-41, TP-42, TP-47 |
| T15 | 20 | Añadir confirmación de DELETE y mensajes de dependencias `ON DELETE RESTRICT` | T10, T11, T12 | Confirmar/cancelar y recomendar desactivación ante referencias | TP-33, TP-34, TP-39, TP-40, TP-45, TP-46, TP-51 |
| T16 | 20 | Reforzar columnas protegidas en INSERT/UPDATE y rechazo de mesa no libre | T07, T08, T12 | Altas y ediciones rechazan `id`, `creado_en`, local ajeno y `mesa.estado`; sin filas parciales | TP-16, TP-22, TP-43, TP-47, TP-48, TP-49, TP-50 |
| T17 | 20 | Ajustar formularios, estados y responsive celular/tablet | T10, T11, T12, T13 | Interfaz usable sin desbordes y estados de guardado distinguibles | TP-13, TP-24, TP-29, TP-53 |
| T18 | 15 | Integrar `/tecnica` autenticada compatible con los cuatro roles y regresión H1 | T04, T13 | Página muestra sesión/conexión/rol sin consultar mesas; API anónima H1 limitada conservada | TP-02, TP-09, TP-10, TP-19, TP-27 |
| T19 | 30 | Preparar validaciones automatizadas de API, INSERT/UPDATE por columna, RLS e integridad | T07, T08, T10, T11, T12, T16 | Altas/ediciones con columnas protegidas o payload mixto rechazadas sin filas parciales | TP-16, TP-19, TP-20, TP-21, TP-22, TP-23, TP-34, TP-40, TP-43, TP-46, TP-48, TP-49, TP-50 |
| T20 | 20 | Validar build, TypeScript y ausencia de secretos | T18, T19 | Build/TypeScript correctos y bundle/logs sin secretos | TP-25, TP-28 |
| T21 | 20 | Consolidar validación técnica y revisión humana responsive | T17, T20 | Evidencias, incidencias y revisión humana registradas sin anticipar aprobación | TP-29, TP-30, TP-53 |

T02–T08 cubren autenticación, roles, privilegios y RLS. T09–T16 cubren carta y administración segura de categorías, productos y mesas. T17–T21 cubren responsive, regresión H1 y validación técnica/humana. La suma exacta de T01–T21 es 540 minutos. Este documento no aprueba el spec ni marca H2 como completado.
