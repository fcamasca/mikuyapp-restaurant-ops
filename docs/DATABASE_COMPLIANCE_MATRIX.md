# MikuyApp — Matriz de Cumplimiento del Estándar de Base de Datos

**Versión:** 1.0  
**Estado:** Actualizada después de PM-001 / DB Standardization (`ACCEPTED + DEPLOYED`)
**Referencia:** `docs/DATABASE_STANDARD.md`  
**Motor:** PostgreSQL / Supabase  
**Esquema evaluado:** `public`

---

## 1. Objetivo

Comparar los objetos actuales de MikuyApp contra el estándar de base de datos definido para el proyecto y determinar:

- qué objetos ya cumplen;
- qué objetos conviene mantener aunque no sigan el estándar objetivo;
- qué objetos deberían renombrarse o refactorizarse en una evolución;
- qué ajustes son únicamente de documentación;
- qué cambios requieren una decisión funcional previa.

Esta matriz **no autoriza cambios en producción**. Cualquier modificación deberá implementarse mediante una migración nueva y con análisis de impacto.

PM-001 aplicó únicamente los ajustes técnicos aprobados en esta matriz. El modelo físico y las recomendaciones deliberadamente pendientes se conservan.

---

## 2. Estados y acciones

### Cumplimiento

| Estado | Significado |
|---|---|
| ✅ Cumple | El objeto ya respeta el estándar |
| 🟡 Parcial | Cumple funcionalmente, pero existe una mejora de estándar |
| 🟠 Revisar | Requiere análisis o decisión antes de modificar |
| 🔵 Excepción justificada | Se aparta de 3NF o del estándar por una razón válida |
| ❌ No cumple | Conviene corregir cuando se programe la normalización técnica |

### Acción recomendada

| Acción | Significado |
|---|---|
| `MANTENER` | No cambiar |
| `RENOMBRAR` | Ajustar solo nomenclatura |
| `REFACTORIZAR` | Cambiar estructura o responsabilidad |
| `DOCUMENTAR` | Incorporar comentarios o definición |
| `REVISAR` | Resolver primero una decisión funcional/técnica |

---

# 3. Tablas

| Objeto actual | Clasificación | 3NF | Cumplimiento de nombre | Acción | Prioridad | Observación |
|---|---|---:|---|---|---|---|
| `local` | Configuración | ✅ | ✅ | MANTENER | — | Nombre claro y estable |
| `rol` | Seguridad / referencia | ✅ | ✅ | MANTENER | — | Catálogo controlado de roles |
| `perfil_usuario` | Seguridad | ✅ | ✅ | MANTENER | — | Integración correcta con `auth.users` |
| `categoria` | Maestra | ✅ | ✅ | MANTENER | — | Sin redundancias relevantes |
| `producto` | Maestra | 🔵 | ✅ | MANTENER | — | `local_id` es redundante respecto de `categoria_id`, pero refuerza aislamiento por local mediante FK/RLS |
| `mesa` | Maestra operativa | ✅ | ✅ | MANTENER | — | `estado` representa estado operativo actual |
| `pedido` | Movimiento / cabecera | 🔵 | ✅ | MANTENER | — | `local_id` es derivable desde `mesa_id`, pero es útil para aislamiento, RLS e índices |
| `detalle_pedido` | Detalle transaccional | ✅ | ✅ | MANTENER | — | `precio_unitario` es snapshot histórico intencional |
| `historial_estado` | Histórico / auditoría | ✅ | ✅ | MANTENER | — | `estado_anterior` facilita auditoría sin reconstrucción |
| `pago` | Movimiento financiero | ✅ | ✅ | MANTENER | — | `importe` es snapshot del cobro registrado |

## 3.1 Conclusión de normalización

El modelo está **mayoritariamente en 3NF**.

Se identifican como excepciones controladas:

- `producto.local_id`;
- `pedido.local_id`.

