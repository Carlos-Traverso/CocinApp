# Migraciones

Agregar aquí migraciones SQL numeradas de forma cronológica. Incluir tablas, claves, constraints, índices, políticas RLS y funciones PostgreSQL junto con el cambio que las necesita. Mantener cada migración aplicada como inmutable.

## Nombres de tablas en español

`202611010009_rename_tables_spanish.sql` es el corte final de nombres y renombra las 36 tablas de la aplicación en una transacción. Conserva filas y columnas, claves, políticas, índices y triggers; `auth.users`, los nombres de RPC y los contratos JSON permanecen intactos. También actualiza las referencias de tablas en funciones PL/pgSQL y los despachadores de triggers que comparan `TG_TABLE_NAME`.

| Nombre previo | Nombre final |
| --- | --- |
| `pantry_items` | `articulos_despensa` |
| `personal_data` | `datos_personales` |
| `user_roles` | `roles_usuario` |
| `catalog_core` | `catalogo_base` |
| `shared_recipes` | `recetas_compartidas` |
| `account_status` | `estado_cuenta` |
| `admin_audit_log` | `registro_auditoria` |
| `dietary_tags` | `etiquetas_dieteticas` |
| `nutrition_config` | `configuracion_nutricional` |
| `profiles` | `perfiles` |
| `user_dietary_preferences` | `preferencias_dieteticas_usuario` |
| `categories` | `categorias` |
| `units` | `unidades` |
| `ingredients` | `ingredientes` |
| `ingredient_dietary_tags` | `etiquetas_dieteticas_ingrediente` |
| `recipes` | `recetas` |
| `recipe_meal_shifts` | `turnos_comida_receta` |
| `recipe_dietary_tags` | `etiquetas_dieteticas_receta` |
| `recipe_ingredients` | `ingredientes_receta` |
| `recipe_steps` | `pasos_receta` |
| `recipe_step_ingredients` | `ingredientes_paso_receta` |
| `favorite_recipes` | `recetas_favoritas` |
| `meal_plans` | `planes_comida` |
| `meal_plan_slots` | `turnos_plan_comida` |
| `pantry_receipts` | `comprobantes_despensa` |
| `shopping_lists` | `listas_compras` |
| `shopping_items` | `articulos_compra` |
| `shopping_item_sources` | `origenes_articulo_compra` |
| `pantry_receipt_items` | `articulos_comprobante_despensa` |
| `cooking_sessions` | `sesiones_cocina` |
| `cooking_session_steps` | `pasos_sesion_cocina` |
| `cooking_events` | `eventos_cocina` |
| `cooking_event_ingredients` | `ingredientes_evento_cocina` |
| `recipe_generation_requests` | `solicitudes_generacion_receta` |
| `receipt_recognition_requests` | `solicitudes_reconocimiento_ticket` |
| `admin_recipe_write_state` | `estado_escritura_receta_admin` |

La aplicación cliente que consulta estas tablas debe publicarse junto con la migración; antes del corte, la base remota todavía conserva los nombres anteriores. El ensayo remoto está en `../tests/table_rename_rehearsal.sql`: requiere las siete tablas legacy, instala dentro de la transacción las migraciones pendientes hasta 202611010008 y termina en `ROLLBACK`. Ejecutar el archivo completo como `postgres` y conservar ese rollback final. No se aplicó ningún cambio remoto. Para validar localmente, ejecutar `../tests/run_table_rename_local.ps1`; prueba el ensayo desde el corte legacy, verifica que el rollback restaura tablas/datos y elimina estructuras/RPCs staged, luego instala el historial completo, aplica el 009 real, compara OIDs/columnas/constraints/índices/RLS/policies/triggers/grants y corre los 18 stages con rollback.

## Modelo relacional CocinAPP

`202610300002_add_relational_domain_tables.sql` es una migración aditiva preparada para introducir las tablas relacionales del modelo acordado. Depende de las funciones ya aplicadas `current_app_role()` y `current_account_is_active()`, y del esquema existente de `pantry_items`. Crea las nuevas tablas con RLS y conserva intactas las filas JSON de `personal_data`, `catalog_core` y `shared_recipes`.

