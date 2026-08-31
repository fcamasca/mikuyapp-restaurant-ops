# MikuyApp — Estándar de Base de Datos

**Versión:** 1.0  
**Estado:** Propuesta inicial para revisión  
**Motor:** PostgreSQL / Supabase  
**Ámbito:** objetos propios de MikuyApp en el esquema `public`

---

## 1. Objetivo

Definir un estándar único para el diseño y nomenclatura de objetos de base de datos de MikuyApp, con el fin de:

- mantener consistencia entre tablas, funciones, triggers, índices y políticas RLS;
- facilitar mantenimiento, soporte y evolución;
- distinguir claramente objetos públicos de aplicación de objetos internos;
- preservar integridad, trazabilidad y seguridad;
- evitar renombrados o estructuras sin beneficio técnico real.

Este estándar aplica a objetos nuevos y sirve como referencia para evaluar los objetos existentes.

> La adopción de este estándar no implica renombrar automáticamente los objetos actuales. Todo cambio sobre objetos existentes debe pasar primero por análisis de impacto.

---

## 2. Principios generales

1. Usar nombres en **español**, salvo términos técnicos propios de PostgreSQL/Supabase.
2. Usar siempre **minúsculas** y formato `snake_case`.
3. Evitar abreviaturas ambiguas.
4. Preferir nombres que indiquen responsabilidad funcional.
5. No codificar información redundante en el nombre cuando PostgreSQL ya expresa el tipo del objeto.
6. Mantener las reglas críticas de negocio en PostgreSQL cuando deban ser transaccionales.
7. Aplicar RLS y privilegios de mínimo acceso.
8. Diseñar normalmente hasta **Tercera Forma Normal (3NF)**, admitiendo desnormalización únicamente cuando exista justificación funcional, histórica, de seguridad o rendimiento.
9. Toda excepción al estándar debe quedar documentada.

---

## 3. Esquemas

### 3.1 Esquema de aplicación

Los objetos propios de MikuyApp se mantienen actualmente en:

```text
public
```

No se deben crear objetos funcionales en esquemas administrados por Supabase como:

```text
auth
storage
realtime
```

salvo referencias explícitamente requeridas por Supabase.

### 3.2 Uso de nombres calificados

En funciones `SECURITY DEFINER` se deben usar nombres calificados:

```sql
public.pedido
public.detalle_pedido
public.mesa
auth.uid()
```

---

## 4. Clasificación de tablas

La clasificación funcional estándar será:

| Prefijo conceptual | Clasificación | Ejemplo |
|---|---|---|
| `cfg_` | Configuración | local, parámetros |
| `mae_` | Maestra | producto, categoría, mesa |
| `seg_` | Seguridad / identidad | perfil de usuario, rol |
| `mov_` | Movimiento / cabecera transaccional | pedido, pago |
| `det_` | Detalle transaccional | detalle de pedido |
| `his_` | Histórico / auditoría | historial de estados |

### 4.1 Aplicación a MikuyApp

Los prefijos anteriores forman parte de la **clasificación estándar**, pero no obligan a renombrar las tablas actuales.

Los nombres actuales son semánticos y legibles:

```text
local
rol
perfil_usuario
mesa
categoria
producto
pedido
detalle_pedido
historial_estado
pago
```

Antes de aplicar prefijos físicos como `mae_`, `mov_` o `det_` sobre tablas existentes debe evaluarse el impacto en:

- frontend;
- funciones RPC;
- funciones internas;
- triggers;
- RLS;
- Realtime;
- migraciones;
- pruebas;
- documentación.

Para nuevas tablas se debe decidir expresamente si se mantiene el estilo semántico actual o si se adopta el prefijo físico de clasificación.

---

## 5. Nombres de tablas

### 5.1 Reglas

- Usar sustantivos en singular.
- Usar nombres funcionales, no técnicos.
- Evitar nombres genéricos como `data`, `master`, `transaction`.
- No incluir el nombre del proyecto en cada tabla.
- Evitar sufijos de versión (`_v2`, `_new`, `_old`).

### 5.2 Ejemplos válidos

```text
pedido
detalle_pedido
producto
historial_estado
```

### 5.3 Ejemplos no recomendados

```text
tbl_pedido
tabla_producto
pedido_v2
data_pedido
```

---

## 6. Columnas

### 6.1 Clave primaria

La PK se denomina:

