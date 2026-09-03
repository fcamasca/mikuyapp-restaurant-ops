# MikuyApp — PM-002 Separación de ambientes DEV/Preview y PROD: requisitos

## 1. Objetivo

Separar de forma inequívoca los ambientes de MikuyApp para que el proyecto Supabase actual pase a ser **DEV / PREVIEW** y un proyecto Supabase nuevo sea utilizado exclusivamente por **PROD**. La intervención deberá preservar el MVP `v1.0.0` y PM-001, reconstruir PROD desde el estado versionado del repositorio y evitar que desarrollo, pruebas, demos o deployments Preview alcancen PROD.

Este documento pertenece a Spec Mode. No crea proyectos, no cambia variables, no aplica migraciones y no modifica ambientes remotos.

## 2. Estado observado

- `main` coincide con la referencia local `origin/main` en `026b960`; el árbol solo contiene como elemento no versionado preexistente `supabase/Carga Inicial/`.
- El frontend obtiene `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY` en build time. No existe una variable de identidad de ambiente ni una validación del project ref esperado.
- `.env.local` está ignorado y contiene las dos variables públicas más credenciales de cuatro usuarios de prueba. `.env.example` expone solo los nombres de las dos variables públicas.
- La configuración operativa de Cloudflare Pages, incluidas variables de Production y Preview, no está versionada. El repositorio no incluye `wrangler.toml` ni workflow de despliegue; CI solo ejecuta instalación, typecheck y build.
- `supabase/config.toml` configura el stack local, PostgreSQL 17, migraciones habilitadas, `seed.sql`, Auth y Realtime. No representa por sí solo toda la configuración del proyecto alojado.
- Existen 28 migraciones ordenadas. La evidencia de PM-001 registra 28/28 aplicadas, 10 tablas con RLS y 27 policies en el proyecto remoto entonces vigente.
- Realtime está versionado para `detalle_pedido`, `pedido` y `mesa`; `pago` no se publica.
- `seed.sql` es idempotente y carga cuatro roles, `MIKUY-DEMO`, seis mesas, cinco categorías y diez productos. No crea usuarios Auth ni perfiles.
- Los cuatro usuarios Auth de prueba y sus perfiles se aprovisionan mediante Dashboard y una plantilla SQL manual. No existe un procedimiento versionado completo para crear usuarios productivos.
- `supabase/Carga Inicial/MikuyApp_Carga_Inicial_Maestras.xlsx` contiene maestros para `POOLPOS`: local, una mesa, una categoría y un producto. Es una fuente humana no versionada y no ejecutable; no contiene roles, usuarios Auth, perfiles ni configuración de plataforma.
- No se encontró una exportación versionada de configuración alojada de Auth, URL allow-list, SMTP, restricciones de red, backups, secretos, claves, Realtime u otros ajustes del Dashboard.

La evidencia histórica demuestra reproducibilidad local al cierre de PM-001, pero no demuestra ausencia de drift actual entre repositorio y proyecto Supabase existente. Esa comparación debe ejecutarse de forma no destructiva antes de construir PROD.

## 3. Alcance

### PM002-R01 — Estados y matriz obligatoria de ambientes

PM-002 reconoce tres estados explícitos:

| Estado | Local | Cloudflare Preview | Cloudflare Production | Condición |
|---|---|---|---|---|
| `LEGACY_SHARED` | Supabase actual | Supabase actual | Supabase actual | Estado inicial vigente; el proyecto actual todavía presta producción y no puede considerarse exclusivamente DEV. |
| `TRANSITIONING` | Supabase actual, destino DEV | Supabase actual, destino DEV | Supabase actual hasta el cutover | El PROD nuevo se prepara y valida sin interrumpir Production vigente. |
| `SEPARATED` | DEV actual | DEV actual | PROD nuevo | Cutover aprobado y verificado; separación efectiva. |

La arquitectura final será:

| Consumidor | Supabase permitido |
|---|---|
| Desarrollo local | DEV actual |
| Pruebas técnicas y funcionales | DEV actual o stack local desechable, nunca PROD |
| Demos y usuarios de prueba | DEV actual |
| Cloudflare Preview | DEV actual |
| Cloudflare Production | PROD nuevo |

Ningún desarrollo, prueba, demo ni Preview puede utilizar el PROD nuevo. Durante `LEGACY_SHARED` y `TRANSITIONING`, Production puede seguir usando legítimamente el proyecto actual hasta el cutover. Las guardias no deberán bloquear esa ruta vigente. PM-002 solo se considerará separado cuando se alcance y verifique `SEPARATED`.

