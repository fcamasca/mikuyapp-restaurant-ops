# MikuyApp — Hito H2: Diseño

## D-01 — Auth, sesión y persistencia

Se reutiliza el cliente público Supabase existente con Auth email/password, `getSession` para restauración inicial y `onAuthStateChange` para cambios posteriores. La persistencia es la configuración predeterminada del cliente en el navegador autorizado; no se crea almacenamiento propio para contraseñas o tokens. El estado distingue sesión ausente, sesión cargando, sesión validada y error recuperable. Logout invoca `signOut`, limpia perfil/contexto y navega a `/login`.

## D-02 — Perfil propio y contexto sin recursión

La aplicación consulta `public.perfil_usuario` filtrando `id = auth.uid()` y recupera el rol/local asociados mediante lecturas de sus propias filas autorizadas. La política `SELECT` de `perfil_usuario` se define exclusivamente con `USING (id = auth.uid())`: no consulta `perfil_usuario` otra vez, no expone otros perfiles y permite detectar si el perfil propio está inactivo para rechazarlo correctamente.

Una única función auxiliar de autorización, denominada `public.h2_auth_context()`, suministra a las demás políticas el contexto válido del usuario. Su contrato es:

- Parámetros: ninguno; la identidad siempre se obtiene internamente con `auth.uid()`.
- Retorno: `TABLE(local_id uuid, rol_id smallint, rol_codigo text)`; devuelve exactamente una fila cuando perfil, rol y local están activos y el código pertenece a `ADMINISTRADOR`, `MOZO`, `COCINA` o `CAJA`; devuelve cero filas en cualquier otro caso.
- Implementación futura: función SQL `STABLE SECURITY DEFINER SET search_path = pg_catalog`; todas las referencias se califican como `public.perfil_usuario`, `public.rol`, `public.local` y `auth.uid()`.
- Propietario: `postgres`, rol administrativo propietario de las tablas que permite consultar el perfil sin volver a evaluar su política; el frontend nunca obtiene sus credenciales.
- Privilegios: `REVOKE ALL ON FUNCTION public.h2_auth_context() FROM PUBLIC, anon`; conceder únicamente `EXECUTE` a `authenticated`. No otorgar ejecución a usuarios anónimos ni exponer parámetros que permitan elegir otra identidad.

Una sesión sin contexto válido se cierra o queda bloqueada sin revelar datos. El frontend valida además que la fila propia, rol y local cumplen estas condiciones antes de mostrar rutas operativas.

## D-03 — Rutas y guardas

Rutas mínimas: `/login`, `/tecnica`, `/admin/catalogo`, `/mozo/mesas` y `/403`. `AuthGuard` exige sesión y contexto válido; `RoleGuard` exige rol autorizado. Una solicitud anónima a cualquier ruta protegida, incluida `/tecnica`, redirige a `/login`. Una ruta de otro rol redirige al destino permitido o muestra `/403`; únicamente se conserva una ruta de retorno interna y autorizada.

## D-04 — Destinos por rol

ADMINISTRADOR llega a `/admin/catalogo`; MOZO a `/mozo/mesas`; COCINA y CAJA llegan temporalmente a `/tecnica`. `/tecnica` también puede abrirse con sesión válida de administrador o mozo. Esta página técnica autenticada muestra aplicación cargada, sesión válida, conexión Supabase, rol validado y estado de configuración o error seguro; usa únicamente el contexto/perfil propio autorizado y no consulta `mesa` ni otros recursos prohibidos para COCINA o CAJA. Ningún rol debe observar un error de autorización esperado. No existen pantallas de cocina o caja operativas en H2.

## D-05 — Carta y administración de categorías y productos

La sección administrativa `/admin/catalogo` contiene dos bloques simples: categorías y productos. El formulario de categoría permite crear y editar `codigo`, `nombre`, `orden` y `activo`; el formulario de producto permite crear y editar `codigo`, `nombre`, `precio`, `categoria_id` y `activo`. `local_id` procede exclusivamente del contexto autenticado en el alta y no puede editarse; `id` y `creado_en` no aparecen en formularios.

`catalogService` consulta para el administrador categorías y productos activos/inactivos del propio local; MOZO, COCINA y CAJA solo reciben categorías activas y productos activos cuya categoría también esté activa. Se ordena por `categoria.orden`; la carta vacía incluye categorías activas sin productos activos. Después de cada creación, edición, eliminación o cambio de disponibilidad se actualizan categorías, productos y carta afectada.

