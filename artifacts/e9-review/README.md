# E9: revisión técnica independiente, 2026-10-01

Rama feature/E9-OperationalDay; HEAD inicial 89b9406827be0bb21a1ede07fa15a2d992cc9748, árbol limpio. Baseline de tests 313794a, migraciones hasta 20260930000200 (59); E9 61 hasta 20261001000200. PostgreSQL efímero 17.6, imagen local public.ecr.aws/supabase/postgres:17.6.1.166, contenedor e9-baseline-audit sin puertos publicados. Stack Supabase real exclusivamente loopback http://127.0.0.1:54321. Nunca linked, DEV compartido o PROD.

## Reproducción

1. Levantar un PostgreSQL efímero con bash, usuario postgres, socket /tmp, puerto 54329 y wal_level=logical; usar la imagen indicada, initdb en /tmp, sin montar datos compartidos.
2. Copiar scripts/, supabase/migrations/, tests y seed del repositorio con finales LF. Exportar los tests baseline mediante git show 313794a:<archivo>.
3. Ejecutar scripts/e10_local_replay.sh para bases distintas, una hasta 20260930000200 y otra all; correr e10_local_sql_suite.sh con los tests de cada lado. Conservar cada salida. comparison.json enumera cada fallo con ambos errores.
4. Para e9_concurrency.sh y e9_t02_precondicion.sh usar plantillas NUEVAS y limpias; nunca las bases pobladas por la suite. Las salidas sin sufijo clean muestran el intento incorrecto con plantillas pobladas, se conservan y se excluyen de conclusiones.
5. Diagnóstico complementario en copias de tests: mismos cambios 40001→PT409, texto/comportamiento de auditoría E7 y publicación E10 que scripts/e9_t07_campaign.sh §6. No modifica tests versionados, no es criterio de aceptación.
6. En Windows: powershell -ExecutionPolicy Bypass -File scripts\e9_t06_local.ps1. Usa únicamente Supabase local y hace reset local. SQL 4/4, Realtime 7/7, typecheck/build PASS.
7. node --experimental-strip-types --test tests/*.test.mjs: 430/430 PASS.

## Evidencia

suite-base.txt: 46 PASS / 23 FAIL. suite-e9.txt: revisión inicial 52/21. suite-final.txt: homologación final 52/21. comparison.json: 21/21 nombres reproducen, ninguno nuevo; dos deltas de contrato homologados descritos en implementation.md §9.3. diag-base.txt 57/12, diag-e9.txt 61/12, mismos nombres restantes. hz-base/e9.txt: 42883 idéntico. defs-clean-*.txt: mismas definiciones previas, once añadidas. concurrency-clean.txt 13/13; precondition-clean.txt 4/4. node.txt 430/430. realtime-final.txt y local-final.txt: ejecución desde reset completo, cinco confirmaciones CDC antes del INSERT, 7/7. Dos intentos Realtime fallidos se conservan; el último evita ambos sin sleeps fijos. local-first-review.txt corresponde a la revisión inicial fallida, con typecheck/build PASS.

No aceptación humana: E9-T08 no ejecutada, ningún acceptance.md creado.