Ambas se consideran **desnormalizaciones justificadas** por aislamiento por local, RLS, integridad y consultas.

No deben tratarse como defectos.

También se consideran snapshots válidos y no violaciones de diseño:

- `detalle_pedido.precio_unitario`;
- `pago.importe`;
- `historial_estado.estado_anterior`.

---

# 4. Columnas y auditoría

| Área | Estado | Acción | Prioridad | Observación |
|---|---|---|---|---|
| PK llamadas `id` | ✅ Cumple | MANTENER | — | Consistente |
| FK con sufijo `_id` | ✅ Cumple | MANTENER | — | Consistente |
| Booleanos afirmativos (`activo`) | ✅ Cumple | MANTENER | — | Consistente |
| Timestamps con sufijo `_en` | ✅ Cumple | MANTENER | — | `creado_en`, `modificado_en`, `enviado_en`, `pagado_en` |
| Usuario creador/modificador | ✅ Cumple | MANTENER | — | `creado_por`, `modificado_por` |
| Importes/precios `numeric(10,2)` | ✅ Cumple | MANTENER | — | Apropiado para el MVP |
| `pedido.modificado_en/modificado_por` | 🟠 Revisar | REVISAR | Media | Falta definir si significa última modificación de cualquier campo o solo modificación funcional del contenido |
| Comentarios de catálogo seleccionados | ✅ Cumple | MANTENER | — | PM-001 incorporó los 16 `COMMENT ON` aprobados para reglas no evidentes |

---

# 5. Constraints

El patrón actual ya es consistente con el estándar.

| Tipo | Convención esperada | Estado | Acción |
|---|---|---|---|
| Primary Key | `pk_<tabla>` | ✅ | MANTENER |
| Foreign Key | `fk_<tabla>_<referencia>` | ✅ | MANTENER |
| Unique | `uq_<tabla>_<regla>` | ✅ | MANTENER |
| Check | `ck_<tabla>_<regla>` | ✅ | MANTENER |

### Ejemplos conformes

```text
pk_pedido
fk_pedido_mesa_local
fk_detalle_pedido_producto
uq_pago_pedido_id
ck_pago_importe_positivo
ck_detalle_pedido_envio_coherente
```

No se recomienda renombrar constraints existentes.

---

# 6. Índices

| Objeto / patrón | Estado | Acción | Prioridad | Observación |
|---|---|---|---|---|
| `idx_<tabla>_<columnas/proposito>` | ✅ Cumple | MANTENER | — | Convención uniforme |
| `uq_pedido_mesa_id_vigente` | ✅ Cumple | MANTENER | — | Excelente uso de índice único parcial para regla funcional |
| Índices generados por PK/UQ | ✅ Cumple | MANTENER | — | PostgreSQL los administra adecuadamente |

No se detecta necesidad de renombrar índices.

---

# 7. Funciones y RPC

## 7.1 Operaciones públicas de aplicación

| Objeto actual | Clasificación | Nombre estándar objetivo | Estado | Acción | Prioridad |
|---|---|---|---|---|---|
| `actualizar_estado_detalle_cocina` | RPC | `rpc_actualizar_estado_detalle_cocina` | 🟡 | RENOMBRAR | Baja |
| `agregar_detalle_pedido` | RPC | `rpc_agregar_detalle_pedido` | 🟡 | RENOMBRAR | Baja |
| `crear_o_recuperar_pedido_mesa` | RPC | `rpc_crear_o_recuperar_pedido_mesa` | 🟡 | RENOMBRAR | Baja |
| `entregar_pedido` | RPC | `rpc_entregar_pedido` | 🟡 | RENOMBRAR | Baja |
| `enviar_pedido_cocina` | RPC | `rpc_enviar_pedido_cocina` | 🟡 | RENOMBRAR | Baja |
| `exportar_productos_local` | RPC | `rpc_exportar_productos_local` | 🟡 | RENOMBRAR | Baja |
| `exportar_ventas_hoy` | RPC | `rpc_exportar_ventas_hoy` | 🟡 | RENOMBRAR | Baja |
| `liberar_mesa_pedido_vacio` | RPC | `rpc_liberar_mesa_pedido_vacio` | 🟡 | RENOMBRAR | Baja |
| `obtener_creadores_pedidos_vigentes` | RPC de consulta | `rpc_obtener_creadores_pedidos_vigentes` | 🟡 | RENOMBRAR | Baja |
| `obtener_pedidos_pendientes_pago_caja` | RPC | `rpc_obtener_pedidos_pendientes_pago_caja` | 🟡 | RENOMBRAR | Baja |
| `obtener_resumen_ventas_hoy` | RPC | `rpc_obtener_resumen_ventas_hoy` | 🟡 | RENOMBRAR | Baja |
| `obtener_tablero_cocina` | RPC | `rpc_obtener_tablero_cocina` | 🟡 | RENOMBRAR | Baja |
| `registrar_pago_pedido` | RPC | `rpc_registrar_pago_pedido` | 🟡 | RENOMBRAR | Baja |