No ejecutar esta migración hasta completar una revisión previa del SQL contra el esquema desplegado y preparar una copia de seguridad verificada. Aplicarla no completa todavía la migración de datos ni conecta el frontend al nuevo modelo. El backfill se hará con scripts separados, repetibles y con reportes de reconciliación; no quitar las tablas/columnas anteriores durante esta etapa.

Revisión local realizada: la migración completa ejecutó correctamente en PostgreSQL 18 aislado, con dependencias de Auth simuladas, y creó 28 tablas con RLS. Eso comprueba ejecución del DDL, no reemplaza las pruebas de permisos en Supabase/PostgreSQL 17. Se agregaron políticas restrictivas para cuentas activas y validaciones de enlaces entre unidades, recetas y planes. Las nuevas tablas solo conceden SELECT al cliente hasta incorporar las RPC de escritura y sus verificaciones de concurrencia. Los repositorios existentes siguen utilizando las tablas anteriores.

Antes del backfill, ejecutar únicamente `../diagnostics/relational_backfill_inventory.sql` y revisar sus resultados. Devuelve cantidades, nombres de campos y tipos JSON; no devuelve valores personales ni identificadores de cuentas. La ejecución en producción de la migración estructural sigue pendiente.


## Primer grupo de RPC personales

`202610300003_personal_write_rpcs.sql` agrega versión al perfil y las funciones `save_my_profile` (perfil y preferencias atómicos) y `set_my_favorite` (estado deseado, propietario autenticado). Las tablas siguen sin DML directo para clientes. Las pruebas locales incluyeron dos conexiones simultáneas, desactivación administrativa y bloqueo de Auth. El ensayo remoto de este grupo fue aprobado; para repetirlo, ejecutar únicamente el envoltorio rollback-only `../tests/personal_write_rpcs_rehearsal.sql`. Contratos y alcance en `../RPC_CONTRACTS.md`. No conectar los repositorios nuevos antes de desplegar esquema, backfill y RPC coherentemente.


## Planificación y compras

`202610300004_planning_write_rpcs.sql` agrega guardado semanal con versión e ID estable. `202610300005_shopping_write_rpcs.sql` agrega versión de listas, creación idempotente/archivado, artículos y orígenes atómicos, marcado y eliminación conservando los comprobantes. Necesitan 300002 y 300003. No incluyen todavía sugerencias, transferencia de stock ni finalización de cocción. Pruebas locales de permisos, datos inválidos, versiones y concurrencia aprobadas; revisión independiente sin hallazgos bloqueantes. El usuario confirmó PASS remoto del envoltorio `../tests/planning_shopping_write_rpcs_rehearsal.sql` completo con su ROLLBACK. No aplicar estas migraciones definitivamente antes del corte acordado.


## Transferencia y propuestas de compras

`202610300006_shopping_transfer_rpcs.sql` agrega transferencia atómica con comprobantes e idempotencia y amplía cantidad/mínimo de despensa a cuatro decimales. Conserva artículos manuales sin asociación al catálogo. `202610300007_shopping_suggestions_rpc.sql` agrega propuestas de planificación, favoritos y reposición sin escribir listas. Contratos en `../RPC_CONTRACTS.md`.

Los envoltorios `../tests/shopping_transfer_rehearsal.sql` y `../tests/shopping_suggestions_rehearsal.sql` incluyen sus dependencias y terminan en ROLLBACK. Ejecutar completos como postgres, con dos cuentas existentes activas y la aplicación inactiva. En el SQL Editor elegir **Run without RLS** si aparece la confirmación: los ensayos ya declaran RLS. No ejecutar las migraciones sueltas durante los ensayos. La comprobación remota de este grupo sigue pendiente.

