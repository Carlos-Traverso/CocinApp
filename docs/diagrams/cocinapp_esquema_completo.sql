-- CocinAPP: modelo estructural completo para importar en un generador de diagramas.
-- Estado implementado hasta 202611010012; pendiente de despliegue permanente.
-- 36 tablas de aplicacion, 271 atributos y 56 FK. No contiene datos de usuarios.
-- auth.users se representa SOLO mediante su id como referencia externa de Supabase.
-- Este archivo es documental: NO ejecutar en el proyecto Supabase existente.
-- No incluye RPC, triggers ni politicas RLS; para desplegar usar las migraciones.
CREATE SCHEMA IF NOT EXISTS "public";
CREATE SCHEMA IF NOT EXISTS "auth";

-- Referencia externa, no es una tabla propia de CocinAPP.
CREATE TABLE "auth"."users" (
    "id" uuid NOT NULL,
    CONSTRAINT "users_pkey" PRIMARY KEY (id)
);

CREATE TABLE "public"."articulos_compra" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "list_id" uuid NOT NULL,
    "ingredient_id" uuid,
    "name_snapshot" text NOT NULL,
    "category_snapshot" text DEFAULT 'Otros'::text NOT NULL,
    "quantity" numeric(14,4) NOT NULL,
    "unit_id" uuid NOT NULL,
    "note" text DEFAULT ''::text NOT NULL,
    "checked" boolean DEFAULT false NOT NULL,
    "transferred_at" timestamp with time zone,
    "source" text NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT "shopping_items_name_snapshot_check" CHECK (((length(TRIM(BOTH FROM name_snapshot)) >= 1) AND (length(TRIM(BOTH FROM name_snapshot)) <= 120))),
    CONSTRAINT "shopping_items_pkey" PRIMARY KEY (id),
    CONSTRAINT "shopping_items_quantity_check" CHECK (((quantity > (0)::numeric) AND (quantity <= (1000000)::numeric))),
    CONSTRAINT "shopping_items_source_check" CHECK ((source = ANY (ARRAY['manual'::text, 'recipe'::text, 'plan'::text, 'favorites'::text, 'pantry'::text])))
);

CREATE TABLE "public"."articulos_comprobante_despensa" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "receipt_id" uuid NOT NULL,
    "original_shopping_item_id" uuid NOT NULL,
    "shopping_item_id" uuid,
    "pantry_item_id" uuid,
    "quantity_added" numeric(14,4) NOT NULL,
    "unit_abbreviation_snapshot" text NOT NULL,
    "ingredient_id_snapshot" uuid,
    "name_snapshot" text,
    "category_snapshot" text,
    "purchased_quantity" numeric(14,4),
    "purchased_unit_id_snapshot" uuid,
    "purchased_unit_abbreviation_snapshot" text,
    "pantry_unit_id_snapshot" uuid,
    CONSTRAINT "pantry_receipt_items_original_shopping_item_id_key" UNIQUE (original_shopping_item_id),
    CONSTRAINT "pantry_receipt_items_pkey" PRIMARY KEY (id),
    CONSTRAINT "pantry_receipt_items_quantity_added_check" CHECK ((quantity_added > (0)::numeric))
);

CREATE TABLE "public"."articulos_despensa" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "user_id" uuid NOT NULL,
    "name" text NOT NULL,
    "category" text NOT NULL,
    "quantity" numeric(14,4) DEFAULT 0 NOT NULL,
    "unit" text NOT NULL,
    "minimum" numeric(14,4) DEFAULT 0 NOT NULL,
    "expiry" date,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    "ingredient_id" text,
    "source_shopping_ids" text[] DEFAULT '{}'::text[] NOT NULL,
    "ingredient_ref" uuid,
    "unit_ref" uuid,
    "version" bigint DEFAULT 1 NOT NULL,
    CONSTRAINT "pantry_items_category_check" CHECK (((length(TRIM(BOTH FROM category)) >= 1) AND (length(TRIM(BOTH FROM category)) <= 80))),
    CONSTRAINT "pantry_items_minimum_check" CHECK (((minimum >= (0)::numeric) AND (minimum <= (1000000)::numeric))),
    CONSTRAINT "pantry_items_name_check" CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 120))),
    CONSTRAINT "pantry_items_pkey" PRIMARY KEY (id),
    CONSTRAINT "pantry_items_quantity_check" CHECK (((quantity >= (0)::numeric) AND (quantity <= (1000000)::numeric))),
    CONSTRAINT "pantry_items_unit_check" CHECK (((length(TRIM(BOTH FROM unit)) >= 1) AND (length(TRIM(BOTH FROM unit)) <= 24))),
    CONSTRAINT "pantry_items_version_check" CHECK ((version > 0))
);

CREATE TABLE "public"."catalogo_base" (
    "catalog_key" text DEFAULT 'main'::text NOT NULL,
    "payload" jsonb DEFAULT '{"units": [], "categories": [], "ingredients": []}'::jsonb NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    "version" integer DEFAULT 1 NOT NULL,
    CONSTRAINT "catalog_core_catalog_key_check" CHECK ((catalog_key = 'main'::text)),
    CONSTRAINT "catalog_core_payload_shape" CHECK (((jsonb_typeof(payload) = 'object'::text) AND (jsonb_typeof((payload -> 'categories'::text)) = 'array'::text) AND (jsonb_typeof((payload -> 'units'::text)) = 'array'::text) AND (jsonb_typeof((payload -> 'ingredients'::text)) = 'array'::text))),
    CONSTRAINT "catalog_core_pkey" PRIMARY KEY (catalog_key),
    CONSTRAINT "catalog_core_version_check" CHECK ((version > 0))
);