### Criterio

Los nombres actuales son claros y funcionalmente correctos.

La recomendación de `rpc_` sirve para distinguir la API de aplicación de las funciones internas.  
**No es prioritario renombrarlas en el MVP ya liberado**, porque el impacto afecta frontend, tests, migraciones y documentación.

---

## 7.2 Funciones internas

| Objeto actual | Responsabilidad | Nombre estándar objetivo | Estado | Acción | Prioridad | Observación |
|---|---|---|---|---|---|---|
| `sincronizar_estado_operativo_pedido` | Regla interna de derivación | `fn_sincronizar_estado_operativo_pedido` | 🟡 | RENOMBRAR | Baja | No tiene `EXECUTE` para `authenticated`; correctamente interna |
| `obtener_contexto_autenticado` | Seguridad/contexto | `fn_obtener_contexto_autenticado` | 🟡 | MANTENER / RENOMBRAR | Baja | Es helper interno, aunque requiere `EXECUTE` de `authenticated` porque las policies RLS la invocan |
| `conservar_auditoria_pedido` | Trigger function | `tgf_pedido_conservar_auditoria` | ❌ | RENOMBRAR | Baja | Su tipo real es función de trigger |
| `registrar_auditoria_detalle_pedido` | Trigger function / invariantes | `tgf_detalle_pedido_auditoria` | 🟠 | REVISAR | Media | Mezcla auditoría, inmutabilidad de `enviado_en` y propagación de modificación al pedido |

---

# 8. Volatilidad de funciones

| Función | Actual | Recomendado | Acción | Prioridad |
|---|---|---|---|---|
| `obtener_contexto_autenticado` | `STABLE` | `STABLE` | MANTENER | — |
| `obtener_pedidos_pendientes_pago_caja` | `STABLE` | `STABLE` | MANTENER | — |
| `obtener_tablero_cocina` | `STABLE` | `STABLE` | MANTENER | — |
| `exportar_productos_local` | `STABLE` | `STABLE` | MANTENER | — |
| `exportar_ventas_hoy` | `STABLE` | `STABLE` | MANTENER | — |
| `obtener_resumen_ventas_hoy` | `STABLE` | `STABLE` | MANTENER | — |
| `obtener_creadores_pedidos_vigentes` | `STABLE` | `STABLE` | MANTENER | — |
| Funciones transaccionales de escritura | `VOLATILE` | `VOLATILE` | MANTENER | — |
| Trigger functions | `VOLATILE` | `VOLATILE` | MANTENER | — |

---

# 9. SECURITY DEFINER

| Regla | Estado | Acción |
|---|---|---|
| Uso de `SECURITY DEFINER` en operaciones sensibles | ✅ | MANTENER |
| `SET search_path TO 'pg_catalog'` | ✅ | MANTENER |
| Referencias calificadas `public.<objeto>` | ✅ | MANTENER |
| Validación de `auth.uid()` | ✅ | MANTENER |
| Validación de local/rol | ✅ | MANTENER |
| Restricción de `EXECUTE` según función | ✅ / 🟡 | REVISAR solo durante futuras evoluciones |

