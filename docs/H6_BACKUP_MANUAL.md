# MikuyApp — Respaldo manual semanal del MVP

## Frecuencia y responsable

El `ADMINISTRADOR` realiza un respaldo una vez por semana y siempre antes de publicar cambios. El procedimiento usa únicamente las exportaciones CSV de ventas y productos de MikuyApp.

## Procedimiento

1. Iniciar sesión como `ADMINISTRADOR` y abrir **Ventas**.
2. Descargar **ventas CSV** y **productos CSV**.
3. Confirmar que ambos archivos existen, tienen tamaño mayor que cero y pueden abrirse como CSV. La exportación de ventas debe incluir sus encabezados incluso si el día no registra ventas.
4. Crear una carpeta con fecha, por ejemplo `MikuyApp/Respaldos/2026-08-30`.
5. Guardar allí ambos archivos como primera copia en la computadora administrativa.
6. Copiar la carpeta completa a un medio o ubicación independiente de esa computadora, por ejemplo una memoria USB custodiada, un disco externo o una computadora autorizada distinta.
7. Comparar nombres y tamaños; cuando sea posible, comparar también hashes SHA-256.
8. Registrar fecha, responsable, ubicación de ambas copias y resultado de la comprobación.

## Conservación

- Mantener como mínimo cuatro respaldos semanales completos.
- Al crear el quinto, puede eliminarse el más antiguo solo después de comprobar que permanecen cuatro respaldos válidos.
- Realizar y comprobar un respaldo adicional antes de cada publicación.
- No incluir contraseñas, claves de Supabase ni archivos `.env`.

## Restauración y límites

El MVP no incorpora restauración automática. Ante una pérdida, se preservan los CSV y se evalúa la recuperación manual antes de modificar producción. Este procedimiento no crea infraestructura, almacenamiento cloud adicional ni exportación de configuraciones.

## Registro mínimo

| Fecha | Responsable | Copia administrativa | Segunda copia independiente | Ventas | Productos | Resultado |
|---|---|---|---|---:|---:|---|
| AAAA-MM-DD | Nombre | Ruta/medio | Ruta/medio | bytes | bytes | Conforme/Incidencia |
