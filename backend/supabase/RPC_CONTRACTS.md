# Contratos de escritura relacional

## Estado

Primer grupo preparado: perfil, preferencias y favoritos en `202610300003_personal_write_rpcs.sql`. Depende del esquema `202610300002`. Pruebas locales de permisos, validación, atomicidad, concurrencia y rollback aprobadas; ensayo remoto de este primer grupo también aprobado. El segundo grupo agrega planificación y CRUD de compras en `202610300004` y `202610300005`, con ensayos locales y remotos aprobados. Ninguno de estos ensayos instala cambios definitivamente. El estado global se registra en IMPLEMENTATION_STATUS.md.

Las tablas continúan con SELECT para clientes; las nuevas funciones conceden EXECUTE a `authenticated`. Las funciones derivan siempre el propietario de `auth.uid()`. No aceptan una cuenta destino. El helper interno `lock_my_relational_account()` no concede EXECUTE al cliente.

## `save_my_profile`

Firma: `save_my_profile(p_profile jsonb, p_preference_keys text[], p_expected_version bigint) → profiles`.

- Guarda una instantánea completa. `display_name` es obligatorio; los campos opcionales omitidos o JSON null quedan NULL.
- Campos permitidos: `display_name`, `birth_date`, `weight_kg`, `height_cm`, `metabolic_sex`, `activity_level`, `goal`. Email, identificadores, roles, versiones y campos adicionales se rechazan. Email sigue en Supabase Auth.
- Preferencias: lista completa de claves estables de `dietary_tags.tag_key`. Una lista vacía quita las preferencias; NULL, duplicados, valores desconocidos e inactivos se rechazan. Perfil y preferencias se guardan o revierten juntos.
- Versión esperada 0 permite crear solamente. Los perfiles existentes requieren su versión exacta; los migrados empiezan en 1. Cada guardado aumenta la versión. Un conflicto devuelve `40001`; el cliente debe recargar antes de guardar y no reemplazar silenciosamente la versión esperada.
- Devuelve la fila propia guardada, incluidos `user_id`, `version` y timestamps. Conserva `created_at` al actualizar.
- Rechaza fechas inválidas/futuras, tipos incorrectos y medidas fuera del rango acordado antes del redondeo de PostgreSQL. Las estimaciones nutricionales siguen siendo cálculos derivados.
- Los errores de conversión y constraints se convierten en `22023` con mensaje fijo, sin devolver filas ni valores personales en DETAIL.

El futuro repositorio debe leer perfil y preferencias en una sola consulta consistente. Dos consultas separadas pueden mezclar una versión del perfil con preferencias de otra versión. El frontend actual usa camelCase: `name → display_name`, `birthDate → birth_date`, `weightKg → weight_kg`, `heightCm → height_cm`, `metabolicSex → metabolic_sex`, `activityLevel → activity_level`; `goal` se conserva y `preferences` se envía por separado. La transición también debe adaptar la edición administrativa de nombres, que todavía usa el perfil JSON anterior.

## `set_my_favorite`

Firma: `set_my_favorite(p_recipe_id uuid, p_is_favorite boolean) → boolean`.

- Fija el estado deseado; nunca alterna el estado existente. Repetir un alta no duplica filas y repetir una baja no la vuelve a agregar.
- El alta requiere una receta activa, no borrada, oficial publicada o privada propia. El acceso de revisión de un administrador a recetas privadas ajenas no autoriza marcarlas como favoritas.
- La baja permite quitar un favorito aunque la receta haya sido archivada o ya no esté disponible. Quitar un UUID inexistente devuelve false.
- Solo modifica favoritos del usuario autenticado. Devuelve el estado solicitado.
- El frontend debe resolver los IDs antiguos de recetas mediante `recipes.legacy_id`; la RPC recibe el UUID relacional.

## Autorización y concurrencia

Las escrituras requieren READ COMMITTED. Adquieren el bloqueo asesor compartido `(74539,1)` utilizado en modo exclusivo por las RPC administrativas existentes, luego un bloqueo por cuenta y bloqueos FOR SHARE sobre Auth y el estado existente. Después vuelven a comprobar que la cuenta esté activa. Las distintas cuentas pueden guardar en paralelo.

Ese es el punto de autorización de la operación. Una desactivación que obtiene primero su bloqueo hace que el guardado espere y se rechace; un guardado ya admitido termina antes de la desactivación que espera. Los cambios de bloqueo de Supabase Auth también se ordenan mediante su fila. Los bloqueos se retienen hasta finalizar la transacción.

Cerrar sesión en el navegador no cancela una petición JWT ya admitida. El guardado sigue perteneciendo a la cuenta que lo inició. La protección de sesión/caché del frontend debe mantenerse durante el cambio de repositorios. Las escrituras manuales de operadores de la base que omitan este protocolo de bloqueo no son el flujo de concurrencia de la aplicación.

## Verificación reproducible

1. Regenerar: `python backend/supabase/tests/build_relational_permissions.py` y `python backend/supabase/tests/build_personal_write_rehearsal.py`.
2. Ensayo local: `backend/supabase/tests/run_backfill_local.ps1 -PersonalWrites`.
3. Concurrencia local: `backend/supabase/tests/run_backfill_local.ps1 -Concurrency`. Crea un PostgreSQL aislado en loopback, instala únicamente allí las funciones y datos ficticios, comprueba transacciones solapadas observando sus bloqueos y detiene el servidor al terminar. El archivo `tests/fixtures/personal_rpc_concurrency_install.sql` es exclusivamente para este clúster local; no es un archivo de despliegue en Supabase.
4. Supabase SQL Editor, como postgres, ejecutar completo `tests/personal_write_rpcs_rehearsal.sql`, conservando `ROLLBACK`. Necesita dos cuentas existentes activas; sus cambios de rol/estado y los datos sintéticos se revierten. Debería devolver PASS. Ninguna clave ni credencial se incluye en los archivos.

## Planificación semanal

`save_my_meal_plan(p_week_start date, p_slots jsonb, p_expected_version bigint) → meal_plans` reemplaza una semana completa. El inicio debe ser lunes y cada entrada debe pertenecer a sus siete días. Admite hasta 140 entradas, con `meal_date` ISO, `meal_shift` en breakfast/lunch/snack/dinner, `recipe_id` UUID, porciones enteras de 1 a 20 y `position` opcional (1 por defecto; entero de 1 a 100). La combinación fecha/turno/posición no se repite. Los enteros JSON equivalentes como 2.0 son válidos; las fracciones se rechazan.

La versión 0 crea el plan; guardar uno existente exige su versión vigente e incrementa esa versión. El plan mantiene su UUID y conserva así las referencias de compras; solo reemplaza sus turnos, cuyos IDs se generan en el servidor. Un array vacío limpia la semana. Las recetas deben estar activas y ser privadas propias u oficiales publicadas; el acceso de revisión ADMIN no permite planificar recetas privadas ajenas. Los errores de formato y constraints se sanitizan como 22023; los conflictos de versión usan 40001 y el acceso no permitido 42501.

## Lista y artículos de compras

Todas estas RPC derivan el propietario de la sesión y devuelven la fila de `shopping_lists`, incluida su versión. Las mutaciones de artículos requieren la lista propia activa y su versión vigente.

