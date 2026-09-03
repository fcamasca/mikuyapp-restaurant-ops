# PM-002 — Ambientes y guardia durante la separación

## Estado registrado

Estado vigente: **`LEGACY_SHARED`**.

El contexto confirmado para este bloque es:

| Consumidor | Proyecto actual | Identidad lógica | Evidencia disponible |
|---|---|---|---|
| Desarrollo local | Supabase actual compartido | `DEV` como destino | `.env.local` ignorado y vínculo local de Supabase CLI; refs coincidentes verificados sin publicar valores. |
| Cloudflare Preview | Supabase actual compartido | `DEV` como destino | Contexto operativo confirmado; valores/scopes del proveedor no están versionados. |
| Cloudflare Production | Supabase actual compartido | `SHARED` | Contexto operativo confirmado; no se modificó ni inspeccionó un valor sensible. |

El proyecto actual todavía presta Production. No se denomina DEV exclusivo hasta el cutover verificado.

## Rutas permitidas por estado

| Estado | Local | Preview | Production |
|---|---|---|---|
| `LEGACY_SHARED` | actual / `DEV` | actual / `DEV` | actual / `SHARED` |
| `TRANSITIONING` | actual / `DEV` | actual / `DEV` | actual / `SHARED` |
| `SEPARATED` | DEV actual / `DEV` | DEV actual / `DEV` | PROD nuevo / `PROD` |

No existe replicación, refresh ni sincronización. PM-002 permanece en `LEGACY_SHARED` durante T02–T07.

## Variables

| Nombre | Uso | Clasificación |
|---|---|---|
| `VITE_SUPABASE_URL` | URL efectiva; la guardia extrae su project ref | Pública de frontend |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Cliente público; solo se valida presencia | Pública de frontend |
| `MIKUY_ENVIRONMENT_STATE` | `LEGACY_SHARED`, `TRANSITIONING` o `SEPARATED` | Metadato de build |
| `MIKUY_LOGICAL_ENVIRONMENT` | `DEV`, `SHARED` o `PROD` | Metadato de build |
| `MIKUY_EXPECTED_SUPABASE_PROJECT_REF` | Ref esperado del deployment | Metadato de build |
| `MIKUY_DEV_SUPABASE_PROJECT_REF` | Ref permitido para Local/Preview | Metadato de build |
| `MIKUY_SHARED_SUPABASE_PROJECT_REF` | Ref permitido para Production antes del cutover | Metadato de build |
| `MIKUY_PROD_SUPABASE_PROJECT_REF` | Ref permitido para Production después del cutover | Metadato futuro; vacío mientras PROD no existe |
| `MIKUY_PRODUCTION_BRANCH` | Rama Production de Cloudflare, `main` por defecto | Metadato de build |

Cloudflare deriva el contexto real con `CF_PAGES=1` y `CF_PAGES_BRANCH`. Fuera de Cloudflare, el contexto es Local. Local puede obtener el ref DEV esperado desde `supabase/.temp/project-ref`; Cloudflare debe declarar los refs por scope.

La guardia no intenta vincular criptográficamente la publishable key con un proyecto. Esa correspondencia requiere configuración/conectividad o smoke test. Los mensajes de error no muestran URL, key ni ref completo.

## Desarrollo local

`.env.local` continúa ignorado y contiene únicamente configuración pública del proyecto actual y, cuando se necesitan verificaciones, credenciales de usuarios de prueba DEV. Los valores de PROD no pertenecen al archivo habitual. Una futura operación administrativa contra PROD usará un contexto separado, efímero y explícito.

Ejecutar:

```bash
npm run test:environment
npm run build
```

`predev` y `prebuild` ejecutan automáticamente la guardia. Los secretos administrativos nunca usan `VITE_` ni se almacenan en `.env.example`.
