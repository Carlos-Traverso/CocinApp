# Table names in Spanish

Migration `202611010009_rename_tables_spanish.sql` renames the 36 application tables in one transaction. Existing migration files remain unchanged. The cutover changes table names only: columns, RPC names, JSON contracts, and `auth.users` stay as they are.

| Previous table | Final table |
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

## Verification

Local verification passed with:

```powershell
backend/supabase/tests/run_table_rename_local.ps1
```

The runner installs the immutable migration history only through the seven-table legacy baseline, seeds legacy fixtures, executes the self-contained rollback-only rehearsal, verifies that the rollback restores those seven tables/data and removes all staged domain tables and sample RPCs, installs the pending migrations locally, applies the real rename migration, compares table OIDs and RLS flags, columns, constraints, indexes, policies, triggers, relation grants, and routine owners/OIDs/ACLs, checks stale qualified routine references, and executes all 18 SQL stages with rollback.

The remote rollback-only rehearsal is at `tests/table_rename_rehearsal.sql`. It preflights the seven legacy tables, stages all pending application migrations through 202611010008, renames the 36 tables and verifies their row counts and column metadata, then rolls back the entire transaction. It passed against the legacy-only local fixture. It was not run against Supabase, and no remote migration was deployed. Publish the frontend table-reference changes and apply the final migration together during the cutover.