CREATE TABLE "public"."categorias" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "legacy_id" text,
    "name" text NOT NULL,
    "normalized_name" text NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "is_deleted" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    "version" bigint DEFAULT 1 NOT NULL,
    CONSTRAINT "categories_legacy_id_key" UNIQUE (legacy_id),
    CONSTRAINT "categories_name_check" CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 100))),
    CONSTRAINT "categories_pkey" PRIMARY KEY (id),
    CONSTRAINT "categories_version_check" CHECK ((version > 0))
);

CREATE TABLE "public"."comprobantes_despensa" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "owner_user_id" uuid NOT NULL,
    "idempotency_key" uuid NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "shopping_list_id" uuid,
    "requested_list_id" uuid,
    "requested_item_ids" uuid[],
    "resulting_list_version" bigint,
    CONSTRAINT "pantry_receipts_owner_user_id_idempotency_key_key" UNIQUE (owner_user_id, idempotency_key),
    CONSTRAINT "pantry_receipts_pkey" PRIMARY KEY (id)
);

CREATE TABLE "public"."configuracion_nutricional" (
    "config_version" integer NOT NULL,
    "activity_factors" jsonb NOT NULL,
    "goal_adjustments" jsonb NOT NULL,
    "source_note" text NOT NULL,
    "effective_at" timestamp with time zone DEFAULT now() NOT NULL,
    "updated_by" uuid,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT "nutrition_config_activity_factors_check" CHECK ((jsonb_typeof(activity_factors) = 'object'::text)),
    CONSTRAINT "nutrition_config_config_version_check" CHECK ((config_version > 0)),
    CONSTRAINT "nutrition_config_goal_adjustments_check" CHECK ((jsonb_typeof(goal_adjustments) = 'object'::text)),
    CONSTRAINT "nutrition_config_pkey" PRIMARY KEY (config_version)
);

CREATE TABLE "public"."datos_personales" (
    "user_id" uuid NOT NULL,
    "data_key" text NOT NULL,
    "value" jsonb NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT "personal_data_data_key_check" CHECK ((data_key = ANY (ARRAY['profile'::text, 'favorites'::text, 'meal_plan'::text, 'shopping'::text, 'cooking_progress'::text, 'cooking_history'::text]))),
    CONSTRAINT "personal_data_pkey" PRIMARY KEY (user_id, data_key)
);

CREATE TABLE "public"."estado_cuenta" (
    "user_id" uuid NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT "account_status_pkey" PRIMARY KEY (user_id)
);

CREATE TABLE "public"."estado_escritura_receta_admin" (
    "recipe_id" uuid NOT NULL,
    "create_payload" jsonb,
    "last_payload" jsonb,
    "last_version" bigint,
    "duplicate_source_id" uuid,
    "duplicate_source_version" bigint,
    CONSTRAINT "admin_recipe_write_state_create_payload_check" CHECK (((create_payload IS NULL) OR (jsonb_typeof(create_payload) = 'object'::text))),
    CONSTRAINT "admin_recipe_write_state_last_payload_check" CHECK (((last_payload IS NULL) OR (jsonb_typeof(last_payload) = 'object'::text))),
    CONSTRAINT "admin_recipe_write_state_pkey" PRIMARY KEY (recipe_id)
);

CREATE TABLE "public"."etiquetas_dieteticas" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "tag_key" text NOT NULL,
    "label" text NOT NULL,
    "description" text DEFAULT ''::text NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    "version" bigint DEFAULT 1 NOT NULL,
    CONSTRAINT "dietary_tags_label_check" CHECK (((length(TRIM(BOTH FROM label)) >= 1) AND (length(TRIM(BOTH FROM label)) <= 80))),
    CONSTRAINT "dietary_tags_pkey" PRIMARY KEY (id),
    CONSTRAINT "dietary_tags_tag_key_check" CHECK ((tag_key ~ '^[a-z0-9-]{2,50}$'::text)),
    CONSTRAINT "dietary_tags_tag_key_key" UNIQUE (tag_key),
    CONSTRAINT "dietary_tags_version_check" CHECK ((version > 0))
);

CREATE TABLE "public"."etiquetas_dieteticas_ingrediente" (
    "ingredient_id" uuid NOT NULL,
    "dietary_tag_id" uuid NOT NULL,
    "compatibility" text NOT NULL,
    "note" text DEFAULT ''::text NOT NULL,
    CONSTRAINT "ingredient_dietary_tags_compatibility_check" CHECK ((compatibility = ANY (ARRAY['suitable'::text, 'contains'::text, 'unknown'::text]))),
    CONSTRAINT "ingredient_dietary_tags_pkey" PRIMARY KEY (ingredient_id, dietary_tag_id)
);

CREATE TABLE "public"."etiquetas_dieteticas_receta" (
    "recipe_id" uuid NOT NULL,
    "dietary_tag_id" uuid NOT NULL,
    CONSTRAINT "recipe_dietary_tags_pkey" PRIMARY KEY (recipe_id, dietary_tag_id)
);

