# MikuyApp — Estandarización técnica de base de datos: diseño

## D01. Estrategia de migración

La construcción futura usará una única migración nueva y transaccional (`begin`/`commit`) posterior a H6. Redefinirá con `create or replace function` las cuatro funciones afectadas y añadirá `COMMENT ON`; no alterará tablas, constraints, índices, RLS ni nombres.

La migración deberá volver a declarar de forma explícita cada contrato completo —firma, `RETURNS TABLE`, lenguaje, `STABLE`, `SECURITY DEFINER` y `SET search_path = pg_catalog`— y reafirmar owner/grants. Al final emitirá `notify pgrst, 'reload schema'` por el cambio de metadatos de funciones.

## D02. Centralización del contexto

En las tres RPC H6 se sustituye el join duplicado sobre `perfil_usuario`/`rol` por el patrón ya usado por las funciones operativas:

```sql
select auth_context.local_id, auth_context.rol_codigo
into v_local_id, v_rol_codigo
from public.obtener_contexto_autenticado() as auth_context;
```

Luego se conserva la autorización existente:

- `obtener_resumen_ventas_hoy`: rol en `('ADMINISTRADOR', 'CAJA')`;
- `exportar_ventas_hoy`: `ADMINISTRADOR`;
- `exportar_productos_local`: `ADMINISTRADOR`.

La comprobación deberá tratar la falta de contexto y `NULL` de forma inequívoca, preferentemente con `v_local_id is null` y `v_rol_codigo is distinct from ...`, y lanzar SQLSTATE `42501` con mensaje público `No autorizado`.

Esto es un **hardening de seguridad intencional**. En las definiciones H6 actuales, una consulta de contexto que no encuentra fila deja variables en `NULL`; ciertas comparaciones posteriores con `NULL` no son verdaderas y algunas RPC pueden terminar devolviendo cero filas sin excepción. La nueva definición elimina ese retorno silencioso: perfil inexistente, perfil inactivo, rol inactivo, local inactivo y contexto autenticado inexistente deben rechazarse explícitamente. Para contextos válidos no se alteran firmas, resultados, filtros, orden ni matriz de roles.

No se elimina la validación de rol de cada RPC: el helper autentica y resuelve contexto, mientras cada operación autoriza su capacidad concreta.

## D03. Volatilidad `STABLE`

Las cuatro funciones son lecturas sin efectos laterales:

| Función | Dependencias variables | Decisión |
|---|---|---|
| `exportar_productos_local()` | sesión autenticada y catálogo del local | `STABLE` |
| `exportar_ventas_hoy()` | sesión, pagos/pedidos/mesas y fecha de la sentencia | `STABLE` |
| `obtener_resumen_ventas_hoy()` | sesión, pagos/pedidos y fecha de la sentencia | `STABLE` |
| `obtener_creadores_pedidos_vigentes(bigint[])` | sesión, pedidos y perfiles | `STABLE` |

`now()` es estable dentro de la transacción/sentencia y es compatible con esta clasificación. `auth.uid()` y el helper común dependen de la sesión, por lo que impiden `IMMUTABLE`, pero no requieren `VOLATILE`. La declaración `STABLE` expresa correctamente que las funciones leen una instantánea y permite optimizaciones lícitas de PostgreSQL.

No se cambia PL/pgSQL a SQL para evitar una refactorización innecesaria de autorización y manejo de errores.

## D04. Trigger de auditoría: decisión de mantener cohesión

La función efectiva, redefinida por `20260827000400_order_detail_sent_at.sql`, posee cinco responsabilidades relacionadas que se ejecutan en un único `BEFORE` row trigger:

1. resuelve el autor desde `auth.uid()` o, para contexto interno sin JWT, desde el creador del pedido;
2. establece y protege `creado_por/creado_en` y actualiza `modificado_por/modificado_en` del detalle;
3. impide cambiar un `enviado_en` ya fijado;
4. permite fijar `enviado_en` solo en `ABIERTO → ENVIADO`;
5. actualiza `pedido.modificado_*` en insert/delete o cambios de cantidad, observación, pedido o producto, excluyendo el cambio aislado de estado.

La decisión para esta intervención es mantener la función y el trigger sin cambios de código ni nombre. Aunque hay más de una responsabilidad conceptual, todas participan en la misma escritura y su orden actual forma parte del comportamiento probado. Separarlas exigiría decidir precedencia de triggers del mismo momento, compartir la identidad resuelta, preservar atomicidad y cerrar antes la semántica pendiente de `pedido.modificado_*`.

La mejora será documental mediante comentarios. Una separación futura solo será admisible con una decisión funcional previa y pruebas de equivalencia para INSERT, UPDATE, DELETE, envío, transición de estado y ejecución interna sin JWT.

## D05. Comportamiento actual de `pedido.modificado_*` (pendiente)

Se documenta, sin aprobarlo como semántica futura:

