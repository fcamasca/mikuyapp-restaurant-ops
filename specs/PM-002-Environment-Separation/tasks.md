# MikuyApp — PM-002 Separación de ambientes DEV/Preview y PROD: tareas

> PM002-T01 fue completada en Spec Mode. T02–T07 y T09–T10 están completadas; T12 fue validada funcionalmente con evidencia manual del usuario. PM-002 permanece en `TRANSITIONING`, sin cutover.

| ID | Objetivo | Dependencias | Resultado verificable | Pruebas |
|---|---|---|---|---|
| PM002-T01 | **Completada en Spec Mode.** Inventariar repositorio, planes, H6, PM-001, Cloudflare versionado, variables, Supabase, migraciones, seed, Auth, RLS, Realtime, CI, pruebas y carga inicial; documentar hechos, brechas y decisiones abiertas. | H6 y PM-001 aceptados | Cuatro documentos de Spec creados; sin cambios de runtime/remotos. | Revisión documental |
| PM002-T02 | **Completada.** Registrar `LEGACY_SHARED`, inventariar la matriz actual Local/Preview/Production y documentar el criterio de transición a `TRANSITIONING`/`SEPARATED`. | T01, acceso de lectura cuando corresponda | Estado vigente y rutas permitidas por fase documentados sin cambiar variables. | PM002-TP01–TP06 |
| PM002-T03 | **Completada.** Definir la matriz objetivo y las variables públicas por ámbito, preservando Production vigente durante la transición. | T01–T02 | Refs esperados y contextos por estado explícitos; valores sensibles no entran en evidencia. | TP03–TP06 |
| PM002-T04 | **Completada.** Implementar la guardia build-time acotada: contexto, estado/identidad lógica, URL/ref efectivo y ref esperado. | T03, D02–D03 | TP07–TP12 aprobaron 8/8: bloqueos obligatorios y Production vigente permitida antes del cutover. | TP07–TP12 |
| PM002-T05 | **Completada.** Actualizar `.env.example`, documentación local, CI y scripts de validación para que local use DEV y secretos PROD queden fuera del flujo habitual. | T04, D04 | Guardia aprobada en prebuild; configuración pública sintética en CI; scan sin secretos detectados. | TP10–TP12 |
| PM002-T06 | **Completada.** Reconstruir el baseline desde cero en instancia local/desechable, sin seed demo, y capturar catálogo esperado. | T01, D05 | 28/28 migraciones; 10 tablas con RLS, 27 policies, 17 funciones, 2 triggers y Realtime esperado; lint, 25 suites SQL, 5 concurrencias, 305 tests, typecheck y build aprobados. | TP13–TP20 |
| PM002-T07 | **Completada.** La auditoría no destructiva confirmó 28/28 migraciones alineadas, clasificó grants/default privileges e inventarió Supabase alojado y Cloudflare. Production/Preview permanecen en el proyecto compartido `LEGACY_SHARED`; las variables adicionales de la guardia son dependencias conocidas de T12/T13. El historial de variables no disponible se registra N/A sin asumir datos. | T06, acceso lectura DEV/Cloudflare | Diferencias y configuración alojada clasificadas en `docs/PM002_T07_HOSTED_AUDIT.md`; no queda una dependencia productiva desconocida exclusiva del proyecto actual. | TP21–TP23 |
| PM002-T08 | Preparar el mecanismo más sencillo, controlado, reproducible y seguro para cargar los maestros iniciales aprobados necesarios para habilitar PROD. | T06–T07, decisión de maestros antes de habilitar | Fuente validada, carga transaccional, duplicados/idempotencia cuando corresponda y reconciliación; sin arquitectura genérica de importación. | TP24–TP27 |
| PM002-T09 | **Completada.** Se creó `mikuyapp-prod` en la organización actual, región `sa-east-1`, plan Free y administración restringida al propietario vigente. Project ref PROD distinto, credenciales propias, PostgreSQL 17, proyecto vacío y defaults alojados inventariados sin aplicar migraciones, seed, usuarios o datos. | T06–T07; organización, región, plan, administradores y secretos aprobados | Evidencia en `docs/PM002_T09_EXECUTION.md`; PM-002 entra en `TRANSITIONING` mientras Local, Preview y Production permanecen en el proyecto actual. | TP28–TP30 aplicables; validaciones de esquema/Auth/datos diferidas a T10/T11 |
| PM002-T10 | **Completada.** Se aplicaron 28/28 migraciones versionadas a `mikuyapp-prod`, sin seed ni datos. Historial, 10 tablas, RLS 10/10, 27 policies, 17 funciones, 2 triggers, constraints/índices, owners y Realtime fueron reconciliados; lint remoto aprobó. Los grants/default privileges adicionales se clasificaron como comportamiento administrado de Supabase. | T09, aprobación explícita de ejecución | Evidencia en `docs/PM002_T10_EXECUTION.md`; PROD reconstruido sin usuarios, demo, maestros ni transacciones y PM-002 permanece `TRANSITIONING`. | TP13–TP23 y TP28–TP31 aplicables; pruebas con Auth/maestros diferidas a T11/T13 |
| PM002-T11 | Configurar Auth, ejecutar la carga inicial acotada y crear usuarios/perfiles productivos mediante procedimiento controlado. | T08, T10; Auth, maestros y usuarios aprobados antes de habilitar | Maestros y cuatro capacidades de rol reconciliados; cero cuenta de prueba copiada. | TP24–TP30, TP32 |
| PM002-T12 | **Completada.** Cloudflare Preview quedó configurado para DEV bajo `TRANSITIONING`; un deployment nuevo finalizó correctamente y el usuario validó el flujo completo hasta cobro en caja sin incidencias. Production permaneció sin cambios sobre el proyecto actual compartido y `mikuyapp-prod` no fue modificado. | T03–T05 | Evidencia en `docs/PM002_T12_EXECUTION.md`; Preview verificado contra DEV, guardia negativa cubierta y ausencia de cutover confirmada. | TP03–TP12, TP33; validación humana de Preview |
| PM002-T13 | En ventana aprobada, configurar Cloudflare Production → PROD y ejecutar smoke, regresión técnica y validación humana. | T10–T12; ventana, responsables, rollback/recuperación y aprobación explícita | Production usa PROD; Preview/local siguen DEV; `SEPARATED` declarado solo tras verificación. | TP31–TP39, TP41 |
| PM002-T14 | Actualizar README, plan general, documentación Supabase/despliegue, changelog e índice; consolidar evidencia y solicitar aceptación. | T13 | Arquitectura oficial reflejada; PM-002 no se cierra sin aprobación. | TP40 y checklist humana |

