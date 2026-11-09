# Lecturas de recetas: contrato posterior al renombrado

Migración: `202611010010_recipe_read_contract.sql`, después de 009. No crea tablas ni modifica datos existentes. Usa los nombres españoles finales.

- `list_known_recipes(p_limit=500,p_offset=0)` devuelve un array JSON paginado de recetas conocidas. Límite 1..500; offset 0..5000; orden título/UUID. Incluye oficiales publicadas, incluso archivadas, y recetas propias de origen user/ai. El adaptador deberá paginar; no debe asumir que una sola página contiene todo el catálogo.
- `get_my_recipe_detail(p_recipe_id=null,p_legacy_id=null,p_include_inactive=false)` exige exactamente un identificador. Usar el argumento legacy para IDs anteriores, incluso si tienen formato UUID. Devuelve null si no existe/no es visible; si existe devuelve `{recipe,stock:null,percentage:null,label}`. El indicador de archivo debe ser explícito; null es inválido. No reemplaza la consulta de stock ni autoriza iniciar una receta archivada.
- `admin_get_recipe(p_recipe_id)` requiere ADMIN activo y devuelve el export de edición de una receta oficial, incluidos borradores, con versión. No entrega recetas privadas ajenas.

Las lecturas personales no conceden privilegios adicionales por ser ADMIN: nunca muestran privadas ajenas ni borradores oficiales. El payload conserva referencias de catálogo archivadas y agrega categoría de ingredientes; mantiene version e IDs. El helper de payload sigue sin EXECUTE para clientes. Las políticas de escritura no se amplían.

## Comprobación

Ejecutar localmente `backend/supabase/tests/run_table_rename_local.ps1 -RecipeReads -Port 55441`. Instala las siete tablas legacy, ejecuta el ensayo completo, verifica rollback y después instala realmente las migraciones y ejecuta todos los escenarios. Auth local simulado; esto no equivale a prueba E2E del frontend.

Para Supabase usar únicamente `tests/recipe_read_contract_rehearsal.sql` completo, como postgres y con dos cuentas existentes. Prepara las migraciones pendientes dentro de una sola transacción, reutiliza cuentas para las pruebas de roles y termina en ROLLBACK. No ejecutar el stage aislado ni aplicar la migración permanente durante el ensayo.

Esta corrección cierra el contrato backend de detalle/conocidas y la lectura individual de edición de B04. El adaptador frontend, la lectura completa de catálogo/versiones del editor y los otros bloqueos del informe de auditoría siguen pendientes. No se activó este contrato en producción.
