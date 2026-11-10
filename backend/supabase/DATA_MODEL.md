# CocinAPP data model proposal

## Purpose and status

This document records the agreed relational design before adding new application tables or migrating existing JSON data. It maps the current CocinAPP flows and the supplied SRS to Supabase/PostgreSQL. It is a design specification, not a migration; do not run SQL from this document.

The project already contains `pantry_items`, `personal_data`, `user_roles`, `account_status`, `catalog_core`, `shared_recipes`, and `admin_audit_log`. Catalog and recipe rows currently hold JSON documents. Preserve those objects during transition; migrate existing records before removing or renaming anything.

## Design decisions

- Supabase Auth remains the identity source. Every private row references `auth.users(id)` with `ON DELETE CASCADE`; shared catalog rows do not have an owner.
- Normalize entities that are independently searched, filtered, referenced, or updated. Store small fixed configuration as versioned relational rows. Do not create tables for derived screens, calculations, filters, or transient receipt images.
- Use UUID primary keys for new entities, `timestamptz` for instants, `date` for calendar days, `numeric` for quantities, and foreign keys for catalog references.
- Retain historical meaning: recipes and catalog items referenced by plans or cooking history are archived/deactivated instead of physically deleted. Historical cooking records also retain a recipe and ingredient snapshot.
- Private tables enable RLS and enforce ownership through `auth.uid()`, plus the existing active-account predicate. Only admin RPCs can change shared catalog and roles. Client roles never grant authority by themselves.
- Use database transactions/RPCs for multi-row business operations, with validation and idempotency keys at the database boundary.
- Ticket images are processed in memory by an Edge Function and discarded. Do not add an image table or storage bucket for ticket photos. OCR output remains a proposal until the user confirms it.

## Proposed tables

### Identity and personal settings

| Table | Main columns and relationships | Access |
| --- | --- | --- |
| `profiles` | `user_id` PK/FK Auth; display name; birth date; weight kg; height cm; metabolic sex; activity level; goal; timestamps | Owner reads/writes own row. Admin directory exposes only the fields needed for account administration. |
| `dietary_tags` | Stable key, label, description, active flag; seeded values include gluten-free, vegetarian, vegan, lactose-free, nut-free | Authenticated read; admin manages. |
| `user_dietary_preferences` | `(user_id, dietary_tag_id)` PK; both FKs | Owner reads/writes own preferences. |
| `user_roles`, `account_status` | Existing tables; Auth user FK, role/active value, timestamps | Existing protected RPCs and policies remain authoritative. |

Age and energy estimates are derived from profile fields and documented configuration, not stored as stale duplicate values. Do not store calculated health estimates as medical records.

### Shared catalog and recipes

| Table | Main columns and relationships | Access |
| --- | --- | --- |
| `categories` | Name, normalized name unique, active/deleted flags, timestamps | Authenticated read; admin RPC writes. |
| `units` | Name, abbreviation unique, dimension, optional base-unit FK, multiplier, active/deleted flags | Authenticated read; admin RPC writes. Restrict conversion links to one dimension. |
| `ingredients` | Name, normalized name, category FK, base-unit FK, active/deleted flags, timestamps | Authenticated read; admin RPC writes. |
| `ingredient_dietary_tags` | `(ingredient_id, dietary_tag_id)` PK; compatibility classification and optional note | Authenticated read; admin RPC writes. Labels are informational, never a safety guarantee. |
| `recipes` | Title, author/source, description, legacy category label, total minutes, optional preparation/cooking minutes, portions, difficulty, calories per portion, symbol/color/image, publication state, active/deleted/featured flags, owner FK nullable for official recipes, timestamps | Published official recipes readable by authenticated users; draft/private recipes readable by owner/admin. Admin RPC writes official recipes. Recipe category labels currently represent meal shifts and must not be linked to ingredient categories. |
| `recipe_meal_shifts` | `(recipe_id, meal_shift)` PK | Read follows recipe visibility; admin/owner writes. |
| `recipe_dietary_tags` | `(recipe_id, dietary_tag_id)` PK | Read follows recipe visibility; admin/owner writes. |
| `recipe_ingredients` | Recipe FK, ingredient FK, quantity, unit FK, optional note, position; unique recipe/position | Read follows recipe visibility; admin/owner writes. Validate unit dimension against ingredient base unit. |
| `recipe_steps` | Recipe FK, position, instruction, duration minutes, temperature, tip, warning, utensils, special instructions; unique recipe/position | Read follows recipe visibility; admin/owner writes. |
| `recipe_step_ingredients` | `(step_id, recipe_ingredient_id)` relationship, optional step quantity override | Read follows recipe visibility; admin/owner writes. |

The recipe design supports official recipes and user-owned recipes with one model. AI-generated recipes are user-owned drafts until validation/publishing rules approve them. Admin publication rules must not let a user write official recipes.

### User inventory and planning