- al insertar un pedido, `modificado_*` se iguala a `creado_*`;
- insertar o borrar un detalle actualiza `pedido.modificado_*`;
- cambiar cantidad, observación, `pedido_id` o `producto_id` de un detalle lo actualiza;
- una transición aislada de `detalle_pedido.estado`, incluido el envío, actualiza la auditoría del detalle pero no `pedido.modificado_*`;
- otras funciones pueden asignar estos campos explícitamente según sus contratos vigentes.

El comentario de catálogo usará lenguaje descriptivo (“comportamiento actual”) y señalará que la semántica definitiva está pendiente. No se tocará el trigger `pedido_conservar_auditoria_creacion`.

## D06. Comentarios de catálogo

Se priorizan reglas no evidentes:

| Objeto | Contenido que debe explicar |
|---|---|
| `pedido.estado` | estado operativo derivado/sincronizado y estados terminales |
| `pedido.enviado_en` | instante del primer envío de la cabecera, no de cada detalle posterior |
| `pedido.modificado_en`, `pedido.modificado_por` | comportamiento comercial actual y carácter pendiente de su semántica definitiva |
| `detalle_pedido.estado` | ciclo independiente del detalle y su papel en derivar cabecera/mesa |
| `detalle_pedido.precio_unitario` | snapshot del precio aplicado |
| `detalle_pedido.enviado_en` | primer envío individual, inmutable después de fijarse |
| `pago.importe` | snapshot del cobro persistido |
| `obtener_contexto_autenticado()` | fuente autoritativa de usuario/local/rol activos |
| consultas `STABLE` | rol permitido, aislamiento por local y fecha Lima cuando aplique |
| `sincronizar_estado_operativo_pedido()` | regla interna de derivación |
| `registrar_auditoria_detalle_pedido()` | responsabilidades y propagación selectiva al pedido |
| `detalle_pedido_registrar_auditoria` | momento/eventos y función ejecutada |

Antes de escribir cada comentario se verificará la definición efectiva en la secuencia completa de migraciones. Si el texto repite únicamente el nombre, se omitirá. Los comentarios se escribirán en español y no prometerán comportamientos no respaldados por constraints/pruebas.

## D07. Nomenclatura

No existe justificación fuerte para renombrar objetos en esta intervención. Los nombres actuales son comprensibles y forman parte de contratos PostgREST, frontend, pruebas y documentación. Los prefijos `rpc_`, `fn_`, `tgf_`, `trg_` y `pol_` se aplicarán a objetos nuevos y podrán evaluarse en una campaña futura con aliases/transición, inventario de consumidores y coste de compatibilidad.

Ni siquiera el trigger auditado se renombrará: mezclar un ajuste de semántica declarativa con cambios de identidad dificulta el rollback y amplía la regresión.

## D08. Seguridad, RLS e impacto

- `SECURITY DEFINER`, owner `postgres` y `search_path = pg_catalog` permanecen invariantes.
- Todos los objetos de tablas se referencian con `public.*`; el UID con `auth.uid()`.
- Los grants se reafirman tras `create or replace`: sin ejecución para `PUBLIC`/`anon`, con ejecución para `authenticated` en las RPC actuales.
- `obtener_contexto_autenticado()` mantiene su `EXECUTE` para `authenticated` porque lo usan policies y funciones bajo el contrato existente.
- No se alteran las 27 policies inventariadas en `public`, RLS, Realtime ni privilegios de columnas.
- No hay cambio esperado en frontend ni tipos generados porque nombres, argumentos y retornos permanecen iguales.

## D09. Rollback

El rollback será una migración compensatoria explícita, no la edición o eliminación de la migración aplicada. Debe:

1. restaurar las definiciones previas de las tres RPC con resolución directa de perfil/rol si la centralización causa una regresión;
2. restaurar `VOLATILE` en las cuatro funciones (`ALTER FUNCTION ... VOLATILE` o definiciones previas completas);
3. retirar únicamente los comentarios añadidos mediante `COMMENT ON ... IS NULL`, guardando antes cualquier comentario preexistente;
4. reafirmar owner, grants, `SECURITY DEFINER`, `search_path` y recargar el esquema PostgREST.

No requiere rollback de datos ni DDL de tablas porque la intervención no modifica datos ni estructura. La reversión de comentarios y volatilidad es inmediata; la reversión del helper restaura código conocido de H6. Antes del rollback se ejecutarán pruebas dirigidas para confirmar que el problema proviene de esta migración.

## D10. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Confundir el hardening con una regresión de compatibilidad | separar pruebas de contextos válidos —sin cambios— y contextos inválidos —nuevo rechazo `42501 / No autorizado`— |
| Perder grants al redefinir funciones | metadatos y `has_function_privilege` en prueba postmigración |
| Diferencia por `NULL` en comparación de rol | usar validaciones `is null`/`is distinct from` |
| Alterar filas o su orden | comparar resultados antes/después con fixtures H6 |
| Optimización `STABLE` incorrecta | confirmar ausencia de DML y `provolatile = 's'`; mantener `now()` estable |
| Comentario que decide una regla abierta | revisión humana del texto sobre `pedido.modificado_*` |
| Refactor del trigger introduce orden distinto | no dividir ni renombrar en esta intervención |
