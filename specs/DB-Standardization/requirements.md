# MikuyApp — Estandarización técnica de base de datos: requisitos

## 1. Objetivo

Preparar una evolución técnica acotada del esquema `public` para aplicar los ajustes seguros identificados en `docs/DATABASE_COMPLIANCE_MATRIX.md`, preservando íntegramente el MVP H1–H6 aceptado. La futura implementación deberá centralizar la resolución del contexto autenticado en tres RPC de H6, declarar correctamente la volatilidad de cuatro funciones de solo lectura y añadir comentarios de catálogo únicamente donde expliquen reglas no evidentes.

Este Spec define la intervención; no la implementa, no aplica migraciones y no toca Supabase remoto.

## 2. Estado observado

- `public.obtener_contexto_autenticado()` ya es `STABLE`, `SECURITY DEFINER`, usa `search_path = pg_catalog`, valida usuario, perfil, rol y local activos, y devuelve `local_id`, `rol_id` y `rol_codigo`.
- `exportar_productos_local()`, `exportar_ventas_hoy()` y `obtener_resumen_ventas_hoy()` vuelven a resolver perfil y rol directamente y omiten la comprobación de `local.activo` incorporada en el helper común.
- Las tres funciones anteriores y `obtener_creadores_pedidos_vigentes(bigint[])` son de solo lectura, pero actualmente figuran como `VOLATILE` por defecto.
- `registrar_auditoria_detalle_pedido()` es una trigger function `BEFORE INSERT OR UPDATE OR DELETE`, invocada por `detalle_pedido_registrar_auditoria`. Mantiene auditoría del detalle, protege `creado_*`, controla la asignación/inmutabilidad de `enviado_en` y propaga al pedido las modificaciones de contenido.
- Las pruebas SQL existentes cubren seguridad y comportamiento de las exportaciones (`h6_t02_sales_exports.sql`) y la auditoría (`order_audit_trail.sql`), pero no verifican explícitamente `provolatile`, la reutilización del helper ni todos los metadatos/comentarios propuestos.
- El árbol revisado contiene migraciones acumulativas hasta H6, RLS activa, grants mínimos, funciones `SECURITY DEFINER` con `search_path` seguro y pruebas SQL de H1–H6.

## 3. Alcance

### DBSTD-R01 — Migración nueva y única

Todo ajuste futuro de este Spec se realizará mediante una migración nueva, posterior a `20260830000300_h6_sales_exports.sql`. No se editarán migraciones históricas.

### DBSTD-R02 — Contexto autenticado común

Las funciones siguientes deberán obtener `local_id` y `rol_codigo` exclusivamente desde `public.obtener_contexto_autenticado()`:

- `public.exportar_productos_local()`;
- `public.exportar_ventas_hoy()`;
- `public.obtener_resumen_ventas_hoy()`.

Para usuarios con perfil, rol y local válidos se conservarán exactamente las firmas, columnas de retorno, filtros, orden, zona horaria `America/Lima`, roles autorizados y aislamiento por local.

La centralización incluye un **hardening de seguridad intencional** respecto del comportamiento efectivo de las RPC H6. Actualmente, algunas comparaciones con variables `NULL` pueden finalizar sin excepción y devolver cero filas cuando no se obtiene contexto. Después del ajuste, cualquiera de estos casos deberá producir explícitamente SQLSTATE `42501` con mensaje `No autorizado`:

- perfil inexistente;
- perfil inactivo;
- rol inactivo;
- local inactivo;
- contexto autenticado inexistente, incluido `auth.uid()` nulo o sin contexto resoluble.

Este rechazo no se considera una regresión ni una preservación del comportamiento anterior: es el cambio de seguridad aprobado. No deberá existir retorno silencioso de cero filas para esos contextos inválidos.

### DBSTD-R03 — Volatilidad declarada

Se deberán declarar `STABLE`:

- `public.exportar_productos_local()`;
- `public.exportar_ventas_hoy()`;
- `public.obtener_resumen_ventas_hoy()`;
- `public.obtener_creadores_pedidos_vigentes(bigint[])`.

La clasificación se justifica porque solo consultan datos y contexto de sesión y no escriben. No se declararán `IMMUTABLE`. Las funciones transaccionales y trigger functions permanecerán `VOLATILE`.

### DBSTD-R04 — Responsabilidad del trigger de detalle

La intervención deberá mantener una sola trigger function y un solo trigger para el comportamiento actual de `detalle_pedido`. No se separarán responsabilidades en esta migración. Se documentará que la unidad actual preserva el orden atómico de:

1. determinar autor;
2. proteger auditoría de creación;
3. validar `enviado_en`;
4. actualizar auditoría del detalle;
5. propagar al pedido solo cambios de contenido, no meras transiciones de estado.

Una separación futura requerirá primero cerrar la semántica de `pedido.modificado_en/modificado_por`, definir orden de múltiples triggers y demostrar equivalencia mediante pruebas. Esta decisión evita un refactor de riesgo sin beneficio funcional inmediato.

### DBSTD-R05 — Comentarios de catálogo selectivos

Solo se propondrán comentarios para reglas que no se deducen del nombre o del tipo. Como conjunto inicial:

- columnas: `pedido.estado`, `pedido.enviado_en`, `pedido.modificado_en`, `pedido.modificado_por`, `detalle_pedido.estado`, `detalle_pedido.precio_unitario`, `detalle_pedido.enviado_en`, `pago.importe`;
- funciones: `obtener_contexto_autenticado()`, `sincronizar_estado_operativo_pedido()`, `registrar_auditoria_detalle_pedido()` y las cuatro consultas declaradas `STABLE`;
- trigger: `detalle_pedido_registrar_auditoria`.