CREATE TABLE "public"."eventos_cocina" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "owner_user_id" uuid NOT NULL,
    "session_id" uuid NOT NULL,
    "recipe_id" uuid,
    "recipe_snapshot" jsonb NOT NULL,
    "portions" integer NOT NULL,
    "cooked_at" timestamp with time zone DEFAULT now() NOT NULL,
    "deduct_stock" boolean DEFAULT false NOT NULL,
    "hidden_at" timestamp with time zone,
    CONSTRAINT "cooking_events_pkey" PRIMARY KEY (id),
    CONSTRAINT "cooking_events_portions_check" CHECK (((portions >= 1) AND (portions <= 100))),
    CONSTRAINT "cooking_events_recipe_snapshot_check" CHECK ((jsonb_typeof(recipe_snapshot) = 'object'::text)),
    CONSTRAINT "cooking_events_session_id_key" UNIQUE (session_id)
);

CREATE TABLE "public"."ingredientes" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "legacy_id" text,
    "name" text NOT NULL,
    "normalized_name" text NOT NULL,
    "category_id" uuid NOT NULL,
    "base_unit_id" uuid NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "is_deleted" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    "version" bigint DEFAULT 1 NOT NULL,
    CONSTRAINT "ingredients_legacy_id_key" UNIQUE (legacy_id),
    CONSTRAINT "ingredients_name_check" CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 120))),
    CONSTRAINT "ingredients_normalized_name_key" UNIQUE (normalized_name),
    CONSTRAINT "ingredients_pkey" PRIMARY KEY (id),
    CONSTRAINT "ingredients_version_check" CHECK ((version > 0))
);

CREATE TABLE "public"."ingredientes_evento_cocina" (
    "event_id" uuid NOT NULL,
    "ingredient_id" uuid,
    "name_snapshot" text NOT NULL,
    "quantity_used" numeric(14,4) NOT NULL,
    "unit_abbreviation_snapshot" text NOT NULL,
    CONSTRAINT "cooking_event_ingredients_pkey" PRIMARY KEY (event_id, name_snapshot, unit_abbreviation_snapshot),
    CONSTRAINT "cooking_event_ingredients_quantity_used_check" CHECK ((quantity_used >= (0)::numeric))
);

CREATE TABLE "public"."ingredientes_paso_receta" (
    "step_id" uuid NOT NULL,
    "recipe_ingredient_id" uuid NOT NULL,
    "quantity_override" numeric(14,4),
    CONSTRAINT "recipe_step_ingredients_pkey" PRIMARY KEY (step_id, recipe_ingredient_id),
    CONSTRAINT "recipe_step_ingredients_quantity_override_check" CHECK ((quantity_override > (0)::numeric))
);

CREATE TABLE "public"."ingredientes_receta" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "recipe_id" uuid NOT NULL,
    "ingredient_id" uuid NOT NULL,
    "quantity" numeric(14,4) NOT NULL,
    "unit_id" uuid NOT NULL,
    "note" text DEFAULT ''::text NOT NULL,
    "position" integer NOT NULL,
    CONSTRAINT "recipe_ingredients_pkey" PRIMARY KEY (id),
    CONSTRAINT "recipe_ingredients_position_check" CHECK (("position" > 0)),
    CONSTRAINT "recipe_ingredients_quantity_check" CHECK ((quantity > (0)::numeric)),
    CONSTRAINT "recipe_ingredients_recipe_id_position_key" UNIQUE (recipe_id, "position")
);

CREATE TABLE "public"."listas_compras" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "owner_user_id" uuid NOT NULL,
    "plan_id" uuid,
    "name" text DEFAULT 'Lista de compras'::text NOT NULL,
    "status" text DEFAULT 'active'::text NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    "version" bigint DEFAULT 1 NOT NULL,
    CONSTRAINT "shopping_lists_pkey" PRIMARY KEY (id),
    CONSTRAINT "shopping_lists_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text]))),
    CONSTRAINT "shopping_lists_version_check" CHECK ((version > 0))
);

CREATE TABLE "public"."origenes_articulo_compra" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "shopping_item_id" uuid NOT NULL,
    "source" text NOT NULL,
    "recipe_id" uuid,
    "plan_id" uuid,
    CONSTRAINT "shopping_item_sources_check" CHECK ((((source = 'recipe'::text) AND (recipe_id IS NOT NULL)) OR (source <> 'recipe'::text))),
    CONSTRAINT "shopping_item_sources_check1" CHECK ((((source = 'plan'::text) AND (plan_id IS NOT NULL)) OR (source <> 'plan'::text))),
    CONSTRAINT "shopping_item_sources_pkey" PRIMARY KEY (id),
    CONSTRAINT "shopping_item_sources_shopping_item_id_source_recipe_id_pla_key" UNIQUE NULLS NOT DISTINCT (shopping_item_id, source, recipe_id, plan_id),
    CONSTRAINT "shopping_item_sources_source_check" CHECK ((source = ANY (ARRAY['manual'::text, 'recipe'::text, 'plan'::text, 'favorites'::text, 'pantry'::text])))
);

