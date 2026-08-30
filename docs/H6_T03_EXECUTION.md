# MikuyApp — Evidencia H6-T03

Fecha de validación: 2026-08-30.

## Resultado técnico H6-TP08

Se autenticó una cuenta `ADMINISTRADOR` y se ejecutaron las RPC `exportar_ventas_hoy` y `exportar_productos_local` contra Supabase remoto. No se crearon fixtures para esta prueba porque ambas exportaciones devolvieron datos utilizables.

| Archivo | Filas | Bytes | SHA-256 |
|---|---:|---:|---|
| `mikuyapp-ventas-2026-08-30.csv` | 5 | 355 | `8f1fb5be1b1cb5a3fa40641a495cac6d5d5a8669e29c5c8f714324b0f7d9bf88` |
| `mikuyapp-productos-2026-08-30.csv` | 10 | 824 | `487b88af0cbc3deb70ba7ce78151cebcab82cad4534a2b2cfd4c6eea0217854a` |

La primera copia quedó en `artifacts/h6-t03-backup/administrativa`. La copia secundaria de validación quedó en el segundo root autorizado de Codex. Tamaños y hashes coinciden.

## Validación física de la segunda copia

Se conectó una memoria **Kingston DataTraveler 3.0**, identificada como unidad removible `E:` y disco físico independiente `DiskNumber 1`. La copia administrativa permanece en el disco físico 0.

Ubicación externa utilizada: `E:\MikuyApp\Respaldos\2026-08-30`.

| Archivo | Copia administrativa | Copia USB | SHA-256 coincidente | Resultado |
|---|---:|---:|---|---|
| `mikuyapp-ventas-2026-08-30.csv` | 355 bytes | 355 bytes | `8f1fb5be1b1cb5a3fa40641a495cac6d5d5a8669e29c5c8f714324b0f7d9bf88` | Conforme |
| `mikuyapp-productos-2026-08-30.csv` | 824 bytes | 824 bytes | `487b88af0cbc3deb70ba7ce78151cebcab82cad4534a2b2cfd4c6eea0217854a` | Conforme |

H6-TP08 queda aprobada: exportaciones no vacías, primera copia administrativa, segunda copia en medio físico externo, procedimiento documentado, conservación mínima de cuatro respaldos semanales y respaldo previo a publicaciones. No fue necesario esperar cuatro semanas reales.
