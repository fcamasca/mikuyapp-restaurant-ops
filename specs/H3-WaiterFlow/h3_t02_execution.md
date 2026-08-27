# MikuyApp — H3-T02: evidencia de ejecución

## Alcance

Registro de implementación y validación de **H3-T02 — Abrir o recuperar pedido vigente**. No constituye aceptación de H3 ni autoriza el inicio de H3-T03.

## Implementación

- Migración: `supabase/migrations/20260826000200_h3_t02_open_or_recover_order.sql`.
- Función: `public.crear_o_recuperar_pedido_mesa(p_mesa_id uuid)`.
- La identidad procede de `auth.uid()` y local/rol de `public.obtener_contexto_autenticado()`.
- Solo un perfil activo con rol `MOZO` y el mismo local puede operar una mesa activa.
- La mesa se bloquea con `FOR UPDATE` antes de recuperar o crear el pedido.
- Si existe un pedido vigente, se devuelve sin crear cabecera ni historial adicionales.
- Si no existe y la mesa está `LIBRE`, se crea el pedido `ABIERTO`, se registra el historial inicial y la mesa pasa a `OCUPADA` en una única transacción.
- El índice `uq_pedido_mesa_id_vigente` de H3-T01 permanece como defensa adicional ante concurrencia.
- No se concedieron privilegios directos sobre `pedido`, `historial_estado` ni `mesa.estado`; solo `EXECUTE` de la función a `authenticated`.

## Pruebas SQL remotas

| Prueba | Resultado |
|---|---|
| `h3_t02_open_or_recover_order.sql` | Aprobada mediante `supabase db query --linked --file`; transacción revertida al finalizar |
| `tp09_tp11_schema.sql` | Aprobada |
| `tp10_constraints.sql` | Aprobada |
| `h3_t01_model.sql` | Aprobada |
| `supabase db lint --linked` | `No schema errors found` |

La prueba H3-T02 cubrió creación, historial, ocupación, recuperación idempotente, mesa inactiva, otro local, rol distinto de `MOZO`, privilegios mínimos y rollback inducido.

`tp12_tp13_seed.sql` no es aplicable al remoto H2 aceptado porque verifica que `auth.users` esté vacío y el entorno contiene los cuatro usuarios H2. Su ejecución se detuvo exactamente con `auth.users debe permanecer vacío`; no señaló una regresión del esquema, seed o H3-T02.

## Concurrencia real

Se creó una mesa fixture temporal y se realizaron simultáneamente dos llamadas RPC desde sesiones MOZO independientes.

```text
H3-T02 concurrencia aprobada: pedido=4, creado=1, recuperado=1
```

Ambas respuestas devolvieron el mismo `pedido_id`; una sola indicó creación. Después de la prueba se eliminaron historial, pedido y mesa fixture. La verificación final remota devolvió:

```text
mesas=0, pedidos=0, historiales=0
```

## Validaciones de aplicación

- `npm run typecheck`: aprobado.
- `npm run build`: aprobado.
- Suite automatizada H1/H2: 212/212 pruebas aprobadas.
- `git diff --check`: aprobado.

## Historial de migraciones

`supabase migration list --linked` confirmó coincidencia local/remota hasta `20260826000200`, incluida H3-T01 y H3-T02.

## Estado

**H3-T02: APROBADA.**

- Aprobación humana registrada el 2026-08-26.
- Implementación completada y validada.
- No quedan validaciones obligatorias pendientes.
- H3-T03 no se ha iniciado.