## Orden y puertas

1. T02–T07 pueden avanzar sin decisiones de Auth, maestros, usuarios o cutover; son inventario, controles tempranos, baseline y drift.
2. Antes de T09 se aprueban organización, región, plan, administradores y manejo de secretos; T06–T07 bloquean T09 si existe drift necesario no resuelto.
3. Antes de T11 se aprueban Auth, maestros y usuarios productivos. T08 no exige dry-run o loader genérico.
4. T09 y cualquier acción remota requieren instrucción/autorización explícita posterior.
5. T12 precede T13; Preview se valida sin tocar Production y Production vigente no es bloqueado en `TRANSITIONING`.
6. Antes de T13 se aprueban ventana, responsables, rollback/recuperación, criterio de primera escritura y cutover explícito.
7. T14 no crea aceptación; solo prepara la evidencia.

## Checklist de construcción

- [x] Estado vigente y matriz por fase documentados.
- [x] Variables públicas y secretos clasificados por ambiente/ámbito.
- [x] Guardias positivas y negativas cubiertas por pruebas.
- [x] Ningún secreto con prefijo `VITE_`.
- [x] Baseline limpio sin `seed.sql` aprobado.
- [ ] Drift DEV ↔ repositorio resuelto.
- [ ] Configuración alojada de Supabase registrada.
- [ ] Mecanismo acotado de carga inicial validado, transaccional y reconciliado.
- [ ] Usuarios PROD nuevos y perfiles vinculados sin persistir secretos/UUID.
- [x] Preview confirmado en DEV antes de cambiar Production.
- [ ] Production confirmado en PROD.
- [ ] Secret scan de Git, bundle, sourcemaps, artefactos y logs aprobado.
- [ ] Regresión funcional y validación humana aprobadas.
- [ ] Documentación maestra actualizada.

## Trabajo deliberadamente no planificado

No se incluyen replicación, refresh, branching, read replicas, anonimización, backups entre ambientes, sincronización de datos, limpieza de DEV ni cambios funcionales. Tampoco se crea una pipeline automática de promoción de datos DEV → PROD.

## Pendientes bloqueantes de construcción

- Acceso administrativo a Cloudflare y Supabase para inventarios/verificación.
- Antes de crear PROD: organización, región, plan, administradores, secretos y orden explícita.
- Antes de habilitar PROD: configuración Auth, fuente maestra final, usuarios productivos y canal de alta.
- Antes del cutover: ventana, responsables, criterio de primera escritura, rollback/recuperación y aprobación explícita.