### PM002-R02 — DEV / PREVIEW

El proyecto Supabase actual será declarado exclusivamente DEV al alcanzar `SEPARATED`. Durante `LEGACY_SHARED` y `TRANSITIONING` conserva temporalmente su función productiva vigente, además de desarrollo, pruebas, demos y Preview. Conservará sus credenciales, usuarios de prueba y datos existentes. No se limpiará ni reconstruirá salvo necesidad técnica demostrada y aprobada. Local y Preview deberán quedar orientados al destino DEV desde los controles tempranos, sin anticipar el corte de Production.

### PM002-R03 — PROD dedicado

Se creará posteriormente un proyecto Supabase nuevo con credenciales nuevas, acceso administrativo restringido y uso exclusivo por Cloudflare Production. No se copiarán credenciales, usuarios de prueba ni datos transaccionales desde DEV. El esquema se construirá aplicando las 28 migraciones versionadas, más cualquier migración correctiva que PM-002 demuestre necesaria antes de la creación.

### PM002-R04 — Variables públicas por ámbito Cloudflare

Cloudflare Pages deberá definir `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY` separadamente para Production y Preview. En `SEPARATED`, Production apuntará a PROD y Preview a DEV. Durante la transición, Production puede continuar apuntando al proyecto actual. La guardia obligatoria comparará contexto del deployment, estado/identidad lógica del ambiente, URL/project ref efectivo y project ref esperado.

El proceso de build deberá fallar si:

- un build Preview recibe la URL/ref de PROD;
- un build Production recibe la URL/ref de DEV después del cutover, en `SEPARATED`;
- un build Local recibe la URL/ref de PROD;
- falta o no coincide la identidad lógica, el contexto de deployment o el project ref esperado.

No se exigirá derivar ni demostrar criptográficamente que una publishable key pertenece al project ref. La correspondencia URL/key se comprobará mediante configuración, conectividad o smoke test cuando corresponda.

### PM002-R05 — Desarrollo local seguro

`.env.local` continuará ignorado y apuntará a DEV. La documentación y el archivo de ejemplo deberán distinguir variables públicas de frontend y credenciales locales de usuarios de prueba. Ningún valor de PROD se almacenará en `.env.local` de desarrollo habitual. Cualquier operación administrativa contra PROD deberá usar un contexto separado, efímero y explícito.

### PM002-R06 — Frontera de secretos

Solo la URL y publishable key de cada proyecto podrán llegar al frontend. `service_role`, access tokens, contraseñas de base, secretos JWT, claves SMTP y demás secretos administrativos:

- no existirán bajo prefijo `VITE_`;
- no se almacenarán en Git ni en archivos distribuidos a usuarios de prueba;
- no aparecerán en bundle, sourcemaps, artefactos, logs o evidencia;
- residirán únicamente en almacenes de secretos y procesos que los requieran;
- usarán credenciales distintas para DEV y PROD y mínimo privilegio.

### PM002-R07 — Reconstrucción reproducible de esquema

Antes de habilitar PROD se deberá demostrar en una instancia local limpia o proyecto desechable que:

1. las 28 migraciones se aplican en orden desde una base vacía;
2. se crean las 10 tablas, funciones, triggers, constraints, grants, RLS y 27 policies esperadas;
3. Realtime contiene exactamente `detalle_pedido`, `pedido` y `mesa` dentro del alcance MikuyApp, y no `pago`;
4. las pruebas SQL, lint, suite automatizada, typecheck y build pasan;
5. no existen dependencias implícitas de objetos creados manualmente en DEV.

### PM002-R08 — Detección de drift y configuración no versionada

Antes de crear PROD se capturará, sin modificar DEV, un inventario del catálogo y de la configuración alojada. Se comparará con migraciones y archivos versionados. Cualquier objeto o ajuste necesario que exista solo en DEV deberá clasificarse como:

- incorporable mediante migración/configuración versionada;
- configuración operativa documentada y reproducible;
- dato/usuario que no debe promoverse;
- drift accidental que requiere decisión humana.

Una diferencia necesaria bloquea la construcción de PROD hasta ser resuelta. No se permitirá `db pull` o dump aplicado ciegamente sobre migraciones históricas.