Los comentarios sobre `pedido.modificado_*` describirán únicamente el comportamiento actual: se inicializan con la creación y cambian por modificaciones de contenido del detalle; las transiciones de estado por sí solas no los actualizan. No fijarán esa semántica como decisión definitiva.

No se comentarán objetos obvios (`id`, `nombre`, PK/FK, índices autoexplicativos) ni se llenará el catálogo de descripciones redundantes.

### DBSTD-R06 — Seguridad y contratos

Se conservarán:

- `SECURITY DEFINER` y propietario `postgres`;
- `SET search_path = pg_catalog`;
- referencias calificadas `public.*`, `auth.uid()` y funciones `pg_catalog.*` cuando corresponda;
- `REVOKE` para `PUBLIC`/`anon` y `EXECUTE` para `authenticated` según el contrato actual;
- RLS, policies y privilegios de tablas/columnas;
- firmas PostgREST y nombres consumidos por frontend/pruebas.

### DBSTD-R07 — Compatibilidad funcional

Para usuarios y roles con contexto válido, los resultados, autorizaciones y errores de H1–H6 deberán permanecer equivalentes. La única diferencia intencional es el nuevo rechazo explícito `42501 / No autorizado` cuando el contexto sea inexistente o inválido. En particular:

- resumen: `ADMINISTRADOR` y `CAJA`;
- exportaciones: solo `ADMINISTRADOR`;
- creadores de pedidos vigentes: solo `MOZO` de su local;
- productos y ventas: cero fuga entre locales;
- ventas: solo pedidos `PAGADO` del día en `America/Lima`;
- auditoría, envío a cocina y propagación hacia `pedido`: sin cambios.
- perfil inexistente/inactivo, rol inactivo, local inactivo o contexto autenticado inexistente: rechazo `42501`, aunque alguna RPC H6 anterior pudiera devolver cero filas por comparación con `NULL`.

## 4. Exclusiones y recomendaciones que no conviene implementar

- No renombrar tablas ni aplicar prefijos físicos `cfg_`, `mae_`, `seg_`, `mov_`, `det_` o `his_`: los nombres actuales son claros y el impacto excede el beneficio.
- No cambiar PK, FK, UNIQUE, CHECK, índices ni secuencias identity: cumplen el estándar y sustentan integridad/rendimiento ya probado.
- No eliminar `producto.local_id` ni `pedido.local_id`: son desnormalizaciones justificadas para aislamiento, FK, RLS e índices.
- No eliminar ni recalcular `detalle_pedido.precio_unitario`, `pago.importe` o `historial_estado.estado_anterior`: son snapshots/trazabilidad intencionales.
- No realizar renombrados masivos `rpc_`, `fn_`, `tgf_`, `trg_` o `pol_`: serían cambios de catálogo de baja prioridad con impacto en frontend, PostgREST, migraciones, pruebas y documentación. El estándar sí aplica a objetos nuevos; los existentes se mantienen salvo una futura justificación específica.
- No dividir `registrar_auditoria_detalle_pedido()` ahora: cambiaría el orden y acoplamiento de invariantes sin una necesidad funcional ni una semántica cerrada para `pedido.modificado_*`.
- No modificar RLS, grants, reglas funcionales, estados, zona horaria ni contratos RPC.
- No crear vistas, procedures, enums, domains, tablas o índices preventivos: no existe necesidad identificada.
- No decidir ni implementar una nueva semántica para `pedido.modificado_en/modificado_por`.

## 5. Impacto y dependencias

- Dependencia directa: `obtener_contexto_autenticado()` y las tablas `perfil_usuario`, `rol`, `local`.
- Consumidores: servicios/frontend que llaman las cuatro RPC por sus nombres actuales; no requieren cambios si se preservan firmas.
- Seguridad: policies RLS también invocan el helper; su contrato y grants no pueden alterarse.
- Auditoría: `detalle_pedido_registrar_auditoria`, `enviar_pedido_cocina()` y operaciones de alta/edición/borrado de detalle dependen del orden actual.
- Pruebas base: todas las SQL de `supabase/tests`, especialmente `h6_t02_sales_exports.sql` y `order_audit_trail.sql`, más la suite automatizada, typecheck y build.

## 6. Pendientes para decisión humana

1. Definir en una evolución separada si `pedido.modificado_*` representa cualquier cambio de la fila o solo cambios de contenido comercial. Este Spec solo registra el comportamiento vigente.
2. Decidir, después del punto anterior, si la trigger function debe dividirse y cuál sería el orden explícito de triggers. Recomendación actual: mantenerla unida.
3. Aprobar el texto exacto y el nivel de detalle de los `COMMENT ON` antes de construir; los comentarios deben describir, no redefinir, reglas.
4. Decidir si una futura campaña de compatibilidad justifica prefijos de nomenclatura. Recomendación actual: no hacerla.

## 7. Criterios de salida de la futura intervención

- Una nueva migración reversible contiene solo los cambios aprobados.
- Las tres RPC reutilizan el helper común y las cuatro consultas figuran como `STABLE`.
- Firmas, owner, seguridad, grants, RLS y resultados permanecen iguales.
- El trigger conserva estructura y comportamiento; solo recibe documentación de catálogo.
- Los comentarios aprobados existen y no contienen decisiones funcionales abiertas.
- Pruebas nuevas y regresiones completas pasan localmente antes de cualquier despliegue remoto.
