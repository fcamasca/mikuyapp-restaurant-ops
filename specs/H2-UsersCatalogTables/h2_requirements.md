# MikuyApp — Hito H2: Requerimientos

## 1. Objetivo, fuente y límite

H2 comprende los bloques funcionales de los días 3 y 4 del plan oficial `docs/PLAN_MVP.md`, con una estimación revisada de 540 minutos. Su resultado es **acceso por roles y administración completa de categorías, productos y mesas** para el único local existente. Se apoya en la especificación aceptada de `specs/H1-TechnicalBasis/`, la migración `20260823235106_h1_initial_schema.sql`, el seed y el despliegue de H1.

La convención real del repositorio es agrupar cada hito en `specs/`; H2 usa `specs/H2-UsersCatalogTables/`, con documentos identificados mediante el prefijo `h2_`. H2 no implementa pedidos, cocina o caja operativas, pagos, impresión ni funcionalidades de hitos posteriores.

## 2. Resultado verificable

Existen cuatro cuentas de prueba, una por rol. Cada cuenta inicia y cierra sesión, conserva una sesión válida en su dispositivo autorizado y solo accede a rutas y datos permitidos. El administrador consulta registros activos e inactivos y crea, edita, activa, desactiva y elimina categorías, productos y mesas de su local, respetando restricciones e historial. Los demás roles solo consultan la carta operativamente disponible y el mozo solo ve mesas activas. PostgreSQL y RLS rechazan operaciones, columnas protegidas y registros de otro local incluso mediante solicitudes directas a la API.

## 3. Requerimientos funcionales

- **RF-01 — Autenticación:** iniciar y cerrar sesión con Supabase Auth; no ofrecer registro público, recuperación o cambio de contraseña, invitaciones ni administración de usuarios.
- **RF-02 — Sesión:** restaurar la sesión persistida, mostrar carga mientras se valida y consultar exclusivamente el perfil propio, su rol y su local.
- **RF-03 — Denegaciones:** invalidar o cerrar la sesión operativa si no existe perfil, el perfil está inactivo, el rol está inactivo o no pertenece a los cuatro códigos aprobados, el local está inactivo o la sesión es inválida.
- **RF-04 — Navegación:** proteger rutas por autenticación y rol; redirigir ADMINISTRADOR a `/admin/catalogo`, MOZO a `/mozo/mesas`, COCINA y CAJA a `/tecnica`.
- **RF-05 — Carta operativa:** agrupar productos por categoría, orden y local; mostrar nombre y precio. El administrador consulta categorías/productos activos e inactivos. MOZO, COCINA y CAJA solo reciben categorías activas y productos activos pertenecientes a categorías activas.
- **RF-06 — Categorías:** el ADMINISTRADOR crea, edita `codigo`, `nombre` y `orden`, activa, desactiva y elimina categorías del propio local. La eliminación física se rechaza si existe cualquier producto relacionado, incluso inactivo; se recomienda desactivar y nunca se elimina en cascada.
- **RF-07 — Productos:** el ADMINISTRADOR crea, edita `codigo`, `nombre`, `precio` y `categoria_id`, activa, desactiva y elimina productos del propio local. La categoría debe pertenecer al mismo local; la eliminación física se rechaza si existen detalles de pedidos y se recomienda desactivar.
- **RF-08 — Mesas:** el ADMINISTRADOR crea mesas con estado inicial `LIBRE`, edita `codigo` y `nombre`, activa, desactiva y elimina mesas del propio local. Una mesa no `LIBRE` no puede desactivarse; una mesa con pedidos no puede eliminarse; `estado` nunca se edita administrativamente. El mozo solo consulta mesas activas y visualiza `LIBRE`, `OCUPADA`, `PEDIDO_LISTO` y `PENDIENTE_PAGO`.
- **RF-09 — Página técnica:** `/tecnica` pasa de página pública H1 a ruta autenticada para los cuatro roles; muestra aplicación cargada, sesión válida, conexión Supabase, rol validado y configuración/error seguro. No depende de consultas a mesas ni solicita recursos no autorizados para COCINA o CAJA. El acceso anónimo redirige a `/login`; las lecturas anónimas mínimas H1 se conservan únicamente como comprobaciones técnicas de API.
- **RF-10 — Usuarios de prueba:** crear exactamente cuatro cuentas manualmente en Supabase Dashboard; asociar sus UUID con perfiles usando SQL administrativo parametrizado, sin versionar UUID del entorno, correos reales ni contraseñas.
- **RF-11 — Estados y responsive:** distinguir carga, éxito, vacío y error; tratar como carta vacía también las categorías activas sin productos visibles. La interfaz funciona en celular y tablet sin desbordamiento horizontal.
- **RF-12 — Eliminación confirmada:** solicitar confirmación explícita, permitir cancelación, ejecutar `DELETE` real cuando no existan dependencias y traducir conflictos `ON DELETE RESTRICT` a mensajes funcionales que recomienden desactivación.
- **RF-13 — Validaciones:** exigir campos obligatorios, códigos/nombres no vacíos, unicidad de código por local, precio no negativo, orden válido y categoría del mismo local; informar conflictos y conservar datos del formulario.
- **RF-14 — Inmutabilidad e historial:** impedir cambios administrativos de `id`, `local_id`, `creado_en` y `mesa.estado`; la desactivación no elimina filas ni modifica historial, pedidos, detalles o pagos.