```text
id
```

### 6.2 Claves foráneas

Formato:

```text
<entidad>_id
```

Ejemplos:

```text
local_id
pedido_id
producto_id
usuario_id
```

### 6.3 Campos estándar

| Propósito | Nombre |
|---|---|
| Código funcional | `codigo` |
| Nombre visible | `nombre` |
| Estado | `estado` |
| Indicador activo | `activo` |
| Fecha creación | `creado_en` |
| Usuario creador | `creado_por` |
| Fecha modificación | `modificado_en` |
| Usuario modificador | `modificado_por` |

### 6.4 Booleanos

Usar nombres afirmativos:

```text
activo
habilitado
procesado
```

Evitar:

```text
no_activo
sin_procesar
```

### 6.5 Timestamps

Usar `timestamptz`.

Convención:

```text
<evento>_en
```

Ejemplos:

```text
creado_en
modificado_en
enviado_en
pagado_en
```

### 6.6 Importes y precios

Usar `numeric(p,s)`.

No usar `float` ni `double precision` para importes monetarios.

Ejemplo:

```text
numeric(10,2)
```

---

## 7. Constraints

Los nombres de constraints son obligatorios y deben ser explícitos.

### 7.1 Primary Key

```text
pk_<tabla>
```

Ejemplo:

```text
pk_pedido
```

### 7.2 Foreign Key

```text
fk_<tabla>_<referencia>
```

Ejemplos:

```text
fk_pedido_local
fk_pedido_mesa_local
fk_detalle_pedido_producto
```

### 7.3 Unique

```text
uq_<tabla>_<columnas_o_regla>
```

Ejemplos:

```text
uq_local_codigo
uq_pago_pedido_id
```

### 7.4 Check

```text
ck_<tabla>_<regla>
```

Ejemplos:

```text
ck_pago_importe_positivo
ck_detalle_pedido_estado_valido
```

### 7.5 Reglas

- Toda relación debe declarar explícitamente su comportamiento `ON DELETE`.
- Para datos históricos se prefiere `ON DELETE RESTRICT`.
- Las reglas simples de dominio deben implementarse con constraints antes que con triggers.

---

## 8. Índices

### 8.1 Convención

```text
idx_<tabla>_<columnas_o_proposito>
```

Ejemplos:

```text
idx_pedido_local_id_estado_creado_en
idx_detalle_pedido_pedido_id_estado
```

### 8.2 Índices únicos parciales

Cuando implementen una regla funcional, el nombre debe expresar la regla.

Ejemplo:

```text
uq_pedido_mesa_id_vigente
```

### 8.3 Principio

No crear índices preventivos sin una consulta o restricción identificada.

---

## 9. Funciones y RPC

Se distinguen dos categorías.

### 9.1 RPC públicas

Funciones invocables por la aplicación mediante Supabase/PostgREST.

Convención objetivo:

```text
rpc_<verbo>_<entidad_o_proceso>
```

Ejemplos:

```text
rpc_agregar_detalle_pedido
rpc_registrar_pago_pedido
rpc_obtener_tablero_cocina
```

### 9.2 Funciones internas

Funciones auxiliares que no forman parte de la API pública de la aplicación.

Convención objetivo:

```text
fn_<verbo>_<entidad_o_proceso>
```

Ejemplos:

```text
fn_sincronizar_estado_operativo_pedido
fn_obtener_contexto_autenticado
```

### 9.3 Verbos recomendados

Usar verbos que indiquen claramente la acción:

```text
crear
obtener
agregar
actualizar
registrar
sincronizar
validar
exportar
liberar
entregar
```

### 9.4 Parámetros

Convención:

```text
p_<nombre>
```

Ejemplos:

```text
p_pedido_id
p_producto_id
p_estado_nuevo
```

### 9.5 Variables locales

Convención:

```text
v_<nombre>
```

Ejemplos:

```text
v_usuario_id
v_local_id
v_pedido
```

---

## 10. SECURITY DEFINER

Toda función `SECURITY DEFINER` debe cumplir:

```sql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
```

y debe usar referencias calificadas:

```sql
public.<objeto>
auth.<funcion>
```

Además:

- validar `auth.uid()` cuando corresponda;
- obtener y validar contexto de usuario/local/rol;
- aplicar privilegio mínimo mediante `GRANT EXECUTE`;
- evitar depender de objetos resolubles por un `search_path` inseguro.