Validación 2026-10-31: ambos ensayos locales y ROLLBACK completo aprobados; reintentos concurrentes de transferencia aprobados. Auditoría independiente sin hallazgos pendientes. Ensayos remotos todavía pendientes.

Actualización remota: transferencia PASS confirmado; sugerencias requiere repetir el ensayo corregido. Ninguna de estas RPC fue instalada permanentemente.

Sugerencias: ensayo remoto corregido completado por el usuario con «Success. No rows returned». El archivo completo termina en ROLLBACK; no se instalaron estructuras permanentemente. El grupo transferencia/sugerencias tiene aprobación local y remota.


## Operaciones de despensa

`202610310001_pantry_write_rpcs.sql` prepara CRUD con versiones por artículo y confirmación por lote atómica. El trigger de versión también alcanza escrituras confiables de transferencia. Revoca escritura directa de clientes al desplegarse: requiere adaptar el repositorio legacy al corte, no ejecutarla sola en la base actual.

Ensayo remoto: ejecutar completo `../tests/pantry_write_rpcs_rehearsal.sql`, como postgres, con dos cuentas Auth activas y la app inactiva. Incluye sus dependencias y termina en ROLLBACK. Elegir **Run without RLS** si aparece el aviso. Los archivos `fixtures/pantry_write_concurrency_install.sql` y `pantry_rpc_concurrency_local.py` son exclusivamente para el PostgreSQL aislado local.

Despensa: el usuario confirmó PASS remoto de CRUD/lotes, reintentos, validación, conflictos de versión con transferencia, aislamiento y revocación de DML. El archivo completo incluye ROLLBACK; despliegue definitivo y cambio de repositorio siguen pendientes.


## Sesiones y temporizadores

`202610310002_cooking_session_rpcs.sql` agrega inicio idempotente, snapshot, consulta de reanudación, progreso con versión y timers con deadlines del servidor. No descuenta stock ni finaliza cocción. Pruebas locales con ROLLBACK y concurrencia aprobadas; auditoría sin bloqueantes. Ensayo remoto pendiente: ejecutar únicamente `../tests/cooking_session_rehearsal.sql` completo, con ROLLBACK. La instalación aislada para concurrencia no es un script de despliegue remoto. El nuevo escritor administrativo deberá bloquear la receta padre antes de modificar sus detalles para coordinar snapshots consistentes.

Sesiones y temporizadores: éxito remoto confirmado por el usuario («Success. No rows returned»); el envoltorio completo termina en ROLLBACK. No hace falta un ROLLBACK adicional si se ejecutó completo. La finalización con stock e historial es el siguiente grupo.


## Finalización de cocción

`202610310003_cooking_finish_rpcs.sql` agrega finalización atómica con descuento opcional de stock, evento único por sesión y snapshots agregados de consumo. Las repeticiones conservan el evento y la decisión inicial. El grupo aprobó pruebas locales, rollback completo y concurrencia; pendiente de ensayo remoto con `../tests/cooking_finish_rehearsal.sql` completo. El frontend, limpieza visual del historial y despliegue definitivo continúan pendientes. No ejecutar las migraciones individuales durante los ensayos.

Finalización de cocción: ensayo remoto completo aprobado por el usuario con «Success. No rows returned». El ROLLBACK ya incluido revierte los cambios; no hubo instalación permanente. Siguiente grupo: consultas de faltantes e historial con ocultación segura, sin borrar el evento de idempotencia.


## Faltantes e historial

`202610310004_cooking_queries_history_rpcs.sql` agrega consulta de stock por receta/sesión y lectura paginada, ocultación y limpieza del historial. Conserva eventos/consumos de idempotencia; RLS filtra los ocultos. PASS local con ROLLBACK; pendiente remoto `../tests/cooking_queries_rehearsal.sql` completo. El frontend deberá usar el snapshot/porciones de la sesión al consultar faltantes y paginar/filtrar historia visible también para recomendaciones.

Consultas de cocción e historial: éxito remoto confirmado por el usuario («Success. No rows returned») del envoltorio completo con ROLLBACK. No se instalaron cambios permanentemente.


