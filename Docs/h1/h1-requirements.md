# MikuyApp — Hito H1: Requerimientos

## 1. Objetivo y límite

H1 comprende los días 1 y 2 del plan, con un máximo planificado de cuatro horas. Su objetivo es establecer la base técnica mínima del MVP para un solo local: producto `mikuyapp` en el repositorio GitHub oficial `fcamasca/mikuyapp-restaurant-ops`, aplicación React + TypeScript + Tailwind construida con Vite, base PostgreSQL en Supabase y despliegue en Cloudflare Pages.

## 2. Resultado verificable

H1 produce una aplicación que carga localmente y desde una URL pública, comunica el estado de conexión y consulta datos demo desde Supabase. El esquema, seed y protección anónima son reproducibles y verificables. La aprobación del spec y la finalización de H1 requieren confirmación humana separada.

## 3. Requerimientos funcionales

- **RF-01 — Página técnica:** mostrar una página mínima que confirme que la aplicación cargó.
- **RF-02 — Consulta demo:** consultar y mostrar mesas, categorías y productos activos desde Supabase.
- **RF-03 — Estados comprensibles:** distinguir carga, conexión exitosa, resultado vacío, configuración ausente y error de conexión sin revelar credenciales.
- **RF-04 — Reglas documentadas:** registrar los cuatro roles, los estados de mesa, los ocho estados de pedido y el flujo operativo principal.
- **RF-05 — Datos reproducibles:** sembrar de forma idempotente cuatro roles, un local, seis mesas, cinco categorías y al menos diez productos demo.
- **RF-06 — Acceso público mínimo:** permitir con la clave pública únicamente las lecturas necesarias para RF-02 y rechazar `INSERT`, `UPDATE` y `DELETE` anónimos.

## 4. Requerimientos técnicos

- **RT-01:** crear o inicializar el repositorio GitHub oficial `fcamasca/mikuyapp-restaurant-ops` para el producto `mikuyapp`, con Git, rama principal y configuración mínima documentada.
- **RT-02:** usar Vite, React y TypeScript; usar Tailwind CSS sin router ni estado global en H1.
- **RT-03:** usar npm, Node.js 22 LTS compatible con Vite (`>=22.12.0`) y conservar `package-lock.json`.
- **RT-04:** separar páginas, componentes, servicios, tipos y datos de prueba.
- **RT-05:** configurar Supabase mediante variables de entorno públicas; prohibir `service_role` y cualquier secreto en cliente, repositorio o logs.
- **RT-06:** mantener migraciones SQL versionadas y un seed idempotente.
- **RT-07:** desplegar el artefacto `dist` en Cloudflare Pages mediante `npm run build`.
- **RT-08:** registrar como evidencia de ejecución el nombre y la región elegidos al crear Supabase; no son decisiones de arquitectura.

## 5. Roles, estados y flujo

| Rol | Código | Responsabilidad futura |
|---|---|---|
| Administrador | `ADMINISTRADOR` | Configuración y consultas globales |
| Mozo | `MOZO` | Mesas, registro y entrega de pedidos |
| Cocina | `COCINA` | Recepción y preparación |
| Caja | `CAJA` | Cobro y cierre |

Estados de mesa: `LIBRE`, `OCUPADA`, `PEDIDO_LISTO`, `PENDIENTE_PAGO`.

Estados de pedido: `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO`, `ENTREGADO`, `PAGADO`, `ANULADO`.

Flujo documentado para hitos posteriores: el mozo abre mesa y pedido, agrega productos y observaciones y lo envía; cocina lo recibe, prepara y marca listo; el mozo lo entrega; caja registra el pago; el pedido queda pagado y la mesa vuelve a libre.

## 6. Integridad obligatoria