| RPC | Contrato |
| --- | --- |
| `create_my_shopping_list(p_list_id uuid, p_name text, p_plan_id uuid default null)` | El UUID estable del cliente identifica la creación. Crea la lista y archiva la activa anterior atómicamente. Un reintento con el mismo UUID y parámetros devuelve la fila existente; si ya está archivada, no la reactiva. Plan opcional propio. |
| `put_my_shopping_item(p_list_id uuid, p_item jsonb, p_expected_version bigint)` | Inserta/reemplaza un artículo y todos sus orígenes atómicamente; aumenta la versión. No puede mover un artículo entre listas o reutilizar la identidad de un artículo transferido. |
| `set_my_shopping_checked(p_list_id uuid, p_item_ids uuid[], p_checked boolean, p_expected_version bigint)` | Cambia el estado de hasta 1000 IDs distintos y propios de la lista. No puede cambiar el estado de un artículo transferido. Si todos ya tienen el estado deseado, la versión no cambia. |
| `remove_my_shopping_item(p_list_id uuid, p_item_id uuid, p_expected_version bigint)` | Elimina el artículo de esa lista y sus orígenes. Un ID ausente es un no-op sin cambio de versión. Permite eliminar un artículo transferido: el comprobante conserva su ID original y snapshots. |

`p_item` admite únicamente `id`, `ingredient_id`, `name_snapshot`, `category_snapshot`, `quantity`, `unit_id`, `note`, `checked`, `source`, `sources`. Requiere ID, unidad, cantidad numérica positiva de hasta un millón, origen principal y de 1 a 20 orígenes. `checked` por defecto es false y `note` vacío (hasta 1000 caracteres). Cada origen tiene `source` y, exclusivamente para recipe o plan, su `recipe_id` o `plan_id`. Los orígenes deben ser distintos y contener el origen principal.

Un ingrediente de catálogo debe estar activo y aporta su nombre y categoría desde el servidor; las etiquetas provistas por el cliente se validan si están presentes y se reemplazan por las oficiales. Las unidades deben estar activas y compartir la misma raíz de conversión, no solamente la dimensión. Los artículos manuales sin ingrediente conservan su nombre validado y categoría (Otros por defecto). No se aceptan propietario, timestamps ni estado de transferencia desde el cliente.

Los vínculos con receta/plan se validan bajo bloqueo: planes propios y recetas activas privadas propias u oficiales publicadas. Registran la procedencia de la propuesta; cambiar después el plan no recalcula automáticamente cantidades compradas. Los planes mantienen su identidad y las recetas referenciadas se archivan; el borrado físico no es el flujo acordado.

La futura transferencia deberá respetar el orden de bloqueos cuenta → lista → IDs de artículo ordenados, usando `hashtextextended('cocinapp.shopping-item:' || id, 0)` como las RPC actuales. El UUID original se conserva en el comprobante después de eliminar el artículo y no puede volver a insertarse como compra nueva.

Regenerar el ensayo: `python backend/supabase/tests/build_planning_shopping_rehearsal.py`. Ejecutar localmente `backend/supabase/tests/run_backfill_local.ps1 -PlanningShopping`. La variante `-PlanningShoppingConcurrency` también instala únicamente en el clúster aislado la versión de prueba y comprueba transacciones solapadas: versiones semanales, creación de una sola lista activa y colisión de UUID entre cuentas. Estas pruebas pasaron localmente. En Supabase, como postgres, ejecutar completo `tests/planning_shopping_write_rpcs_rehearsal.sql` conservando el ROLLBACK final. Incluye el esquema y las dependencias; requiere dos cuentas existentes activas y no instala nada permanentemente.

Pendientes: verificación remota de transferencia/sugerencias, CRUD de inventario, sesiones/temporizadores y finalización de cocción; nuevas escrituras de catálogo y recetas, funciones de consulta, funciones Edge de IA/tickets y cambio de repositorios. No retirar el almacenamiento anterior ni aplicar el corte definitivo con estos grupos.


## Transferencia de compras a despensa

`transfer_my_shopping_to_pantry(p_list_id uuid, p_item_ids uuid[], p_idempotency_key uuid, p_expected_version bigint) → pantry_receipts`, preparada en `202610300006_shopping_transfer_rpcs.sql`.

- Recibe de 1 a 1000 IDs distintos. Exige sesión activa, lista propia activa y versión vigente. Bloquea cuenta → lista → IDs de artículo ordenados con el mismo bloqueo asesor de las RPC de compras.
- Transfiere únicamente artículos comprados y no transferidos. Revalida catálogo, categorías y unidades activas, dimensiones y raíz de conversión. Los artículos manuales siguen admitidos: se conserva su referencia NULL y sus etiquetas, sin asociarlos por nombre al catálogo.
- Incrementa existencias compatibles no vencidas o crea una fila. Conserva los lotes vencidos. El stock manual solo se combina con stock manual; el de catálogo conserva su identidad. Cantidades, comprobante, snapshots, estado de transferencia y versión se guardan en una sola transacción.
- La migración amplía cantidad y mínimo de despensa a cuatro decimales, conservando sus valores anteriores y límites. Una conversión que no pueda representarse exactamente se rechaza; no redondea silenciosamente ni trunca etiquetas para hacerlas entrar en despensa.
- La clave de idempotencia pertenece a la cuenta. Repetir clave, lista y conjunto de IDs devuelve el comprobante original, aunque la versión haya cambiado, la lista se haya archivado o se hayan eliminado artículos transferidos. Reutilizar la clave con otra selección se rechaza. Una clave nueva no permite transferir otra vez el mismo artículo.
- El comprobante guarda los IDs originales, cantidades/unidades compradas y agregadas, nombre, categoría e ingrediente. Los UUID de snapshot no son referencias vivas: conservan el significado histórico aunque después desaparezca una fila referenciada. Eliminar una compra conserva su UUID original en el comprobante.
- La operación deja las compras marcadas como transferidas; el cliente puede eliminarlas después mediante la RPC existente. No debe intentar sumar stock por su cuenta. La versión resultante de lista está en `resulting_list_version`.

Los conflictos de versión devuelven `40001`, permisos `42501` y datos inválidos `22023` sin DETAIL con valores personales. El frontend todavía usa repositorios anteriores. El inventario completo y su política de escritura requieren su siguiente módulo antes del corte; la transferencia no sustituye todas las operaciones de despensa.

## Sugerencias de compra

`suggest_my_shopping(p_source text, p_plan_id uuid default null, p_as_of date default current_date) → jsonb`, preparada en `202610300007_shopping_suggestions_rpc.sql`.

- Fuentes permitidas: `plan`, `favorites`, `pantry`. Solo `plan` recibe un ID de plan propio. La identidad siempre proviene de la sesión activa; no acepta una cuenta destino.
- Planificación suma todos sus turnos y escala cada receta según sus porciones. Favoritos calcula una preparación con las porciones base de cada receta disponible. Las recetas privadas ajenas no participan, incluso para administradores.
- Descuenta stock propio no vencido con conversiones compatibles. Para cálculos puede reconocer stock manual por nombre normalizado; eso no escribe ni inventa una asociación persistida. Referencias relacionales existentes mantienen su identidad.
- Reposición agrupa lotes compatibles, suma stock utilizable y toma el mayor mínimo convertido del grupo. Conserva la reposición de artículos manuales y la regla de artículos agotados/vencidos sin mínimo que utiliza el frontend.
- Devuelve propuestas con `ingredient_id` nullable, `name_snapshot`, `category_snapshot`, `quantity`, `unit_id`, `source` y `sources`. Las cantidades positivas se redondean hacia arriba a cuatro decimales para cubrir el faltante. No genera IDs de artículo ni escribe listas.
- La consulta usa una instantánea consistente de sus entradas. La propuesta no reserva existencias. La futura integración debe enviar la fecha local explícitamente en `p_as_of`, mostrar la propuesta y confirmar cada artículo por `put_my_shopping_item`, con UUID estable y versión actualizada. Reutilizar el UUID evita duplicar un alta; no sumar otra vez cantidades al reintentar.

No hay recalculado automático de una compra confirmada cuando cambia después un plan, receta o stock. La importación de varias propuestas mediante distintas llamadas `put` puede quedar parcialmente confirmada ante un error; un futuro flujo que necesite confirmación conjunta deberá incorporar una RPC de lote.


## Verificación del grupo de transferencia y sugerencias (2026-10-31)