Este patrón debe conservarse como estándar obligatorio.

---

# 10. Duplicación de resolución de contexto

| Función | Estado | Acción | Prioridad | Observación |
|---|---|---|---|---|
| `exportar_productos_local` | ✅ | MANTENER | — | PM-001 reutiliza `obtener_contexto_autenticado()` |
| `exportar_ventas_hoy` | ✅ | MANTENER | — | PM-001 reutiliza `obtener_contexto_autenticado()` |
| `obtener_resumen_ventas_hoy` | ✅ | MANTENER | — | PM-001 reutiliza `obtener_contexto_autenticado()` |
| Resto de funciones operativas | ✅ | MANTENER | — | Reutilizan `obtener_contexto_autenticado()` |

### Estado después de PM-001

La resolución quedó centralizada en una única función autoritativa para:

```text
usuario
local
rol
estado activo
```

Esto evita divergencias futuras. La centralización fue implementada y desplegada para las tres RPC H6, incluido el hardening aprobado `42501 / No autorizado` ante contextos inválidos.

---

# 11. Triggers

| Trigger actual | Función | Nombre estándar objetivo | Estado | Acción | Prioridad |
|---|---|---|---|---|---|
| `detalle_pedido_registrar_auditoria` | `registrar_auditoria_detalle_pedido()` | `trg_detalle_pedido_before_write_auditoria` | 🟡 | RENOMBRAR / REVISAR | Media |
| `pedido_conservar_auditoria_creacion` | `conservar_auditoria_pedido()` | `trg_pedido_before_write_auditoria` | 🟡 | RENOMBRAR | Baja |

### Hallazgo principal

`registrar_auditoria_detalle_pedido()` realiza actualmente varias responsabilidades:

- asigna auditoría;
- protege `creado_por` y `creado_en`;
- actualiza `modificado_por/modificado_en`;
- protege la inmutabilidad de `enviado_en`;
- valida cuándo puede fijarse `enviado_en`;
- propaga modificación hacia `pedido`.

No se recomienda dividirla automáticamente. Primero debe revisarse si estas invariantes deben seguir juntas o separarse.

---

# 12. RLS Policies

El estado efectivo contiene **27 policies** en el esquema `public`.

La seguridad funcional es correcta, pero la nomenclatura mezcla:

- objeto primero / rol primero;
- español / inglés;
- `active` / `activo`;
- condiciones antes o después del rol.

Se recomienda adoptar:

```text
pol_<tabla>_<operacion>_<rol>[_<condicion>]
```

## 12.1 Categoría

| Actual | Objetivo | Acción |
|---|---|---|
| `anon_select_active_categoria` | `pol_categoria_select_anon_activa` | RENOMBRAR |
| `categoria_delete_administrador` | `pol_categoria_delete_administrador` | RENOMBRAR |
| `categoria_insert_administrador` | `pol_categoria_insert_administrador` | RENOMBRAR |
| `categoria_select_local` | `pol_categoria_select_authenticated_local` | RENOMBRAR |
| `categoria_update_administrador` | `pol_categoria_update_administrador` | RENOMBRAR |

## 12.2 Detalle de pedido

| Actual | Objetivo | Acción |
|---|---|---|
| `detalle_pedido_delete_abierto_mozo` | `pol_detalle_pedido_delete_mozo_abierto` | RENOMBRAR |
| `detalle_pedido_select_cocina_local` | `pol_detalle_pedido_select_cocina_local` | RENOMBRAR |
| `detalle_pedido_select_mozo_local` | `pol_detalle_pedido_select_mozo_local` | RENOMBRAR |
| `detalle_pedido_update_abierto_mozo` | `pol_detalle_pedido_update_mozo_abierto` | RENOMBRAR |

