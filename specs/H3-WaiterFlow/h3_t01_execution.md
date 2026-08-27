# MikuyApp — H3-T01: evidencia de ejecución

## Alcance

Registro de implementación y validación de **H3-T01 — Cambio mínimo de modelo**. Este documento no constituye `acceptance.md` ni autoriza el inicio de H3-T02.

## Implementación validada

- Migración: `supabase/migrations/20260826000100_h3_t01_order_detail_state.sql`.
- `detalle_pedido.estado`: `text NOT NULL DEFAULT 'ABIERTO'`.
- Estados permitidos del detalle: `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO`.
- Índice: `idx_detalle_pedido_pedido_id_estado (pedido_id, estado)`.
- Índice único parcial: `uq_pedido_mesa_id_vigente (mesa_id)` para pedidos `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` o `ENTREGADO`.
- `PAGADO` y `ANULADO` quedan fuera del índice parcial y permiten un nuevo ciclo.
- `PENDIENTE_PAGO` no se incorporó como estado de pedido.

## Validación humana en Supabase remoto

Resultados informados el 2026-08-26:

| Ejecución | Resultado |
|---|---|
| `20260826000100_h3_t01_order_detail_state.sql` | `Success. No rows returned` |
| `tp09_tp11_schema.sql` | `Success. No rows returned` |
| `tp10_constraints.sql` | `Success. No rows returned` |
| `h3_t01_model.sql` | `Success. No rows returned` |

El estado aceptado de H2 no contenía datos transaccionales. Por decisión humana no se requirió fabricar un escenario adicional con pedidos históricos.

## Compatibilidad H1/H2

- `npm run typecheck`: aprobado.
- `npm run build`: aprobado.
- Suite automatizada H1/H2: 212/212 pruebas aprobadas.
- Las pruebas estructurales históricas se actualizaron únicamente para reconocer la nueva columna, check e índices de H3-T01.

## Historial de migraciones

La migración fue aplicada manualmente mediante Supabase SQL Editor, por lo que inicialmente la versión local `20260826000100` no figuraba en el historial remoto. Se ejecutó el mecanismo estándar sin reaplicar SQL:

```text
supabase migration repair 20260826000100 --status applied --linked
```

Resultado:

```text
Repaired migration history: [20260826000100] => applied
```

La comprobación posterior con `supabase migration list --linked` mostró coincidencia local/remota para:

- `20260823235106`
- `20260825000100`
- `20260825000200`
- `20260825000300`
- `20260826000100`

## Estado

**H3-T01 completada y validada.** No quedan pruebas obligatorias pendientes para T01. H3-T02 no se ha iniciado.
