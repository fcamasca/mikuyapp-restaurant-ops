# MikuyApp — Plan del video de presentación

**Fecha de estimación:** 28 de agosto de 2026  
**Tipo de pieza:** video promocional animado  
**Duración objetivo:** 45–50 segundos  
**Formato principal:** horizontal 16:9, 1080p  
**Momento recomendado de producción:** después de completar y estabilizar el flujo del MVP en H6

## 1. Objetivo

Presentar de forma entretenida cómo MikuyApp sincroniza al mozo, cocina y caja durante la atención de una mesa, sin convertir el video en un tutorial.

La historia mostrará el flujo aprobado del MVP:

> Cliente llega → mozo registra y envía el pedido → cocina recibe y prepara → mozo entrega → caja registra el pago → la mesa queda libre.

El video será una pieza promocional independiente. No modifica el alcance funcional ni el cronograma de los hitos de MikuyApp.

## 2. Dirección creativa

### Concepto

**“Un restaurante en sincronía.”**

Montaje musical de anime urbano y costumbrista, con personajes adultos relajados, humor visual ligero, colores cálidos y tropicales, fondos gráficos y cortes sincronizados con la música.

La referencia sirve únicamente para definir energía, ritmo y lenguaje visual. No se copiarán personajes, planos, música ni elementos identificables de ninguna serie.

### Tratamiento

- Sin diálogos ni sincronización labial.
- Música funk/jazz-hop con matices peruanos sutiles.
- Sonidos puntuales: puerta, toque del celular, notificación de cocina, preparación del plato e impresora.
- Interfaz real de MikuyApp superpuesta en celulares y tablet; la IA no generará textos ni botones críticos.
- Comanda luminosa que viaja mediante una nube como metáfora de la sincronización en tiempo real.
- Textos mínimos: `Pedido enviado`, `En preparación`, `Listo`, `Entregado`, `Mesa libre`.

## 3. Secuencia narrativa preliminar

| Tiempo | Escena | Mensaje |
|---:|---|---|
| 0–5 s | Cliente entra y el local cobra vida | Inicio de la atención |
| 5–11 s | Mozo toma el pedido y usa MikuyApp | Registro rápido |
| 11–17 s | Mesa, productos, observación y botón **Enviar** | Pedido confirmado |
| 17–22 s | La comanda viaja por una nube hacia cocina | Sincronización |
| 22–30 s | Cocina recibe, revisa y prepara | Control operativo |
| 30–35 s | Cocina marca **Listo** y avisa al mozo | Actualización inmediata |
| 35–40 s | Mozo entrega el plato | Servicio coordinado |
| 40–46 s | Caja registra el pago e imprime | Cierre del consumo |
| 46–50 s | Mesa libre, equipo y logo | Resultado y marca |

## 4. Entregables

1. Libreto visual-musical definitivo.
2. Storyboard con 8–10 planos.
3. Guía visual de personajes, vestuario, restaurante, paleta y objetos.
4. Animatic sencillo con imágenes fijas y música provisional.
5. Piloto animado de 8–10 segundos.
6. Video final horizontal de 45–50 segundos en 1080p.
7. Versión vertical de 20–30 segundos para redes, solamente si el montaje permite recortarla sin regenerar escenas.
8. Carpeta de imágenes, clips, audio, capturas de MikuyApp y proyecto de edición.

## 5. Equivalencia con un proyecto de desarrollo

| Desarrollo de software | Producción del video | Entregable equivalente |
|---|---|---|
| Requerimientos | Brief y libreto | Qué debe comunicar el video |
| Diseño UX/UI | Storyboard | Cómo se verá cada plano |
| Sistema de diseño | Guía de personajes y escenarios | Apariencia reutilizable |
| Implementación | Generación de imágenes y animación | Clips de video |
| Integración | Montaje y composición | Secuencia completa |
| Pruebas | Revisión visual y funcional | Lista de defectos |
| Build | Exportación | Archivo MP4 final |

## 6. Herramienta utilizada en cada actividad

Se empleará una cadena mínima de tres herramientas principales y dos auxiliares. Cada una tiene una responsabilidad distinta:

| Herramienta | Responsabilidad | Entrada | Salida |
|---|---|---|---|
| **ChatGPT, incluida su generación de imágenes** | Brief, libreto, storyboard, prompts, personajes, restaurante e imágenes maestras | Plan del MVP, descripción visual y referencias aprobadas | Documentos, prompts y archivos PNG |
| **Runway** | Convertir cada imagen maestra en un clip con movimiento | PNG + prompt de movimiento | Clips MP4 de 3–5 segundos |
| **OBS Studio o grabador de Windows** | Capturar la interfaz verdadera de MikuyApp | Aplicación ejecutándose | Grabaciones o capturas de pantalla |
| **Mixkit Music** | Proporcionar música provisional con licencia gratuita | Búsqueda por ritmo y tono | Archivo de audio descargado y licencia registrada |
| **DaVinci Resolve** | Unir clips, colocar la interfaz, textos, logo, música y sonidos | MP4, PNG, audio y capturas | Video final MP4 |

### Flujo de archivos

1. ChatGPT define el plano y genera una imagen PNG.
2. El PNG se carga en Runway y se anima.
3. Runway devuelve un clip MP4 sin textos críticos.
4. OBS o el grabador de Windows captura la pantalla real de MikuyApp.
5. Se descarga de Mixkit una pista provisional y se conserva la referencia de su licencia.
6. DaVinci coloca la pantalla sobre el celular o tablet, agrega sonidos y une los clips.
7. DaVinci exporta el piloto o el video final.

No se utilizará Runway para escribir botones, estados ni precios porque la IA puede deformarlos. Tampoco se requieren Blender, After Effects, Figma o animación cuadro por cuadro para el piloto.

## 7. Plan específico del piloto

### Alcance

Un clip terminado de **8–10 segundos**, compuesto por cuatro planos:

| Tiempo | Plano | Producción |
|---:|---|---|
| 0–2.5 s | El mozo camina relajadamente entre las mesas | Imagen en ChatGPT; movimiento en Runway |
| 2.5–4.5 s | Mira el celular y pulsa **Enviar** | Movimiento en Runway; pantalla en DaVinci |
| 4.5–7.5 s | La comanda luminosa viaja mediante una nube | Base visual en ChatGPT; movimiento en Runway y ajuste en DaVinci |
| 7.5–10 s | Cocina recibe el pedido en la tablet | Imagen en ChatGPT; movimiento en Runway; pantalla en DaVinci |

### Actividades y tiempos

| Paso | Actividad | Herramienta | Salida verificable | Tiempo |
|---:|---|---|---|---:|
| P01 | Definir el microguion, ritmo y cuatro planos | ChatGPT | Libreto del piloto | 0.5 h |
| P02 | Diseñar al mozo, cocinero y restaurante | Imágenes de ChatGPT | Hoja de referencia PNG | 1.5 h |
| P03 | Crear las cuatro imágenes maestras | Imágenes de ChatGPT | Storyboard PNG | 1 h |
| P04 | Animar y seleccionar los cuatro planos | Runway, inicialmente modo Turbo | Clips MP4 | 2 h |
| P05 | Seleccionar música provisional y colocar interfaz, comanda, logo y sonidos | Mixkit Music y DaVinci Resolve | Primera edición | 1 h |
| P06 | Revisar en PC y celular y exportar 1080p | DaVinci Resolve | Piloto MP4 | 0.5 h |
| — | Regeneraciones y correcciones | ChatGPT, Runway o DaVinci | Contingencia | 1.5 h |
|  | **Total del piloto** |  |  | **8 h** |

### Criterios de aprobación del piloto

- La secuencia se entiende sin explicación ni narración.
- El estilo se siente relajado, divertido y propio de MikuyApp.
- El mozo y el cocinero mantienen una apariencia reconocible.
- La comanda que viaja mediante la nube comunica sincronización.
- La pantalla de MikuyApp se lee correctamente.
- No hay deformaciones visibles en manos, rostros, objetos principales o movimiento.
- El piloto genera suficiente entusiasmo para producir los otros 40 segundos.

Si el piloto se rechaza, solamente se corrige la dirección visual; todavía no se generan las demás escenas. Si se aprueba, sus personajes, restaurante, colores y transición se reutilizan en el video completo.

## 8. Plan de producción completa

| Fase | Actividad | Herramientas | Horas |
|---:|---|---|---:|
| 1 | Piloto aprobado | ChatGPT, Runway y DaVinci | 8 h |
| 2 | Completar libreto y storyboard de 45–50 s | ChatGPT e imágenes de ChatGPT | 2 h |
| 3 | Generar y seleccionar los clips restantes | Runway | 5 h |
| 4 | Grabar pantallas reales de mozo, cocina y caja | MikuyApp y OBS o grabador de Windows | 1 h |
| 5 | Montaje, interfaz, música, sonidos, textos y logo | DaVinci Resolve | 2 h |
| 6 | Correcciones, revisión y exportaciones | DaVinci Resolve | 2 h |
|  | **Total estimado** |  | **20 h** |