PASS local en PostgreSQL 18 aislado: transferencia atómica, artículos manuales, conversiones exactas, snapshots, reintentos, aislamiento y autorización; sugerencias con porciones acumuladas, conversión de stock, vencimientos, reposición manual, Unicode NFD y validación de unidades. Ambos envoltorios verificaron ROLLBACK completo. Reintentos simultáneos de transferencia devolvieron el mismo comprobante y sumaron stock una sola vez. Auditoría independiente sin hallazgos pendientes.

Regenerar con `python backend/supabase/tests/build_shopping_transfer_rehearsal.py` y `python backend/supabase/tests/build_shopping_suggestions_rehearsal.py`. Ejecutar localmente `backend/supabase/tests/run_backfill_local.ps1 -ShoppingTransferConcurrency` y `backend/supabase/tests/run_backfill_local.ps1 -Suggestions`. El archivo `fixtures/shopping_transfer_concurrency_install.sql` es exclusivamente local.

Pendiente remoto: ejecutar completos, como postgres y con la app inactiva, `tests/shopping_transfer_rehearsal.sql` y luego `tests/shopping_suggestions_rehearsal.sql`. Cada archivo incluye dependencias, requiere dos cuentas existentes activas y conserva su ROLLBACK final. Elegir **Run without RLS** si aparece el aviso. No aplicar migraciones individuales durante estos ensayos.

Transferencia: PASS remoto confirmado por el usuario ejecutando el envoltorio completo. Sugerencias: ensayo remoto todavía pendiente de aprobación tras fallar su comprobación de reposición.

Corrección del ensayo de sugerencias: la aserción de reposición compara cantidades convertidas (200 g equivale a 0,2 kg) y prueba ambos órdenes de lotes. El ensayo aísla el stock de la cuenta de prueba dentro de la transacción: sus filas previas se retiran temporalmente y se restauran con el ROLLBACK final. PASS local y ROLLBACK completo verificados; repetir únicamente este envoltorio en Supabase. La RPC no cambió por esta corrección.

Sugerencias: ensayo remoto corregido completado por el usuario con «Success. No rows returned». El archivo completo termina en ROLLBACK; no se instalaron estructuras permanentemente. El grupo transferencia/sugerencias tiene aprobación local y remota.


## Operaciones de despensa

Preparadas en `202610310001_pantry_write_rpcs.sql`, dependiente del esquema y grupos anteriores. No aplicar definitivamente durante los ensayos.

- `put_my_pantry_item(p_item jsonb, p_expected_version bigint) → pantry_items`: instantánea individual con UUID estable. Versión 0 crea o reintenta la misma creación sin modificaciones posteriores; editar exige versión vigente. Admite cantidad cero, cantidad/mínimo hasta un millón con cuatro decimales, vencimiento opcional y artículos manuales sin asociación inferida.
- `put_my_pantry_items(p_items jsonb) → jsonb`: confirmación atómica de hasta 200 entradas `{item, expected_version}` con IDs distintos. Sirve para kits o propuestas de tickets ya revisadas. Si una entrada falla, revierte todo el lote. Reintentos de creación usan los mismos UUID; reintentos de actualizaciones requieren recargar versiones tras un conflicto.
- `delete_my_pantry_item(p_item_id uuid, p_expected_version bigint) → boolean`: elimina únicamente la fila propia con su versión vigente; si ya no existe devuelve false. Los comprobantes mantienen sus snapshots y la FK a despensa pasa a NULL.

`p_item` admite `id`, `name`, `category`, `quantity`, `unit` (abreviación), `minimum`, `expiry`, `ingredient_ref` y compatibilidad `ingredient_id`. Las referencias relacionales se validan contra catálogo activo y unidades con la misma raíz; una referencia legacy no se convierte automáticamente en UUID relacional. El servidor conserva `source_shopping_ids`, propietario y timestamps, sin admitirlos del cliente.

Cada UPDATE aumenta la versión por trigger, incluidos los realizados por transferencia. Así una edición vieja no puede pisar stock comprado. Errores de datos se sanitizan, las versiones obsoletas usan 40001 y cada RPC obtiene la cuenta desde Auth. La migración revoca DML directo de clientes; el repositorio anterior que sincroniza la despensa entera deberá reemplazarse al corte, junto con el despliegue y conversión. Este módulo no conecta todavía el frontend ni implementa reconocimiento real de tickets.

Con `ingredient_ref` no nulo se deriva el identificador legacy oficial; si el cliente proporciona uno distinto se rechaza. Validación local final aprobada: CRUD/lotes, transferencia real que incrementa versión, conflictos, aislamiento, concurrencia y ROLLBACK completo. Regenerar con `python backend/supabase/tests/build_pantry_write_rehearsal.py`; ejecutar localmente `backend/supabase/tests/run_backfill_local.ps1 -PantryConcurrency`. Pendiente remoto: archivo completo `tests/pantry_write_rpcs_rehearsal.sql`.

Despensa: el usuario confirmó PASS remoto de CRUD/lotes, reintentos, validación, conflictos de versión con transferencia, aislamiento y revocación de DML. El archivo completo incluye ROLLBACK; despliegue definitivo y cambio de repositorio siguen pendientes.


## Sesiones, progreso y temporizadores de cocción

Preparados en `202610310002_cooking_session_rpcs.sql`; no incluyen finalización, historial ni descuento de stock.

- `start_my_cooking_session(p_session_id uuid, p_recipe_id uuid, p_portions integer) → cooking_sessions`: UUID estable del cliente, receta disponible propia u oficial publicada y 1..20 porciones. Guarda snapshot de receta/pasos/ingredientes y crea filas de progreso. Repetir el mismo inicio devuelve la sesión original; otra receta o cantidad inicial con el mismo UUID se rechaza. Las porciones iniciales se conservan aparte de las porciones actuales.
- `get_my_cooking_session(p_session_id uuid) → jsonb`: devuelve la sesión propia abierta con snapshot, versión y todos sus pasos/temporizadores, en una consulta consistente. Calcula el tiempo restante a partir del vencimiento del servidor sin escribir al leer.
- `update_my_cooking_session(p_session_id uuid, p_expected_version bigint, p_action text, p_step integer default null, p_portions integer default null) → cooking_sessions`: acciones `move`, `complete`, `uncomplete`, `portions`, `timer_start`, `timer_pause`, `timer_resume`, `timer_reset`, `timer_finish`. Exige versión vigente y solo actúa sobre una sesión propia abierta.

`p_step` y `current_step` son índices desde 0; `cooking_session_steps.step_position` empieza en 1. `portions` recibe únicamente `p_portions`; las otras acciones no reciben esa cantidad. El timer toma su duración del snapshot y sus deadlines se calculan en el servidor. Cambiar de paso pausa el timer anterior y conserva su tiempo, en vez de perderlo. Un timer running ya iniciado no se vuelve a extender por repetir start. Un vencimiento transcurrido se presenta con tiempo restante cero.

La futura integración debe renderizar el snapshot de la sesión, convirtiendo sus objetos de pasos a `Recipe.steps`/`stepMeta`; no debe mezclar el progreso guardado con la receta viva del catálogo. Persistirá el UUID de inicio antes de enviar la petición y leerá la sesión completa para reanudar. Las RPC no aceptan deadlines ni tiempo restante arbitrario enviados por el cliente. Las funciones usan permisos de cuenta activa y las tablas siguen sin DML directo para clientes.


La construcción del snapshot bloquea la receta y sus detalles/referencias. Las futuras RPC administrativas que cambien receta o hijos deben obtener primero FOR UPDATE sobre la receta padre; las operaciones SQL de operador que omitan ese protocolo no pertenecen al flujo concurrente de la aplicación. Los clientes actuales solo tienen SELECT sobre esos hijos.

