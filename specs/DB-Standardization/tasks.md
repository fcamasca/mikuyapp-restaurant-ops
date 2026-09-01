# MikuyApp — Estandarización técnica de base de datos: tareas

> Este documento es planificación. Ninguna tarea de construcción ha sido iniciada ni ejecutada.

| ID | Objetivo | Dependencias | Resultado verificable | Pruebas |
|---|---|---|---|---|
| DBSTD-T01 | **Completada en Spec Mode.** Inventariar estándar, matriz, migraciones acumuladas, funciones, triggers, RLS, grants y pruebas H1–H6; fijar alcance y exclusiones. | H1–H6 aceptado | Requisitos/diseño basados en definiciones efectivas; sin cambios de runtime. | Revisión documental |
| DBSTD-T02 | **Completada.** Se creó una migración nueva que redefine las tres RPC H6 para usar `obtener_contexto_autenticado()`, preserva firma, retornos, roles, filtros y orden para contextos válidos, y aplica el rechazo aprobado `42501 / No autorizado` para contextos inválidos. | T01, D01–D02 | No queda resolución directa duplicada de perfil/rol ni retorno silencioso por contexto inválido en esas tres funciones. TP01–TP12 aprobaron en Supabase local. | TP01–TP12 |
| DBSTD-T03 | **Completada.** Se declararon `STABLE` las tres RPC H6 y `obtener_creadores_pedidos_vigentes(bigint[])`, reafirmando owner, seguridad, `search_path` y grants dentro de la migración DBSTD existente. | T02, D03/D08 | Las cuatro funciones tienen `pg_proc.provolatile = 's'`; firmas, retornos, `SECURITY DEFINER`, owner `postgres`, `search_path = pg_catalog`, grants y comportamiento permanecen intactos. TP13–TP15 y regresiones T02 aprobaron en Supabase local. | TP13–TP15 |
| DBSTD-T04 | **Completada.** Se incorporaron en la migración DBSTD existente los 16 `COMMENT ON` aprobados, con el texto exacto y sin comentarios adicionales. | T01, D05–D06, aprobación humana del texto | Los comentarios de catálogo explican snapshots, derivación, contexto y auditoría sin redefinir reglas. TP16–TP17 y las regresiones T02/T03/auditoría aprobaron en Supabase local. | TP16–TP17 |
| DBSTD-T05 | **Completada.** Se verificó que `registrar_auditoria_detalle_pedido()` y `detalle_pedido_registrar_auditoria` permanecen unidos y sin cambios de cuerpo, nombre, eventos, momento, nivel fila ni vínculo; no se realizó separación ni refactor. | T01, D04, semántica `pedido.modificado_*` pendiente | El cuerpo efectivo coincide con la línea base histórica y el trigger conserva `BEFORE INSERT OR UPDATE OR DELETE FOR EACH ROW`. TP18–TP21 aprobaron en Supabase local y `pedido.modificado_*` mantiene exactamente su comportamiento actual. | TP18–TP21 |
| DBSTD-T06 | **Completada.** Se inventarió y consolidó la cobertura SQL existente, ajustando únicamente aserciones faltantes de grants, exclusividad de comentarios, ejecución interna sin JWT e identidad estructural de la función/trigger de auditoría. | T02–T05 | DBSTD-TP01–TP21 tienen cobertura explícita sin suites redundantes; compatibilidad válida, hardening, metadatos, grants, 27 policies/RLS, 16 comentarios y auditoría aprobaron como conjunto dirigido en Supabase local. | TP01–TP21 |
| DBSTD-T07 | **Completada.** Se ejecutó un reset completo de Supabase local, se aplicaron las 28 migraciones en orden hasta DBSTD y se ejecutaron los 43 archivos SQL de `supabase/tests` con sus secuencias concurrentes. | T06 | TP22–TP23 aprobaron: 28/28 migraciones, 25/25 suites autocontenidas, cinco escenarios concurrentes, DBSTD-TP01–TP21 y regresión H1–H6 sin fallos; residuos concurrentes en cero. | TP22–TP23 |
| DBSTD-T08 | **Completada.** Se ejecutaron la regresión automatizada completa, el lint de PostgreSQL contra Supabase local, typecheck y build de producción. | T07 | TP24 aprobó con 297/297 pruebas automatizadas, lint sin errores de esquema, typecheck limpio y build exitoso; las llamadas RPC, contratos y consumidores frontend permanecen sin regresiones. | TP24 |
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