- Mantener las diez tablas del plan: `local`, `rol`, `perfil_usuario`, `mesa`, `categoria`, `producto`, `pedido`, `detalle_pedido`, `historial_estado` y `pago`.
- Toda tabla tiene PK; toda relación declarada tiene FK y comportamiento `ON DELETE` explícito.
- **RI-01 — Cantidad entera:** `detalle_pedido.cantidad` es un entero mayor que cero; el MVP no admite cantidades fraccionarias.
- **RI-02 — Trazabilidad histórica:** `perfil_usuario.id` se relaciona con `auth.users.id` mediante `ON DELETE RESTRICT`. `pedido.creado_por`, `historial_estado.usuario_id` y `pago.usuario_id` son obligatorios y usan `ON DELETE RESTRICT`.
- Los usuarios con actividad histórica se desactivan mediante `perfil_usuario.activo = false`; no se eliminan físicamente.
- H1 no crea usuarios Auth ni datos de `pedido`, `detalle_pedido`, `historial_estado` o `pago`.
- Los códigos de rol y los estados solo aceptan los valores aprobados.
- Cantidades de detalle enteras mayores que cero; precios no negativos; importes de pago mayores que cero.
- Códigos de local, mesa, categoría y producto no vacíos y únicos en su ámbito.
- `pedido.id` es un número secuencial `bigint` apto para identificar el pedido en la futura precuenta y ticket.
- `detalle_pedido.precio_unitario` conserva el precio aplicado a la venta.
- Un pedido admite como máximo un pago.
- El diseño completo de columnas, nulabilidad, defaults, claves, checks e índices se especifica en `design.md`.

## 7. Datos demo

El seed incluye los cuatro roles; local `MIKUY-DEMO`; mesas `M01`–`M06` inicialmente `LIBRE`; categorías ceviches, chicharrones, arroces, combos y bebidas; y al menos dos productos por categoría. Los precios demo son no negativos. El catálogo y precios reales no bloquean H1.

## 8. Seguridad mínima

La clave pública puede seleccionar únicamente filas activas de `local`, `mesa`, `categoria` y `producto`, que son las tablas necesarias para la página técnica. No obtiene acceso público a perfiles ni tablas transaccionales. RLS y privilegios PostgreSQL impiden escrituras anónimas. Autenticación, usuarios de prueba y políticas completas por rol pertenecen a H2.

## 9. Alcance y exclusiones

Incluye inicialización del repositorio, frontend mínimo, esquema completo inicial, seed demo, seguridad pública mínima, conexión de lectura, página técnica, pruebas y despliegue. Excluye autenticación funcional, autorización por rol, Realtime, mutaciones de pedidos, pantallas operativas, funciones transaccionales, caja, impresión, reportes, PWA y funciones de hitos posteriores.

## 10. Decisiones cerradas y parámetros de ejecución

- Producto: `mikuyapp`.
- Proyecto Cloudflare Pages: `mikuyapp`.
- Repositorio GitHub oficial: `fcamasca/mikuyapp-restaurant-ops`.
- Spec: `Docs/h1/`.
- Datos: demo reproducibles.
- Stack y hosting: los aprobados en el plan.
- Nombre y región de Supabase: parámetros disponibles al ejecutar; se registra la selección.
- Presupuesto temporal: cuatro horas para días 1 y 2.

## 11. Trazabilidad funcional

| Requisito | Diseño | Tareas | Pruebas |
|---|---|---|---|
| RF-01 | D-04, D-11 | T-13, T-14 | TP-05, TP-18, TP-20 |
| RF-02 | D-04, D-09, D-10 | T-11, T-12, T-13 | TP-12, TP-14, TP-15, TP-18, TP-20 |
| RF-03 | D-04, D-05 | T-13 | TP-15, TP-16, TP-20 |
| RF-04 | D-06, D-07 | T-05, T-08, T-09 | TP-06, TP-10 |
| RF-05 | D-10 | T-06, T-11 | TP-12, TP-13 |
| RF-06 | D-09 | T-10, T-12 | TP-14, TP-17, TP-19 |
| RI-01 | D-07 | T-08, T-09 | TP-10, TP-11 |
| RI-02 | D-07, D-10, D-12 | T-06, T-08, T-09, T-11 | TP-11, TP-12 |

## 12. Asuntos bloqueantes

No quedan decisiones de arquitectura bloqueantes para construir H1. La ejecución sí requiere autorización humana del spec y acceso autorizado a GitHub, Supabase y Cloudflare.