## 9. Puntos de aprobación

La producción se detiene para revisión en tres momentos:

1. **Dirección creativa:** se aprueba el aspecto y tono antes del storyboard.
2. **Animatic:** se aprueban historia, duración y música antes de generar video.
3. **Piloto:** se aprueba el movimiento y consistencia antes de animar el resto.

El video final se acepta cuando:

- El flujo coincide con el MVP.
- Los personajes principales mantienen una apariencia reconocible.
- La interfaz mostrada corresponde a MikuyApp.
- Los textos se leen correctamente.
- No se sugiere pedido directo del cliente ni procesamiento integrado de Yape, Plin o tarjetas.
- El video funciona sin narración y termina con el logo y eslogan oficiales.

## 10. Estimación económica

### Desembolso de herramientas

| Escenario | Herramientas | Estimación |
|---|---|---:|
| Piloto | Créditos gratuitos o plan inicial, edición gratuita | **S/0–50** |
| Recomendado | Un mes de Runway Pro o equivalente, DaVinci Resolve gratuito y música propia/licenciada | **S/120–180** |
| Alta iteración | Plan de alto volumen para muchas regeneraciones | **S/320–400** |

El escenario recomendado utiliza como referencia Runway Pro de USD 35 mensuales. Al tipo de cambio referencial cercano a S/3.35 por dólar, equivale aproximadamente a S/117 antes de impuestos o cargos de la tarjeta.

### Valor del trabajo

Aplicando el valor de **S/70 por hora** usado en el plan del MVP:

- 20 horas × S/70 = **S/1,400** de trabajo.
- Herramientas recomendadas = **S/120–180**.
- Valor económico total = **S/1,520–1,580**.
- Si se produce personalmente, el desembolso efectivo previsto es solamente **S/120–180**.

## 11. Herramientas recomendadas

- **Diseño estático:** generación de imágenes de ChatGPT.
- **Animación:** Runway, usando primero modelos rápidos para pruebas y el modelo de mayor calidad solo en los clips aprobados.
- **Alternativa:** Kling únicamente si Runway no conserva correctamente un movimiento específico.
- **Edición y sonido:** DaVinci Resolve gratuito.
- **Interfaz:** grabaciones reales del MVP y composición durante la edición.
- **Música:** pista original o con licencia comercial verificable; no utilizar música de la serie tomada como referencia.

Runway informa que Gen-4.5 consume 12 créditos por segundo; su plan Standard incluye 625 créditos y Pro 2,250. Para un video final de 45–50 segundos se necesita generar bastante más metraje que el utilizado, por lo que Standard resulta ajustado y Pro es el escenario recomendado. DaVinci Resolve ofrece edición gratuita hasta Ultra HD.

## 12. Dependencia con el MVP

La preproducción puede iniciarse antes de H6, pero las siguientes actividades deben esperar a que el flujo esté estable:

- Captura de las pantallas reales de mozo, cocina y caja.
- Composición de estados y textos definitivos.
- Exportación final del video.

Esto evita rehacer escenas si cambia la interfaz durante H4 o H5.

## 13. Recomendación

Iniciar con el **piloto de 8 horas** definido en la sección 7, que produzca:

1. Una guía visual mínima.
2. Tres imágenes del storyboard.
3. Un clip animado de 8–10 segundos: el mozo envía el pedido y la comanda viaja por la nube hacia cocina.

Solo después de aprobar ese piloto se autoriza la producción completa estimada en 20 horas. Las 8 horas del piloto forman parte de ese total; después de aprobarlo quedan aproximadamente 12 horas. Así se valida la parte más difícil —identidad visual y consistencia— con un desembolso máximo inicial de S/50.

## Fuentes de costos consultadas

- [Runway — planes y créditos](https://runwayml.com/pricing)
- [Runway — consumo de créditos](https://help.runwayml.com/hc/en-us/articles/15124877443219-How-do-credits-work)
- [DaVinci Resolve — versión gratuita](https://www.blackmagicdesign.com/products/davinciresolve)
- [SBS — tipo de cambio](https://www.sbs.gob.pe/app/pp/sistip_portal/paginas/publicacion/tipocambiopromedio.aspx)