## 4. Requerimientos técnicos

- **RT-01:** usar el cliente público Supabase existente y exclusivamente `VITE_SUPABASE_URL` y la clave pública correspondiente; conservar Cloudflare Pages, `npm run build` y salida `dist`.
- **RT-02:** aplicar privilegios PostgreSQL y políticas RLS complementarias por tabla, operación, local y rol; una guarda React no sustituye la autorización en base de datos.
- **RT-03:** conceder a `authenticated` `SELECT`, `DELETE` e `INSERT`/`UPDATE` exclusivamente por columnas administrativas: categoría `INSERT (local_id, codigo, nombre, orden, activo)` y `UPDATE (codigo, nombre, orden, activo)`; producto `INSERT (local_id, categoria_id, codigo, nombre, precio, activo)` y `UPDATE (codigo, nombre, precio, categoria_id, activo)`; mesa `INSERT (local_id, codigo, nombre, activo)` y `UPDATE (codigo, nombre, activo)`. No existe `INSERT` ni `UPDATE` general ni privilegio sobre `id`, `creado_en` o `mesa.estado`; `local_id` solo se acepta en altas del local propio. RLS limita todas las mutaciones al ADMINISTRADOR activo; `PUBLIC` y `anon` no reciben escritura.
- **RT-04:** obtener contexto de autorización mediante una única función auxiliar `SECURITY DEFINER`, con propietario administrativo, `search_path = pg_catalog`, objetos calificados y ejecución restringida a `authenticated`; la política de `perfil_usuario` usa directamente `id = auth.uid()` y nunca se consulta a sí misma.
- **RT-05:** conservar RLS, constraints, claves foráneas, seed idempotente y lecturas anónimas mínimas aprobadas en H1; no conceder acceso a tablas transaccionales ni secuencias.
- **RT-06:** excluir contraseñas, tokens privados, `service_role`, los UUID Auth reales de las cuatro cuentas H2 y sus correos reales de Git, build, frontend y registros; no considerar secretos los UUID estables del seed H1, registros demo o identificadores legítimos versionados.

## 5. Matriz definitiva por recurso y operación

| Recurso | Operación | ADMINISTRADOR | MOZO | COCINA | CAJA | Anónimo |
|---|---|---|---|---|---|---|
| Categorías | Consultar | Activas e inactivas del local | Solo activas | Solo activas | Solo activas | Solo lectura activa H1 |
| Categorías | Crear / editar / eliminar / activar / desactivar | Sí, mismo local e integridad | No | No | No | No |
| Productos | Consultar | Activos e inactivos del local | Solo activos en categoría activa | Solo activos en categoría activa | Solo activos en categoría activa | Solo lectura activa H1 |
| Productos | Crear / editar / eliminar / activar / desactivar | Sí, mismo local e integridad | No | No | No | No |
| Mesas | Consultar | Activas e inactivas del local | Solo activas | No | No | Solo lectura activa H1 |
| Mesas | Crear / editar / eliminar / activar / desactivar | Sí, mismo local y reglas de estado | No | No | No | No |
| Mesas | Cambiar estado operativo | No | No | No | No | No |
| Perfil propio | Consultar | Sí | Sí | Sí | Sí | No |
| `/tecnica` | Acceder con sesión válida | Sí | Sí | Sí | Sí | No; redirige a `/login` |
| Usuarios | Administrar mediante interfaz | No | No | No | No | No |

## 6. Estados de interfaz y errores

