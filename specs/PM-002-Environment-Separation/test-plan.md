# MikuyApp — PM-002 Separación de ambientes DEV/Preview y PROD: plan de pruebas

## 1. Estrategia

La validación combina pruebas estáticas, builds sintéticos, reconstrucción local/desechable, catálogo PostgreSQL, seguridad, integración, regresión funcional y verificación humana. Ninguna prueba destructiva se ejecutará sobre DEV o PROD. La prueba de reconstrucción se hará primero en una instancia local o proyecto desechable y sin `seed.sql` demo.

La evidencia deberá redactar claves, tokens, contraseñas, UUID Auth y URLs sensibles. Los refs podrán mostrarse parcialmente. Las pruebas distinguirán `LEGACY_SHARED`, `TRANSITIONING` y `SEPARATED` para no bloquear Production vigente antes del cutover.

## 2. Gobierno y baseline

| ID | Caso | Resultado esperado |
|---|---|---|
| PM002-TP01 | Revisar estados y puertas de decisión. | `LEGACY_SHARED`, `TRANSITIONING` y `SEPARATED` tienen entradas/salidas claras; cada decisión bloquea solo su fase material. |
| PM002-TP02 | Revisar alcance/exclusiones. | No hay replicación, sincronización, limpieza DEV ni cambio funcional encubierto. |

## 3. Matriz de variables y Cloudflare

| ID | Caso | Resultado esperado |
|---|---|---|
| PM002-TP03 | Inventariar variables Cloudflare por scope y estado. | En transición, Preview y Production pueden usar el proyecto actual; en `SEPARATED`, Preview usa DEV y Production PROD; no existe valor global ambiguo. |
| PM002-TP04 | Resolver el host/ref efectivo de un deployment Preview. | Coincide con DEV y difiere de PROD. |
| PM002-TP05 | Resolver el host/ref efectivo de Production por estado. | Coincide con el proyecto actual en `LEGACY_SHARED`/`TRANSITIONING` y con PROD en `SEPARATED`. |
| PM002-TP06 | Revisar historial/auditoría de variables. | Cambios atribuibles; valores secretos no aparecen en capturas/logs. |
| PM002-TP07 | Build Preview con variables DEV válidas. | Build aprobado. |
| PM002-TP08 | Build Production con combinación válida para el estado. | Proyecto actual aprobado antes del cutover; PROD aprobado en `SEPARATED`. |
| PM002-TP09 | Build Preview con URL/ref PROD. | Falla antes del deployment con error redactado. |
| PM002-TP10 | Build Production con URL/ref del proyecto actual compartido. | Permitido durante `LEGACY_SHARED`/`TRANSITIONING`; Production → DEV exclusivo falla después del cutover en `SEPARATED`. |
| PM002-TP11 | Contexto, identidad lógica, URL/ref efectivo o ref esperado ausente/inconsistente. | Falla de configuración; no se crea artefacto publicable. No se exige prueba criptográfica de pertenencia de la key. |
| PM002-TP12 | Desarrollo local con `.env.local`. | Arranca contra DEV; intento de declarar PROD se rechaza. |

## 4. Reconstrucción de esquema

| ID | Caso | Resultado esperado |
|---|---|---|
| PM002-TP13 | Crear base vacía PostgreSQL 17 y aplicar migraciones ordenadas. | Todas las 28 migraciones/baseline aprobado aplican sin intervención manual. |
| PM002-TP14 | Confirmar que el ensayo PROD omite `seed.sql`. | No existe `MIKUY-DEMO` ni dato demo después de migrar. |
| PM002-TP15 | Inventariar tablas, constraints, índices, secuencias y triggers. | Coinciden con baseline PM-001/H1–H6; 10 tablas públicas. |
| PM002-TP16 | Inventariar funciones, firmas, owner, volatilidad, `SECURITY DEFINER`, `search_path` y grants. | Contratos y hardening PM-001 coinciden; ninguna concesión inesperada. |
| PM002-TP17 | Inventariar RLS y policies. | RLS activa en 10/10 tablas y exactamente 27 policies esperadas. |
| PM002-TP18 | Inventariar Realtime. | Publicadas `detalle_pedido`, `pedido`, `mesa`; `pago` no publicada. |
| PM002-TP19 | Ejecutar todos los SQL tests, incluidos concurrencia y PM-001. | Cero fallos y cero fixtures residuales. |
| PM002-TP20 | Ejecutar lint, 297+ pruebas automatizadas, typecheck y build. | Todo aprobado; cualquier aumento legítimo de conteo queda documentado. |

## 5. Drift y configuración alojada

| ID | Caso | Resultado esperado |
|---|---|---|
| PM002-TP21 | Comparar catálogo reconstruido con DEV sin modificarlo. | Toda diferencia está clasificada y ninguna dependencia productiva queda solo en DEV. |
| PM002-TP22 | Comparar historial de migraciones. | DEV contiene el baseline esperado sin migración desconocida indispensable. |
| PM002-TP23 | Revisar Auth, redirects, SMTP, API, red/SSL, Realtime, Storage, hooks, Edge, Vault y backups. | Matriz DEV/PROD completa; cada ítem tiene valor aprobado o “no usado” explícito. |