| Table | Main columns and relationships | Access |
| --- | --- | --- |
| `pantry_items` | Existing table; add/validate `ingredient_id` and preferably `unit_id`; owner FK, quantity, minimum, expiry, timestamps | Preserve existing owner RLS; owner CRUD. |
| `favorite_recipes` | `(user_id, recipe_id)` PK, created timestamp | Owner reads/writes; only visible recipes can be favorited. |
| `meal_plans` | UUID, owner FK, week-start date, timestamps; unique `(user_id, week_start)` | Owner reads/writes. |
| `meal_plan_slots` | UUID, plan FK, date, meal shift, recipe FK, portions, position; unique `(plan_id, date, meal_shift, position)` | Owner reads/writes. Validate date belongs to plan week. |

Starter-kit selection is a client-side proposal until confirmation; confirmed items are inserted into `pantry_items` in one RPC. Dashboard counts, expiry alerts, and recipe matching are derived queries/RPCs, not separately synchronized tables.

### Shopping and cooking

| Table | Main columns and relationships | Access |
| --- | --- | --- |
| `shopping_lists` | UUID, owner FK, optional plan FK, name/state, timestamps | Owner reads/writes. A partial unique index permits at most one active list per user. Creating a new active list archives the previous one in the same transaction. |
| `shopping_items` | UUID, list FK, optional ingredient FK, name snapshot, category FK or label snapshot, quantity, unit FK, note, checked/transferred state, timestamps | Owner reads/writes; free-text items may have no ingredient FK and can transfer to pantry with that reference remaining NULL; never infer an association from the name. |
| `shopping_item_sources` | Shopping item FK, source kind (manual/recipe/plan/favorites/pantry), optional recipe/plan reference | Owner reads/writes; preserves why an item was suggested. |
| `pantry_receipts` | UUID, owner FK, shopping transfer idempotency key, completion timestamp | Owner reads; inserted by transfer RPC. Unique idempotency key per owner. |
| `pantry_receipt_items` | Receipt FK, shopping item FK, pantry item FK, quantity/unit snapshot | Owner reads; written by transfer RPC in the same transaction as inventory and shopping state updates. |
| `cooking_sessions` | UUID, owner FK, recipe FK, recipe snapshot/version, portions, current step, started/finished timestamps, client idempotency key | Owner reads/writes through RPC. |
| `cooking_session_steps` | `(session_id, step_position)` PK, completion timestamp, remaining milliseconds, timer deadline, paused/finished state | Owner reads/writes through session RPC. Persist timestamps in UTC; clients derive remaining time from server deadlines so a session can resume on another device. No server timer process is required. |
| `cooking_events` | UUID, owner FK, session FK unique, recipe FK nullable, recipe snapshot, portions, cooked timestamp | Owner reads; inserted once by the cooking-finalization RPC. Supports history and trend counts without exposing private inventory. |
| `cooking_event_ingredients` | Event FK, ingredient/name/unit/quantity snapshots | Owner reads; records exactly what the preparation consumed. |

`transfer_shopping_to_pantry` validates ownership, checked state, active ingredient/unit compatibility when linked, validated manual labels otherwise, and duplicate transfer key; increments or creates pantry stock, writes receipt rows, and marks shopping items transferred atomically. `finish_cooking` checks stock, deducts quantities in a stable order, writes the cooking event and consumption snapshots, and closes the session atomically. Both RPCs reject negative quantities and are idempotent.

### Administration, audit, and configuration

| Table | Main columns and relationships | Access |
| --- | --- | --- |
| `admin_audit_log` | Existing append-only audit table; actor, target, action, safe details, timestamp | Existing admin-only read and server/trigger writes remain. Never store passwords, tokens, full profile payloads, or ticket contents. |
| `nutrition_config` | Versioned singleton/dated rows for activity factors and goal ranges; effective date, source/notes, updated-by admin | Public-to-authenticated read; admin RPC writes; changes audited. Values must be documented and are informational. |
| `recipe_generation_requests` | Request status, owner, provider/model identifier, timestamps and safe error code; no secret or image | Owner read; Edge Function writes. A generated recipe is first a user-owned draft and follows the same validation and dietary-tag rules before use. |
| `receipt_recognition_requests` | Optional request ID, owner, status, timestamps, safe error code, expiry time | Owner read; Edge Function writes. Keep only minimal operational metadata with short retention; never persist ticket bytes or full OCR output after the user confirms or discards the preview. |

Recipe trend ranking should be a view/materialized view over published recipes and aggregate `cooking_events`, with featured status as an admin signal. It should not expose who cooked a recipe or private recipe details.

## Current object transition map

| Existing object | Proposed destination |
| --- | --- |
| `personal_data` keys `profile`, `favorites`, `meal_plan`, `shopping`, `cooking_progress`, `cooking_history` | Split into `profiles`, `user_dietary_preferences`, `favorite_recipes`, `meal_plans`/`meal_plan_slots`, shopping tables, and cooking session/event tables. |
| `pantry_items` JSON-compatible fields | Keep table and data; add foreign-key unit/catalog references with a staged backfill. Preserve unmatched names as nullable ingredient references. |
| `catalog_core.payload` | Split categories, units, ingredients, and ingredient tags into rows. Preserve old version guard during backfill, then replace it with transactional admin RPCs and audit triggers. |
| `shared_recipes.recipes` | Split recipes, tags, meal shifts, ingredients, steps, and step-ingredient relations. Keep legacy recipe IDs mapped during backfill. |
| `user_roles`, `account_status`, `admin_audit_log` | Keep and extend only through additive migrations; retain current RLS, RPC, and audit guarantees. |