### PM002-R09 — Carga inicial de PROD

`seed.sql` conservará su papel de dataset demo para desarrollo/pruebas y no se ejecutará automáticamente en PROD mientras contenga `MIKUY-DEMO`.

El libro `supabase/Carga Inicial/MikuyApp_Carga_Inicial_Maestras.xlsx` será una fuente candidata de información para maestros productivos, no un artefacto ejecutable. PM-002 preparará y ejecutará el mecanismo más sencillo que sea controlado, reproducible y seguro para cargar los maestros iniciales aprobados necesarios para habilitar PROD. Durante construcción se deberá:

- validar y aprobar su contenido final;
- conservar una fuente aprobada y validarla antes de escribir;
- cargar roles requeridos, local, mesas, categorías y productos de forma transaccional y con control de duplicados/idempotencia cuando corresponda;
- mantener fuera del libro los UUID Auth y secretos;
- producir evidencia de conteos y reconciliación.

No se exige un loader genérico, reutilizable, con dry-run o hashes salvo que la evidencia de construcción demuestre que esa es la alternativa más sencilla y proporcionada.

El archivo actual es insuficiente como carga final porque contiene una sola fila por maestro y su estado no está versionado.

### PM002-R10 — Usuarios Auth y perfiles de PROD

Los usuarios productivos serán cuentas nuevas, creadas mediante un procedimiento administrativo controlado. No se copiarán las cuatro cuentas de prueba de DEV. El procedimiento deberá vincular cada `auth.users.id` con `perfil_usuario`, local y rol mediante la plantilla/patrón aprobado, sin persistir UUID, correo o contraseña en el repositorio. Se validarán `ADMINISTRADOR`, `MOZO`, `COCINA` y `CAJA` con cuentas productivas autorizadas.

### PM002-R11 — Configuración alojada de Supabase

La construcción deberá inventariar y fijar explícitamente, por ambiente, al menos:

- región y versión mayor PostgreSQL compatible;
- Auth: signup, confirmaciones, redirects/site URL, proveedores y política de contraseñas;
- URL de Production y Preview autorizadas cuando aplique;
- Realtime y publicación;
- exposición de API, grants y schemas;
- restricciones de red/SSL para accesos administrativos;
- backups/retención disponibles según el plan elegido;
- SMTP, Storage, Edge Functions, hooks, Vault y secretos, aunque el resultado sea “no usado”.

Los defaults locales de `config.toml` no se asumirán equivalentes a la configuración alojada.

### PM002-R12 — Promoción y activación controlada

La transición seguirá la secuencia `LEGACY_SHARED → TRANSITIONING → SEPARATED` mediante una checklist con captura previa, construcción, carga inicial, usuarios, pruebas, configuración de Cloudflare Production, smoke test y rollback. Preview permanecerá conectado al proyecto actual destinado a DEV. Production seguirá usando ese mismo proyecto durante `TRANSITIONING` y solo cambiará al PROD nuevo en el cutover aprobado.

Restaurar automáticamente las variables de Cloudflare Production al proyecto anterior solo es un rollback simple mientras el PROD nuevo no haya aceptado escrituras productivas. Después de la primera escritura real en PROD, cualquier retorno requiere una decisión específica de recuperación por posible divergencia de datos; no se ejecutará automáticamente.

### PM002-R13 — Observabilidad sin exposición

Las verificaciones podrán registrar nombre lógico de ambiente y project ref parcialmente enmascarado, nunca claves ni tokens. La aplicación no mostrará credenciales, tokens, UUID Auth ni información administrativa en páginas técnicas o errores.

### PM002-R14 — Regresión funcional

La separación no modificará el flujo mesa → pedido → cocina → entrega → pago. Después de la construcción se validarán autenticación por roles, aislamiento, Realtime, pago único, terminalidad y el flujo integral en DEV/Preview y PROD.

### PM002-R15 — Documentación maestra

Al implementar PM-002 se actualizarán como mínimo:

- `README.md` y `supabase/README.md`;
- `docs/PLAN_MVP.md`, porque hoy declara una única arquitectura productiva y un único Supabase Free;
- `docs/POST_MVP_CHANGELOG.md` cuando PM-002 sea aceptado/desplegado;
- documentación de despliegue, runbook de carga y usuarios, matriz de variables y recuperación;
- `specs/README.md`.

PM-002 no se marcará completado ni se creará `acceptance.md` hasta pruebas humanas y aprobación explícita.