CREATE TABLE "public"."pasos_receta" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "recipe_id" uuid NOT NULL,
    "position" integer NOT NULL,
    "instruction" text NOT NULL,
    "duration_minutes" integer,
    "temperature" text,
    "tip" text,
    "warning" text,
    "utensils" text[] DEFAULT '{}'::text[] NOT NULL,
    "special_instructions" text,
    CONSTRAINT "recipe_steps_duration_minutes_check" CHECK ((duration_minutes >= 0)),
    CONSTRAINT "recipe_steps_instruction_check" CHECK (((length(TRIM(BOTH FROM instruction)) >= 1) AND (length(TRIM(BOTH FROM instruction)) <= 5000))),
    CONSTRAINT "recipe_steps_pkey" PRIMARY KEY (id),
    CONSTRAINT "recipe_steps_position_check" CHECK (("position" > 0)),
    CONSTRAINT "recipe_steps_recipe_id_position_key" UNIQUE (recipe_id, "position")
);

CREATE TABLE "public"."pasos_sesion_cocina" (
    "session_id" uuid NOT NULL,
    "step_position" integer NOT NULL,
    "completed_at" timestamp with time zone,
    "remaining_ms" bigint,
    "timer_deadline_at" timestamp with time zone,
    "timer_state" text DEFAULT 'idle'::text NOT NULL,
    CONSTRAINT "cooking_session_steps_check" CHECK (((timer_state <> 'running'::text) OR (timer_deadline_at IS NOT NULL))),
    CONSTRAINT "cooking_session_steps_pkey" PRIMARY KEY (session_id, step_position),
    CONSTRAINT "cooking_session_steps_remaining_ms_check" CHECK ((remaining_ms >= 0)),
    CONSTRAINT "cooking_session_steps_step_position_check" CHECK ((step_position > 0)),
    CONSTRAINT "cooking_session_steps_timer_state_check" CHECK ((timer_state = ANY (ARRAY['idle'::text, 'running'::text, 'paused'::text, 'finished'::text])))
);

CREATE TABLE "public"."perfiles" (
    "user_id" uuid NOT NULL,
    "display_name" text NOT NULL,
    "birth_date" date,
    "weight_kg" numeric(6,2),
    "height_cm" numeric(6,2),
    "metabolic_sex" text,
    "activity_level" text,
    "goal" text,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    "version" bigint DEFAULT 1 NOT NULL,
    CONSTRAINT "profiles_activity_level_check" CHECK ((activity_level = ANY (ARRAY['sedentary'::text, 'light'::text, 'moderate'::text, 'active'::text, 'very-active'::text]))),
    CONSTRAINT "profiles_display_name_check" CHECK (((length(TRIM(BOTH FROM display_name)) >= 1) AND (length(TRIM(BOTH FROM display_name)) <= 120))),
    CONSTRAINT "profiles_goal_check" CHECK ((goal = ANY (ARRAY['lose'::text, 'maintain'::text, 'gain'::text, 'gain-muscle'::text]))),
    CONSTRAINT "profiles_height_cm_check" CHECK (((height_cm >= (100)::numeric) AND (height_cm <= (250)::numeric))),
    CONSTRAINT "profiles_metabolic_sex_check" CHECK ((metabolic_sex = ANY (ARRAY['female'::text, 'male'::text]))),
    CONSTRAINT "profiles_pkey" PRIMARY KEY (user_id),
    CONSTRAINT "profiles_version_check" CHECK ((version > 0)),
    CONSTRAINT "profiles_weight_kg_check" CHECK (((weight_kg >= (30)::numeric) AND (weight_kg <= (300)::numeric)))
);

CREATE TABLE "public"."planes_comida" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "owner_user_id" uuid NOT NULL,
    "week_start" date NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    "version" bigint DEFAULT 1 NOT NULL,
    CONSTRAINT "meal_plans_owner_user_id_week_start_key" UNIQUE (owner_user_id, week_start),
    CONSTRAINT "meal_plans_pkey" PRIMARY KEY (id),
    CONSTRAINT "meal_plans_version_check" CHECK ((version > 0)),
    CONSTRAINT "meal_plans_week_start_check" CHECK ((EXTRACT(isodow FROM week_start) = (1)::numeric))
);

CREATE TABLE "public"."preferencias_dieteticas_usuario" (
    "user_id" uuid NOT NULL,
    "dietary_tag_id" uuid NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT "user_dietary_preferences_pkey" PRIMARY KEY (user_id, dietary_tag_id)
);