El login diferencia credenciales inválidas, acceso denegado y problemas recuperables de conectividad. Una sesión restaurada no muestra datos hasta validar perfil, rol y local. Cada catálogo administrativo presenta carga, vacío, guardado, éxito, error y confirmación/cancelación de eliminación. La carta operativa queda vacía cuando no existen categorías activas con productos activos. El administrador distingue activos e inactivos; otros roles no reciben registros no disponibles. El tablero del mozo omite mesas inactivas. Conflictos de código, dependencias y mesa no libre se comunican sin SQL, tokens, secretos o perfiles ajenos.

## 7. Decisiones cerradas y exclusiones

Son decisiones cerradas: CRUD administrativo completo de categorías, productos y mesas; eliminación real confirmada sin cascada y con `ON DELETE RESTRICT`; desactivación como alternativa ante dependencias; mesas nuevas `LIBRE`, sin edición administrativa de estado y sin desactivar mesas ocupadas; cuatro cuentas Dashboard más asociación SQL administrativa parametrizada; `/tecnica` autenticada; ausencia de interfaz de usuarios; estimación de 540 minutos frente a 240 originalmente planificados.

Quedan fuera pedidos, cambios operativos de estado de mesa, Realtime, cocina operativa, caja, pagos, impresión, ventas, exportaciones, gestión de usuarios, imágenes, inventario, recetas y promociones. No existen propuestas funcionales pendientes en este spec.

## 8. Asuntos bloqueantes

No se identifica un bloqueo funcional pendiente de decisión. La construcción futura requiere autorización humana expresa y acceso administrativo efectivo al proyecto Supabase para crear las cuatro cuentas; esta última condición es una dependencia operativa, no una alternativa técnica pendiente ni una aprobación concedida por este documento.

## 9. Matriz de trazabilidad

| Requisito | Diseño | Tareas | Pruebas |
|---|---|---|---|
| RF-01 | D-01, D-03 | T02, T04 | TP-01, TP-02, TP-03, TP-04 |
| RF-02 | D-01, D-02 | T02, T03 | TP-05, TP-06, TP-07, TP-08 |
| RF-03 | D-02, D-08 | T03, T06, T08 | TP-06, TP-07, TP-08, TP-20, TP-23 |
| RF-04 | D-03, D-04 | T04, T18 | TP-09, TP-10, TP-27 |
| RF-05 | D-05, D-08 | T09, T10, T11, T13 | TP-11, TP-12, TP-13, TP-14, TP-31, TP-37, TP-52 |
| RF-06 | D-05, D-07, D-08 | T07, T08, T10, T14, T15 | TP-31, TP-32, TP-33, TP-34, TP-35, TP-36, TP-49, TP-50 |
| RF-07 | D-05, D-07, D-08 | T07, T08, T11, T14, T15 | TP-15, TP-37, TP-38, TP-39, TP-40, TP-41, TP-42, TP-49, TP-50 |
| RF-08 | D-06, D-07, D-08 | T07, T08, T12, T13, T16 | TP-17, TP-18, TP-19, TP-43, TP-44, TP-45, TP-46, TP-47, TP-48 |
| RF-09 | D-03, D-11 | T04, T18 | TP-09, TP-10, TP-27 |
| RF-10 | D-09 | T05 | TP-25, TP-26 |
| RF-11 | D-07, D-10 | T10, T11, T12, T17, T21 | TP-13, TP-24, TP-29, TP-30, TP-53 |
| RF-12 | D-07, D-08 | T10, T11, T12, T15 | TP-33, TP-34, TP-39, TP-40, TP-45, TP-46, TP-51 |
| RF-13 | D-05, D-06, D-07 | T10, T11, T12, T14 | TP-35, TP-36, TP-41, TP-42, TP-47, TP-49 |
| RF-14 | D-06, D-08 | T07, T08, T16, T19 | TP-16, TP-22, TP-47, TP-48, TP-50 |
| RT-01 | D-01, D-10 | T02, T20 | TP-25, TP-28 |
| RT-02 | D-02, D-08 | T06, T07, T08, T19 | TP-16, TP-19, TP-20, TP-21, TP-22, TP-23, TP-49, TP-50 |
| RT-03 | D-08 | T07, T08, T19 | TP-16, TP-21, TP-22, TP-23, TP-49, TP-50 |
| RT-04 | D-02, D-08 | T03, T06, T08 | TP-06, TP-07, TP-08, TP-20, TP-23 |
| RT-05 | D-08, D-11 | T01, T07, T08, T18 | TP-20, TP-23, TP-27, TP-34, TP-40, TP-46 |
| RT-06 | D-09, D-10 | T05, T20 | TP-25, TP-26, TP-28 |
