# Relational backfill preparation

Status: inventory and recipe-reference analysis complete; schema/catalog/personal/pantry rehearsal scripts pass on isolated PostgreSQL 18 with fictitious records and simulated Auth. Production conversion is not deployed. The full rehearsal has now passed against remote data with complete rollback verified. Do not upload this JSON as the remote recipe catalog or replace the existing catalogs with it.

`recipe_seed_v3.json` is a snapshot of the 22 public recipes shipped by `frontend/src/mocks/recipes.ts`. It contains no user records or credentials. It preserves the original IDs, instructions, ingredient amounts, calorie estimates, display metadata, images, and dietary labels for use by the upcoming converter.

Apply the same merge rule as the application: seed recipes establish the baseline; entries from `shared_recipes.recipes` override whole recipes with the same ID. Do not merge in the obsolete `catalog_core.payload.recipes` array. Resolve recipe IDs into new UUIDs only after this precedence is applied, and retain every original recipe ID in `recipes.legacy_id`.

Confirmed remote reference inventory:

| Data key | Remote recipe references | Seed-only references | Unresolved |
| --- | ---: | ---: | ---: |
| cooking_history | 1 | 2 | 0 |
| favorites | 1 | 3 | 0 |
| meal_plan | 4 | 3 | 0 |

These are references, not distinct recipe counts. Changes made in the app after the inventory require a fresh reconciliation at conversion time.

Remaining conversion gates: match seed ingredient names to the master catalog without silently inventing associations; preserve partial profiles and original timestamps; use deterministic mappings for historic sessions and events; perform the converter first in an isolated copy and reconcile counts before any production write. The structural migration and conversion remain separate operations. Neither has been applied to Supabase by this preparation step.


## Rehearsal and next gate

Run `python backend/supabase/backfill/build_catalog_rehearsal.py` to regenerate SQL from the public seed and templates. `tests/run_backfill_local.ps1` creates a temporary local PostgreSQL cluster, runs the full rehearsal with synthetic fixtures, verifies that the new schema disappears after ROLLBACK and that pantry quantity remains 150, and stops the cluster. It never contacts Supabase.

`full_validation_rehearsal.sql` wraps structural migration plus catalog, personal, and pantry conversion in ONE transaction ending with ROLLBACK. It creates no permanent tables or migrated data. It temporarily takes source locks, limited by a five-second lock timeout. Run the whole file, without editing transaction boundaries, when the app is idle. On any error, execute `ROLLBACK;` before retrying and report the full error. Do not replace ROLLBACK with COMMIT.

In the Supabase SQL Editor confirmation, choose **Run without RLS**. The structural migration already enables RLS on every new domain table. Automatic RLS adds statements after the final ROLLBACK and is incompatible with these rehearsals. A remote retry still reported missing `src_core`, so the precise remote cause has not been established. The remote table listing after the first failure showed only the original seven public tables.

Use the distinct file `supabase_validation_rehearsal.sql` (version `20261030-03`) for the next dashboard run. It is generated from the same full rehearsal, but staging now uses the private `cocinapp_rehearsal` schema with explicitly qualified references instead of session TEMP tables. Client roles have no schema access. All auxiliary objects, new domain tables, and converted data disappear together at the final ROLLBACK. The script deliberately refuses an existing staging schema rather than overwriting it. The local runner checks that this schema also disappears. The initial version passed remotely when executed through Run without RLS. The revised version adds explicit RLS for all six staging tables, eliminating the SQL Editor RLS modal; that variant also passed remotely.

Catalog conversion uses exact normalized names, resolves remote overrides before recipes are inserted, retains labels and step metadata, and stops on unresolved ingredient/unit links. Profiles may be partial. History receives closed synthetic sessions with an explicitly migration-time recipe snapshot; old consumption is not fabricated. Pantry rehearsal fills nullable references and reports unmatched/dimension mismatches without modifying quantities or expiry dates.

Current data limitation: non-empty shopping lists or active cooking sessions stop the personal rehearsal; their full converters are still pending. The initial remote inventory showed empty arrays for both. New app activity can change that, so the script rechecks each run. Real-data reconciliation and new write RPC/permission tests remain required before cutover. The frontend still uses the legacy repositories. No COMMIT conversion script is offered at this stage.


## Remote rehearsal review (2026-10-30)

The original missing-relation/schema errors were not reproduced when the exact editor SQL was run via **Run without RLS**. Official Studio source confirms it sends the entire script unchanged on this path, while **Run and enable RLS** appends statements after the final ROLLBACK. The previous claim that session TEMP tables were necessarily lost between statements was unsupported. Private staging remains, now with explicit RLS to remove this warning path entirely. Independent read-only source review corroborated this behavior.

A minimal schema/table probe passed remotely with rollback, followed by the full conversion. A second full run with explicit staging RLS and a consolidated report passed without the modal. Totals: categories 8, units 5, ingredients 33, recipes 23, recipe ingredient lines 77, steps 66; profiles 5, preferences 1, favorites 4, plan slots 7, cooking history 3, empty active shopping lists 1. Pantry: 20 rows, unmatched ingredient 1 (name-only legacy row, no explicit ID), unmatched unit 0, incompatible dimension 0. The unmatched pantry row remains intact and requires review before cutover; the converter does not guess its ingredient.

Separate read-only verification after remote rollback: public base tables 7, staging schema absent, recipes table absent, pantry rows 20, relational pantry columns absent. No permanent migration or conversion was applied. Local testing now sends the entire SQL as ONE database request via psql gexec, rather than merely testing statement-by-statement psql -f execution; conversion and rollback both pass, with all 28 new domain tables having RLS enabled locally. This is not yet a live cross-account permission test or proof of complete backend functionality.


## Next permission gate

`tests/relational_permissions_rehearsal.sql` combines the additive schema, synthetic permission fixtures and one final ROLLBACK. It does not run the real data backfill. It requires two existing active Auth accounts, temporarily uses their role/status rows inside the transaction, and tests A/B owner reads on all 16 private tables, recipe details, administrator visibility, same-JWT administrator demotion, inactive accounts, anonymous reads, real denied writes, and forbidden DML/TRUNCATE/REFERENCES/TRIGGER privileges across all 28 tables. Changes to roles/status are uncommitted and must never be committed. Run as postgres with the app idle. The local test passed using real application helper definitions with simulated Auth; Remote permission verification passed for this SELECT-only schema (including same-JWT admin demotion); the full wrapper included its final ROLLBACK. The separate personal write RPC rehearsal also passed remotely; planning/shopping write RPC verification also passed remotely with its final ROLLBACK, as recorded in ../RPC_CONTRACTS.md. The next remote gate covers transfer and shopping suggestions. Regenerate with `python backend/supabase/tests/build_relational_permissions.py`, run locally with `backend/supabase/tests/run_backfill_local.ps1 -Permissions`.

The read-only pantry diagnostic confirmed the unmatched record has a manually entered name and no master ID. The agreed model explicitly preserves such records with nullable ingredient references. No guessed mapping or removal is needed for conversion. Future matching should treat these as unmatched while retaining quantity, unit and original label. Do not commit user-entered labels or account identifiers to fixtures or documentation.
