# MikuyApp — Aceptación del Hito H3

## Identificación

| Campo | Valor |
|---|---|
| Fecha de cierre | 2026-08-27 |
| Hito | H3 — Flujo del mozo |
| Estado | **CERRADO / VALIDADO / ACEPTADO** |
| Evidencia principal | `specs/H3-WaiterFlow/h3_t10_execution.md` |

## Alcance aceptado

Se acepta el flujo operativo del mozo para seleccionar mesas, crear o recuperar un único pedido vigente, agregar y gestionar detalles abiertos, revisar el consumo, enviar a cocina y recuperar el pedido persistido ante recargas, errores o concurrencia.

Forman parte del diseño aceptado el estado individual de `detalle_pedido`; la transición `ABIERTO → ENVIADO`; los agregados posteriores y su envío selectivo dentro del mismo pedido sin retroceder la cabecera; la consolidación de detalles abiertos equivalentes por producto y observación; y la liberación de una mesa ocupada únicamente cuando su pedido `ABIERTO` está vacío, anulando el pedido y registrando el historial.

Los objetos permanentes conservan nombres funcionales de dominio, sin referencias a hitos.

## Resultado y requisitos

H3-R01–H3-R12 quedan cubiertos mediante H3-D01–H3-D11, las tareas H3-T01–H3-T10 y sus pruebas trazadas en el Spec vigente. El resultado fue validado sin ampliar H3 hacia cocina, Realtime, entrega, caja o impresión.

## Evidencia de aceptación

- Pruebas automatizadas integrales H1/H2/H3: **238/238 aprobadas**, sin fallos ni omisiones.
- Suite específica del mozo: **44/44 aprobadas**.
- Verificaciones técnicas: esquema, constraints, índices, RLS, privilegios, funciones transaccionales, atomicidad, idempotencia, aislamiento por rol/local, migraciones sincronizadas, lint sin errores y ausencia de fixtures residuales.
- Concurrencia: creación única por mesa, consolidación simultánea sin líneas equivalentes duplicadas, edición con recuperación del dato ganador, envío concurrente único y liberación segura del pedido vacío.
- Validación humana responsive en celular y tablet para tablero, filtros, carta, cards, revisión, mutaciones, envío, recuperación, conflictos y menú autenticado. La metadata exacta de navegador y viewport no fue consignada y no se fabrica en este documento.

Los detalles de ejecución, resultados por ID y evidencia disponible se mantienen en `h3_t10_execution.md`.

## Defectos relevantes resueltos

Durante las pruebas humanas se corrigieron el feedback durante mutaciones con latencia, la prioridad visual del pedido sobre la carta, la consolidación de detalles abiertos equivalentes, la card compacta y su acción accesible de retiro, los dobles taps, los conflictos concurrentes asociados a la card afectada y la presentación compacta del usuario autenticado. También se incorporó la recuperación segura de una mesa ocupada por un pedido vacío.

## Decisión

La aprobación humana explícita confirma que las pruebas automatizadas, técnicas y humanas de H3 fueron satisfactorias y que no quedan bloqueantes conocidos dentro del alcance aceptado.

**H3 — Flujo del mozo queda CERRADO, VALIDADO y ACEPTADO.**

H4 no ha iniciado. El siguiente hito deberá comenzar en Spec Mode.