CREATE TABLE "public"."recetas" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "legacy_id" text,
    "owner_user_id" uuid,
    "recipe_source" text NOT NULL,
    "title" text NOT NULL,
    "author" text DEFAULT ''::text NOT NULL,
    "description" text DEFAULT ''::text NOT NULL,
    "category_label" text DEFAULT ''::text NOT NULL,
    "total_minutes" integer NOT NULL,
    "preparation_minutes" integer,
    "cooking_minutes" integer,
    "portions" integer NOT NULL,
    "difficulty" text NOT NULL,
    "calories_per_portion" numeric(9,2),
    "publication_status" text DEFAULT 'draft'::text NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "is_deleted" boolean DEFAULT false NOT NULL,
    "featured" boolean DEFAULT false NOT NULL,
    "symbol" text DEFAULT ''::text NOT NULL,
    "color" text DEFAULT 'green'::text NOT NULL,
    "cross_contamination_note" text,
    "image_path" text,
    "image_alt" text,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    "version" bigint DEFAULT 1 NOT NULL,
    CONSTRAINT "recipes_calories_per_portion_check" CHECK ((calories_per_portion >= (0)::numeric)),
    CONSTRAINT "recipes_check" CHECK ((((recipe_source = 'official'::text) AND (owner_user_id IS NULL)) OR ((recipe_source = ANY (ARRAY['user'::text, 'ai'::text])) AND (owner_user_id IS NOT NULL)))),
    CONSTRAINT "recipes_color_check" CHECK ((color = ANY (ARRAY['green'::text, 'gold'::text, 'pink'::text, 'blue'::text]))),
    CONSTRAINT "recipes_cooking_minutes_check" CHECK ((cooking_minutes >= 0)),
    CONSTRAINT "recipes_difficulty_check" CHECK ((difficulty = ANY (ARRAY['easy'::text, 'intermediate'::text, 'advanced'::text]))),
    CONSTRAINT "recipes_legacy_id_key" UNIQUE (legacy_id),
    CONSTRAINT "recipes_pkey" PRIMARY KEY (id),
    CONSTRAINT "recipes_portions_check" CHECK (((portions >= 1) AND (portions <= 100))),
    CONSTRAINT "recipes_preparation_minutes_check" CHECK ((preparation_minutes >= 0)),
    CONSTRAINT "recipes_publication_status_check" CHECK ((publication_status = ANY (ARRAY['draft'::text, 'published'::text, 'rejected'::text]))),
    CONSTRAINT "recipes_recipe_source_check" CHECK ((recipe_source = ANY (ARRAY['official'::text, 'user'::text, 'ai'::text]))),
    CONSTRAINT "recipes_title_check" CHECK (((length(TRIM(BOTH FROM title)) >= 1) AND (length(TRIM(BOTH FROM title)) <= 180))),
    CONSTRAINT "recipes_total_minutes_check" CHECK ((total_minutes > 0)),
    CONSTRAINT "recipes_version_check" CHECK ((version > 0))
);

CREATE TABLE "public"."recetas_compartidas" (
    "catalog_key" text DEFAULT 'main'::text NOT NULL,
    "recipes" jsonb DEFAULT '[]'::jsonb NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    "version" integer DEFAULT 1 NOT NULL,
    CONSTRAINT "shared_recipes_catalog_key_check" CHECK ((catalog_key = 'main'::text)),
    CONSTRAINT "shared_recipes_payload_shape" CHECK ((jsonb_typeof(recipes) = 'array'::text)),
    CONSTRAINT "shared_recipes_pkey" PRIMARY KEY (catalog_key),
    CONSTRAINT "shared_recipes_version_check" CHECK ((version > 0))
);

CREATE TABLE "public"."recetas_favoritas" (
    "user_id" uuid NOT NULL,
    "recipe_id" uuid NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT "favorite_recipes_pkey" PRIMARY KEY (user_id, recipe_id)
);

CREATE TABLE "public"."registro_auditoria" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "occurred_at" timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    "actor_user_id" uuid,
    "action" text NOT NULL,
    "target_user_id" uuid,
    "details" jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT "admin_audit_log_action_check" CHECK ((action = ANY (ARRAY['user.created'::text, 'user.name_updated'::text, 'user.role_changed'::text, 'user.activated'::text, 'user.deactivated'::text, 'catalog.core_saved'::text, 'catalog.recipes_saved'::text, 'catalog.category_saved'::text, 'catalog.unit_saved'::text, 'catalog.ingredient_saved'::text, 'catalog.recipe_saved'::text, 'catalog.recipe_duplicated'::text, 'catalog.recipe_flags_changed'::text, 'catalog.dietary_tag_saved'::text, 'catalog.ingredient_dietary_tags_saved'::text, 'nutrition.config_published'::text]))),
    CONSTRAINT "admin_audit_log_details_check" CHECK ((jsonb_typeof(details) = 'object'::text)),
    CONSTRAINT "admin_audit_log_pkey" PRIMARY KEY (id)
);

CREATE TABLE "public"."roles_usuario" (
    "user_id" uuid NOT NULL,
    "role" text DEFAULT 'USER'::text NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT "user_roles_pkey" PRIMARY KEY (user_id),
    CONSTRAINT "user_roles_role_check" CHECK ((role = ANY (ARRAY['USER'::text, 'ADMIN'::text])))
);

CREATE TABLE "public"."sesiones_cocina" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "owner_user_id" uuid NOT NULL,
    "recipe_id" uuid,
    "recipe_snapshot" jsonb NOT NULL,
    "recipe_version" integer,
    "portions" integer NOT NULL,
    "current_step" integer DEFAULT 0 NOT NULL,
    "client_idempotency_key" uuid NOT NULL,
    "started_at" timestamp with time zone DEFAULT now() NOT NULL,
    "finished_at" timestamp with time zone,
    "version" bigint DEFAULT 1 NOT NULL,
    "requested_portions" integer DEFAULT 1 NOT NULL,
    CONSTRAINT "cooking_sessions_current_step_check" CHECK ((current_step >= 0)),
    CONSTRAINT "cooking_sessions_owner_user_id_client_idempotency_key_key" UNIQUE (owner_user_id, client_idempotency_key),
    CONSTRAINT "cooking_sessions_pkey" PRIMARY KEY (id),
    CONSTRAINT "cooking_sessions_portions_check" CHECK (((portions >= 1) AND (portions <= 100))),
    CONSTRAINT "cooking_sessions_recipe_snapshot_check" CHECK ((jsonb_typeof(recipe_snapshot) = 'object'::text)),
    CONSTRAINT "cooking_sessions_requested_portions_check" CHECK (((requested_portions >= 1) AND (requested_portions <= 20))),
    CONSTRAINT "cooking_sessions_version_check" CHECK ((version > 0))
);

