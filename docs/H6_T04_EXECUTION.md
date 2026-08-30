# MikuyApp — Evidencia H6-T04

Fecha de ejecución: 2026-08-30.

## Resultado

H6-TP09–TP12 quedaron aprobadas sobre el proyecto Supabase remoto vinculado y la rama H6 vigente.

| Verificación | Resultado |
|---|---|
| Suite automatizada completa | 293/293 aprobadas; 0 fallos, omisiones o pendientes |
| Typecheck | Aprobado |
| Build | Aprobado; conserva únicamente el aviso conocido de bundle >500 kB |
| SQL remoto aplicable H1–H6 | 20/20 archivos transaccionales aprobados |
| Doble cobro concurrente | Dos sesiones compitieron; estado persistido verificó exactamente un pago, pedido `PAGADO`, mesa `LIBRE` y un historial |
| Privilegios/RLS/RPC | Contratos `SECURITY DEFINER`, `search_path`, revocación de `anon`, roles y local aprobados |
| Aislamiento | Dos locales y roles cruzados sin exposición ni operación ajena |
| Terminales | `PAGADO`/`ANULADO` bloquean reapertura, modificación, entrega y cobro indebido |
| Realtime | Publicación limitada a `detalle_pedido`, `pedido` y `mesa`; `pago` no publicado |
| `supabase db lint --linked --level error` | Sin errores de esquema |
| Migraciones | Local/remoto alineados hasta `20260830000300` |
| Residuos finales | 0 usuarios, 0 locales, 0 pedidos y 0 pagos de fixtures H5/H6 |

## Diagnósticos históricos no aplicables

Se ejecutaron adicionalmente dos controles H1 de snapshot exacto que no forman parte de la regresión evolutiva vigente:

- `tp09_tp11_schema.sql` espera el esquema inicial y reporta siete diferencias correspondientes a columnas agregadas y aprobadas en H3/H4.
- `tp12_tp13_seed.sql` exige exactamente cinco categorías permanentes, pero el catálogo productivo es administrable y actualmente contiene cuatro.

No representan defectos de seguridad ni regresiones H1–H5. No se modificaron estos controles históricos, el catálogo remoto ni las decisiones aceptadas. Las invariantes vigentes de esquema, constraints, seguridad y operación quedaron cubiertas por las pruebas evolutivas aprobadas.

## Concurrencia

El canal Management API agotó el tiempo de espera al devolver las dos respuestas concurrentes, limitación ya documentada en H5. La consulta independiente posterior aprobó el estado persistido de pago único. El fixture fue eliminado y una auditoría separada confirmó residuos en cero.
