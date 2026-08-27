# MikuyApp — H3-T10: evidencia integral de ejecución

Fecha: 2026-08-26  
Ambiente técnico: repositorio local y proyecto Supabase vinculado.  
Alcance: validación integral de H3; este documento no constituye `acceptance.md` ni aceptación de H3.

## 1. Resultado ejecutivo

**H3-T10 no completada.** Las validaciones funcionales, automatizadas y técnicas están aprobadas; las migraciones ya coinciden y no quedaron fixtures. Solo falta completar metadata documental de las pruebas humanas y confirmar visualmente los dos ajustes UX más recientes. No corresponde repetir las pruebas funcionales ya demostradas.

## 2. Pruebas automatizadas

Comando integral:

```text
node --experimental-strip-types --test tests/*.test.mjs
```

Resultado: **233/233 aprobadas**, 0 fallidas, 0 omitidas. Un intento previo con `node --test tests` falló porque Node interpretó el directorio como módulo; se corrigió el comando al patrón `tests/*.test.mjs`. No fue un defecto del producto.

| ID | Resultado | Evidencia principal |
|---|---|---|
| H3-TA01 | Aprobada | `h3_t02_open_or_recover_order.sql` remoto: cabecera, historial y mesa atómicos. |
| H3-TA02 | Aprobada con evidencia vigente | `h3_t02_execution.md`: dos sesiones, mismo pedido, una creación. Índice único y `FOR UPDATE` revalidados. |
| H3-TA03 | Aprobada | Suite del mozo y clasificación de estados en SQL/modelo. |
| H3-TA04 | Aprobada | `h3_t03_add_order_detail.sql` remoto y suite del mozo: consolidación equivalente solo en `ABIERTO`. |
| H3-TA05 | Aprobada | Contrato RPC sin precio/estado y matriz remota sin `INSERT` directo. |
| H3-TA06 | Aprobada | `h3_t04_open_order_detail_mutations.sql` remoto y pruebas de total/UI. |
| H3-TA07 | Aprobada | SQL remoto rechaza estados enviados/posteriores y evita cambios parciales. |
| H3-TA08 | Aprobada | Suite del mozo: observaciones frecuentes/libres y recuperación. |
| H3-TA09 | Aprobada | Total derivado de `cantidad * precio_unitario`; sin segunda fuente persistida. |
| H3-TA10 | Aprobada | `h3_t05_send_order_to_kitchen.sql` remoto: primer envío, historial y `enviado_en`. |
| H3-TA11 | Aprobada | Matriz remota de privilegios rechaza cambio directo de estado. |
| H3-TA12 | Aprobada | Concurrencia remota T05: `enviados=1/0`, una transición de cabecera. |
| H3-TA13 | Aprobada | SQL remoto y suite del mozo conservan cabecera y crean nuevos `ABIERTO`. |
| H3-TA14 | Aprobada | SQL remoto cubre cabeceras `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` y `ENTREGADO`; no retrocede ni reemplaza `enviado_en`. |
| H3-TA15 | Aprobada | SQL remoto rechaza producto/categoría inactivos y otro local. |

## 3. Pruebas técnicas manuales remotas

Se ejecutaron con `npx supabase db query --linked --file ...`. Los scripts que crean fixtures usan `BEGIN`/`ROLLBACK`.

| ID | Resultado | Evidencia |
|---|---|---|
| H3-TM01 | Aprobada | `h3_t01_model.sql`: índice único parcial y rechazo de segunda cabecera vigente. |
| H3-TM02 | Aprobada | `PAGADO`/`ANULADO` permiten nuevo ciclo; detalle no acepta `ANULADO`; `PENDIENTE_PAGO` no aparece como pedido. |
| H3-TM03 | Aprobada | `authenticated` sin `INSERT`; `EXECUTE` funcional restringido. |
| H3-TM04 | Aprobada | Definición remota lee `producto.precio` y fuerza `ABIERTO`. |
| H3-TM05 | Aprobada | Privilegios de columna y RLS limitan cantidad/observación y DELETE a `ABIERTO`. |
| H3-TM06 | Aprobada | Fallo inducido revierte cabecera, detalle e historial. |
| H3-TM07 | Aprobada | `SECURITY DEFINER`, propietario, search path, grants, roles y locales verificados. |

Scripts remotos aprobados:

- `domain_object_names.sql`
- `h3_t01_model.sql`
- `h3_t02_open_or_recover_order.sql`
- `h3_t03_add_order_detail.sql`
- `h3_t04_open_order_detail_mutations.sql`
- `h3_t05_send_order_to_kitchen.sql`
- `tp09_tp11_schema.sql`
- `tp10_constraints.sql`

Otras verificaciones:

- `npx supabase db lint --linked`: **No schema errors found**.
- Concurrencia T05 con fixture controlado: **aprobada**; limpieza ejecutada en `finally`.
- Auditoría de nombres permanentes: aprobada local y remotamente.
- Fixtures residuales: pedidos, detalles, historiales, locales, mesas, categorías, productos y usuarios técnicos = **0**.
- Migraciones `20260823235106` a `20260826000800`: local/remoto coincidentes.
- `20260826000800` fue registrada mediante `npx supabase migration repair --status applied 20260826000800 --linked`; no se volvió a ejecutar su SQL.

### Evidencia registrada en esta etapa

La validación humana de consolidación concurrente se registra exactamente con los datos proporcionados:

- dos dispositivos/sesiones agregaron simultáneamente el mismo producto equivalente;
- ambas operaciones fueron procesadas;
- quedó un único detalle `ABIERTO`;
- la cantidad final fue `2`;
- no quedaron dos líneas equivalentes.