## Administración de categorías, unidades e ingredientes

`202610310005_catalog_admin_rpcs.sql` agrega versiones, escrituras ADMIN, normalización, archivado/restauración, protección de referencias y acciones nuevas de auditoría. Mantiene las estructuras legacy y no conecta el frontend. PASS local con rollback y concurrencia; pendiente remoto `../tests/catalog_admin_rehearsal.sql` completo. No ejecutar los fixtures catalog_admin_* en Supabase ni las migraciones individuales durante los ensayos.

Administración de categorías/unidades/ingredientes: ensayo remoto completo aprobado por el usuario («Success. No rows returned»). El ROLLBACK final conserva la base anterior; despliegue y adaptación del frontend siguen pendientes.


## Administración de recetas

`202611010001_recipe_admin_rpcs.sql` agrega versión y guardado de recetas oficiales con detalles atómicos, copia idempotente, flags, archivo/restauración y auditoría. Incluye una tabla auxiliar privada para reintentos, adicional a las 28 del dominio, con RLS y sin acceso cliente. PASS local, rollback completo y concurrencia aprobados; pendiente remoto `../tests/recipe_admin_rehearsal.sql` completo. No ejecutar fixtures locales ni aplicar migraciones individuales durante los ensayos. Frontend y despliegue definitivo continúan pendientes.

Recetas administrativas: éxito remoto confirmado por el usuario («Success. No rows returned») del archivo completo con ROLLBACK. No se instalaron cambios permanentemente.


## Etiquetas alimentarias

`202611010002_dietary_admin_rpcs.sql` agrega administración de etiquetas con clave estable, desactivación/restauración y versión, y reemplazo atómico de clasificaciones por ingrediente con su versión compartida. Conserva preferencias/recetas y audita cambios efectivos. PASS local con ROLLBACK y concurrencia; pendiente remoto `../tests/dietary_admin_rehearsal.sql` completo. No aplicar fixtures ni migraciones sueltas en Supabase durante los ensayos; frontend y despliegue siguen pendientes.

Etiquetas alimentarias: éxito remoto confirmado por el usuario («Success. No rows returned») del archivo completo con ROLLBACK. No se instalaron cambios permanentemente.


## Configuración nutricional

`202611010003_nutrition_config_rpcs.sql` agrega publicación de versiones inmutables, fechas de vigencia, lectura actual y listado ADMIN, con auditoría y permisos. No cambia los parámetros/formula actuales ni instala una semilla de producción. PASS local con ROLLBACK y concurrencia; pendiente remoto `../tests/nutrition_config_rehearsal.sql` completo. La activación del nuevo repositorio deberá incluir una configuración inicial verificada; no ejecutar fixtures ni migraciones sueltas en Supabase durante ensayos.

Configuración nutricional: ensayo remoto completo aprobado por el usuario («Success. No rows returned»), con ROLLBACK final; sin despliegue permanente.

## Búsqueda, matching y tendencias

`202611010004_recipe_discovery_rpcs.sql` agrega búsqueda/filtros, readiness usando stock propio y tendencias personales/globales de recetas oficiales. PASS local con ROLLBACK completo; pendiente remoto `../tests/recipe_discovery_rehearsal.sql` como un único lote con ROLLBACK final. Ejecutar localmente `tests/run_backfill_local.ps1 -RecipeDiscovery`; regenerar con `python tests/build_recipe_discovery_rehearsal.py`. Sin tablas nuevas ni integración frontend.

Búsqueda/matching/tendencias: ensayo remoto completo aprobado por el usuario («Success. No rows returned»), conservando ROLLBACK; sin despliegue permanente.

## Metadatos de solicitudes IA/OCR