La categoría del producto debe pertenecer al mismo local, requisito reforzado por la FK compuesta H1. Se validan código/nombre no vacíos, orden permitido, precio no negativo y código único por local. La activación/desactivación es una actualización de `activo`, no un borrado; no altera pedidos ni historial.

## D-06 — Tablero de mesas

La sección administrativa de mesas permite crear, editar `codigo`/`nombre`, activar, desactivar y eliminar mesas del propio local. Una creación usa el default H1 `estado = 'LIBRE'`; el formulario no transmite `estado`, `id`, `creado_en` ni un `local_id` editable. `UPDATE` carece de privilegio sobre `estado`; una regla de integridad en base de datos debe rechazar `activo = false` cuando el estado actual no sea `LIBRE`, incluso mediante API directa.

El administrador consulta mesas activas e inactivas. El tablero operativo del mozo solo consulta mesas activas, ordenadas por código. Las tarjetas muestran nombre/código, etiqueta textual, color y leyenda para `LIBRE`, `OCUPADA`, `PEDIDO_LISTO` y `PENDIENTE_PAGO`. No existe selección para pedidos ni cambio manual del estado operativo.

## D-07 — Componentes mínimos y estados

Componentes/servicios concretos: proveedor de sesión, guardas, login, carta, tablero de mesas y tres formularios administrativos pequeños para categoría, producto y mesa. Pueden compartir componentes simples de formulario, confirmación de eliminación y mensajes/estados, sin construir una arquitectura genérica de administración.

Cada sección muestra carga, vacío, guardado y resultado; valida obligatorios y conflictos de código antes de comunicar éxito. Un `DELETE` solicita confirmación; cancelar no envía la mutación. Ante error de clave foránea `ON DELETE RESTRICT`, se conserva la fila y se informa: “No se puede eliminar porque tiene registros relacionados; puedes desactivarlo”. Una mesa no libre muestra: “Solo puedes desactivar mesas libres”. Conflictos de unicidad, precio inválido y categoría de otro local se traducen a mensajes funcionales sin exponer SQL.

## D-08 — Privilegios PostgreSQL y políticas RLS definitivas

Se conservan las políticas `anon` existentes de H1 para `local`, `mesa`, `categoria` y `producto`, todas limitadas a registros activos. Esto conserva acceso API mínimo y no concede acceso a `/tecnica`.

Para `authenticated`, primero se revocan privilegios amplios heredados o existentes sobre las diez tablas y se conceden solo los siguientes; también se verifica que `PUBLIC` y `anon` no posean permisos de escritura:

| Tabla | Privilegio autenticado | Política / condición | INSERT / UPDATE / DELETE |
|---|---|---|---|
| `perfil_usuario` | `SELECT` | Solo `id = auth.uid()`; sin consulta recursiva | Denegados |
| `rol` | `SELECT` | Solo la fila `rol_id` del contexto válido | Denegados |
| `local` | `SELECT` | Solo `id = contexto.local_id`, local activo | Denegados |
| `categoria` | `SELECT`, `DELETE`; `INSERT (local_id, codigo, nombre, orden, activo)`; `UPDATE (codigo, nombre, orden, activo)` | Mismo local; administrador ve activos/inactivos; demás roles solo activas | Mutaciones solo administrador activo del mismo local |
| `producto` | `SELECT`, `DELETE`; `INSERT (local_id, categoria_id, codigo, nombre, precio, activo)`; `UPDATE (codigo, nombre, precio, categoria_id, activo)` | Mismo local; administrador ve activos/inactivos; demás roles solo activos con categoría activa | Mutaciones solo administrador activo del mismo local y categoría coherente |
| `mesa` | `SELECT`, `DELETE`; `INSERT (local_id, codigo, nombre, activo)`; `UPDATE (codigo, nombre, activo)` | Administrador ve activas/inactivas; MOZO solo activas; COCINA/CAJA sin lectura | Mutaciones solo administrador activo del mismo local; desactivar solo estado `LIBRE` |
| `pedido` | Ninguno | Sin política H2 | Denegados |
| `detalle_pedido` | Ninguno | Sin política H2 | Denegados |
| `historial_estado` | Ninguno | Sin política H2 | Denegados |
| `pago` | Ninguno | Sin política H2 | Denegados |