### Safe data migration sequence

Inventory reported from Supabase before backfill: 5 profile documents, 20 pantry rows (7 with a legacy ingredient ID), 8 shared recipe objects, 4 favorite IDs, 7 meal-plan slots, and 3 history events. Shopping and active cooking progress documents exist but have empty arrays. These counts are a reconciliation baseline, not proof that references or nested values are valid.

`availableRecipes.ts` merges the frontend recipe seed with remote overrides. Backfill must import the relevant seed recipes too, preserve their IDs in `legacy_id`, and apply remote overrides with the same precedence as `mergeRecipeSeed`. The extra `recipes` array found inside `catalog_core.payload` is not the current recipe source: do not concatenate it with `shared_recipes.recipes` or count it as another catalog. Preserve legacy `minutes`, `symbol`, and `color`; do not infer missing preparation/cooking splits from total time.

1. Confirm project identity, take/verify a Supabase backup, and export counts plus representative JSON shapes for each `personal_data.data_key`, `catalog_core.payload`, and `shared_recipes.recipes`. Keep sensitive profile contents out of logs and shared reports.
2. Apply additive schema migrations only. They leave all legacy JSON rows intact and create nullable foreign-key references on `pantry_items` for later matching.
3. Seed stable dietary-tag, unit, and category mappings. Preserve every old string ID in each new entity's `legacy_id` column; generate an explicit old-to-new ID map for rows whose IDs are not UUIDs.
4. Backfill shared catalog and recipes in dependency order: categories, units/base-unit links, ingredients/tags, recipes, meal shifts/tags, recipe ingredients, steps, and step ingredient links. Use `ON CONFLICT (legacy_id) DO UPDATE` only for fields owned by the backfill, so reruns are safe and do not overwrite newer admin edits.
5. Backfill private records per Auth user: profile and preferences; favorites; plans and slots; shopping lists/items/source links; cooking sessions/timer state and history. Validate each JSON value before insertion, quarantine malformed rows for manual review, and report only user IDs/counts rather than personal values.
6. Match pantry rows by existing `ingredient_id`/normalized name and `unit`/dimension. Set `ingredient_ref` and `unit_ref` only for unambiguous matches; retain unmatched rows and their original labels for review.
7. Produce reconciliation counts by data key and owner, orphan/FK reports, quantity/unit checks, and recipe-ID match reports. Re-run the backfill in a non-production copy first. The production cutover requires zero unexplained count differences and reviewed unmatched records.
8. Switch frontend repositories module by module, verify behavior under separate USER and ADMIN sessions, and monitor writes while legacy reads remain available for rollback. Stop writing a legacy key only after the corresponding new repository passes.
9. Keep legacy JSON, ID mappings, and backups through the agreed rollback period. A separate reviewed migration may retire old keys/tables only after production reconciliation and restore testing; that cleanup is not part of the additive schema migration.

Do not drop JSON columns or old tables until counts, IDs, ownership, and relationships reconcile and the application reads/writes the new model successfully. Keep a rollback window and a verified database backup before production cutover.

## Scope coverage and items requiring product decisions

The agreed relational model covers SRS RF-01 through RF-21 and the current implemented flows: profiles, restrictions, starter kit, ticket preview/confirmation, search, matching, scaling, cooking, plans, purchases, administration, favorites, and trends. It reserves persistence for AI-generated recipe drafts and minimal ticket-processing status while keeping ticket images and transient OCR preview data out of permanent storage. Views/RPCs cover derived features; they do not require duplicate persistence tables.

Product decisions confirmed: (1) include AI-generated user-owned recipes and ticket recognition in the model and implement them in later blocks; (2) persist cooking timers so sessions resume across devices; (3) allow one active shopping list per user, archiving the previous list when a new one is created.

After those decisions, build additive migrations in dependency order: catalog reference tables, recipes and joins, profiles/preferences/favorites, plans and shopping, cooking/receipts, then aggregate views/RPCs. Backfill with validation reports, enable RLS on each new private table, test each operation under USER and ADMIN roles, and only then switch frontend repositories and retire legacy JSON storage.


## Internal recipe write state

`202611010001_recipe_admin_rpcs.sql` adds `admin_recipe_write_state`, a server-only 1:1 technical record per managed recipe for initial/last request replay and duplication provenance. It is additional to the 28 domain tables, has RLS enabled with no client policies/grants, and is not a new user-facing entity. The domain-table progress denominator remains 28; the auxiliary record must be counted separately in deployment inventories. The existing seven tables and all legacy data remain during the transition.