`202611010005_external_request_rpcs.sql` agrega RPC de inicio/finalización exclusivamente de servidor, lectura propia, descarte de tickets y purga acotada por vencimiento. No crea tablas ni llama proveedores. PASS local, ROLLBACK completo y concurrencia; pendiente remoto `../tests/external_requests_rehearsal.sql`, completo como postgres, con dos cuentas activas y ROLLBACK final. Regenerar con `python tests/build_external_requests_rehearsal.py`; ejecutar localmente `tests/run_backfill_local.ps1 -ExternalRequestsConcurrency`. El fixture de service_role y el instalador external_requests_schema_local.sql son exclusivamente locales. No desplegar Edge Functions durante este ensayo.

## Consultas personales sin dependencia de IA

`202611010006_personal_read_rpcs.sql` agrega lecturas coherentes de perfil/preferencias, favoritos y planificación semanal. Requiere las RPC personales/planning y el formateador de recetas de 202611010004; no depende de 202611010005 ni del proveedor IA. PASS local y ROLLBACK completo; pendiente remoto `../tests/personal_reads_rehearsal.sql` completo. Regenerar con `python tests/build_personal_reads_rehearsal.py`; ejecutar localmente `tests/run_backfill_local.ps1 -PersonalReads`. Los cambios de permisos mantienen el helper de bloqueo interno sin acceso service_role; solo las tres RPC de lectura son accesibles a authenticated. No conectar el frontend ni aplicar migraciones sueltas durante el ensayo.

Consultas personales: ensayo remoto completo aprobado por el usuario («PASS: personal read RPC rehearsal complete; wrapper ROLLBACK required»). Se verificó que el archivo termina en ROLLBACK; ejecutándolo completo no hace falta otro rollback. Sin despliegue permanente. Siguiente grupo autorizado: consultas de despensa y compras, sin configurar proveedor IA.

## Consultas de compras y despensa

`202611010007_inventory_read_rpcs.sql` agrega lectura paginada de despensa con flags/estados, listas de compras y sus artículos/orígenes/detalle de unidad, sin modificar datos ni versiones. Reutiliza autorización por cuenta; no depende de 005 ni del proveedor IA. PASS local y ROLLBACK completo; pendiente remoto `../tests/inventory_reads_rehearsal.sql`. Regenerar con `python tests/build_inventory_reads_rehearsal.py`; probar localmente con `tests/run_backfill_local.ps1 -InventoryReads`. En Supabase ejecutar solo el ensayo completo como postgres y conservar su ROLLBACK final; no hace falta otro rollback después.

Consultas de compras/despensa: ensayo remoto completo aprobado por el usuario («PASS: inventory reads verified; full script includes ROLLBACK»). Sin despliegue permanente; el archivo completo incluye ROLLBACK. Siguiente grupo autorizado: resumen del panel de inicio, manteniendo pospuesta la configuración IA.

## Resumen del panel de inicio

`202611010008_dashboard_summary_rpc.sql` reúne perfil, alertas completas de despensa, conteos de favoritos/compras, planificación del día e historial propio reciente bajo los bloqueos existentes. Reutiliza consultas previas; fecha de calendario explícita y límite de historial 1..20. No depende de la migración externa 005 ni configura proveedor IA. PASS local y ROLLBACK completo; pendiente remoto `../tests/dashboard_summary_rehearsal.sql`, como único lote postgres con el ROLLBACK final incluido. Regenerar con `python tests/build_dashboard_summary_rehearsal.py`; probar localmente `tests/run_backfill_local.ps1 -DashboardSummary`. No sustituye la integración del repositorio HomePage ni despliega cambios permanentes.

Panel de inicio: ensayo remoto completo aprobado por el usuario («PASS: dashboard summary verified; full script includes ROLLBACK»). Sin despliegue permanente. Auditoría de integración completada en FRONTEND_INTEGRATION_AUDIT.md: adaptadores/versiones/IDs, lecturas conocidas de recetas, reanudación por receta, selección de fechas en sugerencias y nombres administrativos requieren cerrar su integración antes del corte. IA continúa pospuesta; el ensayo externo 005 permanece pendiente. Esta etapa no requiere nuevo ensayo SQL.