CREATE TABLE "public"."solicitudes_generacion_receta" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "owner_user_id" uuid NOT NULL,
    "status" text NOT NULL,
    "provider_model" text,
    "safe_error_code" text,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT (now() + '24:00:00'::interval) NOT NULL,
    CONSTRAINT "recipe_generation_requests_pkey" PRIMARY KEY (id),
    CONSTRAINT "recipe_generation_requests_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text, 'failed'::text, 'expired'::text])))
);

CREATE TABLE "public"."solicitudes_reconocimiento_ticket" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "owner_user_id" uuid NOT NULL,
    "status" text NOT NULL,
    "safe_error_code" text,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT (now() + '01:00:00'::interval) NOT NULL,
    CONSTRAINT "receipt_recognition_requests_pkey" PRIMARY KEY (id),
    CONSTRAINT "receipt_recognition_requests_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text, 'failed'::text, 'discarded'::text, 'expired'::text])))
);

CREATE TABLE "public"."turnos_comida_receta" (
    "recipe_id" uuid NOT NULL,
    "meal_shift" text NOT NULL,
    CONSTRAINT "recipe_meal_shifts_meal_shift_check" CHECK ((meal_shift = ANY (ARRAY['breakfast'::text, 'lunch'::text, 'snack'::text, 'dinner'::text]))),
    CONSTRAINT "recipe_meal_shifts_pkey" PRIMARY KEY (recipe_id, meal_shift)
);

CREATE TABLE "public"."turnos_plan_comida" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "plan_id" uuid NOT NULL,
    "meal_date" date NOT NULL,
    "meal_shift" text NOT NULL,
    "recipe_id" uuid NOT NULL,
    "portions" integer NOT NULL,
    "position" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT "meal_plan_slots_meal_shift_check" CHECK ((meal_shift = ANY (ARRAY['breakfast'::text, 'lunch'::text, 'snack'::text, 'dinner'::text]))),
    CONSTRAINT "meal_plan_slots_pkey" PRIMARY KEY (id),
    CONSTRAINT "meal_plan_slots_plan_id_meal_date_meal_shift_position_key" UNIQUE (plan_id, meal_date, meal_shift, "position"),
    CONSTRAINT "meal_plan_slots_portions_check" CHECK (((portions >= 1) AND (portions <= 20))),
    CONSTRAINT "meal_plan_slots_position_check" CHECK (("position" > 0))
);

CREATE TABLE "public"."unidades" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "legacy_id" text,
    "name" text NOT NULL,
    "abbreviation" text NOT NULL,
    "dimension" text NOT NULL,
    "base_unit_id" uuid,
    "equivalence_multiplier" numeric(14,6),
    "active" boolean DEFAULT true NOT NULL,
    "is_deleted" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
    "version" bigint DEFAULT 1 NOT NULL,
    "normalized_name" text NOT NULL,
    CONSTRAINT "units_abbreviation_key" UNIQUE (abbreviation),
    CONSTRAINT "units_check" CHECK ((((base_unit_id IS NULL) AND (equivalence_multiplier IS NULL)) OR ((base_unit_id IS NOT NULL) AND (equivalence_multiplier IS NOT NULL)))),
    CONSTRAINT "units_dimension_check" CHECK ((dimension = ANY (ARRAY['mass'::text, 'volume'::text, 'count'::text]))),
    CONSTRAINT "units_equivalence_multiplier_check" CHECK ((equivalence_multiplier > (0)::numeric)),
    CONSTRAINT "units_legacy_id_key" UNIQUE (legacy_id),
    CONSTRAINT "units_name_check" CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 60))),
    CONSTRAINT "units_pkey" PRIMARY KEY (id),
    CONSTRAINT "units_version_check" CHECK ((version > 0))
);

-- Relaciones declaradas como claves foraneas (incluye relaciones a la propia tabla).
ALTER TABLE "public"."articulos_compra"
    ADD CONSTRAINT "shopping_items_ingredient_id_fkey" FOREIGN KEY ("ingredient_id")
    REFERENCES "public"."ingredientes" ("id") ON DELETE RESTRICT;
ALTER TABLE "public"."articulos_compra"
    ADD CONSTRAINT "shopping_items_list_id_fkey" FOREIGN KEY ("list_id")
    REFERENCES "public"."listas_compras" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."articulos_compra"
    ADD CONSTRAINT "shopping_items_unit_id_fkey" FOREIGN KEY ("unit_id")
    REFERENCES "public"."unidades" ("id") ON DELETE RESTRICT;
