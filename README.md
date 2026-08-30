# MikuyApp

[![CI](https://github.com/fcamasca/mikuyapp-restaurant-ops/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/fcamasca/mikuyapp-restaurant-ops/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/fcamasca/mikuyapp-restaurant-ops)](LICENSE)
[![Node.js 22](https://img.shields.io/badge/node.js-22-339933)](.nvmrc)

Sistema web de operaciones para restaurantes orientado al flujo **mesa → pedido → cocina → entrega → pago**.

**Estado actual:** H1, H2, H3 y H4 están cerrados, validados y aceptados. H5 — Caja e impresión es el siguiente hito y todavía no ha iniciado.

**Producción:** <https://mikuyapp.pages.dev/>

## Problema y objetivo

La operación de un restaurante requiere coordinar a mozos, cocina y caja. Cuando esa coordinación depende principalmente de comunicación verbal, aumenta el riesgo de pedidos incompletos, estados poco claros y errores al cobrar.

MikuyApp busca centralizar mesas, carta, pedidos, estados operativos y pagos para reducir esos problemas. El alcance inicial está diseñado para un solo local.

H1 establece la base técnica verificable, H2 incorpora autenticación, roles, carta y mesas, H3 completa el flujo operativo del mozo y H4 incorpora la operación de cocina y su sincronización Realtime.

## Estado del proyecto

| Hito | Resultado | Estado |
|---|---|---|
| H1 | Base técnica, Supabase y despliegue | Cerrado, validado y aceptado |
| H2 | Usuarios, carta y mesas | Cerrado, validado y aceptado |
| H3 | Flujo del mozo | Cerrado, validado y aceptado |
| H4 | Cocina en tiempo real | Cerrado, validado y aceptado |
| H5 | Caja e impresión | Siguiente hito; no iniciado |
| H6 | MVP liberado | Pendiente |

El plan base fue de **24 h**. La referencia de planificación vigente es **32.5 h**; las causas y el detalle se mantienen en [CHANGELOG_SCOPE](docs/CHANGELOG_SCOPE.md). Estas cifras no representan tiempo real consumido.

## Funcionalidades disponibles

La aplicación permite comprobar:

- URL productiva: <https://mikuyapp.pages.dev/>;
- local demo `MIKUY-DEMO`;
- autenticación, restauración de sesión y cierre de sesión;
- contexto propio de perfil, rol y local;
- rutas protegidas y destinos por rol;
- carta operativa agrupada por categorías activas;
- tablero de mesas activas para el mozo con los cuatro estados operativos;
- creación o recuperación segura de un único pedido vigente por mesa;
- carta táctil, cantidades, observaciones y retiro de detalles todavía abiertos;
- consolidación de detalles `ABIERTO` equivalentes por producto y observación;
- revisión del consumo y envío selectivo de nuevos detalles a cocina;
- recuperación del pedido persistido ante recargas, errores y concurrencia;
- liberación de una mesa ocupada cuando su pedido `ABIERTO` está vacío, conservando el pedido anulado y su historial;
- tablero de cocina agrupado por pedido y mesa, priorizado por antigüedad y trabajo pendiente;
- transición individual `ENVIADO → RECIBIDO_COCINA → EN_PREPARACION → LISTO`;
- actualización de cocina y mozo mediante señales Realtime y recarga autoritativa desde PostgreSQL;
- estados mixtos, agregados posteriores y derivación transaccional de la cabecera y la mesa;
- administración completa de categorías, productos y mesas;
- identidad autenticada compacta y página técnica disponible para los cuatro roles;
- presentación responsive validada en celular, tablet y escritorio.

Todavía no están implementados entrega, caja, cobro, impresión ni liberación automática posterior al pago. Esas capacidades corresponden a H5 y etapas posteriores.

## Roles y rutas

| Rol | Destino después del login | Accesos actuales |
|---|---|---|
| `ADMINISTRADOR` | `/admin/catalogo` | Administración de categorías, productos y mesas; acceso a `/tecnica` |
| `MOZO` | `/mozo/mesas` | Tablero, pedidos en `/mozo/pedidos/:id`, carta operativa y acceso a `/tecnica` |
| `COCINA` | `/cocina` | Tablero Realtime de cocina y acceso a `/tecnica` |
| `CAJA` | `/tecnica` | Página técnica autenticada |

Las rutas protegidas requieren sesión y contexto válidos. Un acceso de rol no autorizado se dirige a `/403`; una sesión ausente se dirige a `/login`.

## Arquitectura

```mermaid
flowchart TB
    U[Usuario] --> C[Cloudflare Pages]
    C --> F[React y Vite en el navegador]
    F --> A[Supabase Data API y RPC]
    F <--> R[Supabase Realtime]
    A --> P[PostgreSQL con constraints y RLS]
```

- Cloudflare Pages sirve un frontend estático.
- El navegador consulta Supabase mediante una clave publicable apta para frontend.
- PostgreSQL es la fuente de verdad del modelo y los datos demo.
- RLS y los permisos PostgreSQL protegen el acceso en la base de datos.
- No existe un servidor de aplicación personalizado; las reglas transaccionales se ejecutan mediante funciones PostgreSQL en Supabase.
- Realtime actúa como señal: ante un cambio, la interfaz vuelve a consultar el snapshot persistido en lugar de aplicar ciegamente el payload.

## Stack técnico

| Componente | Tecnología | Responsabilidad |
|---|---|---|
| Interfaz | React `19.2.8` | Pantallas operativas y estados de interfaz |
| Lenguaje | TypeScript `7.0.2` | Tipado estático del frontend y servicios |
| Desarrollo y build | Vite `8.2.2` | Servidor local y generación de `dist` |
| Estilos | Tailwind CSS `4.3.3` | Utilidades visuales y diseño responsive |
| Cliente de datos | `@supabase/supabase-js` `2.112.3` | Sesión, consultas autorizadas, RPC y Realtime |
| Base de datos | PostgreSQL administrado por Supabase | Persistencia, constraints, permisos y RLS |
| Herramientas Supabase | Supabase CLI `2.115.0` | Migraciones, lint y verificaciones SQL |
| Runtime | Node.js `22.12.0` | Ejecución de herramientas y scripts |
| Paquetes | npm `10.9.0` | Instalación reproducible mediante lockfile |
| Hosting | Cloudflare Pages | Publicación del frontend estático |

## Alcance implementado en H1–H4

- Proyecto Vite con React y TypeScript.
- Tailwind CSS con comportamiento responsive.
- Cliente Supabase tipado con lecturas públicas H1 y acceso autenticado protegido.
- Login, logout, persistencia de sesión y contexto de autorización.
- Rutas y guardas por rol.
- Página técnica autenticada.
- Esquema PostgreSQL inicial.
- Seed demo idempotente.
- Permisos PostgreSQL y RLS para el acceso anónimo mínimo.
- Privilegios por columna y políticas RLS para usuarios autenticados.
- Carta agrupada y tablero de mesas del mozo.
- CRUD administrativo de categorías, productos y mesas.
- Pedidos persistidos con un único pedido vigente por mesa.
- Precio y estado inicial de detalles controlados por PostgreSQL.
- Edición y retiro permitidos únicamente para detalles `ABIERTO`.
- Envío transaccional `ABIERTO → ENVIADO` por detalle y agregados posteriores selectivos.
- Recuperación, idempotencia, concurrencia y liberación segura de pedidos vacíos.
- Timestamp individual e inmutable de envío por detalle.
- Snapshot seguro y transiciones adyacentes para el rol `COCINA`.
- Derivación transaccional de estados de pedido y mesa.
- Tablero de cocina y resincronización Realtime para cocina y mozo.
- Pruebas SQL de esquema, restricciones y seed.
- 261 pruebas automatizadas en la consolidación integral de H4, además de verificaciones técnicas y humanas.
- H1, H2, H3 y H4 aceptados e integrados en `main`.

### Fuera del alcance implementado

- Caja y pagos.
- Impresión.
- Entrega.
- Reportes.

## Modelo de datos

Las diez tablas se agrupan por responsabilidad:

- **Configuración y catálogo:** `local`, `rol`, `mesa`, `categoria`, `producto`.
- **Identidad:** `perfil_usuario`.
- **Operación de pedidos:** `pedido`, `detalle_pedido`, `historial_estado`.
- **Operación futura de caja:** `pago`.

Métricas verificadas en H1:

| Elemento | Cantidad |
|---|---:|
| Tablas | 10 |
| Columnas | 62 |
| PK | 10 |
| FK | 16 |
| UNIQUE | 9 |
| CHECK | 23 |
| Índices adicionales | 12 |
| Columnas identity | 5 |

La definición completa se encuentra en el [diseño técnico de H1](specs/H1-TechnicalBasis/design.md).

## Datos demo

| Recurso | Cantidad |
|---|---:|
| Roles | 4 |
| Locales | 1 |
| Mesas | 6 |
| Categorías | 5 |
| Productos | 10 |
| Cuentas Auth y perfiles H2 | 4 |
| Filas transaccionales permanentes | 0 |

El seed usa códigos naturales, es idempotente y conservó los mismos 26 identificadores en ejecuciones repetidas.

## Seguridad

| Recurso | SELECT anon | Escritura anon |
|---|---|---|
| `local`, `mesa`, `categoria` y `producto` activos | Sí | No |
| `rol`, `perfil_usuario` y tablas transaccionales | No | No |
| Secuencias | No | No |

- La Publishable key es pública y apta para su uso en el frontend.
- La clave `service_role` está prohibida en el cliente, Git, bundle y logs.
- `.env.local` está ignorado y no se versiona.
- `authenticated` obtiene únicamente los privilegios por tabla y columna necesarios.
- RLS restringe perfil, rol, local y catálogos según usuario, rol, local y estado activo.
- Las tablas transaccionales aplican privilegios mínimos, RLS y operaciones de dominio para el rol `MOZO`.
- El cliente no decide `precio_unitario` ni `detalle_pedido.estado`; PostgreSQL conserva la autoridad.
- Las operaciones críticas de creación, alta/consolidación, envío y liberación de mesa son transaccionales e idempotentes según corresponda.
- Las pruebas reales confirmaron aislamiento, rechazo de elevación y ausencia de cambios parciales.
- La auditoría final confirmó que no existen credenciales, tokens ni UUID Auth en Git, `dist` o logs.
- Ningún secreto privado debe llegar a Git, al bundle compilado ni a los logs.

## Inicio rápido

```bash
git clone https://github.com/fcamasca/mikuyapp-restaurant-ops.git
cd mikuyapp-restaurant-ops
npm ci
```

Crear el archivo local de entorno a partir de `.env.example`:

```bash
cp .env.example .env.local
```

En Windows PowerShell puede usarse:

```powershell
Copy-Item .env.example .env.local
```

Completar únicamente las variables públicas:

```dotenv
VITE_SUPABASE_URL=
VITE_SUPABASE_PUBLISHABLE_KEY=
```

Iniciar la aplicación:

```bash
npm run dev
```

## Comandos principales

| Comando | Propósito |
|---|---|
| `npm run dev` | Iniciar Vite en desarrollo |
| `npm run typecheck` | Validar TypeScript sin emitir archivos |
| `npm run build` | Generar el artefacto `dist` |
| `npm run test:auth` | Probar sesión, login y logout |
| `npm run test:profile` | Probar perfil, rol y local |
| `npm run test:routes` | Probar rutas y guardas |
| `npm run test:catalog` | Probar consultas administrativas y operativas |
| `npm run test:categories` | Probar administración de categorías |
| `npm run test:products` | Probar administración de productos |
| `npm run test:tables` | Probar administración de mesas |
| `npm run test:security` | Probar columnas protegidas e integridad |
| `npm run test:waiter` | Probar tablero, pedidos, mutaciones y envío del flujo del mozo |
| `npm run test:responsive` | Probar contratos responsive y estados de interfaz |
| `npm run test:technical` | Probar la página técnica autenticada |
| `npm run verify:anon` | Validar lecturas permitidas y escrituras anónimas rechazadas |
| `npm run verify:h2-authenticated` | Ejecutar comprobaciones autenticadas reales cuando existan variables locales seguras y fixtures requeridos |
| `npm run preview` | Servir localmente el build generado |

Las suites de cocina y Realtime existen como archivos de Node Test y se ejecutan focalizadamente con comandos reales como:

```bash
node --experimental-strip-types --test tests/kitchenBoard.test.mjs
node --experimental-strip-types --test tests/kitchenRealtimeService.test.mjs
node --experimental-strip-types --test tests/waiterRealtime.test.mjs
```

## Despliegue vigente

El frontend de producción está publicado en Cloudflare Pages en <https://mikuyapp.pages.dev/>. Vite genera el artefacto estático en `dist`. El repositorio versiona el workflow de CI que instala dependencias, ejecuta typecheck y genera el build; la configuración operativa del proyecto de Cloudflare Pages no está versionada en este repositorio.

## Estructura del repositorio

```text
docs/                  Documentación vigente y transversal
specs/
  H1-TechnicalBasis/   Spec, ejecución y aceptación de H1
  H2-UsersCatalogTables/ Spec y aceptación de H2
  H3-WaiterFlow/       Spec, evidencia y aceptación de H3
  H4-KitchenRealtime/  Spec, evidencia y aceptación de H4
scripts/               Verificaciones automatizadas
src/
  data/                Códigos y dataset demo
  pages/               Páginas React
  services/            Cliente y consultas Supabase
  types/               Tipos del dominio y servicios
supabase/
  migrations/          Esquema PostgreSQL versionado
  tests/               Pruebas SQL
  config.toml          Configuración local de Supabase CLI
  seed.sql             Datos demo idempotentes
```

Recursos de base de datos:

- [Migraciones](supabase/migrations/)
- [Seed demo](supabase/seed.sql)
- [Pruebas SQL](supabase/tests/)

## Calidad y pruebas

| Verificación | Cobertura |
|---|---|
| `npm ci` | Instalación reproducible desde `package-lock.json` |
| `npm run typecheck` | Validación TypeScript sin emisión |
| `npm run build` | Build de producción y generación de `dist` |
| `npm run verify:anon` | Lecturas públicas permitidas y escrituras anónimas rechazadas |
| Pruebas SQL | Esquema, constraints, índices, seed e idempotencia |
| GitHub Actions | Instalación limpia, typecheck y build en cada cambio relevante |

H1 cerró con TP-01–TP-20 aprobadas. H2 cerró con 212 pruebas automatizadas, verificaciones reales con cuatro roles y TP-01–TP-53 conformes. H3 cerró con **238/238** pruebas integrales. H4 cerró con la suite integral H1–H4 en **261/261**, SQL remoto H4-T01–T05 aprobado, migraciones sincronizadas, fixtures residuales en `0` y H4-TH01–H4-TH06 aprobadas.

## Documentación

- [Plan general del MVP](docs/PLAN_MVP.md)
- [Índice de especificaciones](specs/README.md)
- [Portada de H1](specs/H1-TechnicalBasis/README.md)
- [Requerimientos de H1](specs/H1-TechnicalBasis/requirements.md)
- [Diseño técnico de H1](specs/H1-TechnicalBasis/design.md)
- [Tareas de H1](specs/H1-TechnicalBasis/tasks.md)
- [Plan de pruebas de H1](specs/H1-TechnicalBasis/test-plan.md)
- [Evidencia de ejecución de H1](specs/H1-TechnicalBasis/execution.md)
- [Aceptación de H1](specs/H1-TechnicalBasis/acceptance.md)
- [Spec H2](specs/H2-UsersCatalogTables/h2_requirements.md)
- [Diseño H2](specs/H2-UsersCatalogTables/h2_design.md)
- [Tareas H2](specs/H2-UsersCatalogTables/h2_tasks.md)
- [Plan de pruebas H2](specs/H2-UsersCatalogTables/h2_test-plan.md)
- [Aceptación de H2](specs/H2-UsersCatalogTables/h2_acceptance.md)
- [Requisitos de H3](specs/H3-WaiterFlow/h3_requirements.md)
- [Diseño de H3](specs/H3-WaiterFlow/h3_design.md)
- [Tareas de H3](specs/H3-WaiterFlow/h3_tasks.md)
- [Plan de pruebas de H3](specs/H3-WaiterFlow/h3_test-plan.md)
- [Evidencia integral de H3](specs/H3-WaiterFlow/h3_t10_execution.md)
- [Aceptación de H3](specs/H3-WaiterFlow/acceptance.md)
- [Requisitos de H4](specs/H4-KitchenRealtime/h4_requirements.md)
- [Diseño de H4](specs/H4-KitchenRealtime/h4_design.md)
- [Tareas de H4](specs/H4-KitchenRealtime/h4_tasks.md)
- [Plan de pruebas de H4](specs/H4-KitchenRealtime/h4_test-plan.md)
- [Evidencia técnica de H4](specs/H4-KitchenRealtime/h4_t09_execution.md)
- [Aceptación de H4](specs/H4-KitchenRealtime/acceptance.md)

## Siguiente etapa

H5 — Caja e impresión es el siguiente hito. Todavía no ha iniciado y deberá comenzar en Spec Mode.

## Licencia

MikuyApp se distribuye bajo la [MIT License](LICENSE).


