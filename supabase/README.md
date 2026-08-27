# Supabase en MikuyApp

Este directorio contiene el esquema PostgreSQL versionado, los datos demo y las verificaciones SQL del proyecto.

## Estructura

```text
supabase/
├── config.toml       Configuración de Supabase CLI
├── seed.sql          Datos demo idempotentes
├── migrations/       Migraciones aplicadas en orden por timestamp
├── tests/            Pruebas SQL ejecutables contra el esquema migrado
├── templates/        Plantillas para procedimientos manuales controlados
└── .temp/            Estado local generado por Supabase CLI; no se versiona
```

## Reglas de uso

- No modificar una migración que ya haya sido aplicada remotamente; crear una nueva migración con timestamp posterior.
- Mantener `seed.sql` idempotente y libre de usuarios Auth, credenciales y datos transaccionales permanentes.
- Mantener las pruebas SQL en `tests/` para conservar la ruta estándar de Supabase.
- Los archivos `*.template.sql` no son migraciones ni seeds. Deben copiarse al SQL Editor y completarse únicamente según su procedimiento documentado.
- No guardar UUID Auth reales, correos, contraseñas, tokens ni claves privadas en el repositorio.

## Contenido actual

- `migrations/`: H1 — esquema inicial; H2 — contexto, privilegios y RLS; H3-T01 — estado por detalle y unicidad de pedido vigente.
- `tests/`: verificaciones históricas de H1/H2 y validación del modelo H3-T01.
- `templates/`: aprovisionamiento de perfiles H2 y preparación/limpieza manual de fixtures H2-T19.

Antes de usar una plantilla manual, se debe leer el encabezado del archivo y el documento del hito correspondiente.
