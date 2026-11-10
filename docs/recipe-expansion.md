# Catálogo ampliado de recetas

El lote agrega las 20 recetas de `frontend/src/mocks/expandedRecipes.ts` al catálogo relacional. Los archivos SQL son independientes de `backfill/`: no leen, regeneran ni reemplazan el histórico `recipe_seed_v3.json` ni los catálogos JSON antiguos.

- Aplicación permanente: [`recipe_expansion_v4.sql`](../backend/supabase/seeds/recipe_expansion_v4.sql), termina con `COMMIT`.
- Ensayo completo: [`recipe_expansion_v4_rehearsal.sql`](../backend/supabase/seeds/recipe_expansion_v4_rehearsal.sql), contiene el mismo lote y termina con `ROLLBACK`.
- Generador: [`build-recipe-expansion-sql.ts`](../frontend/scripts/build-recipe-expansion-sql.ts).
- Referencias/prompts de imágenes: [`recipe-expansion-image-prompts.json`](reference/recipe-expansion-image-prompts.json).

El SQL usa las tablas del esquema relacional final con nombres españoles (`recetas`, `ingredientes`, `unidades`, `categorias`, `etiquetas_dieteticas`, `ingredientes_receta`, `pasos_receta`, `ingredientes_paso_receta`, `turnos_comida_receta`, `etiquetas_dieteticas_receta`). Inserta ingredientes, categorías o unidades solo si faltan y solo cuando tienen definición explícita; no crea etiquetas dietarias. Cada receta guarda su slug original en `legacy_id` y recibe un UUID estable. Las calorías quedan en `NULL`, según el catálogo fuente.

El lote no modifica filas existentes. Reutiliza referencias activas por nombre normalizado, abreviatura y dimensión. Si una receta, ingrediente, unidad, categoría o etiqueta tiene una referencia ausente, inactiva, ambigua o en conflicto, el lote aborta. Las filas exactas de una importación previa se omiten; si sus datos o hijos difieren del catálogo fuente, el lote aborta en lugar de sobrescribirlas. La repetición de la aplicación es, por tanto, segura e idempotente.

## Pasos en Supabase SQL Editor

1. Confirmá que el esquema relacional, los renombres españoles, las columnas de versión y las tablas de estado/auditoría ya estén desplegados. El SQL de este lote no instala migraciones.
2. Abrí [`recipe_expansion_v4_rehearsal.sql`](../backend/supabase/seeds/recipe_expansion_v4_rehearsal.sql), copiá el archivo completo al SQL Editor y ejecutalo como un solo lote. Si aparece la opción de habilitar RLS automáticamente, elegí **Run without RLS**; el lote solo crea tablas temporales de sesión y estas se eliminan al cerrar la transacción.
3. Revisá que aparezca `PASS: preflight, referencias y contenido de las 20 recetas verificados`, junto con el resumen de filas. Confirmá que el script llegó a su `ROLLBACK` final y que el editor indica que la transacción fue revertida. Este ensayo no deja datos persistentes.
4. Abrí [`recipe_expansion_v4.sql`](../backend/supabase/seeds/recipe_expansion_v4.sql), copiá el archivo completo y ejecutalo como un solo lote. Revisá el preflight y el resumen; la última sentencia `COMMIT` persiste el lote.
5. Volvé a ejecutar el mismo archivo de aplicación para comprobar la repetición segura. El resumen debe indicar cero recetas, ingredientes, categorías y unidades nuevos; las 20 recetas existentes se validan contra sus datos y relaciones y se omiten.
6. Si cualquier ejecución devuelve error antes del terminador de transacción, ejecutá `ROLLBACK;` en esa misma sesión antes de volver a intentar. Conservá el error completo y corregí la causa; no cambies `ROLLBACK` por `COMMIT` en el archivo de ensayo.
7. Después de aplicar el SQL, publicá el frontend y las imágenes WebP nuevas de `frontend/public/assets/recipes/`. El SQL solo guarda rutas como `/assets/recipes/quinoa-apple-porridge.webp`; no carga archivos de imagen a Storage ni despliega el frontend. Las 20 imágenes ya están en el workspace y sus nombres corresponden a los slugs importados.

## Regeneración y validación

Desde `frontend/`, regenerá ambos SQL después de cambiar una receta:

```powershell
node --import jiti/register scripts/build-recipe-expansion-sql.ts
```

La generación es local y no accede a Supabase. Para repetir la validación SQL aislada, desde la raíz del proyecto ejecutá:

```powershell
powershell -File backend/supabase/tests/run_recipe_expansion_local.ps1
```

El runner crea y elimina un PostgreSQL 18 temporal; prueba el `ROLLBACK`, una colisión de título sin escrituras parciales, la aplicación de 20 recetas, la repetición idempotente y la preservación de filas de catálogo preexistentes.

**Validación local PASS:** 211 pruebas frontend y build de producción; PostgreSQL 18 pasó rehearsal con rollback, apply de 20 recetas, fallo atómico ante colisión y replay idéntico. Los conteos del runner confirmaron 20 recetas completas y preservaron las filas sentinel existentes.

**Validación remota: no ejecutada.** La aplicación y confirmación en Supabase SQL Editor y el despliegue del frontend/imágenes quedan pendientes del operador. Los resultados locales no demuestran una ejecución remota.