---

## 11. Volatilidad de funciones

Clasificación:

- `IMMUTABLE`: mismo resultado para los mismos argumentos, sin depender de BD ni sesión.
- `STABLE`: consulta datos, pero no modifica la base durante la sentencia.
- `VOLATILE`: modifica datos o puede devolver resultados distintos dentro de la misma sentencia.

Funciones exclusivamente de consulta deben evaluarse para `STABLE`.

Funciones de actualización/transacción deben mantenerse `VOLATILE`.

---

## 12. Procedimientos

Convención para procedimientos futuros:

```text
pr_<verbo>_<entidad_o_proceso>
```

Solo crear `PROCEDURE` cuando exista una necesidad concreta que no sea cubierta adecuadamente por una función.

No crear procedimientos únicamente por clasificación arquitectónica.

---

## 13. Triggers

### 13.1 Trigger function

Convención:

```text
tgf_<tabla>_<proposito>
```

Ejemplo:

```text
tgf_detalle_pedido_auditoria
```

### 13.2 Trigger

Convención:

```text
trg_<tabla>_<momento>_<evento>_<proposito>
```

Ejemplos:

```text
trg_detalle_pedido_before_write_auditoria
trg_pedido_before_update_auditoria
```

### 13.3 Principios

- Evitar lógica de negocio principal oculta en triggers.
- Usar triggers principalmente para:
  - auditoría;
  - invariantes técnicas;
  - mantenimiento de timestamps;
  - reglas imposibles o poco prácticas mediante constraints.
- No duplicar en trigger una regla ya garantizada por constraint.
- Cada trigger function debe tener una responsabilidad claramente identificable.

---

## 14. Vistas

### 14.1 Vista

```text
vw_<concepto>
```

Ejemplo:

```text
vw_ventas_diarias
```

### 14.2 Vista materializada

```text
mv_<concepto>
```

Ejemplo:

```text
mv_resumen_ventas_mensual
```

No crear vistas únicamente para ocultar joins simples sin una necesidad funcional o de seguridad.

---

## 15. Secuencias

Las columnas identity de PostgreSQL deben preferirse sobre secuencias administradas manualmente.

Para secuencias creadas manualmente:

```text
seq_<tabla>_<columna>
```

Las secuencias generadas automáticamente por columnas `IDENTITY` pueden conservar el nombre generado por PostgreSQL.

---

## 16. RLS Policies

### 16.1 Convención

```text
pol_<tabla>_<operacion>_<rol>[_<condicion>]
```

Ejemplos:

```text
pol_categoria_select_anon_activa
pol_categoria_update_administrador
pol_pedido_select_mozo_vigente
pol_pedido_select_caja_cobro
```

### 16.2 Principios

- RLS debe permanecer habilitado en todas las tablas expuestas a Supabase.
- Una policy no sustituye a los privilegios PostgreSQL.
- Aplicar doble control:
  - `GRANT/REVOKE`;
  - RLS.
- Evitar mezclar inglés y español en nombres nuevos.
- Reutilizar una única función autoritativa para resolver contexto autenticado cuando sea posible.

---

## 17. Grants

Aplicar mínimo privilegio.

Roles esperados:

```text
anon
authenticated
service_role
postgres
```

Reglas:

- `anon`: solo acceso explícitamente público.
- `authenticated`: solo tablas/columnas/RPC necesarias.
- `service_role`: uso administrativo/backend, nunca en frontend.
- `postgres`: propietario/administración.

No conceder `EXECUTE` a una función interna si no debe ser invocada por el cliente.

---

## 18. Auditoría

Campos estándar:

```text
creado_por
creado_en
modificado_por
modificado_en
```

Reglas:

- `creado_por` y `creado_en` deben ser inmutables después del INSERT.
- Los cambios de estado que requieran trazabilidad funcional deben registrarse en tablas históricas específicas cuando aplique.
- `historial_estado` debe conservar:
  - estado anterior;
  - estado nuevo;
  - usuario;
  - fecha/hora.

### Pendiente de definición

Debe confirmarse una única semántica para:

```text
modificado_por
modificado_en
```

Alternativas:

1. última modificación de cualquier atributo de la fila;
2. última modificación del contenido funcional, excluyendo transiciones de estado.

No modificar los triggers existentes hasta cerrar esta definición.

---

## 19. Normalización

### 19.1 Regla general

