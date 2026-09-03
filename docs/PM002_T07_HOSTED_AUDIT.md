# PM-002 — T07 Auditoría alojada y drift

## Estado

**COMPLETADA.** Auditoría realizada mediante lectura y evidencia manual confirmada por el usuario. No se modificaron Supabase, Cloudflare, variables, grants, migraciones ni datos.

## Supabase alojado verificado

Proyecto actual: `mikuyapp`, AWS `sa-east-1`, plan Free, project ref registrado solo como `ibfr…uinf`.

| Área | Evidencia observada | Clasificación / acción futura |
|---|---|---|
| Migraciones | 28/28 versiones locales y remotas alineadas. | Baseline reproducible; reproducir en PROD mediante las migraciones existentes. |
| Esquema público | Dumps local/remoto coinciden en objetos lógicos; 10 tablas, 17 funciones, 2 triggers, RLS 10/10, 27 policies y publicación Realtime esperada. | Necesario para PROD; ya está representado por Git. |
| Grants/default privileges | Remoto concede `ALL` a `service_role` sobre funciones, tablas y secuencias y defaults más amplios; local reconstruido muestra un subconjunto. | Comportamiento/configuración administrada de la plataforma observado en el proyecto alojado. Debe verificarse nuevamente en el futuro PROD; no crear una migración para forzarlo sin evidencia de que Supabase no lo aplica automáticamente. |
| Owners | No se detectó diferencia en el dump de esquema. | Reproducido por plataforma/migraciones; volver a verificar tras crear PROD. |
| Extensiones habilitadas | `pgcrypto`, `uuid-ossp`, `plpgsql`, `pg_stat_statements`. | Configuración alojada esperada; comprobar automáticamente en PROD. El resto de extensiones visibles estaba deshabilitado. |
| Auth signup | Signup habilitado; acceso anónimo y linking manual deshabilitados. | Configuración operativa que debe decidirse/reproducirse antes de habilitar PROD. |
| Auth email | Email habilitado y confirmación de correo habilitada. Cambio seguro de email habilitado; reautenticación y contraseña actual para cambiar contraseña, deshabilitados. | Configuración operativa a reproducir o aprobar expresamente. |
| Política de contraseña | Mínimo 6 caracteres; sin requisitos adicionales seleccionados; protección HIBP deshabilitada. OTP: 8 dígitos y 3600 segundos. | Configuración operativa; requiere decisión previa a habilitar PROD. HIBP no está disponible en el plan actual. |
| Proveedores Auth | Solo Email habilitado. Phone, SAML, Web3 y proveedores sociales/OIDC listados están deshabilitados; no hay proveedores custom. | `NO USADO` para los proveedores deshabilitados. |
| URL Auth | Site URL `http://localhost:3000`; no hay redirect URLs permitidas. | Drift/configuración DEV; no debe promoverse literalmente. PROD requiere Site URL y redirects aprobados. |
| SMTP | SMTP custom deshabilitado. | `NO USADO`; decidir antes de habilitar PROD si se mantiene el envío administrado. |
| Auth hooks | No existen hooks configurados. | `NO USADO`. |
| Data API | Habilitada; schemas `public` y `extensions`; búsqueda extra `public, extensions`; máximo 1000 filas; exposición automática de nuevas tablas habilitada. | Configuración operativa relevante. Debe revisarse el hardening antes de PROD; no se modificó. |
| Storage | No existen buckets. | `NO USADO`. |
| Edge Functions | No hay funciones desplegadas. | `NO USADO`. |
| Edge secrets | No existen secretos custom; solo aparecen secretos reservados administrados por Supabase. | `NO USADO` para secretos custom; nunca copiar valores reservados. |
| Vault | Integración instalada, sin secretos registrados. | `NO USADO`. |
| SSL | Enforce SSL para conexiones entrantes está deshabilitado. | Configuración operativa/riesgo a decidir antes de PROD. |
| Restricciones de red | Sin restricciones; base accesible desde cualquier IP. Sin IP bloqueadas. | Configuración operativa/riesgo a decidir antes de PROD. |
| Logging de conexiones | Logging de conexiones y desconexiones deshabilitado. | Configuración operativa. |
| Pool | Nano; pool 15 y máximo 200 clientes administrado por compute. | Configuración administrada/operativa; no copiar como DDL. |
| Backups | Plan Free sin backups de proyecto ni retención disponible. | Riesgo bloqueante para definir plan/retención antes de crear PROD. |

## Cloudflare Pages

Estado clasificado: **`LEGACY_SHARED`**.

| Área | Evidencia confirmada | Clasificación / acción futura |
|---|---|---|
| Scopes | Ámbitos separados `Production` y `Preview`. | Configuración operativa legítima; permite preparar T12 y T13 independientemente. |
| Production | Rama `main`; deployments automáticos habilitados. | Configuración operativa vigente. |
| Preview | Todas las ramas distintas de Production. | Configuración operativa vigente. |
| Build | Comando `npm run build`, salida `dist`, root directory vacío. | Coherente con el repositorio; el nuevo `prebuild` se ejecutará automáticamente. |
| Variables Production | `NODE_VERSION`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_SUPABASE_URL`. | Configuración pública vigente; apunta al proyecto actual `ibfr…uinf`. |
| Variables Preview | `NODE_VERSION`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_SUPABASE_URL`. | Configuración pública vigente; apunta al mismo proyecto actual `ibfr…uinf`. |
| Variables de guardia | No están configuradas en ninguno de los dos scopes. | Dependencia operativa conocida: agregarlas primero en Preview durante T12 y posteriormente en Production durante T13. |
| Historial/auditoría de variables | No disponible con la evidencia/acceso actual. | **N/A para PM002-TP06**: no se asumen datos históricos; el inventario se basa en la configuración vigente confirmada. |

Production y Preview usan actualmente el mismo Supabase compartido. El proyecto no adquiere condición exclusiva de DEV mientras Production continúe apuntándolo.

## Riesgo de la guardia `prebuild`

La guardia se ejecuta antes de cada `vite build`.

- Preview de `feature/Environment-Separation`: con la configuración vigente fallará porque no existen las variables adicionales de estado, identidad lógica y refs esperados. Con la matriz de T12 debe aceptar Preview → proyecto actual.
- Production actual: si este código se publica con la configuración vigente, el build fallará por configuración incompleta. Esto protege el despliegue, pero exige preparar su scope antes de publicar la guardia en Production.
- Antes de T12: declarar para Preview `LEGACY_SHARED` o `TRANSITIONING`, identidad `DEV`, ref esperado/DEV del proyecto actual y conservar URL/key públicas coherentes.
- Antes de T13: mientras Production siga en el proyecto compartido, declarar identidad `SHARED` y ref compartido. Solo después del cutover aprobado se cambia a `SEPARATED`, identidad `PROD` y ref PROD.

No se recomienda desplegar la guardia a Cloudflare hasta preparar los nombres requeridos en el scope correspondiente.

## Criterio de cierre

T07 queda completada: Supabase alojado, Cloudflare vigente y las diferencias relevantes fueron inventariados y clasificados. No quedó una dependencia productiva desconocida exclusiva del proyecto actual.

Permanecen como puertas conocidas antes de T09 las decisiones ya previstas por el Spec: organización, región, plan/retención de backups, administradores y manejo de secretos. La configuración Auth, URLs, SMTP, SSL/red y Data API debe aprobarse antes de habilitar PROD según su puerta correspondiente. Ninguna de estas decisiones reabre T07.