La estrategia exacta revoca `INSERT` y `UPDATE` generales de las tres tablas. Concede `INSERT` exclusivamente sobre categoría `(local_id, codigo, nombre, orden, activo)`, producto `(local_id, categoria_id, codigo, nombre, precio, activo)` y mesa `(local_id, codigo, nombre, activo)`. Concede `UPDATE` exclusivamente sobre categoría `(codigo, nombre, orden, activo)`, producto `(codigo, nombre, precio, categoria_id, activo)` y mesa `(codigo, nombre, activo)`. `id`, `creado_en` y `mesa.estado` no tienen privilegio de inserción ni actualización; `local_id` solo tiene privilegio de inserción, nunca de actualización. Sus valores automáticos usan los defaults H1, incluida mesa `LIBRE`.

Los privilegios `INSERT` y `UPDATE` por columna, `DELETE` de tabla y `SELECT` se conceden técnicamente al rol PostgreSQL `authenticated`, mientras políticas separadas `FOR INSERT ... WITH CHECK`, `FOR UPDATE ... USING/WITH CHECK` y `FOR DELETE ... USING` limitan toda mutación al contexto ADMINISTRADOR activo y al mismo `local_id`. Una solicitud de otro rol tiene privilegio técnico pero ninguna política que autorice filas. Un payload con una columna protegida, aunque también incluya columnas permitidas, se rechaza completo y no genera filas parciales.

`INSERT` debe incluir únicamente `local_id` igual al contexto; `WITH CHECK` rechaza cualquier otro local. Para producto, la categoría pertenece al mismo local por FK compuesta y política. El alta de mesa no posee privilegio de inserción sobre `estado`, por lo que usa obligatoriamente el default `LIBRE`; `WITH CHECK` añade la comprobación `estado = 'LIBRE'`. La desactivación se rechaza en base de datos mediante política `WITH CHECK (activo = true OR estado = 'LIBRE')`, además de la validación visual. `DELETE` real conserva las FK `ON DELETE RESTRICT` sin cascada ni debilitamiento. Cada operación mantiene `SELECT` suficiente para la representación PostgREST.

La política de perfil nunca llama a `h2_auth_context()`. Las políticas de rol, local, categoría, producto y mesa sí utilizan la función, que accede mediante su propietario y evita recursión. No se concede acceso a perfiles ajenos, secuencias ni tablas transaccionales.

## D-09 — Procedimiento único para cuatro usuarios

1. Un administrador autorizado abre Supabase Dashboard y crea manualmente cuatro usuarios Auth, uno para cada rol aprobado, sin habilitar registro público.
2. Obtiene sus UUID únicamente desde Dashboard y mantiene correos/contraseñas fuera de Git, build, frontend y logs.
3. En el editor SQL administrativo del proyecto ejecuta un script parametrizado con valores introducidos para esa sesión: UUID Auth, nombre funcional, código de rol y código del local demo. El script resuelve `rol.id` y `local.id`, inserta o actualiza `public.perfil_usuario` con `id = UUID Auth`, `rol_id`, `local_id`, `nombre` y `activo = true`.
4. Verifica administrativamente cuatro perfiles activos, un perfil por UUID, cuatro roles diferentes y el mismo local activo; después comprueba que cada cuenta puede iniciar sesión y obtener únicamente su propio perfil.
5. No versiona el script rellenado, UUID del entorno, correos reales ni contraseñas; cualquier plantilla documental usa marcadores vacíos. No se utiliza `service_role` en frontend, repositorio o logs. El seed de H1 no crea usuarios Auth.

## D-10 — Responsive y Cloudflare Pages

Diseño mobile-first, una columna en celular y dos cuando el ancho de tablet lo permita, controles táctiles y ausencia de desbordamiento horizontal. Cloudflare conserva `npm run build`, salida `dist`, variables exclusivamente públicas y fallback SPA a `index.html` para rutas directas.

## D-11 — Cambio respecto de H1 y límites

En H1 la página técnica era pública y consultaba mesas, categorías y productos; en H2 `/tecnica` pasa a requerir sesión autenticada y se independiza de esos catálogos para funcionar con los cuatro roles, incluyendo COCINA y CAJA sin permiso de mesas. La pantalla valida aplicación, sesión, conexión, rol y configuración sin consultas prohibidas. Las lecturas anónimas mínimas H1 se conservan y se comprueban mediante pruebas técnicas de API, no mediante la presentación pública anterior.

Quedan fuera pedidos, cambios operativos de estados de mesa, Realtime, cocina operativa, caja, pagos, impresión, gestión de usuarios, imágenes, inventario, recetas y promociones. La administración completa de categorías, productos y mesas corresponde exclusivamente a H2 y respeta todas las restricciones H1.