El modelo debe diseñarse normalmente hasta **3NF**.

### 19.2 Excepciones válidas

Se permite desnormalización cuando exista una razón explícita:

- snapshot histórico;
- aislamiento por tenant/local;
- integridad adicional;
- seguridad RLS;
- rendimiento medido;
- simplificación transaccional justificada.

### 19.3 Casos aprobados conceptualmente en MikuyApp

#### Precio histórico

```text
detalle_pedido.precio_unitario
```

debe conservar el precio aplicado al pedido y no depender del precio actual de `producto`.

#### Importe pagado

```text
pago.importe
```

representa el valor registrado en la transacción de cobro.

#### Tenant/local explícito

Campos como:

```text
producto.local_id
pedido.local_id
```

pueden conservarse cuando permitan garantizar aislamiento e integridad entre locales mediante FK, RLS e índices.

Toda nueva desnormalización debe documentar su motivo.

---

## 20. Estados y valores controlados

Los valores de estado deben:

- tener dominio claramente definido;
- validarse en PostgreSQL;
- usar mayúsculas cuando sean códigos controlados.

Ejemplos:

```text
ABIERTO
ENVIADO
RECIBIDO_COCINA
EN_PREPARACION
LISTO
ENTREGADO
PAGADO
ANULADO
```

No introducir variantes de texto para un mismo concepto.

---

## 21. Comentarios de catálogo

Usar `COMMENT ON` para reglas no evidentes.

Priorizar comentarios en:

- snapshots históricos;
- estados derivados;
- timestamps con semántica especial;
- funciones internas críticas;
- funciones RPC;
- columnas cuya finalidad pueda ser malinterpretada.

No es necesario comentar columnas obvias como `id` o `nombre`.

---

## 22. Migraciones

Toda modificación estructural debe realizarse mediante migraciones versionadas.

Reglas:

1. no editar migraciones ya aplicadas en producción;
2. crear una nueva migración para cada cambio;
3. no renombrar objetos de producción sin análisis de impacto;
4. conservar compatibilidad durante una transición cuando corresponda;
5. validar constraints, RLS, funciones, grants y dependencias después de la migración.

---

## 23. Convenciones resumidas

| Objeto | Convención |
|---|---|
| Tabla | nombre semántico singular en `snake_case` |
| Maestra | clasificación `mae_` |
| Movimiento | clasificación `mov_` |
| Detalle | clasificación `det_` |
| Histórico | clasificación `his_` |
| Configuración | clasificación `cfg_` |
| Seguridad | clasificación `seg_` |
| PK | `pk_<tabla>` |
| FK | `fk_<tabla>_<referencia>` |
| UNIQUE | `uq_<tabla>_<regla>` |
| CHECK | `ck_<tabla>_<regla>` |
| Índice | `idx_<tabla>_<columnas/proposito>` |
| RPC | `rpc_<verbo>_<entidad>` |
| Función interna | `fn_<verbo>_<entidad>` |
| Procedure | `pr_<verbo>_<entidad>` |
| Trigger function | `tgf_<tabla>_<proposito>` |
| Trigger | `trg_<tabla>_<momento>_<evento>_<proposito>` |
| Vista | `vw_<concepto>` |
| Materialized view | `mv_<concepto>` |
| Secuencia manual | `seq_<tabla>_<columna>` |
| RLS policy | `pol_<tabla>_<operacion>_<rol>[_condicion]` |
| Parámetro | `p_<nombre>` |
| Variable local | `v_<nombre>` |

---

## 24. Aplicación sobre objetos existentes

Este documento define el estándar objetivo.

Antes de renombrar cualquier objeto existente se debe generar una matriz:

```text
objeto_actual
tipo
clasificacion
nombre_estandar
cumple
impacto
accion_recomendada
prioridad
```

Las acciones posibles serán:

```text
MANTENER
RENOMBRAR
REFACTORIZAR
DOCUMENTAR
REVISAR
```

No se realizará un cambio exclusivamente por estética si su impacto supera el beneficio técnico.

---

## 25. Criterio de evolución

Toda nueva funcionalidad de base de datos deberá:

1. respetar este estándar;
2. justificar cualquier excepción;
3. preservar las reglas de negocio aprobadas;
4. mantener integridad y seguridad;
5. incluir pruebas de la nueva estructura u objeto;
6. evitar deuda técnica innecesaria.
