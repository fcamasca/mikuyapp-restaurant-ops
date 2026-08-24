# MikuyApp

[![CI](https://github.com/fcamasca/mikuyapp-restaurant-ops/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/fcamasca/mikuyapp-restaurant-ops/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/fcamasca/mikuyapp-restaurant-ops)](LICENSE)
[![Node.js 22](https://img.shields.io/badge/node.js-22-339933)](.nvmrc)

Sistema web de operaciones para restaurantes orientado al flujo **mesa → pedido → cocina → entrega → pago**.

**Estado actual:** Hito H1 aceptado, cerrado y desplegado en producción.

**Producción:** <https://mikuyapp.pages.dev/>

## Problema y objetivo

La operación de un restaurante requiere coordinar a mozos, cocina y caja. Cuando esa coordinación depende principalmente de comunicación verbal, aumenta el riesgo de pedidos incompletos, estados poco claros y errores al cobrar.

MikuyApp busca centralizar mesas, carta, pedidos, estados operativos y pagos para reducir esos problemas. El alcance inicial está diseñado para un solo local.

H1 establece únicamente la base técnica verificable del producto. El flujo operativo completo todavía no está implementado.

## Estado del proyecto

| Hito | Resultado | Estado |
|---|---|---|
| H1 | Base técnica, Supabase y despliegue | Aceptado |
| H2 | Usuarios, carta y mesas | No iniciado |
| H3 | Flujo del mozo | Pendiente |
| H4 | Cocina en tiempo real | Pendiente |
| H5 | Caja e impresión | Pendiente |
| H6 | MVP liberado | Pendiente |

## Demo H1

La aplicación desplegada en producción permite comprobar:

- URL productiva: <https://mikuyapp.pages.dev/>;
- local demo `MIKUY-DEMO`;
- 6 mesas activas;
- 5 categorías activas;
- 10 productos activos;
- conexión real de lectura con Supabase;
- presentación responsive validada en vista amplia y en `390 × 844`.

El visitante puede verificar que React cargó, que Supabase está conectado y que los datos demo se consultan correctamente. Todavía no puede iniciar sesión, crear pedidos, enviar comandas a cocina ni registrar pagos.

## Arquitectura

```mermaid
flowchart TB
    U[Usuario] --> C[Cloudflare Pages]
    C --> F[React y Vite en el navegador]
    F --> A[Supabase Data API]
    A --> P[PostgreSQL con constraints y RLS]
```

- Cloudflare Pages sirve un frontend estático.
- El navegador consulta Supabase mediante una clave publicable apta para frontend.
- PostgreSQL es la fuente de verdad del modelo y los datos demo.
- RLS y los permisos PostgreSQL protegen el acceso en la base de datos.
- H1 no incorpora un backend personalizado.

## Stack técnico

| Componente | Tecnología | Responsabilidad |
|---|---|---|
| Interfaz | React `19.2.8` | Renderizado y estados de la página técnica |
| Lenguaje | TypeScript `7.0.2` | Tipado estático del frontend y servicios |
| Desarrollo y build | Vite `8.2.2` | Servidor local y generación de `dist` |
| Estilos | Tailwind CSS `4.3.3` | Utilidades visuales y diseño responsive |
| Cliente de datos | `@supabase/supabase-js` `2.112.3` | Consultas públicas a Supabase Data API |
| Base de datos | PostgreSQL administrado por Supabase | Persistencia, constraints, permisos y RLS |
| Herramientas Supabase | Supabase CLI `2.115.0` | Migraciones, lint y verificaciones SQL |
| Runtime | Node.js `22.12.0` | Ejecución de herramientas y scripts |
| Paquetes | npm `10.9.0` | Instalación reproducible mediante lockfile |
| Hosting | Cloudflare Pages | Publicación del frontend estático |

## Alcance implementado en H1

- Proyecto Vite con React y TypeScript.
- Tailwind CSS con comportamiento responsive.
- Cliente Supabase tipado y limitado a lectura pública.
- Página técnica con estados `loading`, `success`, `empty`, `configuration-error` y `connection-error`.
- Esquema PostgreSQL inicial.
- Seed demo idempotente.
- Permisos PostgreSQL y RLS para el acceso anónimo mínimo.
- Pruebas SQL de esquema, restricciones y seed.
- Pruebas automatizadas de lectura y rechazo de escrituras anónimas.
- Producción publicada en Cloudflare Pages.

### Fuera del alcance actual

- Autenticación.
- Usuarios funcionales.
- Registro y gestión operativa de pedidos.
- Flujo de cocina.
- Caja y pagos.
- Impresión.
- Realtime.
- Reportes.

## Modelo de datos

Las diez tablas se agrupan por responsabilidad:

- **Configuración y catálogo:** `local`, `rol`, `mesa`, `categoria`, `producto`.
- **Identidad:** `perfil_usuario`.
- **Operación futura:** `pedido`, `detalle_pedido`, `historial_estado`, `pago`.

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
| Usuarios, perfiles y filas transaccionales | 0 |

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
- TP-14 validó las lecturas públicas permitidas.
- TP-17 validó el rechazo de escrituras anónimas.
- TP-19 confirmó la ausencia de secretos privados.
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
| `npm run verify:anon` | Validar lecturas permitidas y escrituras anónimas rechazadas |

## Estructura del repositorio

```text
docs/                  Documentación vigente y transversal
specs/
  H1-TechnicalBasis/   Spec, ejecución y aceptación de H1
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

H1 cerró con TP-01–TP-20 aprobadas. La evidencia reproducible está en [execution.md](specs/H1-TechnicalBasis/execution.md) y la decisión humana en [acceptance.md](specs/H1-TechnicalBasis/acceptance.md).

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

## Siguiente etapa

H2 contempla autenticación, usuarios, carta y mesas. Todavía no ha sido iniciado.

## Licencia

MikuyApp se distribuye bajo la [MIT License](LICENSE).
