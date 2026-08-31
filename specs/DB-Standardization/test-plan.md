# MikuyApp — Estandarización técnica de base de datos: plan de pruebas

## 1. Estrategia

La validación futura se realizará solo en una base local o desechable, aplicando todas las migraciones desde cero. Combina pruebas de catálogo, seguridad, comportamiento y regresión. No se aplicarán migraciones ni consultas de validación a Supabase remoto durante este Spec.

La línea base son `supabase/tests/h6_t02_sales_exports.sql`, `supabase/tests/order_audit_trail.sql` y el resto de `supabase/tests`. Las pruebas nuevas deben ser transaccionales y terminar en `rollback` cuando sea posible.

## 2. Compatibilidad funcional con contexto válido

| ID | Caso | Resultado esperado |
|---|---|---|
| DBSTD-TP01 | Administrador activo consulta `obtener_resumen_ventas_hoy()`. | Mismos totales/medios H6 y solo su local. |
| DBSTD-TP02 | Caja activa consulta resumen. | Autorizada; resultados idénticos al administrador del mismo local. |
| DBSTD-TP03 | Mozo/cocina con perfil, rol y local activos consultan resumen; `anon` lo invoca. | Se conserva la autorización vigente: mozo/cocina rechazados con SQLSTATE `42501`; `anon` carece de `EXECUTE`; ninguna fila expuesta. |
| DBSTD-TP04 | Administrador exporta ventas y productos. | Firmas, columnas, orden y filas coinciden con el contrato H6. |
| DBSTD-TP05 | Caja/mozo/cocina con contexto válido invocan exportaciones; `anon` las invoca. | Se conserva la autorización vigente: roles autenticados no administradores reciben `42501`; `anon` carece de `EXECUTE`; ninguna fuga. |
| DBSTD-TP06 | Dos locales con datos equivalentes. | Cada RPC devuelve únicamente datos del local autenticado. |
| DBSTD-TP07 | Pagos alrededor de medianoche UTC/Lima, de otro día y pedido no `PAGADO`. | Se conserva el filtro por día `America/Lima` y estado `PAGADO`. |

## 3. Hardening de contextos inválidos

Estas pruebas verifican el cambio de seguridad aprobado; no comparan igualdad con el posible retorno silencioso de H6.

| ID | Caso | Resultado esperado |
|---|---|---|
| DBSTD-TP08 | Usuario autenticado sin fila en `perfil_usuario`. | Las tres RPC H6 rechazan con SQLSTATE `42501` y mensaje `No autorizado`; no devuelven cero filas silenciosamente. |
| DBSTD-TP09 | Perfil existente pero inactivo. | Las tres RPC rechazan explícitamente con `42501 / No autorizado`. |
| DBSTD-TP10 | Perfil activo asociado a rol inactivo. | Las tres RPC rechazan explícitamente con `42501 / No autorizado`. |
| DBSTD-TP11 | Perfil y rol activos asociados a local inactivo. | Las tres RPC rechazan explícitamente con `42501 / No autorizado`. |
| DBSTD-TP12 | `auth.uid()` nulo o contexto autenticado inexistente/no resoluble. | Las tres RPC rechazan explícitamente con `42501 / No autorizado`. |

## 4. Metadatos y seguridad

| ID | Caso | Resultado esperado |
|---|---|---|
| DBSTD-TP13 | Consultar `pg_proc` para las cuatro funciones. | `provolatile = 's'`, `prosecdef = true`, owner `postgres`, `proconfig = ARRAY['search_path=pg_catalog']`. |
| DBSTD-TP14 | Consultar privilegios por firma. | `PUBLIC`/`anon` sin `EXECUTE`; `authenticated` conserva `EXECUTE`; no aparecen grants nuevos de tablas/columnas. |
| DBSTD-TP15 | Inspeccionar definiciones con `pg_get_functiondef` y dependencias. | Las tres RPC referencian `public.obtener_contexto_autenticado()` y no contienen resolución duplicada desde `perfil_usuario`/`rol`; referencias sensibles están calificadas. |
| DBSTD-TP16 | Consultar `col_description`, `obj_description` y descripción de funciones. | Solo los objetos aprobados tienen comentarios no vacíos y coherentes. |
| DBSTD-TP17 | Inventariar RLS/policies antes y después. | Se conservan las 27 policies de `public`, con los mismos nombres, expresiones y roles; RLS permanece habilitada. |

