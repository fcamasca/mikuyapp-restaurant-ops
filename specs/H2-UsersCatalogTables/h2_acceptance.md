# MikuyApp — Aceptación del hito H2

## Identificación

- Hito: H2 — Usuarios, carta y mesas.
- Fecha de aceptación: 25 de agosto de 2026.
- Rama validada: `feature/H2-UsuariosCartaMesas`.
- Commit técnico validado: `9e03aaa5f4957da5a13def1cb07767aa593352fd`.
- Preview validado: https://feature-h2-usuarioscartamesa.mikuyapp.pages.dev

## Objetivo y alcance aceptado

Se acepta la integración de autenticación y sesión persistente; contexto propio de perfil, rol y local; rutas y guardas por rol; privilegios PostgreSQL y políticas RLS; carta operativa; tablero de mesas del mozo; página técnica autenticada; y administración completa de categorías, productos y mesas.

El alcance incluye creación, consulta, edición, activación, desactivación, reactivación cuando corresponde y eliminación física controlada, con validaciones de dependencias, aislamiento por local, restricciones por rol y protección de columnas sensibles.

## Evidencia de conformidad

- 212 pruebas automatizadas aprobadas.
- Validación anónima H1 aprobada, conservando únicamente las lecturas públicas autorizadas y rechazando escrituras anónimas.
- Pruebas autenticadas reales aprobadas con `ADMINISTRADOR`, `MOZO`, `COCINA` y `CAJA`.
- CRUD completo de categorías, productos y mesas validado.
- Privilegios por columnas, RLS, aislamiento entre locales y ausencia de elevación de privilegios validados.
- Columnas protegidas y payloads mixtos rechazados completamente, sin modificaciones parciales.
- Estado de mesa protegido y desactivación de mesas no libres rechazada.
- Fixtures controlados T19 y registros temporales eliminados sin residuos.
- Sesiones de prueba cerradas correctamente; las cuatro cuentas Auth de prueba continúan disponibles.
- TypeScript y build de producción aprobados; salida compatible con Cloudflare Pages.
- Preview desplegado y rutas SPA verificadas.
- Auditoría de secretos aprobada: `.env.local` permanece ignorado y no versionado; no se registraron credenciales, contraseñas, tokens ni UUID Auth.
- TP-01 a TP-53 conformes, sin fallos ni pruebas pendientes.
- Validación humana aprobada en sus 15 puntos, cubriendo administración de los tres catálogos, limpieza de temporales, flujo y carta del mozo, cuatro estados de mesa, accesos de cocina y caja, restricciones de rutas, cierre de sesión, celular, tablet y ausencia de desbordamientos o controles ilegibles.
- No existen bloqueantes pendientes.

## Declaración de aceptación

Con base en la evidencia automatizada, las verificaciones técnicas manuales y la validación humana registradas, el hito H2 — Usuarios, carta y mesas queda formalmente aceptado en el alcance aprobado.

Esta aceptación no modifica, adelanta ni amplía el alcance de H3 ni de otros hitos, no implica fusión con `main` y no promueve manualmente el Preview a producción.