PASS local de este grupo: inicio/reintento, snapshot, progreso, porciones, temporizadores, aislamiento y permisos; ROLLBACK completo y actualizaciones simultáneas con conflicto 40001 verificados. Auditoría independiente sin bloqueantes. Regenerar `python backend/supabase/tests/build_cooking_session_rehearsal.py`; ejecutar `backend/supabase/tests/run_backfill_local.ps1 -CookingSessionConcurrency`. El fixture `fixtures/cooking_session_local.sql` es exclusivamente local.

Pendiente remoto: ejecutar completo `tests/cooking_session_rehearsal.sql`, como postgres, con dos cuentas Auth activas y app inactiva, conservando el ROLLBACK final. Elegir Run without RLS si aparece. No aplicar las migraciones individualmente. El frontend y la finalización de cocción todavía están pendientes.

Sesiones y temporizadores: éxito remoto confirmado por el usuario («Success. No rows returned»); el envoltorio completo termina en ROLLBACK. No hace falta un ROLLBACK adicional si se ejecutó completo. La finalización con stock e historial es el siguiente grupo.


## Finalización de cocción

`finish_my_cooking_session(p_session_id uuid, p_expected_version bigint, p_deduct_stock boolean) → cooking_events`, preparada en `202610310003_cooking_finish_rpcs.sql`.

La primera finalización exige sesión propia abierta, cuenta activa y versión vigente. Registra un evento único por sesión, guarda la decisión de descuento y cierra sesión/temporizadores en la misma transacción. Repetir la finalización con la misma decisión devuelve el evento original aunque la versión esperada sea vieja; una decisión distinta se rechaza. No se exige haber marcado todos los pasos, como en el flujo actual.

Con descuento, usa las cantidades y conversiones congeladas en el snapshot, escaladas por las porciones actuales de la sesión. Bloquea cuenta → sesión → filas de despensa por UUID. Consume lotes propios no vencidos por vencimiento más próximo e ID, dejando los lotes sin vencimiento al final. Las asociaciones de catálogo se comparan por ID; el stock manual puede coincidir por nombre normalizado y unidad compatible sin escribir una asociación al catálogo. Un faltante o una cantidad no representable exactamente revierte stock, versiones, evento y cierre juntos.

Sin descuento, registra la preparación sin alterar stock ni fabricar filas de consumo. Las filas de consumo con descuento guardan cantidades agregadas por nombre/unidad del snapshot, no un registro por lote. La fecha para excluir vencidos es `current_date` del servidor; revisar el criterio de fecha local en la integración del frontend. El frontend debe mantener la decisión original y recargar ante un conflicto 40001; no debe descontar otra vez localmente.

La eliminación/limpieza visual del historial aún requiere su siguiente contrato: no borrar físicamente el evento de idempotencia, porque su unicidad protege contra descuentos repetidos. El repositorio/frontend y consultas de déficits/agotados siguen pendientes de integración.


Verificación local de finalización aprobada: cantidades exactas, agotamiento parcial entre lotes, exclusión de vencidos, ingredientes repetidos agregados, etiqueta/unidad incompatible, faltante y precisión no representable con rollback, escalado exacto 3×1/3, versión inicial obsoleta, repetición con versión vieja y mismo descuento, cambio de decisión rechazado, opción sin descuento y aislamiento. La prueba concurrente confirma un solo evento y descuento único. Auditoría independiente corregida, sin bloqueantes pendientes. No se desplegó en Supabase.

Regenerar con `python backend/supabase/tests/build_cooking_finish_rehearsal.py`; probar localmente con `backend/supabase/tests/run_backfill_local.ps1 -CookingFinish`. `fixtures/cooking_finish_local.sql` es exclusivamente local. Pendiente remoto: ejecutar completo `tests/cooking_finish_rehearsal.sql` como postgres, app inactiva, con dos cuentas Auth activas y conservando ROLLBACK. Elegir Run without RLS si aparece el aviso.

Finalización de cocción: ensayo remoto completo aprobado por el usuario con «Success. No rows returned». El ROLLBACK ya incluido revierte los cambios; no hubo instalación permanente. Siguiente grupo: consultas de faltantes e historial con ocultación segura, sin borrar el evento de idempotencia.


## Consultas de faltantes e historial

Preparadas en `202610310004_cooking_queries_history_rpcs.sql`. El historial se oculta de la aplicación, pero conserva físicamente los eventos y consumos que impiden descontar stock dos veces.

- `get_my_cooking_history(p_limit integer default 30, p_before timestamptz default null, p_before_id uuid default null) → jsonb`: página propia visible, con snapshot y consumos, máximo 100 filas. Orden por `cooked_at DESC,id DESC`; enviar ambos valores de la última fila como cursor siguiente. Conserva preparaciones de recetas archivadas/missing mediante su snapshot.
- `hide_my_cooking_history_entry(p_event_id uuid) → boolean`: oculta un evento propio; devuelve false si ya estaba oculto o no está disponible. No borra filas ni descuenta/repone stock.
- `clear_my_cooking_history() → integer`: oculta los eventos propios visibles existentes y devuelve cuántos afectó. Se ordena con finalizaciones mediante el bloqueo de cuenta. Los eventos posteriores a la operación siguen visibles.
- `check_my_cooking_stock(p_recipe_id uuid default null, p_portions integer default null, p_session_id uuid default null) → jsonb`: exactamente una receta disponible o una sesión propia. Para receta enviar porciones 1..20; para sesión omitir porciones para usar las actuales de la sesión, o enviar su mismo valor. La sesión usa el snapshot congelado, no el catálogo vivo.

La consulta devuelve receta/sesión, porciones, fecha del servidor, indicadores de preview y filas de ingredientes con cantidad requerida, disponible y faltante en unidades compatibles. Agrega necesidades repetidas y excluye stock vencido, ajeno o incompatible. La fecha es la misma base `current_date` del finalizador. Es una propuesta consistente sin reserva ni escritura: puede cambiar por operaciones posteriores y no reemplaza la revalidación atómica al finalizar, incluida representabilidad exacta de cantidades.

El frontend deberá mapear estos contratos a `CookingRepository`, paginar el historial, renderizar snapshots y usar solo historia visible en recomendaciones/recientes. No llamar checkStock sobre catálogo vivo al finalizar una sesión que ya tiene snapshot.


Si distintas identidades de catálogo comparten el mismo nombre normalizado y raíz, la consulta rechaza la ambigüedad (22023), evitando mezclar sus existencias. `sufficient` expresa disponibilidad en ese instante, no garantiza representabilidad exacta ni reserva stock; el finalizador conserva la validación definitiva.

PASS local de consultas/historial con ROLLBACK completo. Regenerar `python backend/supabase/tests/build_cooking_queries_rehearsal.py`; ejecutar `backend/supabase/tests/run_backfill_local.ps1 -CookingQueries`. El instalador `fixtures/cooking_queries_local.sql` es exclusivamente local. Pendiente remoto: ejecutar todo `tests/cooking_queries_rehearsal.sql` como postgres, app inactiva, con dos cuentas Auth activas y conservando ROLLBACK; elegir Run without RLS si aparece.

Consultas de cocción e historial: éxito remoto confirmado por el usuario («Success. No rows returned») del envoltorio completo con ROLLBACK. No se instalaron cambios permanentemente.


## Administración relacional del catálogo

`admin_put_category(p_entity jsonb,p_expected_version bigint)`, `admin_put_unit(...)`, `admin_put_ingredient(...) → jsonb`, preparadas en `202610310005_catalog_admin_rpcs.sql`. El helper genérico no es ejecutable por clientes.

Requieren ADMIN activo comprobado en base después de adquirir el bloqueo global exclusivo (74539,1), luego el protocolo de cuenta/Auth. Se ordenan con revocaciones y escrituras personales. Versión 0 crea con UUID estable; una repetición idéntica de la creación devuelve la fila inicial sin duplicar auditoría. Editar exige versión vigente; si el contenido ya coincide no cambia versión ni auditoría. Un conflicto usa 40001. Las validaciones y errores de constraints se sanitizan sin DETAIL personal.

