# Auditoría de contratos antes de integrar el frontend

Fecha: 2026-11-01. Alcance: revisión estática de repositorios, llamadas de pantallas, migraciones y contratos; dos subagentes de lectura y contraste del coordinador. No se modificó código de aplicación ni se ejecutó un despliegue. La configuración del proveedor IA continúa pospuesta.

## Estado comprobado

El usuario aprobó el ensayo remoto completo de dashboard_summary, con ROLLBACK incluido. Las operaciones principales de 26/28 tablas de dominio tienen ensayos locales/remotos aprobados; esto no mide el porcentaje total del backend. El ensayo de metadatos externos 005 sigue pendiente y la integración real IA/OCR está fuera de este bloque. El frontend continúa usando repositorios legacy; ningún ensayo instala el modelo permanentemente.

La mayor parte de las operaciones de dominio ya dispone de RPC. La conexión requiere adaptadores y cerrar diferencias concretas de consulta/comportamiento; los ensayos aislados no demuestran compatibilidad integral de las pantallas.

## Matriz de integración

| Área / operación actual | Contrato relacional disponible | Trabajo pendiente |
| --- | --- | --- |
| Perfil y preferencias | get_my_profile, save_my_profile | Mapear name/camelCase y preference_keys; conservar versión; recargar tras 40001. Revisar preferencias inactivas sin eliminarlas silenciosamente. |
| Favoritos | get_my_favorites, set_my_favorite | Resolver IDs legacy a UUID; sustituir guardado de arrays por estado deseado; conservar favoritos no disponibles para permitir quitarlos. |
| Planificación | get_my_meal_plan, save_my_meal_plan | Separar por semanas ISO, mapear turnos españoles a claves, conservar ID/versión de cada semana y planes vacíos. |
| Compras | get_my_shopping_list(s), create/put/check/remove, transfer_my_shopping_to_pantry | Mapear lista/versiones/unidades/orígenes; mantener claves de reintento y comprobantes; sustituir save(array) por operaciones versionadas. |
| Sugerencias del plan | suggest_my_shopping('plan', plan_id, as_of) | La UI elige fechas concretas, posiblemente de varias semanas; la RPC agrega una semana completa. Cerrar contrato de subconjunto de fechas antes de reemplazar ese flujo. |
| Despensa / confirmación de productos | get_my_pantry, put_my_pantry_item(s), delete_my_pantry_item | Sustituir upsert/delete de listas completas por RPC por fila/lote; conservar versión, manuales y referencias nullable. No enviar orígenes como autoridad. |
| Cocción e historial | start/get/update/finish session, check_my_cooking_stock, get/hide/clear history | Mapear snapshot, versión, índices de pasos y timers; finalizar en una sola RPC. Resolver búsqueda de sesión abierta por receta al recuperar desde otro dispositivo. |
| Recetas | search_my_recipes, stock, tendencias; formateador interno | Cerrar detalle por UUID/legacy_id y listKnown/includeInactive. La búsqueda actual entrega recetas activas; no sustituye por sí sola el catálogo conocido/inactivo. |
| Administración de catálogo/recetas | admin_put_category/unit/ingredient, admin_save_recipe, duplicate/flags, etiquetas y nutrición | Definir lectura coherente de referencias/detalles/versiones para el editor; reemplazar escrituras JSON por operaciones por entidad. admin_recipe_export es interno, sin EXECUTE cliente. |
| Administración de nombres | Edge admin-users y admin_list_users actuales | Continúan escribiendo/leyendo personal_data.profile. Adaptar al perfil relacional, preservando autorización, versión y otros campos. |
| Inicio | get_my_dashboard_summary y consultas de recetas/despensa/perfil | Componer DashboardRepository.loadHome y mantener recomendaciones/ranking del frontend; el resumen no contiene todos sus datos. |
| Nutrición | get_current_nutrition_config y publicación ADMIN | Antes de activar el nuevo repositorio publicar una configuración inicial verificada; no tratar ausencia como configuración válida. Fórmula actual sin cambios. |

## Brechas que deben cerrarse explícitamente