## 12.3 Local

| Actual | Objetivo | Acción |
|---|---|---|
| `anon_select_active_local` | `pol_local_select_anon_activo` | RENOMBRAR |
| `local_select_contexto_autenticado` | `pol_local_select_authenticated_contexto` | RENOMBRAR |

## 12.4 Mesa

| Actual | Objetivo | Acción |
|---|---|---|
| `anon_select_active_mesa` | `pol_mesa_select_anon_activa` | RENOMBRAR |
| `mesa_delete_administrador` | `pol_mesa_delete_administrador` | RENOMBRAR |
| `mesa_insert_administrador` | `pol_mesa_insert_administrador` | RENOMBRAR |
| `mesa_select_cocina_local` | `pol_mesa_select_cocina_local` | RENOMBRAR |
| `mesa_select_local` | `pol_mesa_select_authenticated_local` | RENOMBRAR |
| `mesa_update_administrador` | `pol_mesa_update_administrador` | RENOMBRAR |

## 12.5 Pedido

| Actual | Objetivo | Acción |
|---|---|---|
| `pedido_select_caja_local_cobro` | `pol_pedido_select_caja_cobro` | RENOMBRAR |
| `pedido_select_cocina_local` | `pol_pedido_select_cocina_local` | RENOMBRAR |
| `pedido_select_vigente_mozo_local` | `pol_pedido_select_mozo_vigente` | RENOMBRAR |

## 12.6 Perfil de usuario

| Actual | Objetivo | Acción |
|---|---|---|
| `perfil_usuario_select_propio` | `pol_perfil_usuario_select_authenticated_propio` | RENOMBRAR |

## 12.7 Producto

| Actual | Objetivo | Acción |
|---|---|---|
| `anon_select_active_producto` | `pol_producto_select_anon_activo` | RENOMBRAR |
| `producto_delete_administrador` | `pol_producto_delete_administrador` | RENOMBRAR |
| `producto_insert_administrador` | `pol_producto_insert_administrador` | RENOMBRAR |
| `producto_select_local` | `pol_producto_select_authenticated_local` | RENOMBRAR |
| `producto_update_administrador` | `pol_producto_update_administrador` | RENOMBRAR |

## 12.8 Rol

| Actual | Objetivo | Acción |
|---|---|---|
| `rol_select_contexto_autenticado` | `pol_rol_select_authenticated_contexto` | RENOMBRAR |

### Prioridad global de policies

**Baja.**

La mejora es de catálogo y mantenibilidad; las policies actuales funcionan y no deben tocarse solo por estética durante el cierre del MVP.

---

# 13. Secuencias

| Secuencia | Origen | Estado | Acción |
|---|---|---|---|
| `detalle_pedido_id_seq` | Identity | ✅ | MANTENER |
| `historial_estado_id_seq` | Identity | ✅ | MANTENER |
| `pago_id_seq` | Identity | ✅ | MANTENER |
| `pedido_id_seq` | Identity | ✅ | MANTENER |
| `rol_id_seq` | Identity | ✅ | MANTENER |

Al ser secuencias asociadas a columnas identity, no se recomienda renombrarlas.

---

# 14. Vistas, materialized views, procedures, enums y domains

El inventario actual no contiene:

```text
VIEW
MATERIALIZED VIEW
PROCEDURE
ENUM
DOMAIN
```

No se considera una carencia.

Solo deben crearse cuando exista una necesidad funcional o técnica real.

---

# 15. Grants

| Área | Estado | Acción | Observación |
|---|---|---|---|
| `anon` | ✅ | MANTENER | Lecturas públicas explícitas y limitadas |
| `authenticated` | ✅ | MANTENER | Acceso combinado con RLS |
| `service_role` | ✅ | MANTENER | Rol administrativo |
| `postgres` | ✅ | MANTENER | Propietario |
| `EXECUTE` de RPC | ✅ | MANTENER | Concedido a `authenticated` donde corresponde |
| Funciones internas críticas | ✅ | MANTENER | `sincronizar_estado_operativo_pedido` no tiene `EXECUTE` para `authenticated` |
| Helper de contexto | 🔵 | MANTENER | Necesita `EXECUTE` para `authenticated` porque las policies lo invocan |