Campos comunes: `id`, `name`, `active`, `is_deleted`. Unidad: además `abbreviation`, `dimension` (mass/volume/count), `base_unit_id`, `equivalence_multiplier`. Ingrediente: además `category_id`, `base_unit_id`. No se aceptan propietario, versión en JSON, campos de otra entidad ni datos de auditoría. La versión esperada se envía aparte. El frontend mapeará masa/volumen/conteo a los valores SQL.

El borrado lógico se expresa con `active=false,is_deleted=true`; restaurar con `active=true,is_deleted=false`, enviando el resto del snapshot vigente. Se conservan IDs, referencias y legacy_id; no hay borrado físico. Los nombres se normalizan por espacios, minúsculas y NFD sin diacríticos. Categorías/unidades no borradas reservan su nombre aunque estén inactivas; una restauración que colisiona se rechaza. Los nombres de ingredientes conservan la unicidad global del modelo y las abreviaturas de unidades quedan reservadas aun archivadas: restaurar la identidad previa en lugar de reinterpretar stock antiguo con otra.

Se pueden archivar unidades referenciadas conservando sus referencias, como en el frontend actual; las operaciones que exigen catálogo activo pueden rechazarlas hasta restaurarlas. Cambiar abreviación, dimensión o conversión de unidades referenciadas por stock/compras/recetas/snapshots se rechaza. También se protegen raíces/hijos y la unidad base de ingredientes referenciados. La normalización de unidades se deriva por trigger para admitir los INSERT anteriores del backfill que omiten la columna nueva.

Cada mutación efectiva inserta en `admin_audit_log` una acción catalog.category_saved/unit_saved/ingredient_saved, actor de Auth y detalles limitados a entidad/versión. Se mantiene la lista de acciones anteriores. La adaptación del frontend administrativo y de las etiquetas de auditoría sigue pendiente: no aplicar esta migración sola contra los repositorios actuales.

PASS local y ROLLBACK completo; concurrencia de versiones y revocaciones probada. Regenerar `python backend/supabase/tests/build_catalog_admin_rehearsal.py`; ejecutar `backend/supabase/tests/run_backfill_local.ps1 -CatalogAdminConcurrency`. Los fixtures catalog_admin_* son exclusivamente locales. Pendiente remoto: ejecutar completo `tests/catalog_admin_rehearsal.sql` como postgres, con la app inactiva y dos cuentas activas existentes, manteniendo ROLLBACK. Elegir Run without RLS si aparece. El envoltorio remoto incluye dependencias relacionales reales; no incluye simulación de Auth ni fixtures locales.

Administración de categorías/unidades/ingredientes: ensayo remoto completo aprobado por el usuario («Success. No rows returned»). El ROLLBACK final conserva la base anterior; despliegue y adaptación del frontend siguen pendientes.


## Administración atómica de recetas oficiales

Preparada en `202611010001_recipe_admin_rpcs.sql`. Solo ADMIN activo puede modificar recetas oficiales con owner NULL; no permite modificar recetas privadas de usuarios/IA. Adquiere bloqueo global exclusivo antes del protocolo de cuenta y bloquea la receta padre antes de sustituir detalles, coordinándose con snapshots de cocción.

- `admin_save_recipe(p_recipe_id uuid,p_recipe jsonb,p_expected_version bigint) → jsonb`: instantánea completa, versión 0 para creación con UUID estable y versión vigente para editar. Guarda datos generales, turnos, etiquetas, ingredientes, pasos y vínculos de pasos en una sola transacción. Un error en un hijo revierte todos los cambios y su auditoría. El UUID/legacy_id y las referencias externas de la receta se conservan; los hijos pueden regenerar sus IDs.
- `admin_duplicate_recipe(p_source_id uuid,p_target_id uuid,p_expected_version bigint default 0) → jsonb`: crea copia borrador, activa y no destacada, con título único «Copia de …». Conserva contenido y metadata; el UUID destino es la clave estable. Repetir devuelve la misma copia sin sobreescribir ediciones posteriores; otro origen o un destino previamente ocupado se rechazan. No reutiliza ni reescribe auditoría de creaciones anteriores.
- `admin_set_recipe_flags(p_recipe_id uuid,p_expected_version bigint,p_active boolean default null,p_featured boolean default null,p_archived boolean default null,p_restored boolean default null) → jsonb`: cambia estado/destacada sin exigir validar otra vez todo el contenido de recetas antiguas. Archivar conserva la receta y la deja inactiva; solo restaurar explícitamente quita el archivo, comprobando colisiones de título. Una edición de contenido no restaura implícitamente.

JSON `p_recipe`: `title`, `author`, `description`, `category_label`, `meal_shifts` (breakfast/lunch/snack/dinner), `total_minutes`, `preparation_minutes`, `cooking_minutes`, `portions`, `difficulty`, `calories_per_portion`, `dietary_tags` (claves), `featured`, `symbol`, `color`, `cross_contamination_note`, `image_path`, `image_alt`, `publication_status`, `active`, `ingredients`, `steps`. No admite propietario, fuente, legacy_id, timestamps ni versión dentro del JSON.

Cada ingrediente usa `ingredient_id`, `quantity`, `unit_id`, `note`; el orden del array determina su posición desde 1. Cada paso tiene `instruction`, `duration_minutes`, `temperature`, `tip`, `warning`, `utensils`, `special_instructions`, `ingredients`. Sus vínculos usan `ingredient_position` dentro del array enviado y `quantity_override` opcional. Las conversiones requieren raíz compatible, no solo dimensión. Nuevas referencias deben estar disponibles; se conservan pares de ingrediente/unidad previos para no bloquear la edición de referencias antiguas inactivas.

La cantidad se admite exactamente con hasta cuatro decimales (esquema numeric(14,4)); el frontend actual admite más precisión y deberá alinear formulario/validación antes del corte. El servidor rechaza el exceso en lugar de redondearlo silenciosamente. Una misma solicitud JSONB al guardar con la versión vigente es no-op si sigue siendo la última solicitud exitosa de esa versión; omitir opcionales y enviarlos como null son cuerpos distintos. Las creaciones y copias tienen sus propios reintentos con UUID estable. Conflictos de versión usan 40001; errores se sanitizan sin DETAIL personal.

Se conserva una tabla auxiliar privada `admin_recipe_write_state` con RLS y permisos revocados para clientes; registra reintentos/procedencia, separada de las 28 tablas del dominio. Cada modificación efectiva genera una sola auditoría segura (entidad/versión): catalog.recipe_saved, catalog.recipe_duplicated o catalog.recipe_flags_changed. Los nuevos inicios de cocción fijan recipe_version y conservan snapshot/versión aunque luego se edite el catálogo; las sesiones históricas cerradas no se alteran.

La futura integración debe leer receta, versión y todos sus hijos en una consulta consistente, mapear camelCase/IDs legacy a snake_case/UUID, y convertir stepMeta/ingredientIds a vínculos por posición. Los seed ya convertidos se editan resolviendo recipes.legacy_id; no crear una segunda receta para el mismo override. La publicación/edición de recetas de IA o usuarios requiere sus contratos propios. Las etiquetas nuevas de auditoría deben incorporarse al frontend al corte.

PASS local y ROLLBACK completo, concurrencia de versiones y edición frente a snapshot de cocción. Regenerar `python backend/supabase/tests/build_recipe_admin_rehearsal.py`; ejecutar localmente `backend/supabase/tests/run_backfill_local.ps1 -RecipeAdminConcurrency`. Los fixtures recipe_admin_* son exclusivamente locales. Pendiente remoto: ejecutar completo `tests/recipe_admin_rehearsal.sql`, como postgres con dos cuentas activas y la app inactiva, conservando ROLLBACK. Elegir Run without RLS si aparece.