## 6. Carga inicial y Auth

| ID | Caso | Resultado esperado |
|---|---|---|
| PM002-TP24 | Validar estructura y contenido aprobado de la fuente maestra. | Códigos, nombres, orden, referencias y precios válidos; ausencia de secretos/UUID Auth. |
| PM002-TP25 | Validar previamente el mecanismo acotado de carga. | Fuente y operaciones previstas son reproducibles y seguras; dry-run solo si la solución elegida lo requiere. |
| PM002-TP26 | Aplicación inicial en entorno desechable/PROD autorizado. | Roles, local, mesas, categorías y productos se aplican transaccionalmente. |
| PM002-TP27 | Reejecutar o comprobar control de duplicados según el mecanismo elegido. | No se crean duplicados; idempotencia cuando corresponda y reconciliación consistente. |
| PM002-TP28 | Verificar ausencia de demo/DEV. | No existen `MIKUY-DEMO`, usuarios H2 ni transacciones copiadas. |
| PM002-TP29 | Crear usuarios productivos y perfiles. | Cuentas nuevas vinculadas a local/rol correcto; secretos y UUID no quedan en Git/evidencia. |
| PM002-TP30 | Autenticación por cuatro roles y contexto inválido. | Admin, mozo, cocina y caja acceden solo a capacidades permitidas; inválidos reciben `42501 / No autorizado` según contrato. |

## 7. Seguridad y secretos

| ID | Caso | Resultado esperado |
|---|---|---|
| PM002-TP31 | Escanear Git, working tree relevante, `dist`, sourcemaps, artefactos y logs. | No hay service role, tokens, contraseñas, secretos JWT/SMTP ni credenciales PROD indebidas. |
| PM002-TP32 | Inspeccionar bundle y tráfico del navegador. | Solo URL y publishable key del ambiente; ninguna credencial administrativa. |
| PM002-TP33 | Intentar Preview → PROD mediante variable manipulada. | Guardia bloquea build/deploy; no ocurre solicitud a PROD. |

## 8. Integración y regresión

| ID | Caso | Resultado esperado |
|---|---|---|
| PM002-TP34 | Local: login y consulta técnica controlada. | Evidencia inequívoca de conexión a DEV. |
| PM002-TP35 | Preview: login, catálogo y operación de prueba. | Toda escritura aparece solo en DEV. |
| PM002-TP36 | Production: login con usuarios productivos y catálogo aprobado. | Toda operación aparece solo en PROD; ningún dato DEV visible. |
| PM002-TP37 | RLS/aislamiento y operaciones por rol en PROD. | Acceso cruzado rechazado; privilegios mínimos preservados. |
| PM002-TP38 | Realtime cocina/mozo/caja. | Señales de las tres tablas publicadas y resync autoritativo; `pago` no se publica. |
| PM002-TP39 | Flujo integral mesa → pedido → cocina → entrega → pago y reapertura previa al pago. | Flujo H1–H6 sin regresión, pago único, terminalidad y mesa libre final. |

## 9. Documentación y verificación humana

| ID | Caso | Resultado esperado |
|---|---|---|
| PM002-TP40 | Revisar README, plan, changelog, Supabase README, runbooks, matriz y specs. | La arquitectura oficial y los procedimientos coinciden con lo desplegado; PM-002 no figura aceptado antes de aprobación. |

## 10. Rollback y recuperación

| ID | Caso | Resultado esperado |
|---|---|---|
| PM002-TP41 | Ensayar decisión ante falla de cutover antes y después de la primera escritura real en PROD. | Antes de escrituras, restaurar variables anteriores es rollback simple hacia `TRANSITIONING`; después de una escritura, el retorno automático está prohibido y se exige una decisión específica de recuperación por divergencia. |

La verificación humana debe confirmar explícitamente:

1. desarrollo local conectado a DEV;
2. un deployment Preview conectado a DEV;
3. Production conectado a PROD;
4. nombres/refs visibles de forma segura y distintos;
5. usuarios de prueba incapaces de acceder a PROD;
6. flujo integral y Realtime en dispositivos previstos;
7. antes de la primera escritura productiva en PROD, capacidad de restaurar las variables previas de Production sin destruir datos.

## 11. Comparaciones y evidencia

Conservar:

- commit/baseline y lista ordenada de migraciones;
- inventarios de catálogo antes/después y clasificación de drift;
- matriz de configuración alojada DEV/PROD;
- resultados de builds positivos/negativos;
- validación de fuente, conteos y reconciliación de carga inicial;
- resultados SQL, lint, automatizados, typecheck y build;
- secret scan redactado;
- capturas de scopes Cloudflare sin valores sensibles;
- checklist humana firmada.

## 12. Criterios de aprobación

- PM002-TP01–TP41 aprobadas o marcadas no aplicables con justificación aceptada.
- Cero Preview/local/demo conectado a PROD.
- Cero secreto productivo indebido en frontend, Git, bundle, artefactos o logs.
- Baseline reproducible y drift necesario resuelto.
- RLS, policies, funciones, Realtime, Auth por roles y flujo integral aprobados.
- Cero defecto bloqueante.
- Aprobación explícita del usuario antes de crear `acceptance.md`.