## 5. Trigger y auditoría sin cambios

| ID | Caso | Resultado esperado |
|---|---|---|
| DBSTD-TP18 | INSERT de detalle con usuario autenticado y ejecución interna sin JWT soportada por los flujos actuales. | Autor y timestamps se resuelven igual que antes; fallo `42501` si no puede determinarse autor. |
| DBSTD-TP19 | UPDATE de cantidad/observación y DELETE. | Auditoría del detalle cambia y `pedido.modificado_*` se propaga conforme al comportamiento actual. |
| DBSTD-TP20 | Transición aislada de estado y envío `ABIERTO → ENVIADO`. | Auditoría del detalle cambia; `pedido.modificado_en` no cambia solo por estado; `enviado_en` se fija una vez. |
| DBSTD-TP21 | Intentar cambiar `enviado_en` fijado o fijarlo fuera de `ABIERTO → ENVIADO`. | Rechazo con SQLSTATE `22000`; cuerpo/nombre de trigger function y trigger coinciden con la línea base. |

TP18–TP21 deben reutilizar y ampliar `order_audit_trail.sql`; no deben reinterpretar `pedido.modificado_*` como una decisión definitiva.

## 6. Instalación y regresión

| ID | Caso | Resultado esperado |
|---|---|---|
| DBSTD-TP22 | Aplicar migraciones desde una base vacía/local. | Orden completo exitoso, sin editar migraciones históricas. |
| DBSTD-TP23 | Ejecutar todas las pruebas de `supabase/tests`. | Cero regresiones H1–H6 para contextos válidos y aprobación del nuevo rechazo para contextos inválidos; concurrencia, cocina, caja y exportaciones permanecen correctas. |
| DBSTD-TP24 | Ejecutar suite automatizada, lint si existe, typecheck y build. | Consumidores frontend siguen llamando las mismas RPC y todo pasa. |

## 7. Migración y rollback

| ID | Caso | Resultado esperado |
|---|---|---|
| DBSTD-TP25 | Aplicar migración candidata y luego rollback compensatorio en una base local con fixtures. | Se restauran definiciones H6, `VOLATILE`, comentarios previos/nulos, owner y grants; no cambian filas. |
| DBSTD-TP26 | Repetir pruebas dirigidas H6 tras rollback. | Los contextos válidos, exportaciones, creadores y auditoría funcionan como la línea base; se documenta que el rollback también retira el hardening `42501`. |

El rollback no debe usar `DROP ... CASCADE`, editar el historial ni borrar datos. Si existía un comentario previo, debe restaurarse literalmente en lugar de asignar `NULL`.

## 8. Comparaciones antes/después

Capturar en el entorno local antes y después:

- `pg_get_function_identity_arguments`, tipo de retorno y `pg_get_function_result`;
- `provolatile`, `prosecdef`, owner y `proconfig`;
- ACL/`has_function_privilege`;
- inventario y expresiones de policies;
- conteos y filas ordenadas de los tres reportes H6 con fixtures fijos;
- definición de `registrar_auditoria_detalle_pedido()` y vínculo del trigger;
- comentarios existentes y nuevos.

Solo deben diferir el cuerpo de resolución de contexto de las tres RPC —incluido el rechazo explícito de contexto inválido—, `provolatile` de las cuatro funciones y los comentarios aprobados. Las comparaciones de filas antes/después aplican únicamente a fixtures con contexto válido.

## 9. Criterios de aprobación

- TP01–TP26 aprobadas en entorno local/desechable.
- Cero cambios de firma, columnas de retorno, RLS o grants.
- Para contextos válidos, cero cambios de resultados, filtros, orden o autorizaciones.
- Para contextos inválidos, rechazo nuevo y obligatorio `42501 / No autorizado`, sin retorno silencioso de cero filas.
- Cero modificación funcional del trigger y de `pedido.modificado_*`.
- Diff limitado a una migración nueva y pruebas correspondientes.
- Rollback ensayado sin pérdida de datos.
- Revisión humana aprueba comentarios y confirma que los pendientes siguen abiertos.

## 10. Evidencia requerida

- salida de aplicación completa de migraciones;
- resultados de pruebas SQL y suite automatizada;
- consultas de catálogo antes/después;
- diff de migración/pruebas;
- evidencia del rollback local;
- lista explícita de pendientes humanos, sin `acceptance.md`.