Recetas administrativas: éxito remoto confirmado por el usuario («Success. No rows returned») del archivo completo con ROLLBACK. No se instalaron cambios permanentemente.


## Etiquetas alimentarias y clasificaciones de ingredientes

Preparadas en `202611010002_dietary_admin_rpcs.sql`.

- `admin_put_dietary_tag(p_tag jsonb,p_expected_version bigint) → jsonb`: campos exactos `id`, `tag_key`, `label`, `description`, `active`. Versión 0 crea con UUID estable; el reintento idéntico de creación solo se admite mientras la fila siga en versión 1. Editar exige la versión actual y no-op conserva versión/auditoría. La clave slug de 2..50 caracteres es inmutable; label 1..80 y description hasta 2000 caracteres. Desactivar/restaurar usa `active=false/true`; no se borra la etiqueta ni se alteran preferencias o recetas privadas que la referencien.
- `admin_save_ingredient_dietary_tags(p_ingredient_id uuid,p_tags jsonb,p_expected_version bigint) → jsonb`: reemplaza atómicamente hasta 100 vínculos `{tag_key,compatibility,note}`. `compatibility` es suitable/contains/unknown, nota obligatoria hasta 1000 caracteres; [] quita todos los vínculos. Rechaza claves repetidas, referencias inexistentes y nuevas etiquetas inactivas. Los vínculos inactivos o de un ingrediente inactivo se pueden conservar exactamente o quitar. Comparación sin importar orden: el no-op no aumenta versión ni auditoría.

Las clasificaciones comparten la versión del ingrediente existente: un cambio efectivo aumenta `ingredients.version`, de modo que otra edición de sus datos con versión vieja devuelve 40001. El cliente debe leer ingrediente, versión y vínculos en una consulta consistente; no confundir esta versión con `dietary_tags.version`, que protege los datos de la etiqueta.

Solo ADMIN activo puede escribir, con bloqueo global exclusivo antes del helper de cuenta/Auth. Se revoca DML directo; el admin puede leer etiquetas inactivas mediante la política existente. Se conservan todas las acciones de auditoría anteriores y se agregan catalog.dietary_tag_saved y catalog.ingredient_dietary_tags_saved, limitadas a entidad/versión, una fila por mutación efectiva. Errores sanitizados sin DETAIL personal.

Las claves de preferencias actuales (gluten-free, vegetarian, vegan, lactose-free, nut-free) se conservan; las etiquetas/aliases en español del frontend deberán mapearse por clave y no usarse como identidad lógica. Una etiqueta nueva no implica que el frontend actual de opciones fijas ya la ofrezca: la adaptación dinámica queda para la integración. Ninguna RPC infiere clasificaciones por nombres o modifica automáticamente las etiquetas declaradas de las recetas. Ausencia de clasificación no se transforma automáticamente en suitable.

PASS local y ROLLBACK completo. Concurrencia verificada entre escrituras de clasificaciones y datos del ingrediente, y democión mediante la sesión de operador que respeta el bloqueo global antes de actualizar user_roles; la llamada posterior con el mismo JWT se rechaza. Esta prueba ejercita el protocolo de revocación, no instala ni simula otro admin_set_user_role.

Regenerar `python backend/supabase/tests/build_dietary_admin_rehearsal.py`; ejecutar `backend/supabase/tests/run_backfill_local.ps1 -DietaryAdminConcurrency`. Los fixtures dietary_admin_* son exclusivamente locales. Pendiente remoto: ejecutar completo `tests/dietary_admin_rehearsal.sql` como postgres, con la app inactiva y dos cuentas activas, conservando el ROLLBACK final. Elegir Run without RLS si aparece.

Etiquetas alimentarias: éxito remoto confirmado por el usuario («Success. No rows returned») del archivo completo con ROLLBACK. No se instalaron cambios permanentemente.


## Configuración nutricional versionada

Preparada en `202611010003_nutrition_config_rpcs.sql`, sin insertar parámetros de producción durante la migración.

- `admin_publish_nutrition_config(p_config jsonb,p_expected_latest_version integer) → nutrition_config`: ADMIN activo publica una nueva fila inmutable. La versión se asigna como esperada+1; 0 inicia la primera. Si esa posición ya contiene exactamente los mismos datos/fecha/autor devuelve la fila original sin otra auditoría, incluso después de publicaciones posteriores. Una posición ocupada con otros datos o una versión esperada obsoleta devuelve 40001.
- `get_current_nutrition_config() → nutrition_config`: cuenta activa, devuelve la fila efectiva al comienzo de la petición con mayor `effective_at`, desempate por `config_version`; NULL si todavía no hay una efectiva. Una publicación futura no se convierte en vigente antes de su fecha. No recibe ni modifica perfiles de usuarios.
- `admin_list_nutrition_configs() → setof nutrition_config`: ADMIN activo, historial por versión descendente incluido lo programado. Revalida el rol después de esperar los bloqueos. El resto de usuarios no puede consultar versiones futuras mediante RLS.

Campos exactos de `p_config`: `activity_factors`, `goal_adjustments`, `source_note`, `effective_at`. Actividad requiere sedentary/light/moderate/active/very-active numéricos positivos hasta 10 con seis decimales; objetivos requiere lose/maintain/gain/gain-muscle, cada uno con minimum y maximum enteros dentro de ±10000 y minimum<=maximum. Son límites técnicos de entrada, no recomendaciones clínicas. La nota de origen es obligatoria, no vacía y hasta 2000 caracteres. La fecha exige ISO con zona horaria explícita y valor finito; debe conservarse al reintentar.

El cálculo y parámetros actuales del frontend se conservan; el ensayo extrae sus constantes directamente de `profile.ts`. El corte deberá publicar y verificar una configuración inicial equivalente antes de conectar el cálculo a esta lectura. Antes del corte el frontend sigue usando constantes; después deberá obtener una configuración vigente explícita, sin ocultar una ausencia mediante fallback silencioso. La fórmula y sus redondeos no se trasladan ni cambian en este módulo.

No se actualizan ni eliminan versiones antiguas: para corregir valores o deshacer una programación se publica otra versión con la fecha de vigencia adecuada. La versión máxima publicada y la actualmente efectiva son conceptos distintos. A igual fecha gana la versión más alta; una versión publicada ahora no cancela automáticamente otra ya programada para después.

La referencia `updated_by` proviene de Auth. La inmutabilidad permite únicamente que su FK pase a NULL al borrar al autor, manteniendo intactos parámetros, fechas y versión; el ensayo usa un usuario sintético creado y eliminado dentro del ROLLBACK, nunca elimina las cuentas reales de prueba. Auditoría nutrition.config_published limita detalles a versión/fecha y conserva acciones anteriores. Clientes sin DML directo; errores sanitizados.

PASS local y ROLLBACK completo. Concurrencia de dos publicaciones y denegación posterior a revocación, incluidas llamadas ADMIN en espera, aprobadas. Regenerar `python backend/supabase/tests/build_nutrition_config_rehearsal.py`; ejecutar localmente `backend/supabase/tests/run_backfill_local.ps1 -NutritionConfigConcurrency`. Los fixtures nutrition_config_* son exclusivamente locales. Pendiente remoto: ejecutar completo `tests/nutrition_config_rehearsal.sql` como postgres, con la app inactiva y dos cuentas activas, conservando ROLLBACK. Elegir Run without RLS si aparece.

Configuración nutricional: ensayo remoto completo aprobado por el usuario («Success. No rows returned»), con ROLLBACK final; sin despliegue permanente.


## Búsqueda, matching y tendencias de recetas

Migración `202611010004_recipe_discovery_rpcs.sql`; frontend pendiente de integración.