## 4. Exclusiones

- Replicación, sincronización o refresh PROD ↔ DEV.
- Copias periódicas de datos productivos hacia DEV y anonimización.
- Supabase Branching, Read Replicas y restauraciones periódicas entre ambientes.
- Backups usados como mecanismo de sincronización.
- Nuevas funcionalidades operativas o cambios al flujo principal.
- Copiar usuarios, credenciales o transacciones de DEV a PROD.
- Limpiar o reconstruir DEV sin necesidad técnica aprobada.

## 5. Riesgos y dependencias

| ID | Riesgo/dependencia | Tratamiento obligatorio |
|---|---|---|
| PM002-RSK01 | Cloudflare está fuera de Git y no puede auditarse desde el checkout. | Inventario autenticado y capturas/exportación de ámbitos antes del cambio. |
| PM002-RSK02 | No hay guardia Preview → PROD. | Validación build-time por ambiente y project ref, más prueba negativa. |
| PM002-RSK03 | El proyecto actual puede tener drift posterior a PM-001. | Comparación no destructiva catálogo/configuración antes de PROD. |
| PM002-RSK04 | Auth y perfiles dependen de pasos manuales. | Runbook de mínimo privilegio, doble revisión y reconciliación. |
| PM002-RSK05 | `seed.sql` contiene demo y `config.toml` lo ejecuta en reset. | Prohibir seed demo en PROD y crear carga productiva separada. |
| PM002-RSK06 | El XLSX es no versionado, incompleto y puede cambiar sin trazabilidad. | Aprobar snapshot/fuente y versionar validación/conversión durante construcción. |
| PM002-RSK07 | Las claves públicas son visibles por diseño y pueden confundirse. | Separación por ámbito, identidad/ref explícitos y smoke test de configuración; sin exigir prueba criptográfica URL/key. |
| PM002-RSK08 | Secretos administrativos pueden filtrarse por CI/logs. | Secret scanning, redacción, permisos mínimos y ausencia de secretos en builds. |
| PM002-RSK09 | Defaults locales de Auth/red no equivalen al cloud. | Matriz explícita de configuración alojada DEV/PROD. |
| PM002-RSK10 | Cambio de variables Production puede interrumpir servicio o dividir escrituras. | Ventana controlada y smoke test; rollback simple solo antes de escrituras reales en PROD, luego decisión específica de recuperación. |

## 6. Asuntos pendientes de decisión humana

Antes de crear PROD:

1. Aprobar organización/proyecto, región, plan y responsables administrativos de Supabase PROD.
2. Elegir el manejo/almacén de secretos administrativos de migración y operación.

Antes de habilitar PROD:

3. Aprobar la configuración productiva de Auth: signup, confirmación de correo, política de contraseña, redirects y SMTP.
4. Aprobar el contenido final de maestros `POOLPOS` y la fuente controlada que se utilizará.
5. Definir las identidades reales y el canal seguro para alta inicial de usuarios productivos.

Antes del cutover:

6. Aprobar la ventana, responsables, criterio de primera escritura, recuperación/rollback y autorización explícita del cambio de Cloudflare Production.

Estos asuntos no impiden cerrar el Spec; sí bloquean las tareas de construcción correspondientes.

## 7. Criterios de salida de PM-002

- Estado `SEPARATED` verificado: Local/Preview → DEV actual y Production → PROD nuevo, sin rutas Preview/Local → PROD.
- PROD nuevo reconstruido desde migraciones versionadas y configuración documentada.
- Drift necesario resuelto y evidencia de 28 migraciones completas o baseline posterior aprobado.
- Carga productiva y usuarios productivos reconciliados sin copiar datos/usuarios de DEV.
- RLS, 27 policies, funciones, grants, Realtime y roles aprobados.
- Ausencia de secretos productivos en Git, frontend, bundle, logs y artefactos.
- Regresión funcional y pruebas humanas aprobadas.
- Documentación actualizada y aprobación explícita antes de `acceptance.md`.

## 8. Trazabilidad

R01–R06 → D01–D04, T02–T05/T12–T13, TP01–TP12/TP33–TP36; R07–R11 → D05–D08, T06–T11, TP13–TP32; R12–R14 → D09–D10, T12–T13, TP33–TP39/TP41; R15 → D11, T14, TP40. Riesgos RSK01–RSK10 se verifican en T01–T14 y en la checklist humana.
