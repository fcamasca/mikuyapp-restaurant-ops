# DB-Standardization — Despliegue

## Estado

**DEPLOYED**

- Fecha y hora: 2026-08-31 22:22:43 -05:00 (America/Lima).
- Proyecto: `mikuyapp` (`ibf…uinf`), Supabase remoto, región `sa-east-1`.
- Migración aplicada: `20260831000100_dbstd_t02_authenticated_context_hardening.sql`.
- Supabase CLI: 2.115.0.

## Estado previo

- Proyecto vinculado y saludable.
- Las 27 migraciones H1–H6 coincidían en los historiales local y remoto.
- La única migración pendiente era DBSTD `20260831000100`.
- El dry-run confirmó una sola migración, sin seeds ni roles.

## Aplicación

`supabase db push --linked` aplicó exclusivamente `20260831000100_dbstd_t02_authenticated_context_hardening.sql`. No se ejecutaron seed, reset, fixtures, pruebas con DML, concurrencia ni rollback.

## Validaciones posteriores no destructivas

- Historial remoto: 28/28 migraciones; DBSTD registrada como `20260831000100`.
- Las tres RPC H6 usan `public.obtener_contexto_autenticado()`, no contienen resolución directa de perfil/rol y conservan sus firmas y tipos de retorno.
- El hardening `42501 / No autorizado` está presente en las tres definiciones.
- Las cuatro funciones aprobadas tienen `provolatile = 's'`, `SECURITY DEFINER`, `search_path = pg_catalog`, owner `postgres`, `EXECUTE` para `authenticated` y sin `EXECUTE` para `anon`/`PUBLIC`.
- Catálogo: exactamente 16 comentarios DBSTD, con identidades y textos aprobados.
- RLS continúa habilitado en las 10 tablas de `public`; existen exactamente 27 policies.
- La migración no contiene DDL/DML de tablas, constraints, índices, RLS, policies, triggers o datos, ni altera grants de tablas/columnas.
- `registrar_auditoria_detalle_pedido()` conserva `md5(prosrc) = e5995bb64d37ba0f5f3a255e84fa354f`, `SECURITY DEFINER`, `search_path = pg_catalog` y owner `postgres`.
- `detalle_pedido_registrar_auditoria` conserva `BEFORE INSERT OR DELETE OR UPDATE`, nivel fila y vínculo con la misma trigger function.
- No se alteró la semántica vigente de `pedido.modificado_en`/`pedido.modificado_por`.
- La migración emitió `NOTIFY pgrst, 'reload schema'` dentro de la transacción aplicada.

Las huellas MD5 globales de policies y grants de tablas/columnas no se compararon entre local y remoto porque incorporan OID de roles y privilegios administrados por la plataforma, por lo que no son portables entre entornos. Se validaron los criterios portables anteriores y el alcance SQL exacto de la migración.

## Resultado

DBSTD quedó desplegada y validada en Supabase remoto. No se desplegó frontend ni Cloudflare Pages. No se ejecutó rollback y esta evidencia no autoriza despliegues adicionales.