- `search_my_recipes(p_search text=null,p_meal_shift text=null,p_max_minutes integer=null,p_difficulty text=null,p_dietary_tag_keys text[]=array[]::text[],p_pantry_only boolean=false,p_portions integer=null,p_limit integer=30,p_offset integer=0)` devuelve `{items:[{recipe,stock,percentage,label}],total,limit,offset}`. Visibilidad: oficiales publicadas o propias, activas y no archivadas, incluso para ADMIN. Búsqueda literal sin distinguir acentos/mayúsculas en título, descripción e ingredientes; turno mediante clave canónica breakfast/lunch/snack/dinner, tiempo máximo, dificultad y todas las etiquetas seleccionadas. `recipe` conserva nombres relacionales snake_case; el adaptador deberá componer los detalles necesarios para el frontend.
- Stock usa exclusivamente la despensa del usuario y `check_my_cooking_stock`, sin recibir cantidades de stock del cliente. Porciones opcionales 1..20; defecto de cada receta. Porcentaje por grupos de ingredientes completamente cubiertos, con etiquetas del frontend. Referencias incompatibles/inactivas producen stock y porcentaje null; no se consideran listas para cocinar. La consulta es una vista previa, sin reserva ni descuento.
- Páginas de 1..50, offset 0..5000. Sin pantryOnly, solo se calcula stock de la página. Con pantryOnly, se evalúan candidatos antes del total/paginado; más de 500 candidatos devuelve 22023 y exige acotar filtros. No se trunca el total silenciosamente.
- `get_recipe_trends(p_days integer=30,p_limit integer=10)` publica únicamente conteos agregados de cocción y señal featured para recetas oficiales publicadas disponibles, nunca identidad ni historial individual. `get_my_recipe_trends` ofrece conteos del historial propio visible. Ambos requieren cuenta activa, orden determinista y límites validados; los resultados son derivados, sin tablas nuevas.

Ensayo remoto: `tests/recipe_discovery_rehearsal.sql`, completo como postgres y conservando ROLLBACK. No constituye despliegue ni conecta repositorios frontend.

Búsqueda/matching/tendencias: PASS local y ROLLBACK completo verificado; ensayo remoto pendiente. Usar null para búsqueda o turno sin filtro (el adaptador transforma los campos vacíos del frontend). Tendencias aceptan días 1..365 y límite 1..50, y excluyen eventos ocultos. La respuesta de búsqueda incluye ingredientes, pasos y vínculos de ingredientes de cada paso con IDs y posiciones estables.

Búsqueda/matching/tendencias: ensayo remoto completo aprobado por el usuario («Success. No rows returned»), conservando ROLLBACK; sin despliegue permanente.


## Solicitudes externas de IA y lectura de tickets

Migración `202611010005_external_request_rpcs.sql`. Controla solo metadatos de `recipe_generation_requests` y `receipt_recognition_requests`; no genera recetas ni interpreta imágenes. Proveedor candidato probable: Google Gemini; elección aún no definitiva. Mantener proveedor y modelo configurables mediante adaptadores, con claves exclusivamente en servidor.

- Servidor (`service_role`): `begin_external_request(p_owner uuid,p_request uuid,p_kind text,p_provider_model text=null)` crea pending con UUID estable, reloj del servidor y TTL fijo: recipe 24 horas, receipt 1 hora. Devuelve id/kind/status/provider_model/safe_error_code/created_at/expires_at. Repetir conserva fechas y resultado; propietario, tipo o modelo incompatibles dan 40001 sin exponer la solicitud ajena. receipt exige modelo null; recipe admite un identificador acotado, nunca credenciales.
- Servidor: `finish_external_request(p_owner uuid,p_request uuid,p_kind text,p_status text,p_safe_error_code text=null)` permite completed o failed desde pending. completed exige código null; failed exige provider_unavailable, provider_timeout, provider_rejected, invalid_provider_response, rate_limited o internal_error. Repetir un resultado idéntico conserva su estado; otro resultado terminal da 40001. pending vencido pasa a expired; repetir esa finalización devuelve expired. No se acepta contenido del proveedor.
- Usuario: `get_my_external_request(p_kind text,p_request uuid)` devuelve únicamente metadatos propios, incluso ADMIN; no acepta owner. `discard_my_receipt_request(p_request uuid)` cambia pending o completed a discarded, de forma idempotente. failed/expired conservan su estado; finish no puede reabrir discarded. Solicitudes inexistentes y ajenas dan P0002.
- Servidor: `purge_expired_external_requests(p_limit integer=100)` borra hasta 1..1000 registros por tabla con expires_at vencido, saltando filas bloqueadas. Devuelve recipe_deleted/receipt_deleted. Índices de vencimiento facilitan lotes; la programación periódica sigue pendiente. La garantía de idempotencia termina al purgar el UUID: el cliente debe generar IDs nuevos para operaciones nuevas.

Las funciones de usuario y servidor comprueban cuenta/ban actuales bajo los bloqueos de cuenta existentes. Se revoca escritura directa a clientes y service_role; las escrituras pasan por RPC privilegiadas. Solo service_role puede iniciar, finalizar y purgar. No se guardan fotos, prompts, texto OCR, respuestas, claves ni errores crudos; no se crean buckets. El resultado completed es un estado operativo: la futura Edge Function debe validar su salida antes de marcarlo y realizar las escrituras de dominio correspondientes. Esta capa no evita por sí sola llamadas duplicadas al proveedor ni conserva una respuesta que permita reconstruir un preview perdido; la integración Edge deberá resolver la adquisición de la ejecución y los reintentos. El descarte no deshace artículos ya confirmados en despensa.

Solicitudes externas: PASS local del ensayo completo y ROLLBACK, más pruebas de concurrencia de identidad/reintentos, revocación y cancelación/finalización. Pendiente remoto `tests/external_requests_rehearsal.sql`; ejecutar el archivo completo como postgres con dos cuentas activas y la app inactiva, conservando ROLLBACK. No supone integración real de Gemini ni despliegue.


## Consultas personales: perfil, favoritos y planificación

Migración `202611010006_personal_read_rpcs.sql`. Depende de personal/planning y del formateador de recetas de `202611010004`; no depende de `202611010005`, de funciones Edge ni del proveedor IA.

- `get_my_profile() → {profile,preference_keys}` devuelve la fila completa con versión o null si falta, y las claves ordenadas de preferencias propias. Conserva claves previamente guardadas aunque una etiqueta se desactive; no inventa un perfil ni escribe valores por defecto. El adaptador debe mostrar/revisar las preferencias inactivas antes de guardar, respetando las validaciones de escritura existentes. No entrega email de Auth ni configura cálculos nutricionales.
- `get_my_favorites(p_limit integer=30,p_offset integer=0) → {items,total,limit,offset}` devuelve items `{recipe_id,created_at,available,recipe}`. Límite 1..100, offset 0..5000; orden created_at descendente y UUID descendente para empates. El total incluye favoritos no disponibles, que se pueden quitar con la RPC existente. recipe solo se compone para oficiales publicadas o privadas propias, activas y no archivadas; de lo contrario es null y available=false, incluso para ADMIN. Los detalles usan snake_case, IDs relacionales y vínculos de pasos del formateador existente, sin calcular stock.
- `get_my_meal_plan(p_week_start date) → {plan,slots}` requiere un lunes finito. Una semana inexistente devuelve plan null y slots []; un plan vacío conserva su fila y versión. Cada slot mantiene sus campos reales (ID, fecha, turno, posición, recipe_id y porciones) y agrega available/recipe con la misma regla de visibilidad. Orden: fecha, breakfast/lunch/snack/dinner, posición, UUID. No existen snapshots de receta en meal_plan_slots y esta migración no los agrega.

Cada respuesta se arma en una sola sentencia SQL después del helper de bloqueo/autorización existente; perfil/preferencias y plan/slots comparten snapshot. Todas las funciones derivan el propietario de auth.uid(), exigen cuenta activa y READ COMMITTED, revocan EXECUTE de public/anon/service_role y lo conceden únicamente a authenticated. No se escriben datos de dominio ni se cambia el frontend. available indica visibilidad de la receta, no stock suficiente ni garantía de que sus referencias de catálogo permitan iniciar una cocción.

