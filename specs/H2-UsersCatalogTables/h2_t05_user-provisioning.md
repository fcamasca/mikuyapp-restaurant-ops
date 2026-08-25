# MikuyApp — H2 / T05: provisión manual de usuarios de prueba

## Objetivo y límites

Crear manualmente cuatro cuentas Supabase Auth y asociar exactamente un perfil activo por cuenta para los roles `ADMINISTRADOR`, `MOZO`, `COCINA` y `CAJA` del local `MIKUY-DEMO`. Este procedimiento no crea usuarios desde seed, frontend, migraciones o `service_role`; tampoco implementa funciones PostgreSQL, privilegios ni RLS.

La plantilla versionada es `supabase/h2_user_profiles.template.sql`. Sus cuatro parámetros UUID permanecen en `NULL`; ejecutarla sin sustituirlos aborta la transacción antes de modificar perfiles. Los valores reales solo deben escribirse en una copia temporal abierta dentro de Supabase Dashboard.

## Requisitos previos

El usuario responsable debe tener acceso administrativo al proyecto Supabase `mikuyapp`, a **Authentication → Users** y a **SQL Editor**. H1 debe contener el local activo `MIKUY-DEMO` y los cuatro roles activos. Correos, contraseñas y UUID Auth reales se conservan exclusivamente en un medio seguro fuera del repositorio, Git, build y logs.

## Procedimiento manual exacto

1. Abrir Supabase Dashboard e ingresar al proyecto `mikuyapp`.
2. Entrar a **Authentication → Users**.
3. Crear manualmente una cuenta para cada rol: `ADMINISTRADOR`, `MOZO`, `COCINA` y `CAJA`. No habilitar registro público ni crear más cuentas para esta tarea.
4. Conservar los correos y contraseñas fuera del repositorio; no introducirlos en archivos, commits, capturas o registros.
5. Copiar temporalmente los UUID Auth de las cuatro cuentas desde **Authentication → Users**.
6. Abrir **SQL Editor** dentro del mismo proyecto Supabase.
7. Copiar el contenido de `supabase/h2_user_profiles.template.sql` y pegarlo en una consulta temporal del editor.
8. Dentro de esa consulta temporal, sustituir únicamente los cuatro `NULL` de `v_administrador_uuid`, `v_mozo_uuid`, `v_cocina_uuid` y `v_caja_uuid` por los UUID correspondientes. No modificar la plantilla versionada.
9. Revisar la correspondencia entre cada UUID y su rol; ejecutar la consulta solamente desde el Dashboard.
10. Comprobar que el resultado informa: **cuatro perfiles activos, cuatro roles diferentes y un único local MIKUY-DEMO**. Si falta un usuario, rol, local o existe un UUID duplicado, la transacción falla completamente.
11. Si se requiere una segunda comprobación visual, revisar los perfiles desde la interfaz administrativa del proyecto sin exportar UUID ni correos a archivos locales.
12. Descartar la consulta temporal rellenada y cualquier copia local accidental que contenga valores reales; no agregar secretos, UUID Auth ni correos al repositorio.
13. Informar al responsable de implementación que las cuatro cuentas y sus perfiles quedaron creados. T05 solo podrá marcarse como completada después de esta confirmación humana.

## Propiedades de la plantilla

- Transaccional: `BEGIN`, bloque administrativo `DO` y `COMMIT`; cualquier error aborta todos los cambios.
- Idempotente: `INSERT ... ON CONFLICT (id) DO UPDATE`, conservando una sola fila por UUID.
- Resuelve `rol.id` exclusivamente a partir de los cuatro códigos aprobados y `local.id` mediante `MIKUY-DEMO`.
- Rechaza marcadores `NULL`, UUID duplicados, usuarios Auth inexistentes, roles/local inactivos o ausentes y resultados finales incompletos.
- Usa nombres funcionales genéricos: Administrador de prueba, Mozo de prueba, Cocina de prueba y Caja de prueba.
- No contiene correos, contraseñas, UUID reales, tokens, claves privadas ni `service_role`.
- No modifica el seed, migraciones, políticas RLS, funciones o datos históricos.

## Estado

**T05 permanece pendiente** hasta que una persona autorizada complete el procedimiento en Supabase Dashboard y confirme la creación/asociación de las cuatro cuentas.