1. **Recetas conocidas, detalle e IDs.** RecipeRepository.ts:9-10 pide listKnown y getById(includeInactive); RecipeDetailPage.tsx:42 e HistoryPage.tsx los usan. search_my_recipes solo descubre activas/no archivadas. La política recipes_read_visible de 202610300002 también excluye inactivas para USER, y las referencias de catálogo inactivas pueden quedar fuera de sus SELECT. Definir un contrato que entregue únicamente oficiales permitidas o privadas propias, incluya los datos históricos necesarios y resuelva legacy_id sin ambigüedad. El permiso de revisión ADMIN no debe ampliar las consultas personales a recetas privadas ajenas.
2. **Reanudación por receta.** CookingRepository.ts:6 y MockCookingRepository.ts:15 buscan por recipeId; get_my_cooking_session exige session_id. Una lectura RLS puede localizar sesiones propias, pero falta fijar el contrato compartido y la regla si hay varias abiertas. El índice actual no impone una sola sesión abierta por usuario/receta. Guardar el UUID solo en un navegador no resuelve la recuperación desde otro dispositivo.
3. **Fechas seleccionadas de planificación.** MockShoppingRepository.ts:46-54 filtra fechas antes de sumar necesidades. 202610300007 selecciona todos los slots del plan. No se deben sumar previews de semanas por separado y luego unirlos: cada preview podría descontar la misma despensa de nuevo. La agregación de fechas elegidas y el descuento de stock deben hacerse una vez.
4. **Nombres administrativos.** functions/admin-users/index.ts:139-159 todavía lee/upserta el JSON de perfil; admin_list_users en 202610170002 también lo consulta. Cambiar solo ProfileRepository dejaría dos fuentes de nombre. La futura operación debe coordinar nombre y versión del perfil relacional sin reemplazar preferencias ni campos privados completos.

La confirmación de varias sugerencias de compras también debe respetar una semántica definida: hoy hay put individual y batch de marcado, pero no batch de alta de artículos. El contrato existente ya reconoce posibles confirmaciones parciales. El adaptador debe mostrar/reintentar resultados por artículo, o implementar un batch transaccional si se decide mantener confirmación todo o nada; no presentar una secuencia HTTP como una transacción atómica.

## Reglas de los adaptadores

- Un único mapeo de IDs/legacy_id, camelCase/snake_case, turnos, tags y unidades. No crear otra receta para un seed ya importado; aplicar la precedencia seed + overrides del backfill.
- Conservar versiones y UUID de operación entre reintentos. Un 40001 exige recarga y resolución; nunca reenviar automáticamente un snapshot viejo con la versión nueva.
- Mantener las comprobaciones de sesión/propietario de personalDataSession.ts antes y después de las peticiones y antes de actualizar cachés. Evitar dobles escrituras legacy/relacional y sincronización por eventos que vuelva a guardar todo el inventario.
- supabasePantryRepository.ts:51-87 upserta la lista y borra IDs ausentes. Al aplicar 202610310001 sus escrituras directas se revocan: el adaptador antiguo fallará. Preparar el reemplazo antes del corte, sin reabrir DML para hacerlo funcionar.
- ProfileRepository.ts:35 y MockShoppingRepository.ts:23 importan automáticamente local si falta el documento remoto. Un perfil/lista relacional vacío no autoriza importar silenciosamente datos de un navegador antiguo; cualquier importación debe ser explícita e idempotente.
- Alinear cantidades a cuatro decimales: RecipesTab.tsx:248 y la confirmación de ticket en PantryPage.tsx:328 admiten 0.000001. No redondear silenciosamente en el adaptador. Los multiplicadores de unidades admiten seis decimales y tienen una regla distinta.
- Completar páginas; una respuesta de 50/100 elementos no significa colección completa. Preservar snapshots, soft-hide y metadatos no disponibles; no convertirlos en borrados físicos.
- Definir día local coherente para alertas: dashboard acepta p_day; inventario/sugerencias tienen sus contratos de fecha propios. No mezclar fechas UTC/locales al componer el panel.

## Orden propuesto y condiciones de corte

1. Cerrar los contratos de lectura de catálogo/recetas e identificación de sesiones, y el subconjunto de fechas de compras; adaptar administración de nombres antes de activar perfil relacional.
2. Preparar adaptadores módulo a módulo, inicialmente sin activarlos en producción. Prioridad: mapeos/sesión/versiones, perfil/favoritos, catálogo/recetas, planificación, compras/despensa, cocción e inicio.
3. Validar los flujos completos en una copia con el modelo nuevo: USER/ADMIN, dos dispositivos, conflictos 40001, reintentos, cambio de cuenta, datos manuales y recetas archivadas. Cerrar las diferencias detectadas, además de los ensayos SQL ya aprobados.
4. Refrescar inventario de datos reales, probar respaldo/restauración, completar convertidores si compras o sesiones activas ya no están vacías y reconciliar referencias. Los conteos históricos documentados no son una consulta actual de producción.
5. Hacer el corte coordinado con escrituras detenidas: migraciones, backfill, reconciliación y activación de adaptadores ya verificados. Las migraciones que revocan DML no se deben adelantar a un frontend todavía dependiente de esas escrituras.
6. Mantener respaldos, IDs legacy y un plan de reversión que preserve también las escrituras posteriores al corte; no basta con volver a activar lectores JSON antiguos. Retirar estructuras legacy en un trabajo separado tras validar el período de transición.

Esta auditoría no cambia contratos existentes ni permisos y no requiere ejecutar SQL. Su validación fue estática; las brechas se aceptan como resueltas cuando tengan implementación y pruebas de los flujos afectados.
