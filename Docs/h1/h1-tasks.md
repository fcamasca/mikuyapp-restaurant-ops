# MikuyApp — Hito H1: Tareas

La estimación total es 240 minutos. Es un límite de planificación, no autorización para construir. Ninguna tarea comienza hasta la aprobación humana del spec.

## Estado de ejecución

- [x] T-01 — Repositorio existente verificado en `feature/h1-TechnicalBasis` y vinculado con `origin`.
- [x] T-02 — Node.js `22.12.0`, npm `10.9.0`, configuración y lockfile verificados mediante `npm ci`.
- [x] T-03 — Proyecto mínimo Vite + React + TypeScript validado mediante TypeScript, build y arranque local.
- [x] T-08 — Migración de las diez tablas aplicada y validada sobre la base remota vacía.
- [x] T-09 — Restricciones, índices y acciones `ON DELETE RESTRICT` aplicados y validados.
- [x] T-10 — Privilegios y RLS anónimos mínimos aplicados y validados.
- [ ] T-04–T-07 y T-11–T-15 — Pendientes.

| ID | Min | Objetivo | Dependencias | Resultado verificable | Pruebas |
|---|---:|---|---|---|---|
| T-01 | 10 | Confirmar workspace e inicializar el repositorio Git oficial `mikuyapp`. | Spec aprobado | Repositorio con rama `main`, `.gitignore` y nombre/remoto documentados. | TP-01 |
| T-02 | 15 | Fijar entorno: Node 22 LTS, npm y lockfile. | T-01 | `.nvmrc`, `package.json` y `package-lock.json` versionados. | TP-02, TP-03 |
| T-03 | 20 | Crear el proyecto Vite React + TypeScript. | T-02 | Scripts de desarrollo, build y TypeScript funcionales. | TP-04, TP-05 |
| T-04 | 15 | Integrar Tailwind y estructura de carpetas. | T-03 | Tailwind compila y estructura coincide con D-02. | TP-07, TP-08 |
| T-05 | 10 | Registrar roles, estados y flujo operativo. | T-01 | Cuatro roles, cuatro estados de mesa, ocho de pedido y flujo consistentes. | TP-06 |
| T-06 | 15 | Definir datos demo y códigos estables. | T-05 | Dataset reproducible de roles, local, mesas, categorías y productos, sin usuarios ni datos transaccionales. | TP-12, TP-13 |
| T-07 | 15 | Crear Supabase Free y registrar nombre/región elegidos. | Acceso autorizado | Proyecto disponible; parámetros de ejecución registrados sin secretos. | TP-09, TP-19 |
| T-08 | 30 | Crear la migración de las diez tablas. | T-07 | Columnas, tipos, defaults, PK y FK de D-07 aplican sobre base vacía, incluida la identidad `bigint` y usuarios históricos obligatorios. | TP-09, TP-11 |
| T-09 | 20 | Añadir UNIQUE, CHECK, índices y `ON DELETE`. | T-08 | Cantidad entera positiva, restricciones e índices coinciden con D-07/D-08; las referencias históricas usan `ON DELETE RESTRICT`. | TP-10, TP-11 |
| T-10 | 15 | Configurar privilegios y RLS anónimos mínimos. | T-08 | Lectura pública limitada; escrituras y tablas privadas bloqueadas. | TP-14, TP-17 |
| T-11 | 15 | Crear y ejecutar el seed idempotente. | T-06, T-09, T-10 | Conteos esperados sin duplicados ni usuarios o filas transaccionales tras dos ejecuciones. | TP-12, TP-13 |
| T-12 | 15 | Configurar variables y cliente Supabase en React. | T-03, T-07, T-10 | Cliente público consulta datos permitidos sin secretos. | TP-14, TP-19 |
| T-13 | 15 | Implementar la página técnica mínima y sus estados. | T-04, T-11, T-12 | Carga, éxito, vacío, configuración ausente y error son visibles. | TP-05, TP-15, TP-16 |
| T-14 | 15 | Configurar y desplegar Cloudflare Pages. | T-01, T-13 | Build `dist` publicado desde `mikuyapp`; URL registrada. | TP-18, TP-19 |
| T-15 | 15 | Ejecutar pruebas técnicas y validación humana; registrar defectos. | T-14 | Evidencias de TP-01–TP-20 y decisión humana pendiente/registrada. | TP-01–TP-20 |

## Orden de ejecución

T-01–T-06 cubren el día 1; T-07–T-15 cubren el día 2. Si una dependencia externa consume el límite, se registra el desvío y no se recorta seguridad, integridad ni pruebas obligatorias para declarar H1 terminado.