---

# 16. Comentarios de catálogo

PM-001 incorporó exactamente 16 comentarios de catálogo para reglas no evidentes en columnas, funciones y el trigger seleccionado.

## Estado aplicado

Se aplicaron `COMMENT ON` únicamente en objetos donde aportan contexto real.

Objetos documentados:

```text
pedido.estado
pedido.enviado_en
pedido.modificado_en
pedido.modificado_por
detalle_pedido.estado
detalle_pedido.precio_unitario
detalle_pedido.enviado_en
pago.importe
obtener_contexto_autenticado
sincronizar_estado_operativo_pedido
registrar_auditoria_detalle_pedido
exportar_productos_local
exportar_ventas_hoy
obtener_resumen_ventas_hoy
obtener_creadores_pedidos_vigentes
detalle_pedido_registrar_auditoria
```

No se recomiendan comentarios adicionales sin una regla no evidente que los justifique.

---

# 17. Resumen de acciones

## No cambiar

- nombres de las 10 tablas;
- PK/FK/UQ/CHECK;
- índices actuales;
- secuencias identity;
- estructura general del modelo;
- snapshots históricos/transaccionales;
- patrón de `SECURITY DEFINER`.

## Revisar antes de modificar

1. Semántica exacta de:
   - `pedido.modificado_en`;
   - `pedido.modificado_por`.

2. Responsabilidades de:
   - `registrar_auditoria_detalle_pedido()`.

## Ajustes implementados por PM-001

1. Contexto autenticado centralizado en:
   - `exportar_productos_local`;
   - `exportar_ventas_hoy`;
   - `obtener_resumen_ventas_hoy`.

2. Las cuatro funciones read-only evaluadas fueron declaradas `STABLE`.
3. Se incorporaron los 16 comentarios seleccionados y se desplegó DBSTD.

## Normalización de nombres de baja prioridad

- `rpc_` para funciones públicas;
- `fn_` para funciones internas;
- `tgf_` para trigger functions;
- `trg_` para triggers;
- `pol_` para policies.

---

# 18. Priorización final

| Prioridad | Cambio | Justificación |
|---|---|---|
| Media | Definir semántica de auditoría `modificado_*` | Puede afectar significado funcional de datos |
| Media | Revisar trigger de `detalle_pedido` | Acumula varias responsabilidades |
| Completado | Centralizar contexto autenticado | Implementado y desplegado en PM-001 |
| Completado | Ajustar volatilidad de cuatro funciones read-only | Implementado y desplegado en PM-001 |
| Completado | Incorporar 16 `COMMENT ON` | Implementado y desplegado en PM-001 |
| Baja | Renombrar RPC/funciones/triggers/policies | Mejora catálogo, no funcionalidad |
| Ninguna | Renombrar tablas existentes | Impacto superior al beneficio |
| Ninguna | Eliminar `local_id` redundantes | Desnormalización justificada |
| Ninguna | Eliminar snapshots | Necesarios para trazabilidad |

---

# 19. Dictamen

El modelo actual de MikuyApp es apto para continuar evolucionando.

PM-001 — DB Standardization fue aceptado y desplegado sin rediseñar el modelo ni ampliar el alcance funcional del MVP.

No se detecta necesidad de reestructuración general ni de una campaña de normalización.

La estrategia recomendada es:

```text
1. conservar el modelo físico actual;
2. fijar el estándar para objetos nuevos;
3. corregir únicamente inconsistencias con beneficio técnico;
4. evitar renombrados retroactivos puramente estéticos;
5. incorporar los ajustes de arquitectura en una evolución técnica planificada.
```
