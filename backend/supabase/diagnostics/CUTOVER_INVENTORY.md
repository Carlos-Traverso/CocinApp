> Salida actual: el archivo devuelve filas en la columna `inventory_report`. Se cambió de NOTICE a resultados visibles porque SQL Editor podía mostrar «Success. No rows returned» sin los conteos. Ese mensaje por sí solo no acredita el inventario.

# Inventario previo al cutover

`cutover_inventory.sql` es una inspección remota de solo lectura para preparar la decisión de conversión entre el esquema JSON legacy (las siete tablas originales) y el modelo relacional. No usa credenciales, variables locales ni conexiones configuradas; el SQL Editor de Supabase consulta el proyecto que el operador tenga seleccionado.

## Ejecución

1. Abrir el SQL Editor del proyecto Supabase correcto y pegar/abrir el archivo completo.
2. Ejecutarlo como una sola consulta con un rol de administración que pueda leer las tablas. El script hace `BEGIN`, fija `READ ONLY`, realiza únicamente consultas y cierra con `ROLLBACK`.
3. Revisar los mensajes `NOTICE` del resultado, además de cualquier resultado que muestre el editor. La salida no contiene registros, UUID, nombres, emails ni valores de perfil; solo conteos, tipos JSON, permisos efectivos anon/authenticated, presencia de objetos y marcadores de migración.
4. Guardar los agregados junto con el respaldo verificado y la revisión de la migración/backfill antes de autorizar un cutover. Este inventario no realiza ni autoriza el corte.

La consulta no crea objetos (incluidas funciones temporales o persistentes), no modifica filas, no inspecciona el entorno del proyecto y no necesita instalar dependencias. El `ROLLBACK` final cierra la transacción de lectura sin cambios.

## Qué informa

- Presencia, conteo y políticas RLS (`enabled`/`forced`) de las siete tablas legacy y una selección de tablas relacionales finales, incluidas las tablas de compras/cocina y la tabla auxiliar `admin_recipe_write_state`. También muestra privilegios efectivos de tabla para `anon` y `authenticated` en select/insert/update/delete.
- Por clave de `personal_data`: número de filas, valores no vacíos y tipos JSON. Resume filas con compra y cooking progress/history no vacíos, más formas inesperadas de profile, meal plan, favorites y cooking. La comprobación de fecha/número/versión se limita a formatos textuales y nunca castea texto no confiable a date/numeric. También cuenta grupos duplicados de día+turno en los slots de `meal_plan` que tienen ambos campos.
- Referencias de receta ausentes o no encontradas en el arreglo legacy `shared_recipes`, conteo de filas relacionales, cantidad de `shopping_items` con campo de procedencia `source_shopping_id`/`legacy_shopping_id`, presencia de arrays `sourceShoppingIds` en despensa, y cantidades nulas/no numéricas en tablas de compra. Para recetas legacy, informa ingredientes sin `unitId` y etiquetas de ingrediente que aparecen con más de una etiqueta textual de unidad; el segundo indicador es una señal de revisión, no prueba equivalencia o ambigüedad semántica.
- Presencia del marcador `schema_migrations` y extremos de versión visibles, y flags de algunas RPCs representativas. Una ausencia solo significa que el objeto no existe o no es visible en ese esquema.

## Lectura y límites

Las líneas de `inventory_report` de tabla faltante son deliberados: sirven tanto para el remoto legacy de siete tablas como para instalaciones posteriores al rename español. Los permisos son los permisos SQL efectivos de cada rol sobre la tabla; no sustituyen la revisión de políticas RLS, privilegios de secuencia, seguridad de funciones ni el comportamiento de la aplicación. Si el rol ejecutor no puede contar una tabla existente, la consulta lo indicará como error de permisos: volver a correr con acceso de lectura suficiente, sin elevar privilegios de la app.

El esquema relacional puede variar entre migraciones; los conteos son flags de presencia y filas, no prueba de que cada migración requerida esté aplicada. `schema_migrations` puede no estar accesible al SQL Editor o no ser el registro usado por el despliegue. Comparar las versiones/funciones con el historial versionado del repo y consultar el estado operativo en Supabase; ningún documento local prueba el estado remoto actual.

Los detectores de formato son un preflight acotado, no una validación exhaustiva del conversor. No convierten nombres de ingredientes/unidades, no determinan semántica de cantidades ni IDs ambiguos y no establecen correspondencias relacionales de cada FK. La fecha de perfil/slots se valida por forma `YYYY-MM-DD`; no se verifica que cada día sea calendario válido. Los duplicados se buscan dentro de cada fila personal y solo cuando el slot tiene día y turno no vacíos. No muestran valores ni infieren asociaciones. Para cerrar esas decisiones hacen falta los conteos de esta consulta, un respaldo restaurable y revisiones específicas de conversores con agregados de coincidencias, duplicados y huérfanos antes de cualquier escritura. `sourceShoppingIds` está incluido como posible propiedad de fila de despensa; si el formato histórico lo guarda anidado o con otro nombre, se necesita un detector correspondiente antes de migrar.

Una ejecución satisfactoria solo confirma que la inspección se pudo ejecutar con los permisos disponibles. No confirma backup, conversión, despliegue ni cutover.
