# Ampliación del catálogo relacional de recetas

Este cambio agrega 20 recetas al catálogo relacional ya desplegado. El SQL es aditivo y separado del backfill histórico v3. Conserva las filas existentes, guarda cada slug de receta en `legacy_id`, y omite filas idénticas en ejecuciones repetidas. Las referencias ausentes, inactivas o incompatibles y cualquier colisión detienen la transacción.

## Aplicación en Supabase SQL Editor

1. Confirmá que el esquema relacional final, incluidos los nombres españoles, versiones y funciones administrativas, ya esté desplegado. Este lote no instala migraciones.
2. Ejecutá [el ensayo reversible](../backend/supabase/seeds/recipe_expansion_v4_rehearsal.sql) completo en SQL Editor. Si el editor pregunta por RLS automático, elegí **Run without RLS**. El archivo crea solo tablas temporales y termina en `ROLLBACK`.
3. Confirmá que el ensayo termina y que no dejó filas nuevas.
4. Ejecutá [la carga definitiva](../backend/supabase/seeds/recipe_expansion_v4.sql) completa. Verificá el resultado `PASS` y `recipes_inserted = 20`; el archivo termina en `COMMIT`.
5. Si una ejecución falla antes del terminador, enviá `ROLLBACK;` en esa misma sesión antes de reintentar. No cambies el `ROLLBACK` del ensayo por `COMMIT`.

El archivo de aplicación se puede volver a ejecutar para comprobar la idempotencia; la segunda ejecución debe insertar cero recetas y cero ingredientes, categorías o unidades. El lote no carga archivos en Storage ni publica el frontend.

## Validación local

Desde la raíz del repositorio del backend, ejecutá:

```powershell
powershell -File backend/supabase/tests/run_recipe_expansion_local.ps1
```

El runner crea un PostgreSQL 18 temporal en localhost y valida rollback, colisión sin cambios parciales, inserción completa de 20 recetas, repetición idempotente y preservación de un registro previo. No conecta a Supabase.

El ensayo y la aplicación pasaron esta prueba local. La ejecución en Supabase y el despliegue del frontend siguen pendientes. El código frontend correspondiente se desarrolla en la branch `feat/cocinapp-etapa-frontend`; las imágenes WebP se referencian como `/assets/recipes/<slug>.webp` y deben incluirse al publicar ese frontend.

Los prompts de las 20 imágenes generadas están en [recipe-expansion-image-prompts.json](reference/recipe-expansion-image-prompts.json).