No se agregan identificadores, dispositivos, navegadores, tiempos ni datos no proporcionados.

## 4. Flujo integrado

La combinación de SQL remoto y pruebas automatizadas demuestra:

```text
mesa libre → pedido ABIERTO → alta/consolidación → cantidad/observación/retiro
→ revisión → primer envío → recuperación → agregado posterior → segundo envío selectivo
```

En el primer envío, los detalles abiertos pasan a enviados, la cabecera cambia una sola vez, se crea un único historial y se fija `enviado_en`. En agregados posteriores se reutiliza el pedido, nacen detalles `ABIERTO`, solo ellos se envían y la cabecera/`enviado_en` no retroceden ni se sobrescriben.

## 5. Pruebas humanas

Durante T06–T09 el usuario ejecutó validaciones humanas y reportó defectos concretos sobre latencia/retiro, prioridad del pedido frente a la carta, consolidación, card compacta, icono y concurrencia de observaciones. Los defectos se corrigieron y las tareas T06–T09 fueron cerradas humanamente.

| ID | Evidencia funcional previamente ejecutada | Metadata disponible / pendiente |
|---|---|---|
| H3-TH01 | Cards de mesas validadas en celular y tablet: estado textual, total y acciones táctiles. | Dispositivos genéricos disponibles: celular/tablet. Faltan navegador, viewport exacto y orientación asociados a la ejecución. |
| H3-TH02 | Filtros por estado y orden ascendente/descendente validados sin desbordamiento crítico reportado. | Faltan navegador, viewport exacto y orientación. |
| H3-TH03 | Recuperación de pedido persistido validada tras navegación/recarga y después de conflicto PC/celular. | Dispositivos genéricos disponibles: PC/celular. Faltan navegador, viewport y orientación. |
| H3-TH04 | Carta, categorías, cards y modo explícito `Agregar productos` validados; no se agrega tocando cualquier zona de la card. | Celular/tablet informados para la validación global. Faltan navegador, viewport exacto y orientación por caso. |
| H3-TH05 | Responsive de carta/revisión validado en celular y tablet durante T07. | Faltan navegador, viewports exactos y confirmación documental de las orientaciones utilizadas. |
| H3-TH06 | Cantidades, observaciones frecuentes/libres, recuperación del texto y retiro con confirmación validados; se corrigió feedback durante latencia. | Faltan dispositivo/navegador/viewport/orientación exactos para esta ejecución. |
| H3-TH07 | Modo pedido, separación `Por enviar / Ya solicitado`, total y primer envío explícito validados. | Faltan dispositivo/navegador/viewport/orientación exactos. |
| H3-TH08 | Agregado posterior y segundo envío selectivo validados; se conservaron los ya solicitados y solo los nuevos detalles fueron enviados. | Faltan dispositivo/navegador/viewport/orientación exactos. |

### Últimos ajustes UX

- Conflicto concurrente: recuperación desde PostgreSQL y descarte del borrador obsoleto están demostrados por el escenario humano que originó la corrección y por pruebas automatizadas.
- Ubicación del aviso dentro de la card afectada: implementada y automatizada; falta confirmación visual humana posterior a ese último cambio.
- Usuario autenticado visible: componente transversal implementado para Administrador, Mozo, Cocina y Caja.
- Avatar compacto tipo Chrome/Teams: implementado con iniciales, popover, cierre externo/Escape y cierre de sesión; pruebas afectadas aprobadas. Falta únicamente confirmación visual humana posterior.

No se repite ninguna prueba funcional por falta de documentación. Para completar el registro solo deben proporcionarse los datos reales faltantes; no pueden deducirse ni fabricarse.

## 6. Regresiones y comandos

| Validación | Resultado |
|---|---|
| Suite completa H1/H2/H3 | 233/233 |
| Suite mozo/T09 | 40/40 en su última corrida individual |
| Responsive técnico | 13/13 en su última corrida individual |
| `npm run typecheck` | Aprobado |
| `npm run build` | Aprobado; 72 módulos transformados |
| Rutas, autenticación, contexto, catálogo y seguridad | Incluidos y aprobados en 233/233 |
| `git diff --check` | Aprobado; solo avisos informativos LF/CRLF |

## 7. Defectos encontrados y corregidos durante H3

- Estados y semántica de envíos posteriores corregidos en Spec antes de construcción.
- Nombres permanentes desacoplados de identificadores de hitos.
- Consolidación atómica de detalles equivalentes `ABIERTO` incorporada y validada concurrentemente.
- Feedback de retiro y mutaciones protegido contra doble tap.
- Pedido existente priorizado frente a la carta para evitar agregados accidentales.
- Card abierta compactada e icono de papelera accesible.
- Conflictos de edición detectados sin sobrescribir al ganador; borrador obsoleto descartado y datos recargados.
- Aviso de conflicto movido a la card específica.
- Identidad autenticada visible mediante componente transversal.
- Presentación de identidad compactada a avatar tipo Chrome/Teams con popover accesible.
- Historial de migración `20260826000800` reparado sin reaplicar SQL.

Durante T10 no se modificó código funcional. El archivo modificado por T10 es esta evidencia consolidada.

## 8. Condición de cierre

Para cerrar H3-T10 deben completarse, sin crear `acceptance.md` ni repetir las pruebas funcionales:

1. proporcionar, para H3-TH01–H3-TH08, navegador, viewport y orientación reales; cuando no haya un único valor común, indicar cuáles correspondieron a cada grupo de pruebas;
2. confirmar visualmente que el aviso de conflicto aparece solo dentro de la card afectada y que el avatar abre nombre/rol/cierre de sesión correctamente en celular/tablet.
