# PM-002 — Evidencia de ejecución T09

## Estado

**PM002-T09 COMPLETADA.** El proyecto gestionado `mikuyapp-prod` fue creado e inventariado sin aplicar migraciones, seed, datos, usuarios ni configuración funcional productiva.

PM-002 entra formalmente en **`TRANSITIONING`**:

- Local → proyecto actual compartido.
- Preview → proyecto actual compartido.
- Production → proyecto actual compartido.
- `mikuyapp-prod` existe, pero todavía no recibe Production.

No se declara `SEPARATED` y Cloudflare no fue modificado.

## Decisiones humanas aplicadas

| Decisión | Valor aprobado |
|---|---|
| Organización | Organización Supabase actual de MikuyApp |
| Nombre | `mikuyapp-prod` |
| Región | South America (São Paulo), `sa-east-1` |
| Plan | Free |
| Administración Supabase | Solo el propietario actual |
| Administración Cloudflare | Solo el propietario actual; sin cambios en T09 |
| Backups administrados | No requeridos por PM-002; limitación Free aceptada |
| Secretos | Solo mecanismos del proveedor; fuera de Git, `VITE_*` y `.env.local` habitual |

## Identidad y aislamiento

- Estado de plataforma: `ACTIVE_HEALTHY`.
- Project ref PROD redactado: `snfm…pavp`, distinto del actual `ibfr…uinf`.
- PostgreSQL: engine 17, versión alojada observada `17.6.1.166`, canal GA.
- El endpoint y el juego de credenciales públicas pertenecen al nuevo project ref y son distintos de DEV; sus valores no se registran ni versionan.
- Historial de migraciones: vacío; las 28 migraciones MikuyApp no fueron aplicadas.
- Esquema `public`: 0 tablas; no existen tablas ni datos transaccionales MikuyApp.
- Auth: 0 usuarios observados; no se copiaron usuarios o UUID desde DEV.
- `MIKUY-DEMO`, maestros, perfiles y seed demo: ausentes porque no existe esquema MikuyApp ni se ejecutó carga alguna.
- No existe replicación, refresh, sincronización ni vínculo de datos con el proyecto actual.
- El proyecto actual no fue modificado ni relinkado; la CLI local continúa vinculada al proyecto actual.

## Configuración inicial alojada

| Configuración | Estado inicial no sensible | Clasificación | Acción futura |
|---|---|---|---|
| Proyecto/región/plan | `mikuyapp-prod`, `sa-east-1`, Free | `APROBADA EN T09` | Conservar. |
| Compute/PostgreSQL | Nano; PostgreSQL 17 GA | `APROBADA EN T09` | Verificar compatibilidad durante T10. |
| Backups | Free no incluye backups administrados ni retención | `APROBADA EN T09` | Limitación aceptada; respaldo manual queda fuera de PM-002. |
| Auth signup | Habilitado por default | `DEFAULT PENDIENTE DE DECISIÓN` | Aprobar antes de habilitar PROD. |
| Confirmación de correo | Habilitada por default | `DEFAULT PENDIENTE DE DECISIÓN` | Aprobar antes de habilitar PROD. |
| Auth anónimo/linking manual | Ambos deshabilitados | `NO USADO` | Mantener salvo decisión posterior explícita. |
| Proveedores Auth | Email habilitado; Phone, SAML, Web3, sociales/OIDC y custom deshabilitados | `DEFAULT PENDIENTE DE DECISIÓN` | Definir Auth productivo antes de T11. |
| Site URL | `http://localhost:3000` | `DEFAULT PENDIENTE DE DECISIÓN` | No promover como valor PROD; configurar después de aprobación. |
| Redirect URLs | Ninguna | `REQUIERE CONFIGURACIÓN POSTERIOR` | Definir antes de habilitar Auth productivo. |
| SMTP | Custom SMTP deshabilitado | `DEFAULT PENDIENTE DE DECISIÓN` | Aprobar proveedor/canal antes de habilitar PROD. |
| Data API | Habilitada; exposición automática de tablas habilitada; automatic RLS deshabilitado | `DEFAULT PENDIENTE DE DECISIÓN` | Revisar hardening después de aplicar esquema, sin inferir cambios en T09. |
| Esquema API | Sin tablas públicas MikuyApp; schemas administrados/default | `REQUIERE CONFIGURACIÓN POSTERIOR` | Reconciliar en T10 después de migraciones. |
| SSL | Enforce SSL entrante deshabilitado | `DEFAULT PENDIENTE DE DECISIÓN` | Aprobar política antes de habilitar PROD. |
| Red | Sin restricciones IP; acceso desde todas las IP | `DEFAULT PENDIENTE DE DECISIÓN` | Aprobar restricciones antes de habilitar PROD. |
| Pool/logging | Pool 15, máximo 200 clientes; logging de conexiones/desconexiones deshabilitado | `DEFAULT PENDIENTE DE DECISIÓN` | Revisar según operación aprobada. |
| Realtime | Sin publicación de tablas MikuyApp porque no existe el esquema | `REQUIERE CONFIGURACIÓN POSTERIOR` | T10 debe reconstruir y verificar solo las tablas aprobadas. |
| Storage | Sin buckets | `NO USADO` | Ninguna acción en PM-002 salvo decisión explícita. |
| Edge Functions | Sin funciones desplegadas | `NO USADO` | Ninguna acción. |
| Auth Hooks | Sin hooks | `NO USADO` | Ninguna acción. |
| Extensiones activas | `pgcrypto`, `uuid-ossp`, `pg_stat_statements`, `plpgsql` | `DEFAULT PENDIENTE DE DECISIÓN` | Reconciliar con baseline en T10. |
| Vault/secretos custom | Sin secreto productivo registrado por PM-002 | `NO USADO` | Usar solo si una tarea posterior lo aprueba; nunca registrar valores. |

## Pruebas diferidas correctamente

Las validaciones de catálogo MikuyApp, RLS, policies, grants, funciones y Realtime dependen de T10. Auth productivo, maestros, usuarios y perfiles dependen de T11. Smoke de Cloudflare y cutover dependen de T12/T13. No se fabricó evidencia para esas tareas.

## Seguridad

La contraseña de base fue generada mediante el mecanismo de Supabase y no se imprimió, copió ni persistió en Git o documentación. No se consultaron ni registraron secret keys, service-role keys o tokens. Las credenciales públicas PROD tampoco fueron incorporadas al repositorio ni a `.env.local`.