Consultas personales: PASS local y ROLLBACK completo verificado. Regenerar con `python backend/supabase/tests/build_personal_reads_rehearsal.py`; ejecutar localmente `backend/supabase/tests/run_backfill_local.ps1 -PersonalReads`. Pendiente remoto `tests/personal_reads_rehearsal.sql`, completo como postgres con la app inactiva y dos cuentas activas, conservando ROLLBACK. El fixture que crea service_role es exclusivamente local; no forma parte del ensayo remoto.

Consultas personales: ensayo remoto completo aprobado por el usuario («PASS: personal read RPC rehearsal complete; wrapper ROLLBACK required»). Se verificó que el archivo termina en ROLLBACK; ejecutándolo completo no hace falta otro rollback. Sin despliegue permanente. Siguiente grupo autorizado: consultas de despensa y compras, sin configurar proveedor IA.


## Consultas de despensa y compras

Migración `202611010007_inventory_read_rpcs.sql`, independiente del proveedor IA y de `202611010005`.

- `get_my_pantry(p_search text=null,p_category text=null,p_status text='all',p_limit integer=50,p_offset integer=0)` devuelve `{items,total,limit,offset,as_of}`. Mantiene cada fila y sus cantidades exactas, versión, referencias nullable y productos manuales. Agrega `flags:{days,empty,low,soon,expired}` y `status`. empty: cantidad cero; low: mínimo positivo y cantidad positiva menor al mínimo; soon: vencimiento de hoy a tres días inclusive; expired: fecha anterior a hoy. Los flags pueden superponerse y el estado visible prioriza expired, empty, soon, low, ok. El filtro low incluye empty; ok excluye todos los flags. Estados aceptados: all/ok/low/empty/soon/expired.
- La búsqueda literal por nombre y la categoría exacta se normalizan por NFD, acentos, mayúsculas y espacios. % y _ no son comodines. Búsqueda/categoría vacías o de solo espacios no filtran; longitudes máximas 120/80. El total se calcula después de filtrar y antes de paginar; orden por nombre normalizado y UUID. No se agregan filas por ingrediente ni se adivinan asociaciones.
- `get_my_shopping_list(p_list_id uuid=null,p_limit integer=100,p_offset integer=0)` devuelve `{list,items,total,limit,offset}`. Sin ID devuelve la lista activa propia, o list null/items []/total 0 si falta. Con ID permite leer listas archivadas propias; UUID desconocido o ajeno da P0002. Cada item conserva sus campos, nombre/categoría guardados, checked y transferred_at; agrega `unit_detail` con la fila del catálogo incluso inactiva, y `sources` con filas de origen ordenadas por UUID. No se expanden recetas ni planes privados a partir de esos orígenes. Artículos ordenados por created_at ascendente y UUID ascendente; la versión de lista, artículos, orígenes y total se componen en una sentencia SQL bajo el bloqueo de cuenta.
- `get_my_shopping_lists(p_status text=null,p_limit integer=30,p_offset integer=0)` devuelve metadatos de listas propias como `{items,total,limit,offset}`. null/all incluye activas y archivadas; acepta active/archived para filtrar. Orden updated_at descendente y UUID descendente.

Las tres páginas aceptan límite 1..100 y offset 0..5000, con errores 22023 para parámetros inválidos. Requieren cuenta activa y READ COMMITTED mediante el helper existente; solo authenticated recibe EXECUTE y el propietario siempre deriva de auth.uid(), incluso ADMIN. Son consultas: no cambian cantidades, versiones, marcas ni transferencias. `as_of` usa la fecha del servidor de la sesión SQL (UTC en la configuración habitual de Supabase); la integración debe decidir cómo presentar el día local y no mezclar bases de fecha al calcular alertas. No se configura IA ni se conecta el frontend con esta migración.

Consultas de compras/despensa: PASS local del ensayo completo y ROLLBACK verificado. Regenerar con `python backend/supabase/tests/build_inventory_reads_rehearsal.py`; ejecutar localmente `backend/supabase/tests/run_backfill_local.ps1 -InventoryReads`. Pendiente remoto `tests/inventory_reads_rehearsal.sql`, completo como postgres y con la app inactiva. El archivo ya incluye ROLLBACK final; no ejecutar fixtures locales en Supabase ni aplicar migraciones sueltas durante el ensayo.

Consultas de compras/despensa: ensayo remoto completo aprobado por el usuario («PASS: inventory reads verified; full script includes ROLLBACK»). Sin despliegue permanente; el archivo completo incluye ROLLBACK. Siguiente grupo autorizado: resumen del panel de inicio, manteniendo pospuesta la configuración IA.


## Resumen personal del panel de inicio

`202611010008_dashboard_summary_rpc.sql`: `get_my_dashboard_summary(p_day date=current_date,p_recent_limit integer=4)` devuelve `{as_of,profile,pantry,favorites,shopping,today_plan,recent_preparations}`. Día finito entre 1900-01-01 y 9999-12-31 y límite 1..20; parámetros inválidos dan 22023. p_day permite usar el día local del usuario para alertas y planificación; no altera stock ni reconstruye un inventario histórico.

profile reutiliza `{profile,preference_keys}`. pantry devuelve total/low/empty/soon/expired sobre todas las filas propias, sin limitarse a una página; low incluye vacíos, soon cubre del día elegido a tres días después y expired fechas anteriores. Las alertas pueden superponerse. favorites devuelve total y available según visibilidad de recetas oficiales publicadas/privadas propias activas y no archivadas, incluso para ADMIN. shopping devuelve active_list_id/version y pending_items/checked_items/transferred_items de la lista activa propia; una transferencia excluye el artículo de los otros dos contadores. Si falta lista, ID/versión son null y contadores cero.

today_plan conserva la fila/versión de la semana correspondiente pero solo incluye slots de p_day, con orden y visibilidad de get_my_meal_plan. recent_preparations reutiliza el historial propio no oculto, ordenado por cooked_at/UUID descendente, conservando snapshots históricos aunque la receta ya no esté disponible; p_day no filtra este historial. Se reutilizan consultas existentes bajo los bloqueos de cuenta y catálogo: las escrituras autorizadas de la misma cuenta y los cambios de catálogo esperan hasta terminar la transacción. Solo authenticated recibe EXECUTE; propietario derivado de auth.uid(), cuenta activa, READ COMMITTED y sin escrituras de dominio.

Este resumen aporta datos al panel y no sustituye por sí solo DashboardRepository.loadHome: las recomendaciones, selección por horario y ranking actuales siguen en el frontend, y el adaptador debe combinar las consultas de recetas/despensa necesarias. No se modifica el frontend ni se configura el proveedor IA en este bloque.

Resumen de panel: PASS local y ROLLBACK completo verificado. Regenerar con `python backend/supabase/tests/build_dashboard_summary_rehearsal.py`; ejecutar localmente `backend/supabase/tests/run_backfill_local.ps1 -DashboardSummary`. Pendiente remoto `tests/dashboard_summary_rehearsal.sql`, completo como postgres, con la app inactiva y conservando ROLLBACK. No incluye la migración externa 005 ni requiere configurar IA.

Panel de inicio: ensayo remoto completo aprobado por el usuario («PASS: dashboard summary verified; full script includes ROLLBACK»). Sin despliegue permanente. Auditoría de integración completada en FRONTEND_INTEGRATION_AUDIT.md: adaptadores/versiones/IDs, lecturas conocidas de recetas, reanudación por receta, selección de fechas en sugerencias y nombres administrativos requieren cerrar su integración antes del corte. IA continúa pospuesta; el ensayo externo 005 permanece pendiente. Esta etapa no requiere nuevo ensayo SQL.
