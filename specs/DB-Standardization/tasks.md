# MikuyApp — Estandarización técnica de base de datos: tareas

> Este documento es planificación. Ninguna tarea de construcción ha sido iniciada ni ejecutada.

| ID | Objetivo | Dependencias | Resultado verificable | Pruebas |
|---|---|---|---|---|
| DBSTD-T01 | **Completada en Spec Mode.** Inventariar estándar, matriz, migraciones acumuladas, funciones, triggers, RLS, grants y pruebas H1–H6; fijar alcance y exclusiones. | H1–H6 aceptado | Requisitos/diseño basados en definiciones efectivas; sin cambios de runtime. | Revisión documental |
| DBSTD-T02 | **Completada.** Se creó una migración nueva que redefine las tres RPC H6 para usar `obtener_contexto_autenticado()`, preserva firma, retornos, roles, filtros y orden para contextos válidos, y aplica el rechazo aprobado `42501 / No autorizado` para contextos inválidos. | T01, D01–D02 | No queda resolución directa duplicada de perfil/rol ni retorno silencioso por contexto inválido en esas tres funciones. TP01–TP12 aprobaron en Supabase local. | TP01–TP12 |
| DBSTD-T03 | Declarar `STABLE` las tres RPC H6 y `obtener_creadores_pedidos_vigentes(bigint[])`; reafirmar owner, seguridad, `search_path` y grants. | T02, D03/D08 | `pg_proc.provolatile = 's'` y contratos de seguridad intactos para las cuatro funciones. | TP13–TP15 |
| DBSTD-T04 | Incorporar `COMMENT ON` selectivos, revisando el texto exacto y omitiendo comentarios obvios. | T01, D05–D06, aprobación humana del texto | Comentarios de catálogo explican snapshots, derivación, contexto y auditoría sin redefinir reglas. | TP16–TP17 |
| DBSTD-T05 | Mantener sin cambios la función `registrar_auditoria_detalle_pedido()` y el trigger `detalle_pedido_registrar_auditoria`; registrar la decisión de no separación. | T01, D04, semántica `pedido.modificado_*` pendiente | Diff de migración sin cambio de cuerpo ni nombre del trigger; comentario descriptivo permitido. | TP18–TP21 |
| DBSTD-T06 | Añadir/ajustar pruebas SQL de metadatos, contexto centralizado, usuarios/locales inactivos, roles, aislamiento, fecha Lima, comentarios y auditoría. | T02–T05 | Cobertura separa compatibilidad de contextos válidos y hardening de contextos inválidos; falla contra el estado anterior cuando corresponde y pasa con la migración candidata. | TP01–TP21 |
| DBSTD-T07 | Ejecutar reset/migración local desde cero y toda la regresión SQL H1–H6. No usar Supabase remoto. | T06 | Todas las migraciones aplican en orden y todas las pruebas SQL pasan. | TP22–TP23 |
| DBSTD-T08 | Ejecutar suite automatizada, typecheck y build para verificar consumidores frontend. | T07 | Sin regresiones en llamadas RPC, contratos o aplicación. | TP24 |
| DBSTD-T09 | Preparar y ensayar rollback compensatorio en entorno local desechable; verificar restauración de definiciones/metadatos. | T07, D09 | Rollback sin pérdida de datos y estado H6 funcional restaurado. | TP25–TP26 |
| DBSTD-T10 | Revisión final humana del diff y evidencia; autorizar separadamente cualquier aplicación remota. | T07–T09 | Alcance respetado, pendientes abiertos visibles y cero cambios funcionales. | Checklist final |

## Orden de ejecución

1. T02 y T03 forman el núcleo funcional/declarativo de la misma migración.
2. T04 se integra solo después de aprobar el texto de comentarios.
3. T05 es una restricción de implementación: no habilita un refactor.
4. T06 precede cualquier validación integral.
5. T07–T09 se ejecutan únicamente en entorno local/desechable.
6. T10 no implica despliegue. Tocar Supabase remoto requerirá una instrucción y autorización posteriores explícitas.

## Checklist de implementación

- [ ] Elegir timestamp/nombre de migración posterior a H6 sin editar archivos históricos.
- [ ] Copiar firmas y tipos de retorno exactos desde las definiciones efectivas.
- [ ] Usar `public.obtener_contexto_autenticado()` en las tres RPC, sin joins duplicados de autenticación.
- [ ] Conservar SQLSTATE/mensaje `42501`, roles y filtros actuales.
- [ ] Añadir `STABLE`, conservar `SECURITY DEFINER` y `SET search_path = pg_catalog`.
- [ ] Reafirmar owner y grants por firma exacta.
- [ ] Mantener cuerpos/nombres de trigger function y trigger sin cambios.
- [ ] Revisar cada `COMMENT ON` contra el catálogo actual y la decisión humana.
- [ ] Incluir `notify pgrst, 'reload schema'`.
- [ ] Añadir pruebas antes de ejecutar la migración en cualquier entorno compartido.
- [ ] Guardar script/guía de rollback compensatorio y evidencia local.

## Pendientes bloqueantes para tareas futuras

- Aprobación humana del texto de comentarios, especialmente `pedido.modificado_en/modificado_por`.
- Decisión humana separada sobre la semántica definitiva de `pedido.modificado_*`; no bloquea T02–T04 si los comentarios se limitan al comportamiento actual, pero sí bloquea cualquier separación del trigger.
- Una orden explícita futura para iniciar construcción. Este Spec no la concede.

## Trabajo deliberadamente no planificado

No se crean tareas de renombrado masivo, cambio de tablas/constraints/índices, eliminación de snapshots o `local_id`, modificación de RLS, creación de nuevos objetos funcionales ni ampliación del MVP. Son recomendaciones que no conviene implementar en esta intervención por su alto impacto y ausencia de beneficio funcional.
