# MikuyApp — PM-002 Separación de ambientes DEV/Preview y PROD: tareas

> Este documento es planificación. Solo PM002-T01 fue completada en Spec Mode. Ninguna tarea de construcción, configuración o despliegue ha sido iniciada.

| ID | Objetivo | Dependencias | Resultado verificable | Pruebas |
|---|---|---|---|---|
| PM002-T01 | **Completada en Spec Mode.** Inventariar repositorio, planes, H6, PM-001, Cloudflare versionado, variables, Supabase, migraciones, seed, Auth, RLS, Realtime, CI, pruebas y carga inicial; documentar hechos, brechas y decisiones abiertas. | H6 y PM-001 aceptados | Cuatro documentos de Spec creados; sin cambios de runtime/remotos. | Revisión documental |
| PM002-T02 | Registrar `LEGACY_SHARED`, inventariar la matriz actual Local/Preview/Production y documentar el criterio de transición a `TRANSITIONING`/`SEPARATED`. | T01, acceso de lectura cuando corresponda | Estado vigente y rutas permitidas por fase documentados sin cambiar variables. | PM002-TP01–TP06 |
| PM002-T03 | Definir la matriz objetivo y las variables públicas por ámbito, preservando Production vigente durante la transición. | T01–T02 | Refs esperados y contextos por estado explícitos; valores sensibles no entran en evidencia. | TP03–TP06 |
| PM002-T04 | Implementar la guardia build-time acotada: contexto, estado/identidad lógica, URL/ref efectivo y ref esperado. | T03, D02–D03 | Preview → PROD, Local → PROD y Production → DEV en `SEPARATED` fallan; Production vigente sigue permitido antes del cutover. | TP07–TP12 |
| PM002-T05 | Actualizar `.env.example`, documentación local y scripts de validación para que local use DEV y secretos PROD queden fuera del flujo habitual. | T04, D04 | Desarrollo local arranca contra DEV; PROD no aparece en archivos locales requeridos. | TP10–TP12 |
| PM002-T06 | Reconstruir el baseline desde cero en instancia local/desechable, sin seed demo, y capturar catálogo esperado. | T01, D05 | 28 migraciones o baseline posterior aprobado aplican en orden; catálogo completo reconciliado. | TP13–TP20 |
| PM002-T07 | Auditar de forma no destructiva el drift entre DEV alojado y baseline; inventariar configuración no SQL. | T06, acceso lectura DEV | Cada diferencia clasificada; cero dependencia necesaria sin resolución. | TP21–TP23 |
| PM002-T08 | Preparar el mecanismo más sencillo, controlado, reproducible y seguro para cargar los maestros iniciales aprobados necesarios para habilitar PROD. | T06–T07, decisión de maestros antes de habilitar | Fuente validada, carga transaccional, duplicados/idempotencia cuando corresponda y reconciliación; sin arquitectura genérica de importación. | TP24–TP27 |
| PM002-T09 | Crear el proyecto PROD con acceso restringido y configuración alojada aprobada. | T06–T07; organización, región, plan, administradores y secretos aprobados | Proyecto nuevo, credenciales nuevas, administradores mínimos y matriz de configuración registrada; estado `TRANSITIONING`. | TP28–TP30 |
| PM002-T10 | Aplicar migraciones a PROD, sin seed demo; validar catálogo, grants, RLS, policies, funciones y Realtime. | T09, aprobación explícita de ejecución | PROD reconstruido y validado sin datos DEV. | TP13–TP23, TP28–TP31 |
| PM002-T11 | Configurar Auth, ejecutar la carga inicial acotada y crear usuarios/perfiles productivos mediante procedimiento controlado. | T08, T10; Auth, maestros y usuarios aprobados antes de habilitar | Maestros y cuatro capacidades de rol reconciliados; cero cuenta de prueba copiada. | TP24–TP30, TP32 |
| PM002-T12 | Configurar Cloudflare Preview → DEV, probar la guardia negativa y mantener Production sin cambios hasta aprobación. | T03–T05 | Todo Preview verificado contra DEV; Preview → PROD bloqueado. | TP03–TP12, TP33 |
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

- [ ] Estado vigente y matriz por fase documentados.
- [ ] Variables públicas y secretos clasificados por ambiente/ámbito.
- [ ] Guardias positivas y negativas cubiertas por pruebas.
- [ ] Ningún secreto con prefijo `VITE_`.
- [ ] Baseline limpio sin `seed.sql` aprobado.
- [ ] Drift DEV ↔ repositorio resuelto.
- [ ] Configuración alojada de Supabase registrada.
- [ ] Mecanismo acotado de carga inicial validado, transaccional y reconciliado.
- [ ] Usuarios PROD nuevos y perfiles vinculados sin persistir secretos/UUID.
- [ ] Preview confirmado en DEV antes de cambiar Production.
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