ALTER TABLE "public"."articulos_comprobante_despensa"
    ADD CONSTRAINT "pantry_receipt_items_pantry_item_id_fkey" FOREIGN KEY ("pantry_item_id")
    REFERENCES "public"."articulos_despensa" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."articulos_comprobante_despensa"
    ADD CONSTRAINT "pantry_receipt_items_receipt_id_fkey" FOREIGN KEY ("receipt_id")
    REFERENCES "public"."comprobantes_despensa" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."articulos_comprobante_despensa"
    ADD CONSTRAINT "pantry_receipt_items_shopping_item_id_fkey" FOREIGN KEY ("shopping_item_id")
    REFERENCES "public"."articulos_compra" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."articulos_despensa"
    ADD CONSTRAINT "pantry_items_ingredient_ref_fkey" FOREIGN KEY ("ingredient_ref")
    REFERENCES "public"."ingredientes" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."articulos_despensa"
    ADD CONSTRAINT "pantry_items_unit_ref_fkey" FOREIGN KEY ("unit_ref")
    REFERENCES "public"."unidades" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."articulos_despensa"
    ADD CONSTRAINT "pantry_items_user_id_fkey" FOREIGN KEY ("user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."comprobantes_despensa"
    ADD CONSTRAINT "pantry_receipts_owner_user_id_fkey" FOREIGN KEY ("owner_user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."comprobantes_despensa"
    ADD CONSTRAINT "pantry_receipts_shopping_list_id_fkey" FOREIGN KEY ("shopping_list_id")
    REFERENCES "public"."listas_compras" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."configuracion_nutricional"
    ADD CONSTRAINT "nutrition_config_updated_by_fkey" FOREIGN KEY ("updated_by")
    REFERENCES "auth"."users" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."datos_personales"
    ADD CONSTRAINT "personal_data_user_id_fkey" FOREIGN KEY ("user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."estado_cuenta"
    ADD CONSTRAINT "account_status_user_id_fkey" FOREIGN KEY ("user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."estado_escritura_receta_admin"
    ADD CONSTRAINT "admin_recipe_write_state_recipe_id_fkey" FOREIGN KEY ("recipe_id")
    REFERENCES "public"."recetas" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."etiquetas_dieteticas_ingrediente"
    ADD CONSTRAINT "ingredient_dietary_tags_dietary_tag_id_fkey" FOREIGN KEY ("dietary_tag_id")
    REFERENCES "public"."etiquetas_dieteticas" ("id") ON DELETE RESTRICT;
ALTER TABLE "public"."etiquetas_dieteticas_ingrediente"
    ADD CONSTRAINT "ingredient_dietary_tags_ingredient_id_fkey" FOREIGN KEY ("ingredient_id")
    REFERENCES "public"."ingredientes" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."etiquetas_dieteticas_receta"
    ADD CONSTRAINT "recipe_dietary_tags_dietary_tag_id_fkey" FOREIGN KEY ("dietary_tag_id")
    REFERENCES "public"."etiquetas_dieteticas" ("id") ON DELETE RESTRICT;
ALTER TABLE "public"."etiquetas_dieteticas_receta"
    ADD CONSTRAINT "recipe_dietary_tags_recipe_id_fkey" FOREIGN KEY ("recipe_id")
    REFERENCES "public"."recetas" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."eventos_cocina"
    ADD CONSTRAINT "cooking_events_owner_user_id_fkey" FOREIGN KEY ("owner_user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."eventos_cocina"
    ADD CONSTRAINT "cooking_events_recipe_id_fkey" FOREIGN KEY ("recipe_id")
    REFERENCES "public"."recetas" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."eventos_cocina"
    ADD CONSTRAINT "cooking_events_session_id_fkey" FOREIGN KEY ("session_id")
    REFERENCES "public"."sesiones_cocina" ("id") ON DELETE RESTRICT;
ALTER TABLE "public"."ingredientes"
    ADD CONSTRAINT "ingredients_base_unit_id_fkey" FOREIGN KEY ("base_unit_id")
    REFERENCES "public"."unidades" ("id") ON DELETE RESTRICT;
ALTER TABLE "public"."ingredientes"
    ADD CONSTRAINT "ingredients_category_id_fkey" FOREIGN KEY ("category_id")
    REFERENCES "public"."categorias" ("id") ON DELETE RESTRICT;
ALTER TABLE "public"."ingredientes_evento_cocina"
    ADD CONSTRAINT "cooking_event_ingredients_event_id_fkey" FOREIGN KEY ("event_id")
    REFERENCES "public"."eventos_cocina" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."ingredientes_evento_cocina"
    ADD CONSTRAINT "cooking_event_ingredients_ingredient_id_fkey" FOREIGN KEY ("ingredient_id")
    REFERENCES "public"."ingredientes" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."ingredientes_paso_receta"
    ADD CONSTRAINT "recipe_step_ingredients_recipe_ingredient_id_fkey" FOREIGN KEY ("recipe_ingredient_id")
    REFERENCES "public"."ingredientes_receta" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."ingredientes_paso_receta"
    ADD CONSTRAINT "recipe_step_ingredients_step_id_fkey" FOREIGN KEY ("step_id")
    REFERENCES "public"."pasos_receta" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."ingredientes_receta"
    ADD CONSTRAINT "recipe_ingredients_ingredient_id_fkey" FOREIGN KEY ("ingredient_id")
    REFERENCES "public"."ingredientes" ("id") ON DELETE RESTRICT;
ALTER TABLE "public"."ingredientes_receta"
    ADD CONSTRAINT "recipe_ingredients_recipe_id_fkey" FOREIGN KEY ("recipe_id")
    REFERENCES "public"."recetas" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."ingredientes_receta"
    ADD CONSTRAINT "recipe_ingredients_unit_id_fkey" FOREIGN KEY ("unit_id")
    REFERENCES "public"."unidades" ("id") ON DELETE RESTRICT;
ALTER TABLE "public"."listas_compras"
    ADD CONSTRAINT "shopping_lists_owner_user_id_fkey" FOREIGN KEY ("owner_user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."listas_compras"
    ADD CONSTRAINT "shopping_lists_plan_id_fkey" FOREIGN KEY ("plan_id")
    REFERENCES "public"."planes_comida" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."origenes_articulo_compra"
    ADD CONSTRAINT "shopping_item_sources_plan_id_fkey" FOREIGN KEY ("plan_id")
    REFERENCES "public"."planes_comida" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."origenes_articulo_compra"
    ADD CONSTRAINT "shopping_item_sources_recipe_id_fkey" FOREIGN KEY ("recipe_id")
    REFERENCES "public"."recetas" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."origenes_articulo_compra"
    ADD CONSTRAINT "shopping_item_sources_shopping_item_id_fkey" FOREIGN KEY ("shopping_item_id")
    REFERENCES "public"."articulos_compra" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."pasos_receta"
    ADD CONSTRAINT "recipe_steps_recipe_id_fkey" FOREIGN KEY ("recipe_id")
    REFERENCES "public"."recetas" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."pasos_sesion_cocina"
    ADD CONSTRAINT "cooking_session_steps_session_id_fkey" FOREIGN KEY ("session_id")
    REFERENCES "public"."sesiones_cocina" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."perfiles"
    ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."planes_comida"
    ADD CONSTRAINT "meal_plans_owner_user_id_fkey" FOREIGN KEY ("owner_user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."preferencias_dieteticas_usuario"
    ADD CONSTRAINT "user_dietary_preferences_dietary_tag_id_fkey" FOREIGN KEY ("dietary_tag_id")
    REFERENCES "public"."etiquetas_dieteticas" ("id") ON DELETE RESTRICT;
ALTER TABLE "public"."preferencias_dieteticas_usuario"
    ADD CONSTRAINT "user_dietary_preferences_user_id_fkey" FOREIGN KEY ("user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."recetas"
    ADD CONSTRAINT "recipes_owner_user_id_fkey" FOREIGN KEY ("owner_user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."recetas_favoritas"
    ADD CONSTRAINT "favorite_recipes_recipe_id_fkey" FOREIGN KEY ("recipe_id")
    REFERENCES "public"."recetas" ("id") ON DELETE RESTRICT;
ALTER TABLE "public"."recetas_favoritas"
    ADD CONSTRAINT "favorite_recipes_user_id_fkey" FOREIGN KEY ("user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."registro_auditoria"
    ADD CONSTRAINT "admin_audit_log_actor_user_id_fkey" FOREIGN KEY ("actor_user_id")
    REFERENCES "auth"."users" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."registro_auditoria"
    ADD CONSTRAINT "admin_audit_log_target_user_id_fkey" FOREIGN KEY ("target_user_id")
    REFERENCES "auth"."users" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."roles_usuario"
    ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY ("user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."sesiones_cocina"
    ADD CONSTRAINT "cooking_sessions_owner_user_id_fkey" FOREIGN KEY ("owner_user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."sesiones_cocina"
    ADD CONSTRAINT "cooking_sessions_recipe_id_fkey" FOREIGN KEY ("recipe_id")
    REFERENCES "public"."recetas" ("id") ON DELETE SET NULL;
ALTER TABLE "public"."solicitudes_generacion_receta"
    ADD CONSTRAINT "recipe_generation_requests_owner_user_id_fkey" FOREIGN KEY ("owner_user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."solicitudes_reconocimiento_ticket"
    ADD CONSTRAINT "receipt_recognition_requests_owner_user_id_fkey" FOREIGN KEY ("owner_user_id")
    REFERENCES "auth"."users" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."turnos_comida_receta"
    ADD CONSTRAINT "recipe_meal_shifts_recipe_id_fkey" FOREIGN KEY ("recipe_id")
    REFERENCES "public"."recetas" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."turnos_plan_comida"
    ADD CONSTRAINT "meal_plan_slots_plan_id_fkey" FOREIGN KEY ("plan_id")
    REFERENCES "public"."planes_comida" ("id") ON DELETE CASCADE;
ALTER TABLE "public"."turnos_plan_comida"
    ADD CONSTRAINT "meal_plan_slots_recipe_id_fkey" FOREIGN KEY ("recipe_id")
    REFERENCES "public"."recetas" ("id") ON DELETE RESTRICT;
ALTER TABLE "public"."unidades"
    ADD CONSTRAINT "units_base_unit_id_fkey" FOREIGN KEY ("base_unit_id")
    REFERENCES "public"."unidades" ("id") ON DELETE RESTRICT;

-- Indices unicos adicionales; los respaldados por PK/UNIQUE ya se crean arriba.
CREATE UNIQUE INDEX categories_non_deleted_normalized_name_uidx ON public.categorias USING btree (normalized_name) WHERE (NOT is_deleted);
CREATE UNIQUE INDEX shopping_lists_one_active_per_user_idx ON public.listas_compras USING btree (owner_user_id) WHERE (status = 'active'::text);
CREATE UNIQUE INDEX units_non_deleted_normalized_name_uidx ON public.unidades USING btree (normalized_name) WHERE (NOT is_deleted);
