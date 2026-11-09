-- TABLE RENAME REHEARSAL: run this complete file as postgres in Supabase SQL Editor.
-- Requires the seven legacy tables only; partial/premature relational installs fail before DDL.
-- All staged migrations, table renames, and checks are rolled back at the end.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
do $preflight_legacy$
declare legacy_names text[] := array['pantry_items','personal_data','user_roles','catalog_core','shared_recipes','account_status','admin_audit_log'];
        relational_names text[] := array['dietary_tags','nutrition_config','profiles','user_dietary_preferences','categories','units','ingredients','ingredient_dietary_tags','recipes','recipe_meal_shifts','recipe_dietary_tags','recipe_ingredients','recipe_steps','recipe_step_ingredients','favorite_recipes','meal_plans','meal_plan_slots','pantry_receipts','shopping_lists','shopping_items','shopping_item_sources','pantry_receipt_items','cooking_sessions','cooking_session_steps','cooking_events','cooking_event_ingredients','recipe_generation_requests','receipt_recognition_requests','admin_recipe_write_state'];
begin
  if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname=any(legacy_names)) <> 7 then
    raise exception 'Preflight failed: expected all seven legacy application tables';
  end if;
  if exists(select 1 from unnest(relational_names) names(name) where to_regclass('public.'||name) is not null) then
    raise exception 'Preflight failed: relational tables already exist; use the normal migration path instead';
  end if;
end;
$preflight_legacy$;
-- The remote project has only the seven legacy tables. Install pending migrations
-- inside this same transaction so they and the final rename all roll back together.
-- Staged from 202610300001_restrict_direct_catalog_writes.sql inside the rehearsal transaction.
-- Shared catalog writes must go through the version-aware RPCs. Restore the
-- intended client grants explicitly in case an earlier setup granted them.
revoke insert, update, delete on table public.catalog_core from public, anon, authenticated;
revoke insert, update, delete on table public.shared_recipes from public, anon, authenticated;

grant select on table public.catalog_core to authenticated;
grant select on table public.shared_recipes to authenticated;

grant execute on function public.admin_save_catalog_core(integer, jsonb) to authenticated;
grant execute on function public.admin_save_shared_recipes(integer, jsonb) to authenticated;


-- Staged from 202610300002_add_relational_domain_tables.sql inside the rehearsal transaction.
-- Additive relational foundation. Legacy JSON tables and data remain untouched.
create table if not exists public.dietary_tags (
  id uuid primary key default gen_random_uuid(),
  tag_key text not null unique check (tag_key ~ '^[a-z0-9-]{2,50}$'),
  label text not null check (length(trim(label)) between 1 and 80),
  description text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.nutrition_config (
  config_version integer primary key check (config_version > 0),
  activity_factors jsonb not null check (jsonb_typeof(activity_factors) = 'object'),
  goal_adjustments jsonb not null check (jsonb_typeof(goal_adjustments) = 'object'),
  source_note text not null,
  effective_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(trim(display_name)) between 1 and 120),
  birth_date date,
  weight_kg numeric(6,2) check (weight_kg between 30 and 300),
  height_cm numeric(6,2) check (height_cm between 100 and 250),
  metabolic_sex text check (metabolic_sex in ('female', 'male')),
  activity_level text check (activity_level in ('sedentary', 'light', 'moderate', 'active', 'very-active')),
  goal text check (goal in ('lose', 'maintain', 'gain', 'gain-muscle')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_dietary_preferences (
  user_id uuid not null references auth.users(id) on delete cascade,
  dietary_tag_id uuid not null references public.dietary_tags(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (user_id, dietary_tag_id)
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  legacy_id text unique,
  name text not null check (length(trim(name)) between 1 and 100),
  normalized_name text not null unique,
  active boolean not null default true,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  legacy_id text unique,
  name text not null check (length(trim(name)) between 1 and 60),
  abbreviation text not null unique,
  dimension text not null check (dimension in ('mass', 'volume', 'count')),
  base_unit_id uuid references public.units(id) on delete restrict,
  equivalence_multiplier numeric(14,6) check (equivalence_multiplier > 0),
  active boolean not null default true,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((base_unit_id is null and equivalence_multiplier is null) or (base_unit_id is not null and equivalence_multiplier is not null))
);

create table if not exists public.ingredients (
  id uuid primary key default gen_random_uuid(),
  legacy_id text unique,
  name text not null check (length(trim(name)) between 1 and 120),
  normalized_name text not null unique,
  category_id uuid not null references public.categories(id) on delete restrict,
  base_unit_id uuid not null references public.units(id) on delete restrict,
  active boolean not null default true,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ingredient_dietary_tags (
  ingredient_id uuid not null references public.ingredients(id) on delete cascade,
  dietary_tag_id uuid not null references public.dietary_tags(id) on delete restrict,
  compatibility text not null check (compatibility in ('suitable', 'contains', 'unknown')),
  note text not null default '',
  primary key (ingredient_id, dietary_tag_id)
);

create table if not exists public.recipes (
  id uuid primary key default gen_random_uuid(),
  legacy_id text unique,
  owner_user_id uuid references auth.users(id) on delete cascade,
  recipe_source text not null check (recipe_source in ('official', 'user', 'ai')),
  title text not null check (length(trim(title)) between 1 and 180),
  author text not null default '',
  description text not null default '',
  category_label text not null default '',
  total_minutes integer not null check (total_minutes > 0),
  preparation_minutes integer check (preparation_minutes >= 0),
  cooking_minutes integer check (cooking_minutes >= 0),
  portions integer not null check (portions between 1 and 100),
  difficulty text not null check (difficulty in ('easy', 'intermediate', 'advanced')),
  calories_per_portion numeric(9,2) check (calories_per_portion >= 0),
  publication_status text not null default 'draft' check (publication_status in ('draft', 'published', 'rejected')),
  active boolean not null default true,
  is_deleted boolean not null default false,
  featured boolean not null default false,
  symbol text not null default '',
  color text not null default 'green' check (color in ('green','gold','pink','blue')),
  cross_contamination_note text,
  image_path text,
  image_alt text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((recipe_source = 'official' and owner_user_id is null) or (recipe_source in ('user', 'ai') and owner_user_id is not null))
);

create table if not exists public.recipe_meal_shifts (
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  meal_shift text not null check (meal_shift in ('breakfast', 'lunch', 'snack', 'dinner')),
  primary key (recipe_id, meal_shift)
);

create table if not exists public.recipe_dietary_tags (
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  dietary_tag_id uuid not null references public.dietary_tags(id) on delete restrict,
  primary key (recipe_id, dietary_tag_id)
);

create table if not exists public.recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  ingredient_id uuid not null references public.ingredients(id) on delete restrict,
  quantity numeric(14,4) not null check (quantity > 0),
  unit_id uuid not null references public.units(id) on delete restrict,
  note text not null default '',
  position integer not null check (position > 0),
  unique (recipe_id, position)
);

create table if not exists public.recipe_steps (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  position integer not null check (position > 0),
  instruction text not null check (length(trim(instruction)) between 1 and 5000),
  duration_minutes integer check (duration_minutes >= 0),
  temperature text,
  tip text,
  warning text,
  utensils text[] not null default '{}',
  special_instructions text,
  unique (recipe_id, position)
);

create table if not exists public.recipe_step_ingredients (
  step_id uuid not null references public.recipe_steps(id) on delete cascade,
  recipe_ingredient_id uuid not null references public.recipe_ingredients(id) on delete cascade,
  quantity_override numeric(14,4) check (quantity_override > 0),
  primary key (step_id, recipe_ingredient_id)
);

create table if not exists public.favorite_recipes (
  user_id uuid not null references auth.users(id) on delete cascade,
  recipe_id uuid not null references public.recipes(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (user_id, recipe_id)
);

create table if not exists public.meal_plans (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  week_start date not null check (extract(isodow from week_start) = 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_user_id, week_start)
);

create table if not exists public.meal_plan_slots (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.meal_plans(id) on delete cascade,
  meal_date date not null,
  meal_shift text not null check (meal_shift in ('breakfast', 'lunch', 'snack', 'dinner')),
  recipe_id uuid not null references public.recipes(id) on delete restrict,
  portions integer not null check (portions between 1 and 20),
  position integer not null default 1 check (position > 0),
  created_at timestamptz not null default now(),
  unique (plan_id, meal_date, meal_shift, position)
);

create table if not exists public.pantry_receipts (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key uuid not null,
  created_at timestamptz not null default now(),
  unique (owner_user_id, idempotency_key)
);

create table if not exists public.shopping_lists (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid references public.meal_plans(id) on delete set null,
  name text not null default 'Lista de compras',
  status text not null default 'active' check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists shopping_lists_one_active_per_user_idx
  on public.shopping_lists(owner_user_id) where status = 'active';

create table if not exists public.shopping_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.shopping_lists(id) on delete cascade,
  ingredient_id uuid references public.ingredients(id) on delete restrict,
  name_snapshot text not null check (length(trim(name_snapshot)) between 1 and 120),
  category_snapshot text not null default 'Otros',
  quantity numeric(14,4) not null check (quantity > 0 and quantity <= 1000000),
  unit_id uuid not null references public.units(id) on delete restrict,
  note text not null default '',
  checked boolean not null default false,
  transferred_at timestamptz,
  source text not null check (source in ('manual', 'recipe', 'plan', 'favorites', 'pantry')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.shopping_item_sources (
  id uuid primary key default gen_random_uuid(),
  shopping_item_id uuid not null references public.shopping_items(id) on delete cascade,
  source text not null check (source in ('manual', 'recipe', 'plan', 'favorites', 'pantry')),
  recipe_id uuid references public.recipes(id) on delete set null,
  plan_id uuid references public.meal_plans(id) on delete set null,
  unique nulls not distinct (shopping_item_id, source, recipe_id, plan_id),
  check ((source = 'recipe' and recipe_id is not null) or source <> 'recipe'),
  check ((source = 'plan' and plan_id is not null) or source <> 'plan')
);

create table if not exists public.pantry_receipt_items (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.pantry_receipts(id) on delete cascade,
  original_shopping_item_id uuid not null unique,
  shopping_item_id uuid references public.shopping_items(id) on delete set null,
  pantry_item_id uuid references public.pantry_items(id) on delete set null,
  quantity_added numeric(14,4) not null check (quantity_added > 0),
  unit_abbreviation_snapshot text not null
);

create table if not exists public.cooking_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  recipe_id uuid references public.recipes(id) on delete set null,
  recipe_snapshot jsonb not null check (jsonb_typeof(recipe_snapshot) = 'object'),
  recipe_version integer,
  portions integer not null check (portions between 1 and 100),
  current_step integer not null default 0 check (current_step >= 0),
  client_idempotency_key uuid not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  unique (owner_user_id, client_idempotency_key)
);

create table if not exists public.cooking_session_steps (
  session_id uuid not null references public.cooking_sessions(id) on delete cascade,
  step_position integer not null check (step_position > 0),
  completed_at timestamptz,
  remaining_ms bigint check (remaining_ms >= 0),
  timer_deadline_at timestamptz,
  timer_state text not null default 'idle' check (timer_state in ('idle', 'running', 'paused', 'finished')),
  primary key (session_id, step_position),
  check ((timer_state <> 'running') or timer_deadline_at is not null)
);

create table if not exists public.cooking_events (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null unique references public.cooking_sessions(id) on delete restrict,
  recipe_id uuid references public.recipes(id) on delete set null,
  recipe_snapshot jsonb not null check (jsonb_typeof(recipe_snapshot) = 'object'),
  portions integer not null check (portions between 1 and 100),
  cooked_at timestamptz not null default now()
);

create table if not exists public.cooking_event_ingredients (
  event_id uuid not null references public.cooking_events(id) on delete cascade,
  ingredient_id uuid references public.ingredients(id) on delete set null,
  name_snapshot text not null,
  quantity_used numeric(14,4) not null check (quantity_used >= 0),
  unit_abbreviation_snapshot text not null,
  primary key (event_id, name_snapshot, unit_abbreviation_snapshot)
);

create table if not exists public.recipe_generation_requests (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('pending', 'completed', 'failed', 'expired')),
  provider_model text,
  safe_error_code text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours'
);

create table if not exists public.receipt_recognition_requests (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('pending', 'completed', 'failed', 'discarded', 'expired')),
  safe_error_code text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '1 hour'
);

-- Cross-row references must preserve dimensions, recipe identity and ownership.
create or replace function public.validate_relational_domain_link()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare target_owner uuid; target_recipe uuid; start_date date; parent_unit public.units;
begin
  if tg_table_name = 'units' then
    if new.base_unit_id is not null then
      select * into parent_unit from public.units where id = new.base_unit_id;
      if not found or new.base_unit_id = new.id or parent_unit.base_unit_id is not null or parent_unit.dimension <> new.dimension then
        raise exception 'La unidad base debe ser raíz, diferente y de la misma dimensión.' using errcode = '23514';
      end if;
    end if;
    if tg_op = 'UPDATE' and (new.dimension, new.base_unit_id, new.equivalence_multiplier) is distinct from (old.dimension, old.base_unit_id, old.equivalence_multiplier)
      and (exists(select 1 from public.units where base_unit_id = old.id)
        or exists(select 1 from public.ingredients where base_unit_id = old.id)
        or exists(select 1 from public.recipe_ingredients where unit_id = old.id)
        or exists(select 1 from public.shopping_items where unit_id = old.id)) then
      raise exception 'No se puede cambiar la conversión de una unidad referenciada.' using errcode = '23514';
    end if;
  elsif tg_table_name = 'recipe_ingredients' then
    if not exists(select 1 from public.ingredients i join public.units b on b.id = i.base_unit_id
      join public.units u on u.id = new.unit_id where i.id = new.ingredient_id and b.dimension = u.dimension) then
      raise exception 'Unidad incompatible con el ingrediente.' using errcode = '23514';
    end if;
  elsif tg_table_name = 'recipe_step_ingredients' then
    if not exists(select 1 from public.recipe_steps s join public.recipe_ingredients i on i.recipe_id = s.recipe_id
      where s.id = new.step_id and i.id = new.recipe_ingredient_id) then
      raise exception 'El paso y el ingrediente deben pertenecer a la misma receta.' using errcode = '23514';
    end if;
  elsif tg_table_name = 'meal_plan_slots' then
    select owner_user_id, week_start into target_owner, start_date from public.meal_plans where id = new.plan_id;
    if start_date is null or new.meal_date < start_date or new.meal_date >= start_date + 7 then
      raise exception 'La fecha debe pertenecer a la semana del plan.' using errcode = '23514';
    end if;
    target_recipe := new.recipe_id;
  elsif tg_table_name = 'favorite_recipes' then
    target_owner := new.user_id; target_recipe := new.recipe_id;
  elsif tg_table_name = 'cooking_sessions' then
    target_owner := new.owner_user_id; target_recipe := new.recipe_id;
  elsif tg_table_name = 'shopping_lists' then
    if new.plan_id is not null and not exists(select 1 from public.meal_plans where id = new.plan_id and owner_user_id = new.owner_user_id) then
      raise exception 'El plan debe pertenecer al dueño de la lista.' using errcode = '23514';
    end if;
  elsif tg_table_name = 'shopping_item_sources' then
    select l.owner_user_id into target_owner from public.shopping_items i join public.shopping_lists l on l.id = i.list_id where i.id = new.shopping_item_id;
    if new.plan_id is not null and not exists(select 1 from public.meal_plans where id = new.plan_id and owner_user_id = target_owner) then
      raise exception 'El plan debe pertenecer al dueño de la compra.' using errcode = '23514';
    end if;
    target_recipe := new.recipe_id;
  end if;
  if target_recipe is not null and not exists(select 1 from public.recipes r where r.id = target_recipe
    and (r.owner_user_id = target_owner or (r.recipe_source = 'official' and r.publication_status = 'published'))) then
    raise exception 'La receta no está disponible para esta cuenta.' using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_relational_domain_link() from public, anon, authenticated;
do $$
declare table_name text;
begin
  foreach table_name in array array['units','recipe_ingredients','recipe_step_ingredients','meal_plan_slots','favorite_recipes','cooking_sessions','shopping_lists','shopping_item_sources'] loop
    execute format('create trigger validate_domain_link before insert or update on public.%I for each row execute function public.validate_relational_domain_link()', table_name);
  end loop;
end;
$$;

-- Protect every new table; grants are narrowed before row policies are applied.
alter table public.dietary_tags enable row level security;
alter table public.nutrition_config enable row level security;
alter table public.profiles enable row level security;
alter table public.user_dietary_preferences enable row level security;
alter table public.categories enable row level security;
alter table public.units enable row level security;
alter table public.ingredients enable row level security;
alter table public.ingredient_dietary_tags enable row level security;
alter table public.recipes enable row level security;
alter table public.recipe_meal_shifts enable row level security;
alter table public.recipe_dietary_tags enable row level security;
alter table public.recipe_ingredients enable row level security;
alter table public.recipe_steps enable row level security;
alter table public.recipe_step_ingredients enable row level security;
alter table public.favorite_recipes enable row level security;
alter table public.meal_plans enable row level security;
alter table public.meal_plan_slots enable row level security;
alter table public.pantry_receipts enable row level security;
alter table public.shopping_lists enable row level security;
alter table public.shopping_items enable row level security;
alter table public.shopping_item_sources enable row level security;
alter table public.pantry_receipt_items enable row level security;
alter table public.cooking_sessions enable row level security;
alter table public.cooking_session_steps enable row level security;
alter table public.cooking_events enable row level security;
alter table public.cooking_event_ingredients enable row level security;
alter table public.recipe_generation_requests enable row level security;
alter table public.receipt_recognition_requests enable row level security;

revoke all on table public.dietary_tags, public.nutrition_config, public.profiles, public.user_dietary_preferences,
  public.categories, public.units, public.ingredients, public.ingredient_dietary_tags,
  public.recipes, public.recipe_meal_shifts, public.recipe_dietary_tags,
  public.recipe_ingredients, public.recipe_steps, public.recipe_step_ingredients,
  public.favorite_recipes, public.meal_plans, public.meal_plan_slots, public.pantry_receipts,
  public.shopping_lists, public.shopping_items, public.shopping_item_sources,
  public.pantry_receipt_items, public.cooking_sessions, public.cooking_session_steps,
  public.cooking_events, public.cooking_event_ingredients,
  public.recipe_generation_requests, public.receipt_recognition_requests
  from public, anon, authenticated;

grant select on public.dietary_tags, public.nutrition_config, public.categories, public.units, public.ingredients,
  public.ingredient_dietary_tags, public.recipes, public.recipe_meal_shifts,
  public.recipe_dietary_tags, public.recipe_ingredients, public.recipe_steps,
  public.recipe_step_ingredients to authenticated;
grant select on public.profiles, public.user_dietary_preferences,
  public.favorite_recipes, public.meal_plans, public.meal_plan_slots,
  public.shopping_lists, public.shopping_items, public.shopping_item_sources,
  public.cooking_sessions, public.cooking_session_steps,
  public.recipe_generation_requests, public.receipt_recognition_requests to authenticated;
grant select on public.pantry_receipts, public.pantry_receipt_items,
  public.cooking_events, public.cooking_event_ingredients to authenticated;

-- Preserve legacy pantry labels while adding nullable relational references for
-- a later validated backfill. Existing rows are not rewritten in this migration.
alter table public.pantry_items
  add column if not exists ingredient_ref uuid references public.ingredients(id) on delete set null,
  add column if not exists unit_ref uuid references public.units(id) on delete set null;

-- Shared catalog reads; administrative writes are restricted by both grants and RLS.
create policy dietary_tags_read_active on public.dietary_tags for select to authenticated using (active);
create policy nutrition_config_read_current on public.nutrition_config for select to authenticated using (effective_at <= now());
create policy nutrition_config_admin_insert on public.nutrition_config for insert to authenticated
  with check ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()));
create policy categories_read_active on public.categories for select to authenticated using (active and not is_deleted);
create policy categories_admin_all on public.categories for all to authenticated
  using ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()))
  with check ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()));
create policy units_read_active on public.units for select to authenticated using (active and not is_deleted);
create policy units_admin_all on public.units for all to authenticated
  using ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()))
  with check ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()));
create policy ingredients_read_active on public.ingredients for select to authenticated using (active and not is_deleted);
create policy ingredients_admin_all on public.ingredients for all to authenticated
  using ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()))
  with check ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()));
create policy ingredient_tags_read on public.ingredient_dietary_tags for select to authenticated using (true);
create policy ingredient_tags_admin_all on public.ingredient_dietary_tags for all to authenticated
  using ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()))
  with check ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()));
create policy dietary_tags_admin_all on public.dietary_tags for all to authenticated
  using ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()))
  with check ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()));

-- Recipe owner/admin checks use SECURITY DEFINER helpers to avoid recursive RLS.
create or replace function public.recipe_is_visible(target_recipe_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (
  select 1 from public.recipes r
  where r.id = target_recipe_id and r.active and not r.is_deleted
    and ((r.recipe_source = 'official' and r.publication_status = 'published')
      or r.owner_user_id = (select auth.uid())
      or (select public.current_app_role()) = 'ADMIN')
    and (select public.current_account_is_active())
) $$;
create or replace function public.recipe_is_manageable(target_recipe_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (
  select 1 from public.recipes r where r.id = target_recipe_id
    and (r.owner_user_id = (select auth.uid()) or (select public.current_app_role()) = 'ADMIN')
    and (select public.current_account_is_active())
) $$;
revoke all on function public.recipe_is_visible(uuid), public.recipe_is_manageable(uuid) from public, anon;
grant execute on function public.recipe_is_visible(uuid), public.recipe_is_manageable(uuid) to authenticated;

create policy recipes_read_visible on public.recipes for select to authenticated
  using (active and not is_deleted and (recipe_source = 'official' and publication_status = 'published'
    or owner_user_id = (select auth.uid()) or (select public.current_app_role()) = 'ADMIN')
    and (select public.current_account_is_active()));
create policy recipes_owner_insert on public.recipes for insert to authenticated
  with check (recipe_source in ('user', 'ai') and owner_user_id = (select auth.uid())
    and publication_status = 'draft' and not featured and (select public.current_account_is_active()));
create policy recipes_owner_update on public.recipes for update to authenticated
  using (owner_user_id = (select auth.uid()) and recipe_source in ('user', 'ai') and (select public.current_account_is_active()))
  with check (owner_user_id = (select auth.uid()) and recipe_source in ('user', 'ai') and publication_status = 'draft' and not featured
    and (select public.current_account_is_active()));
create policy recipes_admin_all on public.recipes for all to authenticated
  using ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()))
  with check ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()));

create policy recipe_meal_shifts_read on public.recipe_meal_shifts for select to authenticated using ((select public.recipe_is_visible(recipe_id)));
create policy recipe_meal_shifts_manage on public.recipe_meal_shifts for all to authenticated using ((select public.recipe_is_manageable(recipe_id))) with check ((select public.recipe_is_manageable(recipe_id)));
create policy recipe_dietary_tags_read on public.recipe_dietary_tags for select to authenticated using ((select public.recipe_is_visible(recipe_id)));
create policy recipe_dietary_tags_manage on public.recipe_dietary_tags for all to authenticated using ((select public.recipe_is_manageable(recipe_id))) with check ((select public.recipe_is_manageable(recipe_id)));
create policy recipe_ingredients_read on public.recipe_ingredients for select to authenticated using ((select public.recipe_is_visible(recipe_id)));
create policy recipe_ingredients_manage on public.recipe_ingredients for all to authenticated using ((select public.recipe_is_manageable(recipe_id))) with check ((select public.recipe_is_manageable(recipe_id)));
create policy recipe_steps_read on public.recipe_steps for select to authenticated using ((select public.recipe_is_visible(recipe_id)));
create policy recipe_steps_manage on public.recipe_steps for all to authenticated using ((select public.recipe_is_manageable(recipe_id))) with check ((select public.recipe_is_manageable(recipe_id)));
create policy recipe_step_ingredients_read on public.recipe_step_ingredients for select to authenticated
  using (exists (select 1 from public.recipe_steps s where s.id = step_id and (select public.recipe_is_visible(s.recipe_id))));
create policy recipe_step_ingredients_manage on public.recipe_step_ingredients for all to authenticated
  using (exists (select 1 from public.recipe_steps s where s.id = step_id and (select public.recipe_is_manageable(s.recipe_id))))
  with check (exists (select 1 from public.recipe_steps s where s.id = step_id and (select public.recipe_is_manageable(s.recipe_id))));

-- Private owner-scoped data. Writes for transfer/finalization ledgers remain RPC-only.
create policy profiles_owner_all on public.profiles for all to authenticated
  using (user_id = (select auth.uid()) and (select public.current_account_is_active()))
  with check (user_id = (select auth.uid()) and (select public.current_account_is_active()));
create policy preferences_owner_all on public.user_dietary_preferences for all to authenticated
  using (user_id = (select auth.uid()) and (select public.current_account_is_active()))
  with check (user_id = (select auth.uid()) and (select public.current_account_is_active()));
create policy favorites_owner_all on public.favorite_recipes for all to authenticated
  using (user_id = (select auth.uid()) and (select public.current_account_is_active()))
  with check (user_id = (select auth.uid()) and (select public.current_account_is_active()));
create policy meal_plans_owner_all on public.meal_plans for all to authenticated
  using (owner_user_id = (select auth.uid()) and (select public.current_account_is_active()))
  with check (owner_user_id = (select auth.uid()) and (select public.current_account_is_active()));
create policy meal_slots_owner_all on public.meal_plan_slots for all to authenticated
  using (exists (select 1 from public.meal_plans p where p.id = plan_id and p.owner_user_id = (select auth.uid()) and (select public.current_account_is_active())))
  with check (exists (select 1 from public.meal_plans p where p.id = plan_id and p.owner_user_id = (select auth.uid()) and (select public.current_account_is_active())));
create policy shopping_lists_owner_all on public.shopping_lists for all to authenticated
  using (owner_user_id = (select auth.uid()) and (select public.current_account_is_active()))
  with check (owner_user_id = (select auth.uid()) and (select public.current_account_is_active()));
create policy shopping_items_owner_all on public.shopping_items for all to authenticated
  using (exists (select 1 from public.shopping_lists l where l.id = list_id and l.owner_user_id = (select auth.uid()) and (select public.current_account_is_active())))
  with check (exists (select 1 from public.shopping_lists l where l.id = list_id and l.owner_user_id = (select auth.uid()) and (select public.current_account_is_active())));
create policy shopping_sources_owner_all on public.shopping_item_sources for all to authenticated
  using (exists (select 1 from public.shopping_items i join public.shopping_lists l on l.id = i.list_id where i.id = shopping_item_id and l.owner_user_id = (select auth.uid()) and (select public.current_account_is_active())))
  with check (exists (select 1 from public.shopping_items i join public.shopping_lists l on l.id = i.list_id where i.id = shopping_item_id and l.owner_user_id = (select auth.uid()) and (select public.current_account_is_active())));

create policy pantry_receipts_owner_read on public.pantry_receipts for select to authenticated using (owner_user_id = (select auth.uid()) and (select public.current_account_is_active()));
create policy pantry_receipt_items_owner_read on public.pantry_receipt_items for select to authenticated
  using (exists (select 1 from public.pantry_receipts r where r.id = receipt_id and r.owner_user_id = (select auth.uid()) and (select public.current_account_is_active())));
create policy cooking_sessions_owner_all on public.cooking_sessions for all to authenticated
  using (owner_user_id = (select auth.uid()) and (select public.current_account_is_active()))
  with check (owner_user_id = (select auth.uid()) and (select public.current_account_is_active()));
create policy cooking_steps_owner_all on public.cooking_session_steps for all to authenticated
  using (exists (select 1 from public.cooking_sessions s where s.id = session_id and s.owner_user_id = (select auth.uid()) and (select public.current_account_is_active())))
  with check (exists (select 1 from public.cooking_sessions s where s.id = session_id and s.owner_user_id = (select auth.uid()) and (select public.current_account_is_active())));
create policy cooking_events_owner_read on public.cooking_events for select to authenticated using (owner_user_id = (select auth.uid()) and (select public.current_account_is_active()));
create policy cooking_event_ingredients_owner_read on public.cooking_event_ingredients for select to authenticated
  using (exists (select 1 from public.cooking_events e where e.id = event_id and e.owner_user_id = (select auth.uid()) and (select public.current_account_is_active())));
create policy recipe_generation_owner_read on public.recipe_generation_requests for select to authenticated using (owner_user_id = (select auth.uid()) and (select public.current_account_is_active()));
create policy receipt_requests_owner_read on public.receipt_recognition_requests for select to authenticated using (owner_user_id = (select auth.uid()) and (select public.current_account_is_active()));

-- The new model remains read-only to clients until validated write RPCs and
-- backfill are deployed. Existing application repositories keep using legacy data.
do $$
declare table_name text;
begin
  foreach table_name in array array[
    'dietary_tags','nutrition_config','profiles','user_dietary_preferences',
    'categories','units','ingredients','ingredient_dietary_tags','recipes',
    'recipe_meal_shifts','recipe_dietary_tags','recipe_ingredients','recipe_steps',
    'recipe_step_ingredients','favorite_recipes','meal_plans','meal_plan_slots',
    'pantry_receipts','shopping_lists','shopping_items','shopping_item_sources',
    'pantry_receipt_items','cooking_sessions','cooking_session_steps','cooking_events',
    'cooking_event_ingredients','recipe_generation_requests','receipt_recognition_requests'
  ] loop
    execute format('create policy active_accounts_only on public.%I as restrictive for all to authenticated using ((select public.current_account_is_active())) with check ((select public.current_account_is_active()))', table_name);
  end loop;
end;
$$;


-- Staged from 202610300003_personal_write_rpcs.sql inside the rehearsal transaction.
-- A complete profile + preference save uses optimistic concurrency.
alter table public.profiles add column version bigint not null default 1 check (version > 0);

-- Authorization point: after the account/ban locks and a fresh active check.
-- Shared advisory lock orders writes with existing admin role/status RPCs,
-- while allowing different accounts to write concurrently. Auth ban updates
-- conflict with FOR SHARE. Locks stay held until the calling transaction ends.
create function public.lock_my_relational_account()
returns uuid language plpgsql volatile security definer set search_path = ''
as $$
declare actor uuid := auth.uid();
begin
  if actor is null then
    raise exception 'Se requiere una sesión activa.' using errcode = '42501';
  end if;
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La operación requiere aislamiento READ COMMITTED.' using errcode = '25000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(74539, 1);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.personal:' || actor::text, 0));
  perform 1 from auth.users where id = actor for share;
  if not found then raise exception 'Se requiere una sesión activa.' using errcode = '42501'; end if;
  perform 1 from public.account_status where user_id = actor for share;
  if not public.current_account_is_active() then
    raise exception 'La cuenta no está activa.' using errcode = '42501';
  end if;
  return actor;
end;
$$;
revoke all on function public.lock_my_relational_account() from public, anon, authenticated;

-- Full snapshot, not a patch: omitted optional fields become NULL. Version 0
-- means create only; an existing row requires its exact current version.
-- Preferences are saved in the same transaction and use stable tag_key values.
-- Email remains in Auth and is deliberately not a writable profile field.
create function public.save_my_profile(p_profile jsonb, p_preference_keys text[], p_expected_version bigint)
returns public.profiles language plpgsql volatile security definer set search_path = ''
as $$
declare
  actor uuid; saved public.profiles; existing_version bigint;
  field text; tag_ids uuid[]; birth date;
begin
  actor := public.lock_my_relational_account();
  if jsonb_typeof(p_profile) is distinct from 'object' or p_expected_version is null or p_expected_version < 0
    or p_preference_keys is null or cardinality(p_preference_keys) > 50
    or coalesce(array_ndims(p_preference_keys), 1) <> 1 then
    raise exception 'Formato de perfil o preferencias inválido.' using errcode = '22023';
  end if;
  if exists(select 1 from jsonb_object_keys(p_profile) k where k not in (
    'display_name','birth_date','weight_kg','height_cm','metabolic_sex','activity_level','goal')) then
    raise exception 'El perfil contiene campos no admitidos.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_profile->'display_name') is distinct from 'string'
    or length(trim(p_profile->>'display_name')) not between 1 and 120 then
    raise exception 'El nombre de perfil es obligatorio y admite hasta 120 caracteres.' using errcode = '22023';
  end if;
  foreach field in array array['birth_date','metabolic_sex','activity_level','goal'] loop
    if p_profile ? field and jsonb_typeof(p_profile->field) not in ('null','string') then
      raise exception 'Tipo de campo de perfil inválido.' using errcode = '22023';
    end if;
  end loop;
  foreach field in array array['weight_kg','height_cm'] loop
    if p_profile ? field and jsonb_typeof(p_profile->field) not in ('null','number') then
      raise exception 'Tipo de medida de perfil inválido.' using errcode = '22023';
    end if;
  end loop;
  -- Validate before numeric(6,2) rounds: values outside the domain must not
  -- become valid merely because the column rounds them toward a boundary.
  if (p_profile->>'weight_kg')::numeric not between 30 and 300
    or (p_profile->>'height_cm')::numeric not between 100 and 250 then
    raise exception 'Las medidas del perfil están fuera del rango admitido.' using errcode = '22023';
  end if;
  if p_profile->>'birth_date' is not null then
    if (p_profile->>'birth_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'Fecha de nacimiento inválida.' using errcode = '22023';
    end if;
    birth := (p_profile->>'birth_date')::date;
    if birth > current_date then raise exception 'Fecha de nacimiento inválida.' using errcode = '22023'; end if;
  end if;
  if exists(select 1 from unnest(p_preference_keys) k where k is null or length(k) not between 2 and 50)
    or (select count(distinct k) from unnest(p_preference_keys) k) <> cardinality(p_preference_keys) then
    raise exception 'Preferencias inválidas o repetidas.' using errcode = '22023';
  end if;
  -- Lock definitions so a tag cannot be deactivated midway through this save.
  select coalesce(array_agg(id), '{}'::uuid[]) into tag_ids from (
    select id from public.dietary_tags where tag_key = any(p_preference_keys) and active order by id for share
  ) tags;
  if cardinality(tag_ids) <> cardinality(p_preference_keys) then
    raise exception 'Hay preferencias no disponibles.' using errcode = '22023';
  end if;
  select version into existing_version from public.profiles where user_id = actor for update;
  if coalesce(existing_version, 0) <> p_expected_version then
    raise exception 'El perfil cambió en otra sesión. Recargalo antes de guardar.' using errcode = '40001';
  end if;
  insert into public.profiles(user_id,display_name,birth_date,weight_kg,height_cm,metabolic_sex,activity_level,goal,version,updated_at)
  values(actor,trim(p_profile->>'display_name'),birth,(p_profile->>'weight_kg')::numeric,
    (p_profile->>'height_cm')::numeric,p_profile->>'metabolic_sex',p_profile->>'activity_level',p_profile->>'goal',1,clock_timestamp())
  on conflict (user_id) do update set display_name=excluded.display_name,birth_date=excluded.birth_date,
    weight_kg=excluded.weight_kg,height_cm=excluded.height_cm,metabolic_sex=excluded.metabolic_sex,
    activity_level=excluded.activity_level,goal=excluded.goal,version=profiles.version+1,updated_at=excluded.updated_at
  returning * into saved;
  delete from public.user_dietary_preferences where user_id=actor;
  insert into public.user_dietary_preferences(user_id,dietary_tag_id) select actor,unnest(tag_ids);
  return saved;
exception
  when data_exception or check_violation or not_null_violation then
    -- Suppress database DETAIL, which otherwise can include personal values.
    raise exception 'Los datos del perfil no son válidos.' using errcode = '22023';
end;
$$;
revoke all on function public.save_my_profile(jsonb,text[],bigint) from public, anon;
grant execute on function public.save_my_profile(jsonb,text[],bigint) to authenticated;

-- Set desired state instead of toggling: retrying a request cannot reverse it.
create function public.set_my_favorite(p_recipe_id uuid, p_is_favorite boolean)
returns boolean language plpgsql volatile security definer set search_path = ''
as $$
declare actor uuid; recipe public.recipes;
begin
  actor := public.lock_my_relational_account();
  if p_recipe_id is null or p_is_favorite is null then
    raise exception 'La receta y el estado de favorito son obligatorios.' using errcode = '22023';
  end if;
  if not p_is_favorite then
    delete from public.favorite_recipes where user_id=actor and recipe_id=p_recipe_id;
    return false;
  end if;
  select * into recipe from public.recipes where id=p_recipe_id for share;
  if not found or not recipe.active or recipe.is_deleted or (
    recipe.owner_user_id=actor or (recipe.recipe_source='official' and recipe.publication_status='published')
  ) is not true then
    raise exception 'La receta no está disponible para favoritos.' using errcode = '42501';
  end if;
  insert into public.favorite_recipes(user_id,recipe_id) values(actor,p_recipe_id) on conflict do nothing;
  return true;
end;
$$;
revoke all on function public.set_my_favorite(uuid,boolean) from public, anon;
grant execute on function public.set_my_favorite(uuid,boolean) to authenticated;

-- Table privileges remain SELECT-only; clients write only through these RPCs.

-- Staged from 202610300004_planning_write_rpcs.sql inside the rehearsal transaction.
alter table public.meal_plans add column version bigint not null default 1 check (version > 0);

-- Replace one complete week, preserving the plan ID and its shopping references.
-- Slot IDs are server-generated; date/shift/position identify a slot in a save.
create function public.save_my_meal_plan(p_week_start date, p_slots jsonb, p_expected_version bigint)
returns public.meal_plans language plpgsql volatile security definer set search_path = ''
as $$
declare
  actor uuid; slot jsonb; field text; recipe public.recipes;
  saved public.meal_plans; existing_version bigint; matched bigint := 0;
begin
  actor := public.lock_my_relational_account();
  if p_week_start is null or not isfinite(p_week_start) or extract(isodow from p_week_start) <> 1
    or p_expected_version is null or p_expected_version < 0
    or jsonb_typeof(p_slots) is distinct from 'array' then
    raise exception 'La semana, la versión o la planificación no son válidas.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_slots) > 140 then
    raise exception 'La planificación admite hasta 140 entradas por semana.' using errcode = '22023';
  end if;
  for slot in select value from jsonb_array_elements(p_slots) loop
    if jsonb_typeof(slot) is distinct from 'object' then
      raise exception 'Formato de entrada de planificación inválido.' using errcode = '22023';
    end if;
    if exists(select 1 from jsonb_object_keys(slot) k where k not in
      ('meal_date','meal_shift','recipe_id','portions','position')) then
      raise exception 'La planificación contiene campos no admitidos.' using errcode = '22023';
    end if;
    foreach field in array array['meal_date','meal_shift','recipe_id'] loop
      if jsonb_typeof(slot->field) is distinct from 'string' then
        raise exception 'Falta una fecha, turno o receta válida.' using errcode = '22023';
      end if;
    end loop;
    if (slot->>'meal_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or (slot->>'meal_date')::date < p_week_start or (slot->>'meal_date')::date >= p_week_start + 7
      or slot->>'meal_shift' not in ('breakfast','lunch','snack','dinner') then
      raise exception 'La fecha o el turno no corresponden a esta semana.' using errcode = '22023';
    end if;
    if jsonb_typeof(slot->'portions') is distinct from 'number' then
      raise exception 'Las porciones deben ser un número entero.' using errcode = '22023';
    end if;
    if (slot->>'portions')::numeric not between 1 and 20
      or trunc((slot->>'portions')::numeric) <> (slot->>'portions')::numeric then
      raise exception 'Las porciones deben estar entre 1 y 20.' using errcode = '22023';
    end if;
    if slot ? 'position' then
      if jsonb_typeof(slot->'position') is distinct from 'number' then
        raise exception 'La posición debe ser un número entero.' using errcode = '22023';
      end if;
      if (slot->>'position')::numeric not between 1 and 100
        or trunc((slot->>'position')::numeric) <> (slot->>'position')::numeric then
        raise exception 'La posición debe estar entre 1 y 100.' using errcode = '22023';
      end if;
    end if;
    -- Validate the UUID before passing it to the lock/visibility query.
    perform (slot->>'recipe_id')::uuid;
  end loop;
  if exists(select 1 from jsonb_array_elements(p_slots) s
    group by s->>'meal_date',s->>'meal_shift',coalesce((s->>'position')::numeric::integer,1) having count(*) > 1) then
    raise exception 'Hay posiciones repetidas en la planificación.' using errcode = '22023';
  end if;

  -- Stable lock order; validate the locked rows, so publication/archival changes
  -- cannot race between validation and the final slot inserts.
  for recipe in select r.* from public.recipes r
    where r.id in (select (s->>'recipe_id')::uuid from jsonb_array_elements(p_slots) s)
    order by r.id for share
  loop
    if not recipe.active or recipe.is_deleted or (
      recipe.owner_user_id = actor or (recipe.recipe_source='official' and recipe.publication_status='published')
    ) is not true then
      raise exception 'Hay recetas no disponibles para esta cuenta.' using errcode = '42501';
    end if;
    matched := matched + 1;
  end loop;
  if matched <> (select count(distinct (s->>'recipe_id')::uuid) from jsonb_array_elements(p_slots) s) then
    raise exception 'Hay recetas no disponibles para esta cuenta.' using errcode = '42501';
  end if;
  select version into existing_version from public.meal_plans
    where owner_user_id=actor and week_start=p_week_start for update;
  if coalesce(existing_version,0) <> p_expected_version then
    raise exception 'La planificación cambió en otra sesión. Recargala antes de guardar.' using errcode = '40001';
  end if;
  insert into public.meal_plans(owner_user_id,week_start,updated_at)
    values(actor,p_week_start,clock_timestamp())
  on conflict (owner_user_id,week_start) do update set
    version=meal_plans.version+1,updated_at=excluded.updated_at
  returning * into saved;
  delete from public.meal_plan_slots where plan_id=saved.id;
  insert into public.meal_plan_slots(plan_id,meal_date,meal_shift,recipe_id,portions,position)
    select saved.id,(s->>'meal_date')::date,s->>'meal_shift',(s->>'recipe_id')::uuid,
      (s->>'portions')::numeric::integer,coalesce((s->>'position')::numeric::integer,1)
    from jsonb_array_elements(p_slots) s;
  return saved;
exception
  when data_exception or integrity_constraint_violation then
    raise exception 'Los datos de planificación no son válidos.' using errcode = '22023';
end;
$$;
revoke all on function public.save_my_meal_plan(date,jsonb,bigint) from public, anon;
grant execute on function public.save_my_meal_plan(date,jsonb,bigint) to authenticated;


-- Staged from 202610300005_shopping_write_rpcs.sql inside the rehearsal transaction.
alter table public.shopping_lists add column version bigint not null default 1 check (version > 0);

-- All shopping mutations share the account authorization/serialization protocol.
-- Clients cannot call this helper or directly mutate the underlying tables.
create function public.lock_my_active_shopping_list(p_list_id uuid, p_expected_version bigint)
returns public.shopping_lists language plpgsql volatile security definer set search_path = ''
as $$
declare actor uuid; selected public.shopping_lists;
begin
  actor := public.lock_my_relational_account();
  if p_list_id is null or p_expected_version is null or p_expected_version < 1 then
    raise exception 'Lista o versión inválida.' using errcode = '22023';
  end if;
  select * into selected from public.shopping_lists
    where id=p_list_id and owner_user_id=actor and status='active' for update;
  if not found then
    raise exception 'La lista no está disponible para esta cuenta.' using errcode = '42501';
  end if;
  if selected.version <> p_expected_version then
    raise exception 'La lista cambió en otra sesión. Recargala antes de guardar.' using errcode = '40001';
  end if;
  return selected;
end;
$$;
revoke all on function public.lock_my_active_shopping_list(uuid,bigint) from public, anon, authenticated;

-- Stable client UUID is the creation idempotency key. Retrying an old request
-- returns that list, including its archived state; it never reactivates it.
create function public.create_my_shopping_list(p_list_id uuid, p_name text, p_plan_id uuid default null)
returns public.shopping_lists language plpgsql volatile security definer set search_path = ''
as $$
declare actor uuid; selected public.shopping_lists;
begin
  actor := public.lock_my_relational_account();
  if p_list_id is null or p_name is null or length(trim(p_name)) not between 1 and 120 then
    raise exception 'El identificador y el nombre de lista son obligatorios.' using errcode = '22023';
  end if;
  select * into selected from public.shopping_lists where id=p_list_id for update;
  if found then
    if selected.owner_user_id<>actor then
      raise exception 'La lista no está disponible para esta cuenta.' using errcode = '42501';
    end if;
    if selected.name is distinct from trim(p_name) or selected.plan_id is distinct from p_plan_id then
      raise exception 'El identificador de lista ya corresponde a otra solicitud.' using errcode = '22023';
    end if;
    return selected;
  end if;
  if p_plan_id is not null then
    perform 1 from public.meal_plans where id=p_plan_id and owner_user_id=actor for share;
    if not found then raise exception 'El plan no está disponible para esta cuenta.' using errcode = '42501'; end if;
  end if;
  update public.shopping_lists set status='archived',version=version+1,updated_at=clock_timestamp()
    where owner_user_id=actor and status='active';
  insert into public.shopping_lists(id,owner_user_id,plan_id,name)
    values(p_list_id,actor,p_plan_id,trim(p_name)) returning * into selected;
  return selected;
exception when unique_violation or foreign_key_violation or check_violation or not_null_violation or data_exception then
  raise exception 'No se pudo crear la lista con esos datos.' using errcode = '22023';
end;
$$;
revoke all on function public.create_my_shopping_list(uuid,text,uuid) from public, anon;
grant execute on function public.create_my_shopping_list(uuid,text,uuid) to authenticated;

-- Item and all provenance links are one atomic replacement. Known catalog
-- ingredients derive their name/category snapshots on the server. Free-text
-- manual entries keep their own labels and have no inferred ingredient link.
-- checked defaults false; note defaults empty. Ownership, transfer state and
-- timestamps are server-controlled and are not accepted in this JSON contract.
create function public.put_my_shopping_item(p_list_id uuid, p_item jsonb, p_expected_version bigint)
returns public.shopping_lists language plpgsql volatile security definer set search_path = ''
as $$
declare
  actor uuid; selected public.shopping_lists; previous public.shopping_items;
  item_id uuid; ingredient_id uuid; unit_id uuid; qty numeric; checked_value boolean;
  item_name text; category_name text; item_note text; primary_source text;
  links jsonb; link jsonb; link_source text; link_recipe uuid; link_plan uuid;
  ingredient public.ingredients; unit public.units; base_unit public.units;
  category public.categories; recipe public.recipes; lock_id uuid;
  unit_root public.units; ingredient_root public.units; changed bigint;
begin
  selected := public.lock_my_active_shopping_list(p_list_id,p_expected_version);
  actor := selected.owner_user_id;
  if jsonb_typeof(p_item) is distinct from 'object' or exists(
    select 1 from jsonb_object_keys(p_item) k where k not in (
      'id','ingredient_id','name_snapshot','category_snapshot','quantity','unit_id','note','checked','source','sources')) then
    raise exception 'Formato de artículo inválido.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_item->'id') is distinct from 'string'
    or jsonb_typeof(p_item->'unit_id') is distinct from 'string'
    or jsonb_typeof(p_item->'quantity') is distinct from 'number'
    or jsonb_typeof(p_item->'source') is distinct from 'string'
    or jsonb_typeof(p_item->'sources') is distinct from 'array' then
    raise exception 'Faltan campos del artículo o sus tipos son inválidos.' using errcode = '22023';
  end if;
  if p_item ? 'ingredient_id' and jsonb_typeof(p_item->'ingredient_id') not in ('null','string')
    or p_item ? 'checked' and jsonb_typeof(p_item->'checked') is distinct from 'boolean'
    or p_item ? 'note' and jsonb_typeof(p_item->'note') is distinct from 'string'
    or p_item ? 'name_snapshot' and jsonb_typeof(p_item->'name_snapshot') is distinct from 'string'
    or p_item ? 'category_snapshot' and jsonb_typeof(p_item->'category_snapshot') is distinct from 'string' then
    raise exception 'Tipo de campo de artículo inválido.' using errcode = '22023';
  end if;
  item_id := (p_item->>'id')::uuid;
  ingredient_id := (p_item->>'ingredient_id')::uuid;
  unit_id := (p_item->>'unit_id')::uuid;
  qty := (p_item->>'quantity')::numeric;
  checked_value := coalesce((p_item->>'checked')::boolean,false);
  item_note := coalesce(p_item->>'note','');
  primary_source := p_item->>'source';
  links := p_item->'sources';
  if qty<=0 or qty>1000000 or round(qty,4)<=0 or length(item_note)>1000
    or primary_source not in ('manual','recipe','plan','favorites','pantry')
    or jsonb_array_length(links) not between 1 and 20
    or p_item ? 'name_snapshot' and length(trim(p_item->>'name_snapshot')) not between 1 and 120
    or p_item ? 'category_snapshot' and length(trim(p_item->>'category_snapshot')) not between 1 and 100 then
    raise exception 'Los datos del artículo están fuera del rango admitido.' using errcode = '22023';
  end if;
  -- Item identity spans accounts and survives removal in receipt history.
  -- Transfer RPCs must take this same lock before creating that history.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.shopping-item:' || item_id::text,0));
  select * into previous from public.shopping_items where id=item_id for update;
  if found and previous.list_id<>p_list_id then
    raise exception 'El artículo no está disponible en esta lista.' using errcode = '42501';
  end if;
  if previous.transferred_at is not null or exists(
    select 1 from public.pantry_receipt_items r where r.original_shopping_item_id=item_id) then
    raise exception 'No se puede modificar o reutilizar un artículo ya transferido.' using errcode = '22023';
  end if;
  -- Catalog locks protect the validation until commit. Lock units in ID order.
  if ingredient_id is not null then
    select * into ingredient from public.ingredients i where i.id=ingredient_id and i.active and not i.is_deleted for share;
    if not found then raise exception 'El ingrediente no está disponible.' using errcode = '22023'; end if;
  end if;
  perform 1 from public.units u where u.id=unit_id or u.id=ingredient.base_unit_id order by u.id for share;
  select * into unit from public.units u where u.id=unit_id;
  if not found or not unit.active or unit.is_deleted then
    raise exception 'La unidad no está disponible.' using errcode = '22023';
  end if;
  if ingredient_id is not null then
    select * into base_unit from public.units u where u.id=ingredient.base_unit_id;
  end if;
  perform 1 from public.units u where u.id=coalesce(unit.base_unit_id,unit.id)
    or u.id=coalesce(base_unit.base_unit_id,base_unit.id) order by u.id for share;
  select * into unit_root from public.units u where u.id=coalesce(unit.base_unit_id,unit.id);
  if not found or not unit_root.active or unit_root.is_deleted then
    raise exception 'La unidad base no está disponible.' using errcode = '22023';
  end if;
  if ingredient_id is not null then
    select * into ingredient_root from public.units u where u.id=coalesce(base_unit.base_unit_id,base_unit.id);
    select * into category from public.categories c where c.id=ingredient.category_id and c.active and not c.is_deleted for share;
    if not found or not base_unit.active or base_unit.is_deleted or base_unit.dimension<>unit.dimension
      or ingredient_root.id is distinct from unit_root.id or not ingredient_root.active or ingredient_root.is_deleted then
      raise exception 'Categoría o unidad incompatible con el ingrediente.' using errcode = '22023';
    end if;
    item_name := ingredient.name; category_name := category.name;
  else
    item_name := trim(p_item->>'name_snapshot');
    category_name := coalesce(trim(p_item->>'category_snapshot'),'Otros');
    if item_name is null then raise exception 'El artículo manual necesita un nombre.' using errcode = '22023'; end if;
  end if;
  -- Validate every provenance object before touching the current item/links.
  for link in select value from jsonb_array_elements(links) loop
    if jsonb_typeof(link) is distinct from 'object' or exists(
      select 1 from jsonb_object_keys(link) k where k not in ('source','recipe_id','plan_id')) then
      raise exception 'Origen de compra inválido.' using errcode = '22023';
    end if;
    link_source := link->>'source';
    if jsonb_typeof(link->'source') is distinct from 'string'
      or link_source not in ('manual','recipe','plan','favorites','pantry')
      or link ? 'recipe_id' and jsonb_typeof(link->'recipe_id') not in ('null','string')
      or link ? 'plan_id' and jsonb_typeof(link->'plan_id') not in ('null','string') then
      raise exception 'Tipo de origen de compra inválido.' using errcode = '22023';
    end if;
    link_recipe := (link->>'recipe_id')::uuid; link_plan := (link->>'plan_id')::uuid;
    if (link_source='recipe') is distinct from (link_recipe is not null)
      or (link_source='plan') is distinct from (link_plan is not null) then
      raise exception 'Las referencias no corresponden al origen de compra.' using errcode = '22023';
    end if;
  end loop;
  if not exists(select 1 from jsonb_array_elements(links) l where l->>'source'=primary_source)
    or (select count(distinct jsonb_build_array(l->>'source',(l->>'recipe_id')::uuid,(l->>'plan_id')::uuid)) from jsonb_array_elements(links) l)<>jsonb_array_length(links) then
    raise exception 'Los orígenes están repetidos o falta el origen principal.' using errcode = '22023';
  end if;
  for lock_id in select distinct (l->>'recipe_id')::uuid from jsonb_array_elements(links) l where l->>'recipe_id' is not null order by 1 loop
    select * into recipe from public.recipes r where r.id=lock_id for share;
    if not found or not recipe.active or recipe.is_deleted or (
      recipe.owner_user_id=actor or (recipe.recipe_source='official' and recipe.publication_status='published')) is not true then
      raise exception 'La receta de origen no está disponible para esta cuenta.' using errcode = '42501';
    end if;
  end loop;
  for lock_id in select distinct (l->>'plan_id')::uuid from jsonb_array_elements(links) l where l->>'plan_id' is not null order by 1 loop
    perform 1 from public.meal_plans p where p.id=lock_id and p.owner_user_id=actor for share;
    if not found then raise exception 'El plan de origen no está disponible para esta cuenta.' using errcode = '42501'; end if;
  end loop;
  insert into public.shopping_items(id,list_id,ingredient_id,name_snapshot,category_snapshot,quantity,unit_id,note,checked,source,updated_at)
    values(item_id,p_list_id,ingredient_id,item_name,category_name,qty,unit_id,item_note,checked_value,primary_source,clock_timestamp())
  on conflict(id) do update set ingredient_id=excluded.ingredient_id,name_snapshot=excluded.name_snapshot,
    category_snapshot=excluded.category_snapshot,quantity=excluded.quantity,unit_id=excluded.unit_id,
    note=excluded.note,checked=excluded.checked,source=excluded.source,updated_at=excluded.updated_at
    where shopping_items.list_id=excluded.list_id and shopping_items.transferred_at is null;
  get diagnostics changed = row_count;
  -- Existence checks cannot see another account's uncommitted insertion. This
  -- predicate also protects the conflict path after waiting for that insertion.
  if changed<>1 then raise exception 'El artículo no está disponible en esta lista.' using errcode = '42501'; end if;
  delete from public.shopping_item_sources s where s.shopping_item_id=item_id;
  insert into public.shopping_item_sources(shopping_item_id,source,recipe_id,plan_id)
    select item_id,l->>'source',(l->>'recipe_id')::uuid,(l->>'plan_id')::uuid from jsonb_array_elements(links) l;
  update public.shopping_lists set version=version+1,updated_at=clock_timestamp() where id=p_list_id returning * into selected;
  return selected;
exception when data_exception or check_violation or not_null_violation or unique_violation or foreign_key_violation then
  raise exception 'Los datos del artículo de compra no son válidos.' using errcode = '22023';
end;
$$;
revoke all on function public.put_my_shopping_item(uuid,jsonb,bigint) from public, anon;
grant execute on function public.put_my_shopping_item(uuid,jsonb,bigint) to authenticated;

create function public.set_my_shopping_checked(p_list_id uuid, p_item_ids uuid[], p_checked boolean, p_expected_version bigint)
returns public.shopping_lists language plpgsql volatile security definer set search_path = ''
as $$
declare selected public.shopping_lists; changed bigint; item_id uuid;
begin
  selected := public.lock_my_active_shopping_list(p_list_id,p_expected_version);
  if p_item_ids is null or p_checked is null or cardinality(p_item_ids)>1000 or coalesce(array_ndims(p_item_ids),1)<>1
    or exists(select 1 from unnest(p_item_ids) i where i is null)
    or (select count(distinct i) from unnest(p_item_ids) i)<>cardinality(p_item_ids) then
    raise exception 'Selección de artículos inválida.' using errcode = '22023';
  end if;
  for item_id in select i from unnest(p_item_ids) i order by i loop
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.shopping-item:' || item_id::text,0));
  end loop;
  if (select count(*) from public.shopping_items where list_id=p_list_id and id=any(p_item_ids))<>cardinality(p_item_ids) then
    raise exception 'Hay artículos que no están disponibles en esta lista.' using errcode = '42501';
  end if;
  if exists(select 1 from public.shopping_items where list_id=p_list_id and id=any(p_item_ids)
    and transferred_at is not null and checked is distinct from p_checked) then
    raise exception 'No se puede cambiar el estado de un artículo transferido.' using errcode = '22023';
  end if;
  update public.shopping_items set checked=p_checked,updated_at=clock_timestamp()
    where list_id=p_list_id and id=any(p_item_ids) and checked is distinct from p_checked;
  get diagnostics changed = row_count;
  if changed>0 then
    update public.shopping_lists set version=version+1,updated_at=clock_timestamp() where id=p_list_id returning * into selected;
  end if;
  return selected;
end;
$$;
revoke all on function public.set_my_shopping_checked(uuid,uuid[],boolean,bigint) from public, anon;
grant execute on function public.set_my_shopping_checked(uuid,uuid[],boolean,bigint) to authenticated;

-- Removal may include transferred rows: receipt snapshots and the unique
-- original_shopping_item_id remain, and the nullable item FK becomes NULL.
create function public.remove_my_shopping_item(p_list_id uuid, p_item_id uuid, p_expected_version bigint)
returns public.shopping_lists language plpgsql volatile security definer set search_path = ''
as $$
declare selected public.shopping_lists; changed bigint;
begin
  selected := public.lock_my_active_shopping_list(p_list_id,p_expected_version);
  if p_item_id is null then raise exception 'Falta el artículo.' using errcode = '22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.shopping-item:' || p_item_id::text,0));
  delete from public.shopping_items where list_id=p_list_id and id=p_item_id;
  get diagnostics changed = row_count;
  if changed>0 then
    update public.shopping_lists set version=version+1,updated_at=clock_timestamp() where id=p_list_id returning * into selected;
  end if;
  return selected;
end;
$$;
revoke all on function public.remove_my_shopping_item(uuid,uuid,bigint) from public, anon;
grant execute on function public.remove_my_shopping_item(uuid,uuid,bigint) to authenticated;


-- Staged from 202610300006_shopping_transfer_rpcs.sql inside the rehearsal transaction.
-- The request is preserved independently of nullable historical foreign keys.
alter table public.pantry_receipts
  add column shopping_list_id uuid references public.shopping_lists(id) on delete set null,
  add column requested_list_id uuid,
  add column requested_item_ids uuid[],
  add column resulting_list_version bigint;
alter table public.pantry_receipt_items
  add column ingredient_id_snapshot uuid,
  add column name_snapshot text,
  add column category_snapshot text,
  add column purchased_quantity numeric(14,4),
  add column purchased_unit_id_snapshot uuid,
  add column purchased_unit_abbreviation_snapshot text,
  add column pantry_unit_id_snapshot uuid;

-- Existing inventory has three decimal places. Retain it without silently
-- rounding four-decimal shopping amounts when converting into stored units.
alter table public.pantry_items alter column quantity type numeric(14,4),
  alter column minimum type numeric(14,4);

create function public.transfer_my_shopping_to_pantry(
  p_list_id uuid, p_item_ids uuid[], p_idempotency_key uuid, p_expected_version bigint)
returns public.pantry_receipts language plpgsql volatile security definer set search_path = ''
as $$
declare
  actor uuid; selected public.shopping_lists; receipt public.pantry_receipts;
  ids uuid[]; item_id uuid; item public.shopping_items; ingredient public.ingredients;
  source_unit public.units; target_unit public.units; ingredient_unit public.units;
  category public.categories; stock public.pantry_items; candidate public.pantry_items;
  addition numeric; target_id uuid; target_abbreviation text; item_name text; item_category text;
begin
  actor := public.lock_my_relational_account();
  if p_list_id is null or p_idempotency_key is null or p_expected_version is null or p_expected_version<1
    or p_item_ids is null or cardinality(p_item_ids) not between 1 and 1000
    or coalesce(array_ndims(p_item_ids),1)<>1
    or exists(select 1 from unnest(p_item_ids) i where i is null)
    or (select count(distinct i) from unnest(p_item_ids) i)<>cardinality(p_item_ids) then
    raise exception 'Solicitud de transferencia inválida.' using errcode='22023';
  end if;
  select array_agg(i order by i) into ids from unnest(p_item_ids) i;
  -- A completed retry works after list archival/deletion of transferred items.
  select * into receipt from public.pantry_receipts
    where owner_user_id=actor and idempotency_key=p_idempotency_key;
  if found then
    if receipt.requested_list_id is distinct from p_list_id or receipt.requested_item_ids is distinct from ids then
      raise exception 'La clave de transferencia ya corresponde a otra solicitud.' using errcode='22023';
    end if;
    return receipt;
  end if;
  select * into selected from public.shopping_lists where id=p_list_id and owner_user_id=actor and status='active' for update;
  if not found then raise exception 'La lista no está disponible para esta cuenta.' using errcode='42501'; end if;
  if selected.version<>p_expected_version then
    raise exception 'La lista cambió en otra sesión. Recargala antes de transferir.' using errcode='40001';
  end if;
  foreach item_id in array ids loop
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.shopping-item:' || item_id::text,0));
  end loop;
  if (select count(*) from public.shopping_items where list_id=p_list_id and id=any(ids))<>cardinality(ids) then
    raise exception 'Hay artículos que no están disponibles en esta lista.' using errcode='42501';
  end if;
  -- Catalog rows and conversion roots are locked in a single stable order.
  perform 1 from public.ingredients where id in (
    select ingredient_id from public.shopping_items where id=any(ids)) order by id for share;
  perform 1 from public.units order by id for share;
  perform 1 from public.categories order by id for share;
  insert into public.pantry_receipts(owner_user_id,idempotency_key,shopping_list_id,requested_list_id,requested_item_ids,resulting_list_version)
    values(actor,p_idempotency_key,p_list_id,p_list_id,ids,selected.version+1) returning * into receipt;
  foreach item_id in array ids loop
    select * into item from public.shopping_items where id=item_id and list_id=p_list_id for update;
    if not item.checked or item.transferred_at is not null or exists(
      select 1 from public.pantry_receipt_items where original_shopping_item_id=item_id) then
      raise exception 'El artículo no está comprado o ya fue transferido.' using errcode='22023';
    end if;
    select * into source_unit from public.units where id=item.unit_id and active and not is_deleted;
    if not found or not exists(select 1 from public.units where id=coalesce(source_unit.base_unit_id,source_unit.id) and active and not is_deleted) then
      raise exception 'La unidad no está disponible.' using errcode='22023';
    end if;
    if item.ingredient_id is not null then
      select * into ingredient from public.ingredients where id=item.ingredient_id and active and not is_deleted;
      if not found then raise exception 'El ingrediente no está disponible.' using errcode='22023'; end if;
      select * into ingredient_unit from public.units where id=ingredient.base_unit_id and active and not is_deleted;
      if not found or coalesce(ingredient_unit.base_unit_id,ingredient_unit.id)<>coalesce(source_unit.base_unit_id,source_unit.id)
        or ingredient_unit.dimension<>source_unit.dimension then
        raise exception 'La unidad no es compatible con el ingrediente.' using errcode='22023';
      end if;
      select * into category from public.categories where id=ingredient.category_id and active and not is_deleted;
      if not found then raise exception 'La categoría no está disponible.' using errcode='22023'; end if;
      item_name:=ingredient.name; item_category:=category.name;
    else
      item_name:=trim(item.name_snapshot); item_category:=trim(item.category_snapshot);
      if not exists(select 1 from public.categories where name=item_category and active and not is_deleted) then
        raise exception 'La categoría del artículo manual no está disponible.' using errcode='22023';
      end if;
    end if;
    if length(item_category)>80 or length(source_unit.abbreviation)>24 then
      raise exception 'La etiqueta no cabe en el inventario actual.' using errcode='22023';
    end if;
    -- Do not infer catalog associations. Manual stock only merges with manual
    -- stock of the same normalized name, keeping prior metadata and expiry.
    stock:=null;
    for candidate in select * from public.pantry_items p where p.user_id=actor
      and p.ingredient_ref is not distinct from item.ingredient_id
      and lower(trim(p.name))=lower(trim(item_name))
      and (p.expiry is null or p.expiry>=current_date) order by p.id for update loop
      select * into target_unit from public.units where id=candidate.unit_ref and active and not is_deleted;
      if not found and candidate.unit_ref is null then
        -- Legacy references may be null: an exact unique abbreviation is safe.
        select * into target_unit from public.units where abbreviation=candidate.unit and active and not is_deleted;
      end if;
      if target_unit.id is not null and target_unit.abbreviation=candidate.unit
        and target_unit.dimension=source_unit.dimension
        and coalesce(target_unit.base_unit_id,target_unit.id)=coalesce(source_unit.base_unit_id,source_unit.id) then
        stock:=candidate; exit;
      end if;
    end loop;
    if stock.id is null then
      target_unit:=source_unit;
      addition:=item.quantity;
      insert into public.pantry_items(user_id,ingredient_id,ingredient_ref,unit_ref,name,category,quantity,unit,minimum,expiry,source_shopping_ids)
        values(actor,case when item.ingredient_id is null then null else coalesce(ingredient.legacy_id,ingredient.id::text) end,
          item.ingredient_id,target_unit.id,item_name,item_category,addition,target_unit.abbreviation,0,null,array[item_id::text])
        returning id into target_id;
    else
      addition:=item.quantity*coalesce(source_unit.equivalence_multiplier,1)/coalesce(target_unit.equivalence_multiplier,1);
      if addition<>round(addition,4) then
        raise exception 'La conversión no puede representarse sin perder cantidad.' using errcode='22023';
      end if;
      if addition<=0 or stock.quantity+addition>1000000 then
        raise exception 'La cantidad excede el rango de inventario.' using errcode='22023';
      end if;
      update public.pantry_items set quantity=quantity+addition,unit_ref=target_unit.id,
        source_shopping_ids=array_append(source_shopping_ids,item_id::text),updated_at=clock_timestamp()
        where id=stock.id and user_id=actor returning id into target_id;
    end if;
    insert into public.pantry_receipt_items(receipt_id,original_shopping_item_id,shopping_item_id,pantry_item_id,
      quantity_added,unit_abbreviation_snapshot,ingredient_id_snapshot,name_snapshot,category_snapshot,
      purchased_quantity,purchased_unit_id_snapshot,purchased_unit_abbreviation_snapshot,pantry_unit_id_snapshot)
      values(receipt.id,item_id,item_id,target_id,addition,target_unit.abbreviation,item.ingredient_id,item_name,item_category,
        item.quantity,item.unit_id,source_unit.abbreviation,target_unit.id);
    update public.shopping_items set transferred_at=receipt.created_at,updated_at=clock_timestamp() where id=item_id;
  end loop;
  update public.shopping_lists set version=version+1,updated_at=clock_timestamp() where id=p_list_id;
  return receipt;
exception when data_exception or check_violation or not_null_violation or unique_violation or foreign_key_violation then
  raise exception 'No se pudo transferir la compra con esos datos.' using errcode='22023';
end;
$$;
revoke all on function public.transfer_my_shopping_to_pantry(uuid,uuid[],uuid,bigint) from public,anon;
grant execute on function public.transfer_my_shopping_to_pantry(uuid,uuid[],uuid,bigint) to authenticated;

-- Conversion definitions referenced by stock are historical meaning too.
create function public.protect_pantry_unit_conversion() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if (new.dimension,new.base_unit_id,new.equivalence_multiplier) is distinct from
     (old.dimension,old.base_unit_id,old.equivalence_multiplier)
    and exists(select 1 from public.pantry_items where unit_ref=old.id) then
    raise exception 'No se puede cambiar la conversión de una unidad usada en despensa.' using errcode='22023';
  end if;
  return new;
end;
$$;
revoke all on function public.protect_pantry_unit_conversion() from public,anon,authenticated;
create trigger protect_pantry_unit_conversion before update on public.units for each row execute function public.protect_pantry_unit_conversion();

-- Staged from 202610300007_shopping_suggestions_rpc.sql inside the rehearsal transaction.
-- Preview only: the user confirms individual suggestions through put_my_shopping_item.
-- No list, stock, favorites or plan is changed by this operation.
create function public.suggest_my_shopping(p_source text, p_plan_id uuid default null, p_as_of date default current_date)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare actor uuid; result jsonb; invalid boolean;
begin
  actor := public.lock_my_relational_account();
  if p_source is null or p_source not in ('plan','favorites','pantry') or p_as_of is null
    or not isfinite(p_as_of) or (p_source='plan') <> (p_plan_id is not null) then
    raise exception 'Origen, plan o fecha de sugerencias inválidos.' using errcode='22023';
  end if;
  if p_source='plan' and not exists(select 1 from public.meal_plans where id=p_plan_id and owner_user_id=actor) then
    raise exception 'El plan no está disponible para esta cuenta.' using errcode='42501';
  end if;

  -- One statement gives the preview a consistent snapshot of every input.
  with unit_map as materialized (
    select u.id,u.abbreviation,coalesce(u.base_unit_id,u.id) root_id,
      coalesce(u.equivalence_multiplier,1) factor
    from public.units u join public.units r on r.id=coalesce(u.base_unit_id,u.id)
    where u.active and not u.is_deleted and r.active and not r.is_deleted
      and r.base_unit_id is null and r.dimension=u.dimension
  ), selected_recipes as (
    select r.id,r.portions,s.portions::numeric planned_portions
    from public.meal_plan_slots s join public.recipes r on r.id=s.recipe_id
    where p_source='plan' and s.plan_id=p_plan_id
      and r.active and not r.is_deleted
      and (r.owner_user_id=actor or (r.recipe_source='official' and r.publication_status='published'))
    union all
    select r.id,r.portions,r.portions::numeric
    from public.favorite_recipes f join public.recipes r on r.id=f.recipe_id
    where p_source='favorites' and f.user_id=actor and r.active and not r.is_deleted
      and (r.owner_user_id=actor or (r.recipe_source='official' and r.publication_status='published'))
  ), requirements as (
    select i.id ingredient_id,i.name,i.category_id,i.base_unit_id unit_id,base.root_id,
      sum(ri.quantity*requested.planned_portions/requested.portions*used.factor/base.factor) required,
      bool_and(i.active and not i.is_deleted and c.active and not c.is_deleted
        and used.id is not null and base.id is not null and used.root_id=base.root_id) valid
    from selected_recipes requested join public.recipe_ingredients ri on ri.recipe_id=requested.id
    join public.ingredients i on i.id=ri.ingredient_id join public.categories c on c.id=i.category_id
    left join unit_map used on used.id=ri.unit_id left join unit_map base on base.id=i.base_unit_id
    group by i.id,i.name,i.category_id,i.base_unit_id,base.root_id
  ), stock as materialized (
    select p.*,u.id resolved_unit_id,u.root_id,u.factor,
      lower(regexp_replace(regexp_replace(normalize(trim(p.name),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')) normalized_name,
      case when p.expiry is null or p.expiry>=p_as_of then p.quantity else 0 end usable
    from public.pantry_items p left join unit_map u
      on (u.id=p.unit_ref and u.abbreviation=p.unit) or (p.unit_ref is null and u.abbreviation=p.unit)
    where p.user_id=actor
  ), recipe_proposals as (
    select r.ingredient_id,r.name,c.name category,r.unit_id,
      greatest(0,r.required-coalesce((select sum(s.usable*s.factor/base.factor) from stock s
        where s.root_id=r.root_id and (s.ingredient_ref=r.ingredient_id or
          (s.ingredient_ref is null and s.normalized_name=lower(regexp_replace(regexp_replace(normalize(trim(r.name),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))))),0)) quantity,
      r.valid and not exists(select 1 from stock s where (s.resolved_unit_id is null or s.root_id is distinct from r.root_id)
        and (s.ingredient_ref=r.ingredient_id or (s.ingredient_ref is null
          and s.normalized_name=lower(regexp_replace(regexp_replace(normalize(trim(r.name),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))))) valid
    from requirements r join public.categories c on c.id=r.category_id
    left join unit_map base on base.id=r.unit_id
  ), restock_groups as (
    -- Manual rows stay manual. Never persist a guessed catalog association.
    select s.ingredient_ref ingredient_id,s.normalized_name,s.root_id,
      (array_agg(s.name order by s.id))[1] name,(array_agg(s.category order by s.id))[1] category,
      (array_agg(s.resolved_unit_id order by s.id))[1] unit_id,
      sum(s.usable*s.factor) usable,max(s.minimum*s.factor) minimum,
      max(s.quantity*s.factor) previous_quantity,
      bool_or(s.quantity=0 or s.expiry<p_as_of) exhausted,
      bool_and(s.resolved_unit_id is not null) valid
    from stock s where p_source='pantry'
    group by s.ingredient_ref,s.normalized_name,s.root_id
  ), restock_proposals as (
    select g.ingredient_id,g.name,g.category,g.unit_id,
      case when g.minimum>0 then greatest(0,g.minimum-g.usable)/u.factor
        when g.usable=0 and g.exhausted then greatest(u.factor,g.previous_quantity)/u.factor else 0 end quantity,
      g.valid and exists(select 1 from public.categories c where c.name=g.category and c.active and not c.is_deleted)
        and (g.ingredient_id is null or exists(select 1 from public.ingredients i join unit_map b on b.id=i.base_unit_id
          where i.id=g.ingredient_id and i.active and not i.is_deleted and b.root_id=g.root_id)) valid
    from restock_groups g left join unit_map u on u.id=g.unit_id
  ), proposals as (
    select * from recipe_proposals where p_source in ('plan','favorites')
    union all select * from restock_proposals
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'ingredient_id',ingredient_id,'name_snapshot',name,'category_snapshot',category,
    'quantity',ceil(quantity*10000)/10000,'unit_id',unit_id,'source',p_source,
    'sources',jsonb_build_array(case when p_source='plan' then jsonb_build_object('source','plan','plan_id',p_plan_id)
      else jsonb_build_object('source',p_source) end)) order by lower(name),unit_id,ingredient_id)
      filter(where quantity>0),'[]'::jsonb),
    coalesce(bool_or(valid is distinct from true or quantity is null or quantity>1000000),false)
  into result,invalid from proposals;
  if invalid then
    raise exception 'No se pueden calcular sugerencias con el catálogo, unidades o cantidades actuales.' using errcode='22023';
  end if;
  return result;
end;
$$;
revoke all on function public.suggest_my_shopping(text,uuid,date) from public,anon;
grant execute on function public.suggest_my_shopping(text,uuid,date) to authenticated;


-- Staged from 202610310001_pantry_write_rpcs.sql inside the rehearsal transaction.
-- Every pantry mutation advances this row's version, including writes made by
-- trusted transfer/cooking RPCs. Clients use the version as an optimistic lock.
alter table public.pantry_items add column version bigint not null default 1 check (version > 0);
alter table public.pantry_items alter column quantity type numeric(14,4),
  alter column minimum type numeric(14,4);

create function public.advance_pantry_item_version()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.version := old.version + 1;
  return new;
end;
$$;
revoke all on function public.advance_pantry_item_version() from public, anon, authenticated;
create trigger advance_pantry_item_version before update on public.pantry_items
  for each row execute function public.advance_pantry_item_version();

-- Full snapshot upsert. The caller supplies a stable UUID and expected version
-- (0 for create). Empty or omitted expiry stays NULL; catalog refs stay NULL
-- unless explicitly selected by the caller.
create function public.put_my_pantry_item(p_item jsonb, p_expected_version bigint)
returns public.pantry_items language plpgsql volatile security definer set search_path = ''
as $$
declare
  actor uuid; item_id uuid; saved public.pantry_items; existing public.pantry_items;
  ingredient public.ingredients; unit_row public.units; category_row public.categories;
  amount numeric; minimum_amount numeric; expiry_date date; name_value text; category_value text;
  unit_value text; ingredient_ref_value uuid; unit_ref_value uuid; ingredient_id_value text;
begin
  actor := public.lock_my_relational_account();
  if jsonb_typeof(p_item) is distinct from 'object' or p_expected_version is null or p_expected_version < 0
    or exists(select 1 from jsonb_object_keys(p_item) k where k not in
      ('id','name','category','quantity','unit','minimum','expiry','ingredient_ref','ingredient_id')) then
    raise exception 'Formato del ingrediente inválido.' using errcode='22023';
  end if;
  if jsonb_typeof(p_item->'id') is distinct from 'string'
    or jsonb_typeof(p_item->'name') is distinct from 'string'
    or jsonb_typeof(p_item->'category') is distinct from 'string'
    or jsonb_typeof(p_item->'unit') is distinct from 'string'
    or jsonb_typeof(p_item->'quantity') is distinct from 'number'
    or jsonb_typeof(p_item->'minimum') is distinct from 'number'
    or (p_item ? 'expiry' and jsonb_typeof(p_item->'expiry') not in ('null','string'))
    or (p_item ? 'ingredient_ref' and jsonb_typeof(p_item->'ingredient_ref') not in ('null','string'))
    or (p_item ? 'ingredient_id' and jsonb_typeof(p_item->'ingredient_id') not in ('null','string')) then
    raise exception 'Faltan datos o hay tipos inválidos.' using errcode='22023';
  end if;
  item_id := (p_item->>'id')::uuid;
  name_value := regexp_replace(trim(p_item->>'name'), '\s+', ' ', 'g');
  category_value := trim(p_item->>'category'); unit_value := trim(p_item->>'unit');
  amount := (p_item->>'quantity')::numeric; minimum_amount := (p_item->>'minimum')::numeric;
  if length(name_value) not between 1 and 120 or length(category_value) not between 1 and 80
    or length(unit_value) not between 1 and 24
    or amount < 0 or amount > 1000000 or amount <> round(amount,4)
    or minimum_amount < 0 or minimum_amount > 1000000 or minimum_amount <> round(minimum_amount,4)
    then
    raise exception 'El nombre o las cantidades están fuera del rango admitido.' using errcode='22023';
  end if;
  if nullif(p_item->>'expiry','') is not null then
    if (p_item->>'expiry') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'La fecha de vencimiento es inválida.' using errcode='22023';
    end if;
    expiry_date := (p_item->>'expiry')::date;
  end if;
  if nullif(p_item->>'ingredient_ref','') is not null then ingredient_ref_value := (p_item->>'ingredient_ref')::uuid; end if;
  if p_item ? 'ingredient_id' then ingredient_id_value := nullif(p_item->>'ingredient_id',''); end if;
  if ingredient_id_value is not null and length(ingredient_id_value)>200 then
    raise exception 'El vínculo histórico del ingrediente no es válido.' using errcode='22023';
  end if;
  select * into unit_row from public.units where abbreviation=unit_value and active and not is_deleted for share;
  if not found or not exists(select 1 from public.units root where root.id=coalesce(unit_row.base_unit_id,unit_row.id)
    and root.active and not root.is_deleted and root.base_unit_id is null) then
    raise exception 'La unidad no está disponible.' using errcode='22023';
  end if;
  unit_ref_value := unit_row.id;
  select * into category_row from public.categories where name=category_value and active and not is_deleted for share;
  if not found then raise exception 'La categoría no está disponible.' using errcode='22023'; end if;
  if ingredient_ref_value is not null then
    select * into ingredient from public.ingredients where id=ingredient_ref_value and active and not is_deleted for share;
    if not found or ingredient.name is distinct from name_value or ingredient.category_id is distinct from category_row.id
      or not exists(select 1 from public.units base where base.id=ingredient.base_unit_id and base.active and not base.is_deleted
        and base.dimension=unit_row.dimension and coalesce(base.base_unit_id,base.id)=coalesce(unit_row.base_unit_id,unit_row.id)) then
      raise exception 'El ingrediente o su unidad no están disponibles.' using errcode='22023';
    end if;
    if p_item ? 'ingredient_id' and nullif(p_item->>'ingredient_id','') is not null
      and p_item->>'ingredient_id' is distinct from coalesce(ingredient.legacy_id,ingredient.id::text) then
      raise exception 'El identificador legado no corresponde al ingrediente.' using errcode='22023';
    end if;
    ingredient_id_value:=coalesce(ingredient.legacy_id,ingredient.id::text);
  end if;

  select * into existing from public.pantry_items where id=item_id and user_id=actor for update;
  if not (p_item ? 'ingredient_id') then
    if found then ingredient_id_value:=existing.ingredient_id;
    elsif ingredient_ref_value is not null then ingredient_id_value:=coalesce(ingredient.legacy_id,ingredient.id::text);
    end if;
  end if;
  if p_expected_version=0 then
    if found then
      -- Safe retry after a lost create response: same UUID and same payload.
      if existing.version=1 and existing.name=name_value and existing.category=category_value
        and existing.quantity=amount and existing.unit=unit_value and existing.minimum=minimum_amount
        and existing.expiry is not distinct from expiry_date
        and existing.ingredient_ref is not distinct from ingredient_ref_value
        and existing.ingredient_id is not distinct from ingredient_id_value then return existing; end if;
      raise exception 'El ingrediente ya existe; recargá la despensa.' using errcode='40001';
    end if;
    insert into public.pantry_items(id,user_id,name,category,quantity,unit,minimum,expiry,ingredient_id,ingredient_ref,unit_ref)
      values(item_id,actor,name_value,category_value,amount,unit_value,minimum_amount,expiry_date,
        ingredient_id_value,
        ingredient_ref_value,unit_ref_value) returning * into saved;
    return saved;
  end if;
  if not found or existing.version<>p_expected_version then
    raise exception 'El ingrediente cambió en otra sesión. Recargalo antes de guardar.' using errcode='40001';
  end if;
  update public.pantry_items set name=name_value,category=category_value,quantity=amount,unit=unit_value,
    minimum=minimum_amount,expiry=expiry_date,ingredient_id=ingredient_id_value,
    ingredient_ref=ingredient_ref_value,unit_ref=unit_ref_value,updated_at=clock_timestamp()
    where id=item_id and user_id=actor returning * into saved;
  return saved;
exception when data_exception or check_violation or not_null_violation or foreign_key_violation or unique_violation then
  raise exception 'Los datos del ingrediente no son válidos.' using errcode='22023';
end;
$$;
revoke all on function public.put_my_pantry_item(jsonb,bigint) from public,anon;
grant execute on function public.put_my_pantry_item(jsonb,bigint) to authenticated;

-- Atomic confirmation for starter kits and reviewed receipt proposals. Each
-- entry is {item: <same full snapshot>, expected_version: bigint}; stable item
-- UUIDs make a completed batch safe to retry after a lost response.
create function public.put_my_pantry_items(p_items jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare entry jsonb; item_id uuid; expected bigint; saved public.pantry_items; output_rows jsonb:='[]'::jsonb;
begin
  perform public.lock_my_relational_account();
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 200
    or exists(select 1 from jsonb_array_elements(p_items) as entries(e) where jsonb_typeof(e) is distinct from 'object'
      or jsonb_typeof(e->'item') is distinct from 'object' or jsonb_typeof(e->'expected_version') is distinct from 'number'
      or exists(select 1 from jsonb_object_keys(e) as keys(k) where k not in ('item','expected_version'))
      or (e->>'expected_version')::numeric < 0
      or (e->>'expected_version')::numeric > 9223372036854775807
      or (e->>'expected_version')::numeric <> trunc((e->>'expected_version')::numeric)) then
    raise exception 'La confirmación de ingredientes no es válida.' using errcode='22023';
  end if;
  if (select count(distinct ((e->'item'->>'id')::uuid)) from jsonb_array_elements(p_items) as entries(e))<>jsonb_array_length(p_items)
    or exists(select 1 from jsonb_array_elements(p_items) as entries(e) where e->'item'->>'id' is null) then
    raise exception 'La confirmación contiene ingredientes repetidos o incompletos.' using errcode='22023';
  end if;
  -- Stable UUID order avoids lock-order inversions when batches overlap.
  for entry in select e from jsonb_array_elements(p_items) as entries(e) order by (e->'item'->>'id') loop
    item_id := (entry->'item'->>'id')::uuid;
    expected := (entry->>'expected_version')::bigint;
    select * into saved from public.put_my_pantry_item(entry->'item',expected);
    output_rows := output_rows || jsonb_build_array(to_jsonb(saved));
  end loop;
  return output_rows;
exception when data_exception or check_violation or not_null_violation or foreign_key_violation or unique_violation then
  raise exception 'No se pudieron confirmar los ingredientes.' using errcode='22023';
end;
$$;
revoke all on function public.put_my_pantry_items(jsonb) from public,anon;
grant execute on function public.put_my_pantry_items(jsonb) to authenticated;

create function public.delete_my_pantry_item(p_item_id uuid, p_expected_version bigint)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; existing public.pantry_items;
begin
  actor:=public.lock_my_relational_account();
  if p_item_id is null or p_expected_version is null or p_expected_version<1 then
    raise exception 'Solicitud de eliminación inválida.' using errcode='22023';
  end if;
  select * into existing from public.pantry_items where id=p_item_id and user_id=actor for update;
  if not found then return false; end if;
  if existing.version<>p_expected_version then
    raise exception 'El ingrediente cambió en otra sesión. Recargalo antes de eliminar.' using errcode='40001';
  end if;
  delete from public.pantry_items where id=p_item_id and user_id=actor;
  return true;
end;
$$;
revoke all on function public.delete_my_pantry_item(uuid,bigint) from public,anon;
grant execute on function public.delete_my_pantry_item(uuid,bigint) to authenticated;

-- Retain owner-scoped reads. All client writes now go through validated RPCs;
-- trusted SECURITY DEFINER transfer/cooking routines retain their behavior.
revoke insert,update,delete on public.pantry_items from anon,authenticated;

-- Staged from 202610310002_cooking_session_rpcs.sql inside the rehearsal transaction.
alter table public.cooking_sessions add column version bigint not null default 1 check (version > 0);
alter table public.cooking_sessions add column requested_portions integer not null default 1 check (requested_portions between 1 and 20);
create function public.start_my_cooking_session(p_session_id uuid, p_recipe_id uuid, p_portions integer)
returns public.cooking_sessions language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; recipe_row public.recipes; saved public.cooking_sessions; snapshot jsonb; ingredient_rows jsonb; step_rows jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_session_id is null or p_recipe_id is null or p_portions is null or p_portions not between 1 and 20 then
    raise exception 'La sesión de cocina no es válida.' using errcode='22023';
  end if;
  select * into saved from public.cooking_sessions where id=p_session_id and owner_user_id=actor for update;
  if found then
    if saved.recipe_id is distinct from p_recipe_id or saved.requested_portions is distinct from p_portions then raise exception 'La clave de sesión ya fue utilizada.' using errcode='23505'; end if;
    return saved;
  end if;
  select * into recipe_row from public.recipes r where r.id=p_recipe_id and r.active and not r.is_deleted
    and ((r.recipe_source='official' and r.publication_status='published') or r.owner_user_id=actor)
    for share;
  if not found then raise exception 'La receta no está disponible.' using errcode='42501'; end if;
  -- Trusted writers that add/remove recipe children must lock the parent recipe
  -- FOR UPDATE first. Clients have read-only catalog grants; this lock order
  -- makes the multi-query snapshot consistent with future write RPCs.
  perform 1 from public.recipe_ingredients ri where ri.recipe_id=p_recipe_id order by ri.id for share;
  perform 1 from public.recipe_steps s where s.recipe_id=p_recipe_id order by s.id for share;
  perform 1 from public.recipe_step_ingredients x join public.recipe_steps s on s.id=x.step_id
    where s.recipe_id=p_recipe_id order by x.step_id,x.recipe_ingredient_id for share of x;
  -- Lock every referenced catalog row in stable order before snapshotting. This
  -- prevents a concurrent admin edit from invalidating the future stock refs.
  perform 1 from public.recipe_ingredients ri
    join public.ingredients i on i.id=ri.ingredient_id
    join public.categories c on c.id=i.category_id
    join public.units u on u.id=ri.unit_id
    join public.units recipe_root on recipe_root.id=coalesce(u.base_unit_id,u.id)
    join public.units ingredient_base on ingredient_base.id=i.base_unit_id
    join public.units ingredient_root on ingredient_root.id=coalesce(ingredient_base.base_unit_id,ingredient_base.id)
    where ri.recipe_id=p_recipe_id order by ri.id
    for share of i,c,u,recipe_root,ingredient_base,ingredient_root;
  if exists(select 1 from public.recipe_ingredients ri
    join public.ingredients i on i.id=ri.ingredient_id join public.categories c on c.id=i.category_id
    join public.units u on u.id=ri.unit_id join public.units recipe_root on recipe_root.id=coalesce(u.base_unit_id,u.id)
    join public.units ingredient_base on ingredient_base.id=i.base_unit_id
    join public.units ingredient_root on ingredient_root.id=coalesce(ingredient_base.base_unit_id,ingredient_base.id)
    where ri.recipe_id=p_recipe_id and (not i.active or i.is_deleted or not c.active or c.is_deleted
      or not u.active or u.is_deleted or not recipe_root.active or recipe_root.is_deleted
      or not ingredient_base.active or ingredient_base.is_deleted or not ingredient_root.active or ingredient_root.is_deleted
      or recipe_root.id<>ingredient_root.id or recipe_root.dimension<>ingredient_root.dimension)) then
    raise exception 'La receta contiene referencias de catálogo no disponibles.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('ingredientId',i.id,'name',i.name,'quantity',ri.quantity,'unit',u.abbreviation,
    'unitId',u.id,'unitRootId',root.id,'unitDimension',u.dimension,'unitFactor',coalesce(u.equivalence_multiplier,1),
    'category',c.name) order by ri.position),'[]'::jsonb)
    into ingredient_rows from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id
    join public.units u on u.id=ri.unit_id join public.units root on root.id=coalesce(u.base_unit_id,u.id)
    join public.categories c on c.id=i.category_id where ri.recipe_id=p_recipe_id;
  select coalesce(jsonb_agg(jsonb_build_object('instruction',s.instruction,'durationMinutes',coalesce(s.duration_minutes,0),
    'temperature',s.temperature,'tip',s.tip,'warning',s.warning,'utensils',to_jsonb(s.utensils),
    'specialInstructions',s.special_instructions,'stepIngredients',coalesce(si.ingredients,'[]'::jsonb)) order by s.position),'[]'::jsonb)
    into step_rows from public.recipe_steps s left join lateral (
      select jsonb_agg(jsonb_build_object('ingredientId',i.id,'name',i.name,'quantity',coalesce(x.quantity_override,ri.quantity),
        'unit',u.abbreviation,'unitId',u.id,'unitRootId',root.id,'unitDimension',u.dimension,
        'unitFactor',coalesce(u.equivalence_multiplier,1),'category',c.name) order by ri.position) ingredients
      from public.recipe_step_ingredients x join public.recipe_ingredients ri on ri.id=x.recipe_ingredient_id
      join public.ingredients i on i.id=ri.ingredient_id join public.units u on u.id=ri.unit_id
      join public.units root on root.id=coalesce(u.base_unit_id,u.id) join public.categories c on c.id=i.category_id
      where x.step_id=s.id
    ) si on true where s.recipe_id=p_recipe_id;
  if jsonb_array_length(step_rows)=0 then raise exception 'La receta no tiene pasos.' using errcode='22023'; end if;
  snapshot := jsonb_build_object('id',recipe_row.id,'name',recipe_row.title,'description',recipe_row.description,
    'category',recipe_row.category_label,'minutes',recipe_row.total_minutes,'portions',recipe_row.portions,
    'difficulty',recipe_row.difficulty,'ingredients',ingredient_rows,'steps',step_rows,
    'symbol',recipe_row.symbol,'color',recipe_row.color,'image',recipe_row.image_path,
    'imageAlt',recipe_row.image_alt,'crossContaminationNote',recipe_row.cross_contamination_note);
  insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,recipe_version,portions,requested_portions,client_idempotency_key)
    values(p_session_id,actor,p_recipe_id,snapshot,null,p_portions,p_portions,p_session_id) returning * into saved;
  insert into public.cooking_session_steps(session_id,step_position) select p_session_id,n from generate_series(1,jsonb_array_length(step_rows)) n;
  return saved;
exception when unique_violation then raise exception 'La sesión ya existe.' using errcode='23505';
  when check_violation or not_null_violation or foreign_key_violation or data_exception then raise exception 'La solicitud de cocina no es válida.' using errcode='22023';
end; $$;

create function public.get_my_cooking_session(p_session_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := auth.uid();
  if actor is null or not public.current_account_is_active() then raise exception 'Se requiere una sesión activa.' using errcode='42501'; end if;
  select to_jsonb(s) || jsonb_build_object('steps',coalesce((select jsonb_agg(to_jsonb(cs) || jsonb_build_object(
      'remaining_ms',case when cs.timer_state='running' then greatest(0,(extract(epoch from (cs.timer_deadline_at-clock_timestamp()))*1000)::bigint) else cs.remaining_ms end
    ) order by cs.step_position) from public.cooking_session_steps cs where cs.session_id=s.id),'[]'::jsonb))
    into result from public.cooking_sessions s where s.id=p_session_id and s.owner_user_id=actor and s.finished_at is null;
  if result is null then raise exception 'La sesión no está disponible.' using errcode='P0002'; end if;
  return result;
end; $$;

create function public.update_my_cooking_session(p_session_id uuid,p_expected_version bigint,p_action text,p_step integer default null,p_portions integer default null)
returns public.cooking_sessions language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; saved public.cooking_sessions; step_count integer; timer_row public.cooking_session_steps; duration_ms bigint; remaining bigint; timer_now timestamptz;
begin
  actor:=public.lock_my_relational_account();
  if p_session_id is null or p_expected_version is null or p_expected_version<1 or p_action is null
    or p_action not in ('move','complete','uncomplete','timer_start','timer_pause','timer_resume','timer_reset','timer_finish','portions')
    or (p_action='portions' and (p_portions is null or p_portions not between 1 and 20 or p_step is not null))
    or (p_action<>'portions' and p_portions is not null) then
    raise exception 'La actualización de cocina no es válida.' using errcode='22023';
  end if;
  select * into saved from public.cooking_sessions where id=p_session_id and owner_user_id=actor for update;
  if not found or saved.finished_at is not null then raise exception 'La sesión no está disponible.' using errcode='P0002'; end if;
  if saved.version<>p_expected_version then raise exception 'La sesión cambió. Recargala antes de continuar.' using errcode='40001'; end if;
  step_count:=jsonb_array_length(saved.recipe_snapshot->'steps');
  if p_action='portions' then
    update public.cooking_sessions set portions=p_portions,version=version+1 where id=p_session_id returning * into saved;
  elsif p_action='move' then
    if p_step is null or p_step<0 or p_step>=step_count then raise exception 'El paso indicado no es válido.' using errcode='22023'; end if;
    if p_step<>saved.current_step then
      select * into timer_row from public.cooking_session_steps where session_id=p_session_id and step_position=saved.current_step+1 for update;
      if timer_row.timer_state='running' then
        timer_now:=clock_timestamp();
        remaining:=greatest(0,(extract(epoch from (timer_row.timer_deadline_at-timer_now))*1000)::bigint);
        update public.cooking_session_steps set remaining_ms=remaining,timer_deadline_at=null,
          timer_state=case when remaining=0 then 'finished' else 'paused' end
          where session_id=p_session_id and step_position=saved.current_step+1;
      end if;
    end if;
    update public.cooking_sessions set current_step=p_step,version=version+1 where id=p_session_id returning * into saved;
  else
    if p_step is null or p_step<0 or p_step>=step_count then raise exception 'El paso indicado no es válido.' using errcode='22023'; end if;
    if p_action in ('timer_start','timer_pause','timer_resume','timer_reset','timer_finish') and p_step<>saved.current_step then
      raise exception 'El temporizador solo se puede cambiar para el paso actual.' using errcode='22023';
    end if;
    select * into timer_row from public.cooking_session_steps where session_id=p_session_id and step_position=p_step+1 for update;
    if p_action='complete' then update public.cooking_session_steps set completed_at=coalesce(completed_at,clock_timestamp()) where session_id=p_session_id and step_position=p_step+1;
    elsif p_action='uncomplete' then update public.cooking_session_steps set completed_at=null where session_id=p_session_id and step_position=p_step+1;
    elsif p_action='timer_start' then
      duration_ms:=coalesce((saved.recipe_snapshot->'steps'->p_step->>'durationMinutes')::bigint,0)*60000;
      if duration_ms not between 1 and 86400000 then raise exception 'El paso no tiene una duración de temporizador válida.' using errcode='22023'; end if;
      if timer_row.timer_state='running' then return saved;
      else
        if timer_row.timer_state='idle' or timer_row.timer_state='finished' then remaining:=duration_ms; else remaining:=timer_row.remaining_ms; end if;
        update public.cooking_session_steps set remaining_ms=remaining,timer_deadline_at=clock_timestamp()+remaining*interval '1 millisecond',timer_state='running' where session_id=p_session_id and step_position=p_step+1;
      end if;
    elsif p_action='timer_pause' then
      if timer_row.timer_state='running' then remaining:=greatest(0,(extract(epoch from (timer_row.timer_deadline_at-clock_timestamp()))*1000)::bigint);
        update public.cooking_session_steps set remaining_ms=remaining,timer_deadline_at=null,timer_state=case when remaining=0 then 'finished' else 'paused' end where session_id=p_session_id and step_position=p_step+1;
      end if;
    elsif p_action='timer_resume' then
      if timer_row.timer_state='paused' and timer_row.remaining_ms>0 then update public.cooking_session_steps set timer_deadline_at=clock_timestamp()+remaining_ms*interval '1 millisecond',timer_state='running' where session_id=p_session_id and step_position=p_step+1; end if;
    elsif p_action='timer_reset' then update public.cooking_session_steps set remaining_ms=null,timer_deadline_at=null,timer_state='idle' where session_id=p_session_id and step_position=p_step+1;
    elsif p_action='timer_finish' then update public.cooking_session_steps set remaining_ms=0,timer_deadline_at=null,timer_state='finished' where session_id=p_session_id and step_position=p_step+1;
    end if;
    update public.cooking_sessions set version=version+1 where id=p_session_id returning * into saved;
  end if;
  return saved;
exception when unique_violation then raise exception 'No se pudo actualizar la sesión.' using errcode='23505';
  when check_violation or not_null_violation or foreign_key_violation or data_exception then raise exception 'La actualización de cocina no es válida.' using errcode='22023';
end; $$;

revoke all on function public.start_my_cooking_session(uuid,uuid,integer),public.get_my_cooking_session(uuid),public.update_my_cooking_session(uuid,bigint,text,integer,integer) from public,anon;
grant execute on function public.start_my_cooking_session(uuid,uuid,integer),public.get_my_cooking_session(uuid),public.update_my_cooking_session(uuid,bigint,text,integer,integer) to authenticated;
revoke insert,update,delete on public.cooking_sessions,public.cooking_session_steps from anon,authenticated;

-- Staged from 202610310003_cooking_finish_rpcs.sql inside the rehearsal transaction.
alter table public.cooking_events add column deduct_stock boolean not null default false;

create function public.finish_my_cooking_session(p_session_id uuid, p_expected_version bigint, p_deduct_stock boolean)
returns public.cooking_events language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid; session_row public.cooking_sessions; event_row public.cooking_events;
  ingredient_row jsonb; lot public.pantry_items; used_rows jsonb := '[]'::jsonb;
  v_recipe_id uuid; v_ingredient_id uuid; root_id uuid; pantry_unit public.units; recipe_unit public.units;
  factor numeric; recipe_factor numeric; needed_root numeric; used_root numeric; lot_root numeric;
  take_root numeric; take_stock numeric; remaining numeric; snapshot_name text; snapshot_unit text;
  demand numeric; today date := current_date;
begin
  actor := public.lock_my_relational_account();
  if p_session_id is null or p_expected_version is null or p_expected_version < 1 or p_deduct_stock is null then
    raise exception 'La finalización de cocina no es válida.' using errcode='22023';
  end if;
  select * into session_row from public.cooking_sessions where id=p_session_id and owner_user_id=actor for update;
  if not found then raise exception 'La sesión no está disponible.' using errcode='P0002'; end if;
  select * into event_row from public.cooking_events where session_id=p_session_id;
  if found then
    if event_row.deduct_stock is distinct from p_deduct_stock then
      raise exception 'La decisión de descuento no coincide con la finalización guardada.' using errcode='22023';
    end if;
    return event_row;
  end if;
  if session_row.finished_at is not null then raise exception 'La sesión no está disponible.' using errcode='P0002'; end if;
  if session_row.version<>p_expected_version then raise exception 'La sesión cambió. Recargala antes de continuar.' using errcode='40001'; end if;
  if jsonb_typeof(session_row.recipe_snapshot->'ingredients') is distinct from 'array'
    or jsonb_array_length(session_row.recipe_snapshot->'ingredients')>200
    or coalesce((session_row.recipe_snapshot->>'portions')::integer,0)<1 then
    raise exception 'La receta guardada no se puede finalizar.' using errcode='22023';
  end if;

  -- Lock every pantry lot up front in a stable order. Writes from pantry RPCs
  -- serialize here, so a shortage rolls back without partial deductions.
  if p_deduct_stock then
    perform 1 from public.pantry_items p where p.user_id=actor order by p.id for update;
    perform 1 from public.units u where u.id in (
      select (value->>'unitId')::uuid from jsonb_array_elements(session_row.recipe_snapshot->'ingredients')
      union select (value->>'unitRootId')::uuid from jsonb_array_elements(session_row.recipe_snapshot->'ingredients')
    ) order by u.id for share;
    for ingredient_row in select value from jsonb_array_elements(session_row.recipe_snapshot->'ingredients') loop
      if jsonb_typeof(ingredient_row->'ingredientId') is distinct from 'string'
        or jsonb_typeof(ingredient_row->'unitId') is distinct from 'string'
        or jsonb_typeof(ingredient_row->'unitRootId') is distinct from 'string'
        or jsonb_typeof(ingredient_row->'unitFactor') is distinct from 'number'
        or jsonb_typeof(ingredient_row->'quantity') is distinct from 'number'
        or jsonb_typeof(ingredient_row->'name') is distinct from 'string'
        or jsonb_typeof(ingredient_row->'unit') is distinct from 'string' then
        raise exception 'La receta guardada contiene un ingrediente inválido.' using errcode='22023';
      end if;
      v_ingredient_id := (ingredient_row->>'ingredientId')::uuid;
      root_id := (ingredient_row->>'unitRootId')::uuid;
      recipe_factor := (ingredient_row->>'unitFactor')::numeric;
      demand := (ingredient_row->>'quantity')::numeric*session_row.portions::numeric
        /(session_row.recipe_snapshot->>'portions')::numeric;
      if demand<=0 or recipe_factor<=0 then raise exception 'La cantidad de receta no es válida.' using errcode='22023'; end if;
      needed_root := demand*recipe_factor; used_root:=0;
      for lot in
        select p.* from public.pantry_items p
        where p.user_id=actor and (p.expiry is null or p.expiry>=today) and p.quantity>0
          and (p.ingredient_ref=v_ingredient_id or (p.ingredient_ref is null
            and lower(regexp_replace(trim(p.name),'\s+',' ','g'))=lower(regexp_replace(trim(ingredient_row->>'name'),'\s+',' ','g'))))
        order by p.expiry nulls last,p.id
      loop
        select * into pantry_unit from public.units u where u.id=coalesce(lot.unit_ref,(select id from public.units where abbreviation=lot.unit))
          and u.abbreviation=lot.unit and u.active and not u.is_deleted for share;
        if not found then continue; end if;
        if not exists(select 1 from public.units root where root.id=root_id and root.active and not root.is_deleted and root.base_unit_id is null)
          or coalesce(pantry_unit.base_unit_id,pantry_unit.id)<>root_id
          or pantry_unit.dimension<>ingredient_row->>'unitDimension' then continue; end if;
        factor:=coalesce(pantry_unit.equivalence_multiplier,1);
        lot_root:=lot.quantity*factor;
        remaining:=needed_root-used_root;
        take_root:=least(remaining,lot_root);
        take_stock:=take_root/factor;
        if take_stock<>round(take_stock,4) then
          -- Use a whole representable lot amount only when it exactly advances
          -- the demand; otherwise fail instead of rounding through a deficit.
          take_stock:=least(lot.quantity,trunc(take_stock,4));
          take_root:=take_stock*factor;
        end if;
        if take_stock<=0 or take_root<=0 then continue; end if;
        update public.pantry_items set quantity=quantity-take_stock,updated_at=clock_timestamp() where id=lot.id;
        used_root:=used_root+take_root;
        if used_root>=needed_root then exit; end if;
      end loop;
      if used_root<>needed_root then raise exception 'La despensa no tiene cantidad suficiente o compatible.' using errcode='22023'; end if;
      select * into recipe_unit from public.units u where u.id=(ingredient_row->>'unitId')::uuid;
      if not found or coalesce(recipe_unit.base_unit_id,recipe_unit.id)<>root_id
        or used_root/recipe_factor<>round(used_root/recipe_factor,4) then
        raise exception 'La cantidad no se puede representar con la unidad de receta.' using errcode='22023';
      end if;
      snapshot_name:=ingredient_row->>'name'; snapshot_unit:=ingredient_row->>'unit';
      used_rows:=used_rows||jsonb_build_array(jsonb_build_object('ingredient_id',v_ingredient_id,
        'name_snapshot',snapshot_name,'quantity_used',used_root/recipe_factor,'unit_abbreviation_snapshot',snapshot_unit));
    end loop;
  end if;
  v_recipe_id:=session_row.recipe_id;
  insert into public.cooking_events(owner_user_id,session_id,recipe_id,recipe_snapshot,portions,deduct_stock)
    values(actor,p_session_id,v_recipe_id,session_row.recipe_snapshot,session_row.portions,p_deduct_stock) returning * into event_row;
  insert into public.cooking_event_ingredients(event_id,ingredient_id,name_snapshot,quantity_used,unit_abbreviation_snapshot)
    select event_row.id,
      case when count(distinct (r.value->>'ingredient_id')::uuid)=1 then (array_agg(distinct (r.value->>'ingredient_id')::uuid))[1] else null end,
      r.value->>'name_snapshot',sum((r.value->>'quantity_used')::numeric),r.value->>'unit_abbreviation_snapshot'
    from jsonb_array_elements(used_rows) r
    group by r.value->>'name_snapshot',r.value->>'unit_abbreviation_snapshot';
  update public.cooking_sessions set finished_at=clock_timestamp(),version=version+1 where id=p_session_id;
  update public.cooking_session_steps set remaining_ms=case when timer_state='running' then
      greatest(0,(extract(epoch from (timer_deadline_at-clock_timestamp()))*1000)::bigint) else remaining_ms end,
    timer_deadline_at=null,timer_state=case when timer_state='running' then 'paused' else timer_state end
    where session_id=p_session_id;
  return event_row;
exception when unique_violation then
  select * into event_row from public.cooking_events where session_id=p_session_id and owner_user_id=actor;
  if found and event_row.deduct_stock is not distinct from p_deduct_stock then return event_row; end if;
  raise exception 'La finalización de cocina no es válida.' using errcode='23505';
when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation or foreign_key_violation or data_exception then
  raise exception 'La finalización de cocina no es válida.' using errcode='22023';
end; $$;

revoke all on function public.finish_my_cooking_session(uuid,bigint,boolean) from public,anon;
grant execute on function public.finish_my_cooking_session(uuid,bigint,boolean) to authenticated;
revoke insert,update,delete on public.cooking_events,public.cooking_event_ingredients from anon,authenticated;

-- Staged from 202610310004_cooking_queries_history_rpcs.sql inside the rehearsal transaction.
alter table public.cooking_events add column hidden_at timestamptz;
drop policy cooking_events_owner_read on public.cooking_events;
create policy cooking_events_owner_read on public.cooking_events for select to authenticated
  using (owner_user_id=(select auth.uid()) and hidden_at is null and (select public.current_account_is_active()));
create index cooking_events_owner_visible_page_idx
  on public.cooking_events(owner_user_id,cooked_at desc,id desc) where hidden_at is null;

create function public.get_my_cooking_history(p_limit integer default 30,p_before timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor:=auth.uid();
  if actor is null or not public.current_account_is_active() then raise exception 'Se requiere una sesión activa.' using errcode='42501'; end if;
  if p_limit is null or p_limit not between 1 and 100 or ((p_before is null)<>(p_before_id is null)) then
    raise exception 'La página del historial no es válida.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(row_data order by cooked_at desc,id desc),'[]'::jsonb) into result from (
    select e.cooked_at,e.id,to_jsonb(e)||jsonb_build_object('ingredients',coalesce((
      select jsonb_agg(to_jsonb(i) order by i.name_snapshot,i.unit_abbreviation_snapshot)
      from public.cooking_event_ingredients i where i.event_id=e.id),'[]'::jsonb)) row_data
    from public.cooking_events e where e.owner_user_id=actor and e.hidden_at is null
      and (p_before is null or (e.cooked_at,e.id)<(p_before,p_before_id))
    order by e.cooked_at desc,e.id desc limit p_limit
  ) page;
  return result;
end; $$;

create function public.hide_my_cooking_history_entry(p_event_id uuid)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid;
begin
  actor:=public.lock_my_relational_account();
  if p_event_id is null then raise exception 'El evento no es válido.' using errcode='22023'; end if;
  update public.cooking_events set hidden_at=clock_timestamp()
    where id=p_event_id and owner_user_id=actor and hidden_at is null;
  return found;
end; $$;

create function public.clear_my_cooking_history()
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; changed integer;
begin
  actor:=public.lock_my_relational_account();
  update public.cooking_events set hidden_at=clock_timestamp()
    where owner_user_id=actor and hidden_at is null;
  get diagnostics changed=row_count;
  return changed;
end; $$;

-- Checks against either a currently visible recipe or an owner's immutable session snapshot.
-- No client-provided quantities, unit factors, ingredient refs, or pantry amounts are trusted.
create function public.check_my_cooking_stock(p_recipe_id uuid default null,p_portions integer default null,p_session_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid; ingredients jsonb; base_portions integer; recipe_row public.recipes; session_row public.cooking_sessions;
  item jsonb; v_id uuid; v_ids uuid[]; v_root uuid; v_unit uuid; v_name text; v_dimension text; v_factor numeric;
  demand numeric; available_root numeric; required_root numeric; pantry public.pantry_items;
  pantry_unit public.units; pantry_factor numeric; output jsonb:='[]'::jsonb; row_result jsonb;
begin
  actor:=auth.uid();
  if actor is null or not public.current_account_is_active() then raise exception 'Se requiere una sesión activa.' using errcode='42501'; end if;
  if (p_session_id is null and (p_portions is null or p_portions not between 1 and 20)) or (p_session_id is null and p_recipe_id is null)
    or (p_session_id is not null and p_recipe_id is not null) then raise exception 'La consulta de despensa no es válida.' using errcode='22023'; end if;
  if p_session_id is not null then
    select * into session_row from public.cooking_sessions s where s.id=p_session_id and s.owner_user_id=actor;
    if not found then raise exception 'La sesión no está disponible.' using errcode='P0002'; end if;
    ingredients:=session_row.recipe_snapshot->'ingredients';
    base_portions:=coalesce((session_row.recipe_snapshot->>'portions')::integer,0);
    if base_portions<1 then raise exception 'La sesión no está disponible.' using errcode='P0002'; end if;
    if p_portions is not null and p_portions<>session_row.portions then raise exception 'La consulta debe usar las porciones de la sesión.' using errcode='22023'; end if;
    p_portions:=session_row.portions;
  else
    select * into recipe_row from public.recipes r where r.id=p_recipe_id and r.active and not r.is_deleted
      and ((r.recipe_source='official' and r.publication_status='published') or r.owner_user_id=actor);
    if not found then raise exception 'La receta no está disponible.' using errcode='P0002'; end if;
    base_portions:=recipe_row.portions;
    select coalesce(jsonb_agg(jsonb_build_object('ingredientId',i.id,'name',i.name,'quantity',ri.quantity,'unit',u.abbreviation,
      'unitId',u.id,'unitRootId',root.id,'unitDimension',u.dimension,'unitFactor',coalesce(u.equivalence_multiplier,1)) order by ri.position),'[]'::jsonb)
      into ingredients from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id
      join public.units u on u.id=ri.unit_id join public.units root on root.id=coalesce(u.base_unit_id,u.id)
      join public.categories c on c.id=i.category_id where ri.recipe_id=p_recipe_id;
    if exists(select 1 from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id
      join public.categories c on c.id=i.category_id join public.units u on u.id=ri.unit_id
      join public.units root on root.id=coalesce(u.base_unit_id,u.id)
      join public.units ingredient_base on ingredient_base.id=i.base_unit_id
      join public.units ingredient_root on ingredient_root.id=coalesce(ingredient_base.base_unit_id,ingredient_base.id)
      where ri.recipe_id=p_recipe_id and (not i.active or i.is_deleted or not c.active or c.is_deleted
        or not u.active or u.is_deleted or not root.active or root.is_deleted
        or not ingredient_base.active or ingredient_base.is_deleted or not ingredient_root.active or ingredient_root.is_deleted
        or root.id<>ingredient_root.id or root.dimension<>ingredient_root.dimension))
      then raise exception 'La receta contiene referencias de catálogo no disponibles.' using errcode='22023'; end if;
  end if;
  if jsonb_typeof(ingredients) is distinct from 'array' or jsonb_array_length(ingredients)>200 then raise exception 'La receta guardada no es válida.' using errcode='22023'; end if;
  -- Aggregate duplicate catalog ingredients and normalized manual labels before computing stock.
  for item in with grouped as (
    select min(e.value->>'ingredientId') ingredient_id,
      coalesce(to_jsonb(array_agg(distinct nullif(e.value->>'ingredientId','')::uuid)
        filter(where nullif(e.value->>'ingredientId','') is not null)),'[]'::jsonb) ingredient_ids,
      min(e.value->>'name') ingredient_name,(e.value->>'unitRootId')::uuid root_id,
      count(distinct nullif(e.value->>'ingredientId','')) ingredient_count,
      e.value->>'unitDimension' unit_dimension,
      sum((e.value->>'quantity')::numeric*(e.value->>'unitFactor')::numeric) quantity
    from jsonb_array_elements(ingredients) as e(value)
    group by lower(regexp_replace(trim(e.value->>'name'),'\s+',' ','g')),
      (e.value->>'unitRootId')::uuid,e.value->>'unitDimension'
  ) select jsonb_build_object('ingredientId',coalesce(g.ingredient_id,''),'ingredientIds',g.ingredient_ids,
      'name',g.ingredient_name,'ingredientCount',g.ingredient_count,'unitId',g.root_id,'unitRootId',g.root_id,'unitDimension',g.unit_dimension,
      'unitFactor','1','unit',root.abbreviation,'quantity',g.quantity)
    from grouped g join public.units root on root.id=g.root_id
  loop
    if coalesce((item->>'ingredientCount')::integer,0)>1 then
      raise exception 'La receta contiene nombres ambiguos de ingredientes.' using errcode='22023';
    end if;
    v_id:=nullif(item->>'ingredientId','')::uuid; v_name:=item->>'name'; v_unit:=(item->>'unitId')::uuid;
    select array_agg(x::uuid) into v_ids from jsonb_array_elements_text(item->'ingredientIds') as ids(x);
    v_root:=(item->>'unitRootId')::uuid; v_dimension:=item->>'unitDimension'; v_factor:=(item->>'unitFactor')::numeric;
    if v_factor<=0 or v_name is null or jsonb_typeof(item->'quantity') is distinct from 'number'
      or not exists(select 1 from public.units u join public.units root on root.id=coalesce(u.base_unit_id,u.id)
        where u.id=v_unit and root.id=v_root and u.dimension=v_dimension and u.active and not u.is_deleted
          and root.active and not root.is_deleted)
      then raise exception 'La receta guardada no es válida.' using errcode='22023'; end if;
    demand:=(item->>'quantity')::numeric*p_portions/base_portions;
    required_root:=demand*v_factor; available_root:=0;
    for pantry in select p.* from public.pantry_items p where p.user_id=actor and p.quantity>0
      and (p.expiry is null or p.expiry>=current_date) and
      (p.ingredient_ref=any(v_ids) or (p.ingredient_ref is null and lower(regexp_replace(trim(p.name),'\s+',' ','g'))=lower(regexp_replace(trim(v_name),'\s+',' ','g'))))
      order by p.expiry nulls last,p.id
    loop
      select * into pantry_unit from public.units u where u.id=coalesce(pantry.unit_ref,(select id from public.units where abbreviation=pantry.unit))
        and u.abbreviation=pantry.unit and u.active and not u.is_deleted;
      if found and coalesce(pantry_unit.base_unit_id,pantry_unit.id)=v_root and pantry_unit.dimension=v_dimension then
        pantry_factor:=coalesce(pantry_unit.equivalence_multiplier,1); available_root:=available_root+pantry.quantity*pantry_factor;
      end if;
    end loop;
    row_result:=jsonb_build_object('ingredientId',v_id,'ingredientIds',to_jsonb(v_ids),'name',v_name,'unit',item->>'unit','required',demand,
      'available',available_root/v_factor,'missing',greatest(0,required_root-available_root)/v_factor,
      'sufficient',available_root>=required_root);
    output:=output||jsonb_build_array(row_result);
  end loop;
  return jsonb_build_object('recipeId',case when p_session_id is null then p_recipe_id else session_row.recipe_id end,
    'sessionId',p_session_id,'portions',p_portions,'ingredients',output,
    'sufficient',coalesce((select bool_and((x->>'sufficient')::boolean) from jsonb_array_elements(output) x),true),
    'asOf',current_date,'preview',true);
exception when invalid_text_representation or numeric_value_out_of_range or check_violation or data_exception then
  raise exception 'La consulta de despensa no es válida.' using errcode='22023';
end; $$;

revoke all on function public.get_my_cooking_history(integer,timestamptz,uuid),public.hide_my_cooking_history_entry(uuid),public.clear_my_cooking_history(),public.check_my_cooking_stock(uuid,integer,uuid) from public,anon;
grant execute on function public.get_my_cooking_history(integer,timestamptz,uuid),public.hide_my_cooking_history_entry(uuid),public.clear_my_cooking_history(),public.check_my_cooking_stock(uuid,integer,uuid) to authenticated;

-- Staged from 202610310005_catalog_admin_rpcs.sql inside the rehearsal transaction.
-- Admin-owned relational catalog. Stable ids plus expected_version=0 make
-- creates safely replayable; updates use the current row version as a lock.
alter table public.categories add column version bigint not null default 1 check (version > 0);
alter table public.units add column version bigint not null default 1 check (version > 0);
alter table public.ingredients add column version bigint not null default 1 check (version > 0);
alter table public.categories drop constraint if exists categories_normalized_name_key;
alter table public.units add column normalized_name text;
update public.units set normalized_name=lower(regexp_replace(regexp_replace(normalize(trim(name),NFD), U&'[\0300-\036f]', '', 'g'), '\s+', ' ', 'g'));
alter table public.units alter column normalized_name set not null;
create unique index if not exists categories_non_deleted_normalized_name_uidx on public.categories(normalized_name) where not is_deleted;
create unique index if not exists units_non_deleted_normalized_name_uidx on public.units(normalized_name) where not is_deleted;

-- Existing backfill writers predate normalized_name. Keep them compatible and
-- ensure every unit write uses the same accent/whitespace folding as the UI.
create or replace function public.normalize_catalog_unit_name()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.normalized_name := lower(regexp_replace(regexp_replace(normalize(trim(new.name),NFD), U&'[\0300-\036f]', '', 'g'), '\s+', ' ', 'g'));
  return new;
end;
$$;
revoke all on function public.normalize_catalog_unit_name() from public,anon,authenticated;
create trigger normalize_catalog_unit_name_before_write
before insert or update of name,normalized_name on public.units
for each row execute function public.normalize_catalog_unit_name();

alter table public.admin_audit_log drop constraint if exists admin_audit_log_action_check;
alter table public.admin_audit_log add constraint admin_audit_log_action_check check (action in (
  'user.created','user.name_updated','user.role_changed','user.activated','user.deactivated',
  'catalog.core_saved','catalog.recipes_saved', 'catalog.category_saved',
  'catalog.unit_saved','catalog.ingredient_saved'
));

create or replace function public.admin_put_catalog_entity(p_kind text, p_entity jsonb, p_expected_version bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_variable
declare
  actor uuid; entity_id uuid; saved jsonb; current_version bigint; normalized text;
  entity_name text; active_value boolean; deleted_value boolean;
  category_id uuid; unit_id uuid; base_id uuid; dim text; mult numeric;
  abbreviation_value text; audit_action text;
begin
  -- Same lock as role changes and account status mutations. Recheck only after
  -- acquiring it, so a concurrent demotion/ban cannot race authorization.
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  actor := (select auth.uid());
  if actor is null or not (select public.current_account_is_active())
    or (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo un administrador activo puede modificar el catálogo.' using errcode='42501';
  end if;
  perform public.lock_my_relational_account();
  if p_kind is null or p_kind not in ('category','unit','ingredient') or jsonb_typeof(p_entity) is distinct from 'object'
    or p_expected_version is null or p_expected_version < 0
    or exists(select 1 from jsonb_object_keys(p_entity) k where k not in
      ('id','name','active','is_deleted','abbreviation','dimension','base_unit_id','equivalence_multiplier','category_id')) then
    raise exception 'La solicitud del catálogo no es válida.' using errcode='22023';
  end if;
  if (p_kind='category' and exists(select 1 from jsonb_object_keys(p_entity) k where k not in ('id','name','active','is_deleted')))
    or (p_kind='unit' and exists(select 1 from jsonb_object_keys(p_entity) k where k not in ('id','name','active','is_deleted','abbreviation','dimension','base_unit_id','equivalence_multiplier')))
    or (p_kind='ingredient' and exists(select 1 from jsonb_object_keys(p_entity) k where k not in ('id','name','active','is_deleted','category_id','base_unit_id'))) then
    raise exception 'La solicitud contiene campos ajenos al tipo de catálogo.' using errcode='22023';
  end if;
  if jsonb_typeof(p_entity->'id') is distinct from 'string' or jsonb_typeof(p_entity->'name') is distinct from 'string'
    or (p_entity ? 'active' and jsonb_typeof(p_entity->'active') <> 'boolean')
    or (p_entity ? 'is_deleted' and jsonb_typeof(p_entity->'is_deleted') <> 'boolean') then
    raise exception 'Faltan datos o hay tipos inválidos.' using errcode='22023';
  end if;
  entity_id := (p_entity->>'id')::uuid;
  entity_name := regexp_replace(trim(p_entity->>'name'), '\s+', ' ', 'g');
  active_value := coalesce((p_entity->>'active')::boolean,true);
  deleted_value := coalesce((p_entity->>'is_deleted')::boolean,false);
  if deleted_value and active_value then raise exception 'Un elemento eliminado debe quedar inactivo.' using errcode='22023'; end if;
  if length(entity_name) < 1 or length(entity_name) > (case p_kind when 'category' then 100 when 'unit' then 60 else 120 end) then
    raise exception 'El nombre está fuera del rango admitido.' using errcode='22023';
  end if;
  normalized := lower(regexp_replace(regexp_replace(normalize(entity_name,NFD), U&'[\0300-\036f]', '', 'g'), '\s+', ' ', 'g'));

  if p_kind='category' then
    audit_action := 'catalog.category_saved';
    select version into current_version from public.categories where id=entity_id for update;
    if p_expected_version=0 then
      if found then
        select to_jsonb(c) into saved from public.categories c where c.id=entity_id;
        if current_version=1 and saved->>'name'=entity_name and saved->>'active'=active_value::text and saved->>'is_deleted'=deleted_value::text then return saved; end if;
        raise exception 'La categoría ya existe con cambios; recargá el catálogo.' using errcode='40001';
      end if;
      insert into public.categories(id,name,normalized_name,active,is_deleted) values(entity_id,entity_name,normalized,active_value,deleted_value) returning to_jsonb(categories.*) into saved;
    else
      if not found or current_version<>p_expected_version then raise exception 'La categoría cambió; recargá el catálogo.' using errcode='40001'; end if;
      select to_jsonb(c) into saved from public.categories c where c.id=entity_id;
      if saved->>'name'=entity_name and saved->>'active'=active_value::text and saved->>'is_deleted'=deleted_value::text then return saved; end if;
      update public.categories set name=entity_name,normalized_name=normalized,active=active_value,is_deleted=deleted_value,updated_at=clock_timestamp(),version=version+1 where id=entity_id returning to_jsonb(categories.*) into saved;
    end if;
  elsif p_kind='unit' then
    audit_action := 'catalog.unit_saved';
    if jsonb_typeof(p_entity->'abbreviation') is distinct from 'string' or jsonb_typeof(p_entity->'dimension') is distinct from 'string'
      or (p_entity ? 'base_unit_id' and jsonb_typeof(p_entity->'base_unit_id') not in ('string','null'))
      or (p_entity ? 'equivalence_multiplier' and jsonb_typeof(p_entity->'equivalence_multiplier') not in ('number','null')) then
      raise exception 'Los datos de la unidad no son válidos.' using errcode='22023'; end if;
    abbreviation_value:=trim(p_entity->>'abbreviation'); dim:=p_entity->>'dimension';
    if length(abbreviation_value) not between 1 and 24 or dim not in ('mass','volume','count') then raise exception 'Unidad fuera de rango.' using errcode='22023'; end if;
    if nullif(p_entity->>'base_unit_id','') is not null then base_id:=(p_entity->>'base_unit_id')::uuid; end if;
    if nullif(p_entity->>'equivalence_multiplier','') is not null then mult:=(p_entity->>'equivalence_multiplier')::numeric; end if;
    if (base_id is null) <> (mult is null) or mult is not null and (mult<=0 or mult>99999999.999999 or mult<>round(mult,6)) then raise exception 'Equivalencia inválida.' using errcode='22023'; end if;
    if base_id is not null and (base_id=entity_id or not exists(select 1 from public.units b where b.id=base_id and b.base_unit_id is null and b.dimension=dim and b.active and not b.is_deleted)) then raise exception 'La unidad base debe ser raíz, activa y compatible.' using errcode='22023'; end if;
    if exists(select 1 from public.units u where u.id<>entity_id and lower(u.abbreviation)=lower(abbreviation_value)) then raise exception 'La abreviatura de unidad ya está reservada.' using errcode='23505'; end if;
    select version into current_version from public.units where id=entity_id for update;
    if p_expected_version=0 then
      if found then select to_jsonb(u) into saved from public.units u where u.id=entity_id;
        if current_version=1 and saved->>'name'=entity_name and saved->>'abbreviation'=abbreviation_value and saved->>'dimension'=dim and saved->>'base_unit_id' is not distinct from base_id::text and (saved->>'equivalence_multiplier')::numeric is not distinct from mult and saved->>'active'=active_value::text and saved->>'is_deleted'=deleted_value::text then return saved; end if;
        raise exception 'La unidad ya existe con cambios; recargá el catálogo.' using errcode='40001'; end if;
      insert into public.units(id,name,normalized_name,abbreviation,dimension,base_unit_id,equivalence_multiplier,active,is_deleted) values(entity_id,entity_name,normalized,abbreviation_value,dim,base_id,mult,active_value,deleted_value) returning to_jsonb(units.*) into saved;
    else
      if not found or current_version<>p_expected_version then raise exception 'La unidad cambió; recargá el catálogo.' using errcode='40001'; end if;
      select to_jsonb(u) into saved from public.units u where u.id=entity_id;
      if saved->>'name'=entity_name and saved->>'abbreviation'=abbreviation_value and saved->>'dimension'=dim and saved->>'base_unit_id' is not distinct from base_id::text and (saved->>'equivalence_multiplier')::numeric is not distinct from mult and saved->>'active'=active_value::text and saved->>'is_deleted'=deleted_value::text then return saved; end if;
      if exists(select 1 from public.units u where u.id<>entity_id and not u.is_deleted and u.normalized_name=normalized) then raise exception 'Nombre de unidad duplicado.' using errcode='23505'; end if;
      if (abbreviation_value is distinct from saved->>'abbreviation' or dim is distinct from saved->>'dimension' or base_id is distinct from nullif(saved->>'base_unit_id','')::uuid or mult is distinct from (saved->>'equivalence_multiplier')::numeric)
        and (exists(select 1 from public.recipe_ingredients r where r.unit_id=entity_id)
          or exists(select 1 from public.pantry_items p where p.unit_ref=entity_id or p.unit_ref is null and p.unit=saved->>'abbreviation')
          or exists(select 1 from public.shopping_items s where s.unit_id=entity_id)
          or exists(select 1 from public.cooking_sessions cs cross join lateral jsonb_array_elements(case when jsonb_typeof(cs.recipe_snapshot->'ingredients')='array' then cs.recipe_snapshot->'ingredients' else '[]'::jsonb end) as item(value) where item.value->>'unitId'=entity_id::text or item.value->>'unitRootId'=entity_id::text)
          or exists(select 1 from public.cooking_events ce cross join lateral jsonb_array_elements(case when jsonb_typeof(ce.recipe_snapshot->'ingredients')='array' then ce.recipe_snapshot->'ingredients' else '[]'::jsonb end) as item(value) where item.value->>'unitId'=entity_id::text or item.value->>'unitRootId'=entity_id::text)) then
        raise exception 'No se puede cambiar la conversión de una unidad referenciada.' using errcode='23514';
      end if;
      if exists(select 1 from public.ingredients i where i.base_unit_id=entity_id) and (dim is distinct from (select dimension from public.units where id=entity_id) or base_id is not null) then raise exception 'No se puede cambiar la dimensión o raíz de una unidad usada como base.' using errcode='23514'; end if;
      if exists(select 1 from public.units child where child.base_unit_id=entity_id) and (dim is distinct from (select dimension from public.units where id=entity_id) or base_id is not null) then raise exception 'La unidad tiene equivalencias dependientes.' using errcode='23514'; end if;
      update public.units set name=entity_name,normalized_name=normalized,abbreviation=abbreviation_value,dimension=dim,base_unit_id=base_id,equivalence_multiplier=mult,active=active_value,is_deleted=deleted_value,updated_at=clock_timestamp(),version=version+1 where id=entity_id returning to_jsonb(units.*) into saved;
    end if;
  else
    audit_action := 'catalog.ingredient_saved';
    if jsonb_typeof(p_entity->'category_id') is distinct from 'string' or jsonb_typeof(p_entity->'base_unit_id') is distinct from 'string' then raise exception 'Faltan categoría y unidad base.' using errcode='22023'; end if;
    category_id:=(p_entity->>'category_id')::uuid; unit_id:=(p_entity->>'base_unit_id')::uuid;
    select version into current_version from public.ingredients where id=entity_id for update;
    if p_expected_version=0 then
      if found then select to_jsonb(i) into saved from public.ingredients i where i.id=entity_id;
        if current_version=1 and saved->>'name'=entity_name and saved->>'category_id'=category_id::text and saved->>'base_unit_id'=unit_id::text and saved->>'active'=active_value::text and saved->>'is_deleted'=deleted_value::text then return saved; end if;
        raise exception 'El ingrediente ya existe con cambios; recargá el catálogo.' using errcode='40001'; end if;
      if not exists(select 1 from public.categories where id=category_id and active and not is_deleted) or not exists(select 1 from public.units where id=unit_id and active and not is_deleted and base_unit_id is null) then raise exception 'Categoría o unidad base no disponible.' using errcode='22023'; end if;
      insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id,active,is_deleted) values(entity_id,entity_name,normalized,category_id,unit_id,active_value,deleted_value) returning to_jsonb(ingredients.*) into saved;
    else
      if not found or current_version<>p_expected_version then raise exception 'El ingrediente cambió; recargá el catálogo.' using errcode='40001'; end if;
      select to_jsonb(i) into saved from public.ingredients i where i.id=entity_id;
      if saved->>'name'=entity_name and saved->>'category_id'=category_id::text and saved->>'base_unit_id'=unit_id::text and saved->>'active'=active_value::text and saved->>'is_deleted'=deleted_value::text then return saved; end if;
      if unit_id is distinct from nullif(saved->>'base_unit_id','')::uuid
        and (exists(select 1 from public.pantry_items p where p.ingredient_ref=entity_id)
          or exists(select 1 from public.recipe_ingredients r where r.ingredient_id=entity_id)
          or exists(select 1 from public.shopping_items s where s.ingredient_id=entity_id)) then
        raise exception 'No se puede cambiar la unidad base de un ingrediente referenciado.' using errcode='23514';
      end if;
      if not exists(select 1 from public.categories where id=category_id and (active and not is_deleted or id=(select i.category_id from public.ingredients i where i.id=entity_id))) or not exists(select 1 from public.units where id=unit_id and dimension=(select dimension from public.units where id=(select i.base_unit_id from public.ingredients i where i.id=entity_id)) and base_unit_id is null and (active and not is_deleted or id=(select i.base_unit_id from public.ingredients i where i.id=entity_id))) then raise exception 'Categoría o unidad base no disponible.' using errcode='22023'; end if;
      update public.ingredients set name=entity_name,normalized_name=normalized,category_id=category_id,base_unit_id=unit_id,active=active_value,is_deleted=deleted_value,updated_at=clock_timestamp(),version=version+1 where id=entity_id returning to_jsonb(ingredients.*) into saved;
    end if;
  end if;
  insert into public.admin_audit_log(actor_user_id,action,details) values(actor,audit_action,jsonb_build_object('entity_id',entity_id,'version',(saved->>'version')::bigint));
  return saved;
exception when unique_violation then raise exception 'Ya existe un elemento del catálogo con ese nombre o identificador.' using errcode='23505';
when data_exception or check_violation or not_null_violation or foreign_key_violation then raise exception 'Los datos del catálogo no son válidos.' using errcode='22023';
end;
$$;
revoke all on function public.admin_put_catalog_entity(text,jsonb,bigint) from public,anon;

create function public.admin_put_category(p_entity jsonb,p_expected_version bigint) returns jsonb language sql volatile security definer set search_path='' as $$ select public.admin_put_catalog_entity('category',p_entity,p_expected_version) $$;
create function public.admin_put_unit(p_entity jsonb,p_expected_version bigint) returns jsonb language sql volatile security definer set search_path='' as $$ select public.admin_put_catalog_entity('unit',p_entity,p_expected_version) $$;
create function public.admin_put_ingredient(p_entity jsonb,p_expected_version bigint) returns jsonb language sql volatile security definer set search_path='' as $$ select public.admin_put_catalog_entity('ingredient',p_entity,p_expected_version) $$;
revoke all on function public.admin_put_category(jsonb,bigint),public.admin_put_unit(jsonb,bigint),public.admin_put_ingredient(jsonb,bigint) from public,anon;
grant execute on function public.admin_put_category(jsonb,bigint),public.admin_put_unit(jsonb,bigint),public.admin_put_ingredient(jsonb,bigint) to authenticated;

revoke insert,update,delete on public.categories,public.units,public.ingredients from public,anon,authenticated;
grant select on public.categories,public.units,public.ingredients to authenticated;

-- Staged from 202611010001_recipe_admin_rpcs.sql inside the rehearsal transaction.
-- Relational official recipes get optimistic versions. The default preserves
-- old importers and backfills that do not know about versions.
alter table public.recipes add column version bigint not null default 1 check (version > 0);

-- Open cooking sessions pin the recipe version at insert. The existing start
-- RPC already holds a FOR SHARE lock on the recipe parent, so this value is
-- consistent with its immutable snapshot; old closed sessions stay untouched.
create or replace function public.pin_open_cooking_recipe_version()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.finished_at is null and new.recipe_id is not null then
    select r.version::integer into new.recipe_version from public.recipes r where r.id=new.recipe_id;
  end if;
  return new;
end;
$$;
revoke all on function public.pin_open_cooking_recipe_version() from public, anon, authenticated;
create trigger pin_open_cooking_recipe_version_before_insert
before insert on public.cooking_sessions
for each row execute function public.pin_open_cooking_recipe_version();

create table public.admin_recipe_write_state (
  recipe_id uuid primary key references public.recipes(id) on delete cascade,
  create_payload jsonb check (create_payload is null or jsonb_typeof(create_payload) = 'object'),
  last_payload jsonb check (last_payload is null or jsonb_typeof(last_payload) = 'object'),
  last_version bigint,
  duplicate_source_id uuid,
  duplicate_source_version bigint
);
alter table public.admin_recipe_write_state enable row level security;
revoke all on public.admin_recipe_write_state from public, anon, authenticated;

alter table public.admin_audit_log drop constraint if exists admin_audit_log_action_check;
alter table public.admin_audit_log add constraint admin_audit_log_action_check check (action in (
  'user.created','user.name_updated','user.role_changed','user.activated','user.deactivated',
  'catalog.core_saved','catalog.recipes_saved','catalog.category_saved','catalog.unit_saved','catalog.ingredient_saved',
  'catalog.recipe_saved','catalog.recipe_duplicated','catalog.recipe_flags_changed'
));

create or replace function public.admin_save_recipe(p_recipe_id uuid, p_recipe jsonb, p_expected_version bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid(); v_old public.recipes; v_out jsonb; v_new_version bigint;
  v_title text; v_author text; v_description text; v_category text; v_minutes integer;
  v_preparation integer; v_cooking integer; v_portions integer; v_difficulty text; v_calories numeric;
  v_status text; v_active boolean; v_featured boolean; v_symbol text; v_color text;
  v_cross_note text; v_image text; v_image_alt text;
  v_ingredient jsonb; v_step jsonb; v_ref jsonb; v_i integer; v_j integer;
  v_ing_id uuid; v_unit_id uuid; v_step_id uuid; v_ing_row_id uuid; v_tag_id uuid;
  v_qty numeric; v_override numeric;
begin
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if v_actor is null or not public.current_account_is_active() or public.current_app_role() <> 'ADMIN' then
    raise exception 'Solo un administrador activo puede modificar recetas.' using errcode='42501';
  end if;
  perform public.lock_my_relational_account();
  if p_recipe_id is null or p_expected_version is null or p_expected_version < 0 or jsonb_typeof(p_recipe) is distinct from 'object' then
    raise exception 'La solicitud de receta no es válida.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_object_keys(p_recipe) k where k not in
    ('title','author','description','category_label','meal_shifts','total_minutes','preparation_minutes','cooking_minutes','portions','difficulty','calories_per_portion','dietary_tags','featured','symbol','color','cross_contamination_note','image_path','image_alt','publication_status','active','ingredients','steps')) then
    raise exception 'La receta contiene campos no permitidos.' using errcode='22023';
  end if;
  if jsonb_typeof(p_recipe->'title') is distinct from 'string' or jsonb_typeof(p_recipe->'author') is distinct from 'string'
    or jsonb_typeof(p_recipe->'description') is distinct from 'string' or jsonb_typeof(p_recipe->'category_label') is distinct from 'string'
    or jsonb_typeof(p_recipe->'total_minutes') is distinct from 'number' or jsonb_typeof(p_recipe->'portions') is distinct from 'number'
    or jsonb_typeof(p_recipe->'difficulty') is distinct from 'string' or jsonb_typeof(p_recipe->'publication_status') is distinct from 'string'
    or jsonb_typeof(p_recipe->'active') is distinct from 'boolean' or jsonb_typeof(p_recipe->'featured') is distinct from 'boolean'
    or jsonb_typeof(p_recipe->'meal_shifts') is distinct from 'array' or jsonb_typeof(p_recipe->'dietary_tags') is distinct from 'array'
    or jsonb_typeof(p_recipe->'ingredients') is distinct from 'array' or jsonb_typeof(p_recipe->'steps') is distinct from 'array' then
    raise exception 'Faltan datos requeridos o hay tipos inválidos.' using errcode='22023';
  end if;
  v_title := regexp_replace(trim(p_recipe->>'title'), '\s+', ' ', 'g');
  v_author := p_recipe->>'author'; v_description := p_recipe->>'description'; v_category := p_recipe->>'category_label';
  v_minutes := (p_recipe->>'total_minutes')::integer; v_portions := (p_recipe->>'portions')::integer;
  v_difficulty := p_recipe->>'difficulty'; v_status := p_recipe->>'publication_status'; v_active := (p_recipe->>'active')::boolean;
  v_featured := (p_recipe->>'featured')::boolean;
  if jsonb_typeof(p_recipe->'preparation_minutes') not in ('number','null') and p_recipe ? 'preparation_minutes' then raise exception 'Tiempo de preparación inválido.' using errcode='22023'; end if;
  if jsonb_typeof(p_recipe->'cooking_minutes') not in ('number','null') and p_recipe ? 'cooking_minutes' then raise exception 'Tiempo de cocción inválido.' using errcode='22023'; end if;
  if jsonb_typeof(p_recipe->'calories_per_portion') not in ('number','null') and p_recipe ? 'calories_per_portion' then raise exception 'Calorías inválidas.' using errcode='22023'; end if;
  if p_recipe ? 'symbol' and jsonb_typeof(p_recipe->'symbol') is distinct from 'string' or p_recipe ? 'color' and jsonb_typeof(p_recipe->'color') is distinct from 'string'
    or p_recipe ? 'image_path' and jsonb_typeof(p_recipe->'image_path') not in ('string','null') or p_recipe ? 'image_alt' and jsonb_typeof(p_recipe->'image_alt') not in ('string','null')
    or p_recipe ? 'cross_contamination_note' and jsonb_typeof(p_recipe->'cross_contamination_note') not in ('string','null') then raise exception 'Metadatos inválidos.' using errcode='22023'; end if;
  v_preparation := case when jsonb_typeof(p_recipe->'preparation_minutes')='number' then (p_recipe->>'preparation_minutes')::integer end;
  v_cooking := case when jsonb_typeof(p_recipe->'cooking_minutes')='number' then (p_recipe->>'cooking_minutes')::integer end;
  v_calories := case when jsonb_typeof(p_recipe->'calories_per_portion')='number' then (p_recipe->>'calories_per_portion')::numeric end;
  v_symbol := coalesce(p_recipe->>'symbol',''); v_color := coalesce(p_recipe->>'color','green');
  v_image := nullif(p_recipe->>'image_path',''); v_image_alt := nullif(p_recipe->>'image_alt','');
  v_cross_note := p_recipe->>'cross_contamination_note';
  if (p_recipe->>'total_minutes')::numeric<>trunc((p_recipe->>'total_minutes')::numeric)
    or (p_recipe->>'portions')::numeric<>trunc((p_recipe->>'portions')::numeric)
    or jsonb_typeof(p_recipe->'preparation_minutes')='number' and (p_recipe->>'preparation_minutes')::numeric<>trunc((p_recipe->>'preparation_minutes')::numeric)
    or jsonb_typeof(p_recipe->'cooking_minutes')='number' and (p_recipe->>'cooking_minutes')::numeric<>trunc((p_recipe->>'cooking_minutes')::numeric)
    or length(v_title) not between 1 and 180 or length(v_author)>180 or length(v_description)>10000 or length(v_category)>120 or length(v_symbol)>80
    or v_minutes not between 1 and 1440 or v_portions not between 1 and 100 or v_difficulty not in ('easy','intermediate','advanced')
    or v_status not in ('draft','published') or v_color not in ('green','gold','pink','blue') or v_calories < 0
    or v_preparation < 0 or v_cooking < 0 or cardinality(array(select jsonb_array_elements_text(p_recipe->'meal_shifts'))) not between 1 and 4
    or jsonb_array_length(p_recipe->'ingredients') not between 1 and 200 or jsonb_array_length(p_recipe->'steps') not between 1 and 100
    or (v_image is not null and v_image_alt is null) or length(v_image)>500 or length(v_image_alt)>500 or length(v_cross_note)>2000 then
    raise exception 'La receta tiene valores fuera de rango.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_recipe->'meal_shifts') x where jsonb_typeof(x) <> 'string' or x #>> '{}' not in ('breakfast','lunch','snack','dinner'))
    or exists(select 1 from (select value, count(*) over(partition by value) n from jsonb_array_elements_text(p_recipe->'meal_shifts') value) q where n>1) then
    raise exception 'Los turnos de comida no son válidos.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_recipe->'dietary_tags') x where jsonb_typeof(x) <> 'string' or length(x #>> '{}') not between 2 and 50) then
    raise exception 'Las etiquetas dietarias no son válidas.' using errcode='22023';
  end if;
  if exists(select 1 from (select value,count(*) over(partition by value) n from jsonb_array_elements_text(p_recipe->'dietary_tags') value) q where n>1) then
    raise exception 'Las etiquetas dietarias no pueden repetirse.' using errcode='22023';
  end if;
  if p_expected_version > 0 then
    select * into v_old from public.recipes r where r.id=p_recipe_id for update;
    if not found or v_old.recipe_source <> 'official' or v_old.owner_user_id is not null then raise exception 'La receta oficial no existe.' using errcode='42501'; end if;
    if v_old.version <> p_expected_version then raise exception 'La receta cambió; recargá los datos.' using errcode='40001'; end if;
    if exists(select 1 from public.admin_recipe_write_state q where q.recipe_id=p_recipe_id and q.last_version=v_old.version and q.last_payload=p_recipe) then
      return public.admin_recipe_export(p_recipe_id);
    end if;
  else
    perform 1 from public.recipes r where r.id=p_recipe_id for update;
    if found then
      if exists(select 1 from public.admin_recipe_write_state q where q.recipe_id=p_recipe_id and q.create_payload=p_recipe)
        and exists(select 1 from public.recipes r where r.id=p_recipe_id and r.recipe_source='official' and r.owner_user_id is null and r.version=1) then
        return public.admin_recipe_export(p_recipe_id);
      end if;
      raise exception 'La receta ya existe con otros datos.' using errcode='40001';
    end if;
  end if;
  if exists(select 1 from public.recipes r where r.id<>p_recipe_id and r.recipe_source='official' and r.owner_user_id is null and not r.is_deleted
    and lower(regexp_replace(regexp_replace(normalize(trim(r.title),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))
      =lower(regexp_replace(regexp_replace(normalize(trim(v_title),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))) then
    raise exception 'Ya existe una receta con ese título.' using errcode='23505';
  end if;
  -- All catalog references are checked before mutating the parent/children.
  for v_ingredient in select value from jsonb_array_elements(p_recipe->'ingredients') loop
    if jsonb_typeof(v_ingredient) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v_ingredient) k where k not in ('ingredient_id','quantity','unit_id','note'))
      or jsonb_typeof(v_ingredient->'ingredient_id') is distinct from 'string' or jsonb_typeof(v_ingredient->'unit_id') is distinct from 'string'
      or jsonb_typeof(v_ingredient->'quantity') is distinct from 'number' or v_ingredient ? 'note' and jsonb_typeof(v_ingredient->'note') is distinct from 'string' then raise exception 'Ingrediente de receta inválido.' using errcode='22023'; end if;
    v_ing_id := (v_ingredient->>'ingredient_id')::uuid; v_unit_id := (v_ingredient->>'unit_id')::uuid; v_qty := (v_ingredient->>'quantity')::numeric;
    if v_qty<=0 or v_qty>1000000 or v_qty<>round(v_qty,4) or length(coalesce(v_ingredient->>'note',''))>500
      or not exists(select 1 from public.ingredients i join public.units base on base.id=i.base_unit_id join public.units useu on useu.id=v_unit_id join public.categories c on c.id=i.category_id
        where i.id=v_ing_id and not i.is_deleted and not base.is_deleted and not useu.is_deleted
        and base.dimension=useu.dimension and coalesce(useu.base_unit_id,useu.id)=base.id
        and ((i.active and base.active and useu.active and c.active and not c.is_deleted) or (p_expected_version>0 and exists(
          select 1 from public.recipe_ingredients oldri where oldri.recipe_id=p_recipe_id and oldri.ingredient_id=i.id and oldri.unit_id=useu.id)))) then
      raise exception 'Ingrediente o unidad incompatible/inactiva.' using errcode='22023';
    end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(p_recipe->'dietary_tags') tag where not exists(select 1 from public.dietary_tags t where t.tag_key=tag #>> '{}' and t.active)) then raise exception 'Etiqueta dietaria inactiva o inexistente.' using errcode='22023'; end if;
  if p_expected_version=0 then
    insert into public.recipes(id,owner_user_id,recipe_source,title,author,description,category_label,total_minutes,preparation_minutes,cooking_minutes,portions,difficulty,calories_per_portion,publication_status,active,is_deleted,featured,symbol,color,cross_contamination_note,image_path,image_alt)
    values(p_recipe_id,null,'official',v_title,v_author,v_description,v_category,v_minutes,v_preparation,v_cooking,v_portions,v_difficulty,v_calories,v_status,v_active,false,v_featured,v_symbol,v_color,v_cross_note,v_image,v_image_alt);
    insert into public.admin_recipe_write_state(recipe_id,create_payload,last_payload,last_version) values(p_recipe_id,p_recipe,p_recipe,1);
  else
    update public.recipes set title=v_title,author=v_author,description=v_description,category_label=v_category,total_minutes=v_minutes,preparation_minutes=v_preparation,cooking_minutes=v_cooking,portions=v_portions,difficulty=v_difficulty,calories_per_portion=v_calories,publication_status=v_status,active=case when v_old.is_deleted then false else v_active end,featured=v_featured,symbol=v_symbol,color=v_color,cross_contamination_note=v_cross_note,image_path=v_image,image_alt=v_image_alt,updated_at=clock_timestamp(),version=version+1 where id=p_recipe_id returning version into v_new_version;
    insert into public.admin_recipe_write_state(recipe_id,last_payload,last_version) values(p_recipe_id,p_recipe,v_new_version)
      on conflict(recipe_id) do update set last_payload=excluded.last_payload,last_version=excluded.last_version;
  end if;
  delete from public.recipe_meal_shifts where recipe_id=p_recipe_id;
  delete from public.recipe_dietary_tags where recipe_id=p_recipe_id;
  delete from public.recipe_ingredients where recipe_id=p_recipe_id;
  delete from public.recipe_steps where recipe_id=p_recipe_id;
  for v_i in 1..jsonb_array_length(p_recipe->'meal_shifts') loop
    insert into public.recipe_meal_shifts(recipe_id,meal_shift) values(p_recipe_id,p_recipe->'meal_shifts'->>(v_i-1));
  end loop;
  for v_ingredient in select value from jsonb_array_elements(p_recipe->'dietary_tags') loop
    select id into v_tag_id from public.dietary_tags where tag_key=v_ingredient #>> '{}';
    insert into public.recipe_dietary_tags(recipe_id,dietary_tag_id) values(p_recipe_id,v_tag_id);
  end loop;
  v_i:=0;
  for v_ingredient in select value from jsonb_array_elements(p_recipe->'ingredients') loop
    v_i:=v_i+1;
    insert into public.recipe_ingredients(recipe_id,ingredient_id,quantity,unit_id,note,position)
    values(p_recipe_id,(v_ingredient->>'ingredient_id')::uuid,(v_ingredient->>'quantity')::numeric,(v_ingredient->>'unit_id')::uuid,coalesce(v_ingredient->>'note',''),v_i);
  end loop;
  v_i:=0;
  for v_step in select value from jsonb_array_elements(p_recipe->'steps') loop
    v_i:=v_i+1;
    if jsonb_typeof(v_step) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v_step) k where k not in ('instruction','duration_minutes','temperature','tip','warning','utensils','special_instructions','ingredients'))
      or jsonb_typeof(v_step->'instruction') is distinct from 'string' or length(trim(v_step->>'instruction')) not between 1 and 5000
      or v_step ? 'duration_minutes' and jsonb_typeof(v_step->'duration_minutes') not in ('number','null')
      or v_step ? 'utensils' and jsonb_typeof(v_step->'utensils') is distinct from 'array'
      or v_step ? 'ingredients' and jsonb_typeof(v_step->'ingredients') is distinct from 'array' then raise exception 'Paso de receta inválido.' using errcode='22023'; end if;
    if v_step ? 'duration_minutes' and v_step->>'duration_minutes' is not null and (((v_step->>'duration_minutes')::numeric<>trunc((v_step->>'duration_minutes')::numeric) or (v_step->>'duration_minutes')::integer not between 0 and 1440)) then raise exception 'Duración de paso inválida.' using errcode='22023'; end if;
    if (v_step ? 'temperature' and jsonb_typeof(v_step->'temperature') not in ('string','null'))
      or (v_step ? 'tip' and jsonb_typeof(v_step->'tip') not in ('string','null'))
      or (v_step ? 'warning' and jsonb_typeof(v_step->'warning') not in ('string','null'))
      or (v_step ? 'special_instructions' and jsonb_typeof(v_step->'special_instructions') not in ('string','null'))
      or length(coalesce(v_step->>'temperature',''))>80 or length(coalesce(v_step->>'tip',''))>240
      or length(coalesce(v_step->>'warning',''))>240 or length(coalesce(v_step->>'special_instructions',''))>400
      or (v_step ? 'utensils' and (jsonb_array_length(v_step->'utensils')>30 or exists(select 1 from jsonb_array_elements(v_step->'utensils') u where jsonb_typeof(u)<>'string' or length(u #>> '{}')>80))) then
      raise exception 'Los metadatos del paso están fuera de rango.' using errcode='22023';
    end if;
    insert into public.recipe_steps(recipe_id,position,instruction,duration_minutes,temperature,tip,warning,utensils,special_instructions)
    values(p_recipe_id,v_i,v_step->>'instruction',nullif(v_step->>'duration_minutes','')::integer,nullif(v_step->>'temperature',''),nullif(v_step->>'tip',''),nullif(v_step->>'warning',''),coalesce(array(select jsonb_array_elements_text(coalesce(v_step->'utensils','[]'::jsonb))),'{}'),nullif(v_step->>'special_instructions','')) returning id into v_step_id;
    if jsonb_typeof(v_step->'ingredients')='array' then
      for v_ref in select value from jsonb_array_elements(v_step->'ingredients') loop
        if jsonb_typeof(v_ref) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v_ref) k where k not in ('ingredient_position','quantity_override'))
          or jsonb_typeof(v_ref->'ingredient_position') is distinct from 'number' or v_ref ? 'quantity_override' and jsonb_typeof(v_ref->'quantity_override') not in ('number','null') then raise exception 'Referencia de ingrediente de paso inválida.' using errcode='22023'; end if;
        if (v_ref->>'ingredient_position')::numeric<>trunc((v_ref->>'ingredient_position')::numeric) then raise exception 'Posición de ingrediente inválida.' using errcode='22023'; end if;
        v_j:=(v_ref->>'ingredient_position')::integer;
        select id into v_ing_row_id from public.recipe_ingredients where recipe_id=p_recipe_id and position=v_j;
        if v_ing_row_id is null then raise exception 'Referencia de ingrediente inexistente.' using errcode='22023'; end if;
        v_override:=nullif(v_ref->>'quantity_override','')::numeric;
        if v_override is not null and (v_override<=0 or v_override>1000000 or v_override<>round(v_override,4)) then raise exception 'Cantidad de paso inválida.' using errcode='22023'; end if;
        insert into public.recipe_step_ingredients(step_id,recipe_ingredient_id,quantity_override) values(v_step_id,v_ing_row_id,v_override);
      end loop;
    end if;
  end loop;
  insert into public.admin_audit_log(actor_user_id,action,details) values(v_actor,'catalog.recipe_saved',jsonb_build_object('entity_id',p_recipe_id,'version',case when p_expected_version=0 then 1 else v_new_version end));
  return public.admin_recipe_export(p_recipe_id);
exception when unique_violation then raise exception 'Ya existe una receta con ese título o identificador.' using errcode='23505';
when data_exception or check_violation or not_null_violation or foreign_key_violation then raise exception 'Los datos de la receta no son válidos.' using errcode='22023';
end;
$$;

create or replace function public.admin_recipe_export(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
select to_jsonb(r) || jsonb_build_object(
 'ingredients',coalesce((select jsonb_agg(jsonb_build_object('ingredient_id',i.ingredient_id,'quantity',i.quantity,'unit_id',i.unit_id,'note',i.note,'position',i.position) order by i.position) from public.recipe_ingredients i where i.recipe_id=r.id),'[]'::jsonb),
 'steps',coalesce((select jsonb_agg(jsonb_build_object('instruction',s.instruction,'duration_minutes',s.duration_minutes,'temperature',s.temperature,'tip',s.tip,'warning',s.warning,'utensils',s.utensils,'special_instructions',s.special_instructions,'ingredients',coalesce((select jsonb_agg(jsonb_build_object('ingredient_position',ri.position,'quantity_override',si.quantity_override) order by ri.position) from public.recipe_step_ingredients si join public.recipe_ingredients ri on ri.id=si.recipe_ingredient_id where si.step_id=s.id),'[]'::jsonb)) order by s.position) from public.recipe_steps s where s.recipe_id=r.id),'[]'::jsonb),
 'meal_shifts',coalesce((select jsonb_agg(ms.meal_shift order by ms.meal_shift) from public.recipe_meal_shifts ms where ms.recipe_id=r.id),'[]'::jsonb),
 'dietary_tags',coalesce((select jsonb_agg(t.tag_key order by t.tag_key) from public.recipe_dietary_tags dt join public.dietary_tags t on t.id=dt.dietary_tag_id where dt.recipe_id=r.id),'[]'::jsonb),
 'category_label',r.category_label,'total_minutes',r.total_minutes,'calories_per_portion',r.calories_per_portion,'publication_status',r.publication_status,'image_path',r.image_path,'image_alt',r.image_alt,'cross_contamination_note',r.cross_contamination_note)
from public.recipes r where r.id=p_id and r.recipe_source='official' and r.owner_user_id is null;
$$;

-- Duplicate target ids are idempotency keys; provenance persists independently
-- of source edits, so retry always resolves to the same draft.
create or replace function public.admin_duplicate_recipe(p_source_id uuid,p_target_id uuid,p_expected_version bigint default 0)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_source public.recipes; v_payload jsonb; v_result jsonb; v_copy_number integer:=1; v_copy_title text; v_copy_prefix text;
begin
  perform pg_catalog.pg_advisory_xact_lock(74539,1);
  if auth.uid() is null or not public.current_account_is_active() or public.current_app_role()<>'ADMIN' then raise exception 'Solo un administrador activo puede duplicar recetas.' using errcode='42501'; end if;
  perform public.lock_my_relational_account();
  if p_source_id is null or p_target_id is null or p_source_id=p_target_id or p_expected_version is distinct from 0 then raise exception 'Solicitud de duplicación inválida.' using errcode='22023'; end if;
  select * into v_source from public.recipes where id=p_source_id for update;
  if not found or v_source.recipe_source<>'official' or v_source.owner_user_id is not null then raise exception 'La receta oficial no existe.' using errcode='42501'; end if;
  if exists(select 1 from public.admin_recipe_write_state d where d.recipe_id=p_target_id and d.duplicate_source_id is not null) then
    if exists(select 1 from public.admin_recipe_write_state d where d.recipe_id=p_target_id and d.duplicate_source_id=p_source_id) then return public.admin_recipe_export(p_target_id); end if;
    raise exception 'El identificador de duplicación ya fue usado.' using errcode='40001';
  end if;
  if exists(select 1 from public.recipes where id=p_target_id) then raise exception 'El identificador de duplicación ya fue usado.' using errcode='40001'; end if;
  v_payload:=public.admin_recipe_export(p_source_id);
  v_payload:=v_payload || jsonb_build_object('publication_status','draft','active',true,'featured',false);
  -- Reserve a unique title with the frontend's normalized copy sequence.
  loop
    v_copy_prefix:=case when v_copy_number=1 then 'Copia de ' else 'Copia '||v_copy_number::text||' de ' end;
    v_copy_title:=v_copy_prefix||left(v_source.title,180-char_length(v_copy_prefix));
    exit when not exists(select 1 from public.recipes r where r.recipe_source='official' and r.owner_user_id is null and not r.is_deleted
      and lower(regexp_replace(regexp_replace(trim(normalize(r.title,NFD)),U&'[\0300-\036f]','','g'),'\s+',' ','g'))
        =lower(regexp_replace(regexp_replace(trim(normalize(v_copy_title,NFD)),U&'[\0300-\036f]','','g'),'\s+',' ','g')));
    v_copy_number:=v_copy_number+1;
  end loop;
  if v_copy_number>100000 then raise exception 'No se pudo reservar un título de copia.' using errcode='23505'; end if;
  v_payload:=jsonb_set(v_payload,'{title}',to_jsonb(v_copy_title));
  -- Convert exported DB names and row objects into the save RPC input shape.
  v_payload:=jsonb_build_object('title',v_payload->>'title','author',v_payload->>'author','description',v_payload->>'description','category_label',v_payload->>'category_label','meal_shifts',v_payload->'meal_shifts','total_minutes',v_payload->'total_minutes','preparation_minutes',v_payload->'preparation_minutes','cooking_minutes',v_payload->'cooking_minutes','portions',v_payload->'portions','difficulty',v_payload->'difficulty','calories_per_portion',v_payload->'calories_per_portion','dietary_tags',v_payload->'dietary_tags','featured',false,'symbol',v_payload->'symbol','color',v_payload->'color','cross_contamination_note',v_payload->'cross_contamination_note','image_path',v_payload->'image_path','image_alt',v_payload->'image_alt','publication_status','draft','active',true,
   'ingredients',(select jsonb_agg(jsonb_build_object('ingredient_id',x->'ingredient_id','quantity',x->'quantity','unit_id',x->'unit_id','note',x->'note') order by (x->>'position')::integer) from jsonb_array_elements(v_payload->'ingredients') x),
   'steps',(select jsonb_agg(jsonb_build_object('instruction',x->'instruction','duration_minutes',x->'duration_minutes','temperature',x->'temperature','tip',x->'tip','warning',x->'warning','utensils',x->'utensils','special_instructions',x->'special_instructions','ingredients',x->'ingredients') order by n) from jsonb_array_elements(v_payload->'steps') with ordinality q(x,n)));
  v_result:=public.admin_save_recipe(p_target_id,v_payload,0);
  update public.admin_recipe_write_state set duplicate_source_id=p_source_id,duplicate_source_version=v_source.version where recipe_id=p_target_id;
  update public.admin_audit_log e set action='catalog.recipe_duplicated'
    where e.id=(select e2.id from public.admin_audit_log e2 where e2.actor_user_id=auth.uid() and e2.action='catalog.recipe_saved'
      and e2.details->>'entity_id'=p_target_id::text and e2.occurred_at>=transaction_timestamp() order by e2.occurred_at desc,e2.id desc limit 1);
  return v_result;
end;
$$;

create or replace function public.admin_set_recipe_flags(p_recipe_id uuid,p_expected_version bigint,p_active boolean default null,p_featured boolean default null,p_archived boolean default null,p_restored boolean default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_row public.recipes; v_deleted boolean; v_desired_active boolean; v_desired_featured boolean;
begin
  perform pg_catalog.pg_advisory_xact_lock(74539,1);
  if auth.uid() is null or not public.current_account_is_active() or public.current_app_role()<>'ADMIN' then raise exception 'Solo un administrador activo puede cambiar recetas.' using errcode='42501'; end if;
  perform public.lock_my_relational_account();
  if p_recipe_id is null or p_expected_version is null or p_expected_version<=0
    or p_archived is true and p_restored is true or p_archived is false and p_restored is not true
    or p_active is true and (p_archived is true or p_restored is not true and p_archived is null) then
    raise exception 'Solicitud de estado inválida.' using errcode='22023';
  end if;
  select * into v_row from public.recipes where id=p_recipe_id for update;
  if not found or v_row.recipe_source<>'official' or v_row.owner_user_id is not null then raise exception 'La receta oficial no existe.' using errcode='42501'; end if;
  if v_row.version<>p_expected_version then raise exception 'La receta cambió; recargá los datos.' using errcode='40001'; end if;
  v_deleted:=case when p_restored is true then false when p_archived is true then true else v_row.is_deleted end;
  if v_row.is_deleted and not v_deleted and exists(select 1 from public.recipes other_recipe
    where other_recipe.id<>p_recipe_id and other_recipe.recipe_source='official' and other_recipe.owner_user_id is null and not other_recipe.is_deleted
      and lower(regexp_replace(regexp_replace(normalize(trim(other_recipe.title),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))
        =lower(regexp_replace(regexp_replace(normalize(trim(v_row.title),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))) then
    raise exception 'Ya existe una receta con ese título.' using errcode='23505';
  end if;
  v_desired_active:=case when v_deleted then false when p_active is not null then p_active when p_restored is true then true else v_row.active end;
  v_desired_featured:=coalesce(p_featured,v_row.featured);
  if v_desired_active=v_row.active and v_desired_featured=v_row.featured and v_deleted=v_row.is_deleted then return public.admin_recipe_export(p_recipe_id); end if;
  update public.recipes set active=v_desired_active,featured=v_desired_featured,is_deleted=v_deleted,updated_at=clock_timestamp(),version=version+1 where id=p_recipe_id;
  insert into public.admin_audit_log(actor_user_id,action,details) values(auth.uid(),'catalog.recipe_flags_changed',jsonb_build_object('entity_id',p_recipe_id,'version',p_expected_version+1));
  return public.admin_recipe_export(p_recipe_id);
end;
$$;

revoke all on function public.admin_save_recipe(uuid,jsonb,bigint),public.admin_duplicate_recipe(uuid,uuid,bigint),public.admin_set_recipe_flags(uuid,bigint,boolean,boolean,boolean,boolean),public.admin_recipe_export(uuid) from public,anon,authenticated;
grant execute on function public.admin_save_recipe(uuid,jsonb,bigint),public.admin_duplicate_recipe(uuid,uuid,bigint),public.admin_set_recipe_flags(uuid,bigint,boolean,boolean,boolean,boolean) to authenticated;

-- Staged from 202611010002_dietary_admin_rpcs.sql inside the rehearsal transaction.
-- Dietary tags have stable keys because recipes and user preferences refer to
-- them. Ingredient links use the existing ingredient version as their write token.
alter table public.dietary_tags add column version bigint not null default 1 check (version > 0);

alter table public.admin_audit_log drop constraint if exists admin_audit_log_action_check;
alter table public.admin_audit_log add constraint admin_audit_log_action_check check (action in (
  'user.created','user.name_updated','user.role_changed','user.activated','user.deactivated',
  'catalog.core_saved','catalog.recipes_saved','catalog.category_saved','catalog.unit_saved','catalog.ingredient_saved',
  'catalog.recipe_saved','catalog.recipe_duplicated','catalog.recipe_flags_changed',
  'catalog.dietary_tag_saved','catalog.ingredient_dietary_tags_saved'
));

create or replace function public.admin_put_dietary_tag(p_tag jsonb, p_expected_version bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_variable
declare
  v_actor uuid := (select auth.uid());
  v_id uuid;
  v_tag_key text;
  v_label text;
  v_description text;
  v_active boolean;
  v_version bigint;
  v_saved jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if v_actor is null or not (select public.current_account_is_active())
    or (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo un administrador activo puede modificar el catálogo.' using errcode='42501';
  end if;
  perform public.lock_my_relational_account();

  if jsonb_typeof(p_tag) is distinct from 'object' or p_expected_version is null or p_expected_version < 0
    or exists(select 1 from jsonb_object_keys(p_tag) k where k not in ('id','tag_key','label','description','active'))
    or jsonb_typeof(p_tag->'id') is distinct from 'string'
    or jsonb_typeof(p_tag->'tag_key') is distinct from 'string'
    or jsonb_typeof(p_tag->'label') is distinct from 'string'
    or jsonb_typeof(p_tag->'description') is distinct from 'string'
    or jsonb_typeof(p_tag->'active') is distinct from 'boolean' then
    raise exception 'La solicitud de etiqueta dietaria no es válida.' using errcode='22023';
  end if;
  v_id := (p_tag->>'id')::uuid;
  v_tag_key := p_tag->>'tag_key';
  v_label := regexp_replace(trim(p_tag->>'label'), '\s+', ' ', 'g');
  v_description := p_tag->>'description';
  v_active := (p_tag->>'active')::boolean;
  if v_tag_key !~ '^[a-z0-9-]{2,50}$' or length(v_label) not between 1 and 80 or length(v_description)>2000 then
    raise exception 'Los datos de la etiqueta dietaria están fuera de rango.' using errcode='22023';
  end if;

  select t.version into v_version from public.dietary_tags t where t.id=v_id for update;
  if p_expected_version=0 then
    if found then
      select jsonb_build_object('id',t.id,'tag_key',t.tag_key,'label',t.label,'description',t.description,'active',t.active,'version',t.version)
        into v_saved from public.dietary_tags t where t.id=v_id;
      if v_version=1 and v_saved->>'tag_key'=v_tag_key and v_saved->>'label'=v_label
        and v_saved->>'description'=v_description and v_saved->>'active'=v_active::text then return v_saved; end if;
      raise exception 'La etiqueta ya existe con cambios; recargá el catálogo.' using errcode='40001';
    end if;
    insert into public.dietary_tags(id,tag_key,label,description,active)
      values(v_id,v_tag_key,v_label,v_description,v_active) returning version into v_version;
  else
    if not found or v_version<>p_expected_version then
      raise exception 'La etiqueta cambió; recargá el catálogo.' using errcode='40001';
    end if;
    select jsonb_build_object('id',t.id,'tag_key',t.tag_key,'label',t.label,'description',t.description,'active',t.active,'version',t.version)
      into v_saved from public.dietary_tags t where t.id=v_id;
    if v_saved->>'tag_key' is distinct from v_tag_key then
      raise exception 'La clave de una etiqueta dietaria es inmutable.' using errcode='22023';
    end if;
    if v_saved->>'label'=v_label and v_saved->>'description'=v_description and v_saved->>'active'=v_active::text then return v_saved; end if;
    update public.dietary_tags set label=v_label,description=v_description,active=v_active,
      updated_at=clock_timestamp(),version=version+1 where id=v_id returning version into v_version;
  end if;
  select jsonb_build_object('id',t.id,'tag_key',t.tag_key,'label',t.label,'description',t.description,'active',t.active,'version',t.version)
    into v_saved from public.dietary_tags t where t.id=v_id;
  insert into public.admin_audit_log(actor_user_id,action,details)
    values(v_actor,'catalog.dietary_tag_saved',jsonb_build_object('entity_id',v_id,'version',v_version));
  return v_saved;
exception
  when unique_violation then raise exception 'Ya existe una etiqueta dietaria con esa clave o identificador.' using errcode='23505';
  when data_exception or check_violation or not_null_violation or foreign_key_violation then
    raise exception 'Los datos de la etiqueta dietaria no son válidos.' using errcode='22023';
end;
$$;
revoke all on function public.admin_put_dietary_tag(jsonb,bigint) from public,anon;
grant execute on function public.admin_put_dietary_tag(jsonb,bigint) to authenticated;

create or replace function public.admin_save_ingredient_dietary_tags(p_ingredient_id uuid,p_tags jsonb,p_expected_version bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_variable
declare
  v_actor uuid := (select auth.uid());
  v_ingredient public.ingredients;
  v_tag jsonb;
  v_key text;
  v_compatibility text;
  v_note text;
  v_tag_id uuid;
  v_changed boolean := false;
  v_new_version bigint;
  v_result jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if v_actor is null or not (select public.current_account_is_active())
    or (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo un administrador activo puede modificar el catálogo.' using errcode='42501';
  end if;
  perform public.lock_my_relational_account();
  if p_ingredient_id is null or p_expected_version is null or p_expected_version<1
    or jsonb_typeof(p_tags) is distinct from 'array' or jsonb_array_length(p_tags)>100 then
    raise exception 'La solicitud de etiquetas del ingrediente no es válida.' using errcode='22023';
  end if;

  select i.* into v_ingredient from public.ingredients i where i.id=p_ingredient_id for update;
  if not found or v_ingredient.version<>p_expected_version then
    raise exception 'El ingrediente cambió o no existe; recargá el catálogo.' using errcode='40001';
  end if;

  for v_tag in select value from jsonb_array_elements(p_tags) loop
    if jsonb_typeof(v_tag) is distinct from 'object'
      or exists(select 1 from jsonb_object_keys(v_tag) k where k not in ('tag_key','compatibility','note'))
      or jsonb_typeof(v_tag->'tag_key') is distinct from 'string'
      or jsonb_typeof(v_tag->'compatibility') is distinct from 'string'
      or jsonb_typeof(v_tag->'note') is distinct from 'string' then
      raise exception 'Una etiqueta del ingrediente no es válida.' using errcode='22023';
    end if;
    v_key:=v_tag->>'tag_key'; v_compatibility:=v_tag->>'compatibility'; v_note:=v_tag->>'note';
    if v_key !~ '^[a-z0-9-]{2,50}$' or v_compatibility not in ('suitable','contains','unknown') or length(v_note)>1000 then
      raise exception 'Una etiqueta del ingrediente está fuera de rango.' using errcode='22023';
    end if;
    if (select count(*) from jsonb_array_elements(p_tags) x where x->>'tag_key'=v_key)>1 then
      raise exception 'Las etiquetas del ingrediente no pueden repetirse.' using errcode='22023';
    end if;
    select t.id into v_tag_id from public.dietary_tags t where t.tag_key=v_key and t.active;
    if v_tag_id is null then
      if not exists(select 1 from public.ingredient_dietary_tags it join public.dietary_tags t on t.id=it.dietary_tag_id
        where it.ingredient_id=p_ingredient_id and t.tag_key=v_key and it.compatibility=v_compatibility and it.note=v_note) then
        raise exception 'Etiqueta dietaria inactiva o inexistente.' using errcode='22023';
      end if;
    end if;
    if (not v_ingredient.active or v_ingredient.is_deleted) and not exists(
      select 1 from public.ingredient_dietary_tags it join public.dietary_tags t on t.id=it.dietary_tag_id
      where it.ingredient_id=p_ingredient_id and t.tag_key=v_key and it.compatibility=v_compatibility and it.note=v_note) then
      raise exception 'Un ingrediente inactivo solo admite conservar o quitar sus etiquetas.' using errcode='22023';
    end if;
  end loop;

  select exists(
    (select t.tag_key,it.compatibility,it.note from public.ingredient_dietary_tags it join public.dietary_tags t on t.id=it.dietary_tag_id where it.ingredient_id=p_ingredient_id
      except select x->>'tag_key',x->>'compatibility',x->>'note' from jsonb_array_elements(p_tags) x)
    union all
    (select x->>'tag_key',x->>'compatibility',x->>'note' from jsonb_array_elements(p_tags) x
      except select t.tag_key,it.compatibility,it.note from public.ingredient_dietary_tags it join public.dietary_tags t on t.id=it.dietary_tag_id where it.ingredient_id=p_ingredient_id)
  ) into v_changed;
  if not v_changed then
    select coalesce(jsonb_agg(jsonb_build_object('tag_key',t.tag_key,'compatibility',it.compatibility,'note',it.note) order by t.tag_key),'[]'::jsonb)
      into v_result from public.ingredient_dietary_tags it join public.dietary_tags t on t.id=it.dietary_tag_id where it.ingredient_id=p_ingredient_id;
    return jsonb_build_object('ingredient_id',p_ingredient_id,'version',v_ingredient.version,'tags',v_result);
  end if;

  delete from public.ingredient_dietary_tags it where it.ingredient_id=p_ingredient_id;
  for v_tag in select value from jsonb_array_elements(p_tags) loop
    select t.id into v_tag_id from public.dietary_tags t where t.tag_key=v_tag->>'tag_key';
    insert into public.ingredient_dietary_tags(ingredient_id,dietary_tag_id,compatibility,note)
      values(p_ingredient_id,v_tag_id,v_tag->>'compatibility',v_tag->>'note');
  end loop;
  update public.ingredients set version=version+1,updated_at=clock_timestamp() where id=p_ingredient_id returning version into v_new_version;
  select coalesce(jsonb_agg(jsonb_build_object('tag_key',t.tag_key,'compatibility',it.compatibility,'note',it.note) order by t.tag_key),'[]'::jsonb)
    into v_result from public.ingredient_dietary_tags it join public.dietary_tags t on t.id=it.dietary_tag_id where it.ingredient_id=p_ingredient_id;
  insert into public.admin_audit_log(actor_user_id,action,details)
    values(v_actor,'catalog.ingredient_dietary_tags_saved',jsonb_build_object('entity_id',p_ingredient_id,'version',v_new_version));
  return jsonb_build_object('ingredient_id',p_ingredient_id,'version',v_new_version,'tags',v_result);
exception
  when unique_violation then raise exception 'Las etiquetas del ingrediente no pueden repetirse.' using errcode='23505';
  when data_exception or check_violation or not_null_violation or foreign_key_violation then
    raise exception 'Los datos de las etiquetas del ingrediente no son válidos.' using errcode='22023';
end;
$$;
revoke all on function public.admin_save_ingredient_dietary_tags(uuid,jsonb,bigint) from public,anon;
grant execute on function public.admin_save_ingredient_dietary_tags(uuid,jsonb,bigint) to authenticated;

revoke insert,update,delete on public.dietary_tags,public.ingredient_dietary_tags from public,anon,authenticated;
grant select on public.dietary_tags,public.ingredient_dietary_tags to authenticated;

-- Staged from 202611010003_nutrition_config_rpcs.sql inside the rehearsal transaction.
-- Nutrition configuration is an informational, versioned singleton. Values are
-- supplied by an administrator and are deliberately not seeded here.
alter table public.admin_audit_log drop constraint if exists admin_audit_log_action_check;
alter table public.admin_audit_log add constraint admin_audit_log_action_check check (action in (
  'user.created','user.name_updated','user.role_changed','user.activated','user.deactivated',
  'catalog.core_saved','catalog.recipes_saved','catalog.category_saved','catalog.unit_saved','catalog.ingredient_saved',
  'catalog.recipe_saved','catalog.recipe_duplicated','catalog.recipe_flags_changed',
  'catalog.dietary_tag_saved','catalog.ingredient_dietary_tags_saved','nutrition.config_published'
));

create policy nutrition_config_admin_read_all on public.nutrition_config for select to authenticated
  using ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()));

create function public.prevent_nutrition_config_rewrite()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.updated_by is not null and new.updated_by is null
    and new.config_version is not distinct from old.config_version
    and new.activity_factors is not distinct from old.activity_factors
    and new.goal_adjustments is not distinct from old.goal_adjustments
    and new.source_note is not distinct from old.source_note
    and new.effective_at is not distinct from old.effective_at
    and new.created_at is not distinct from old.created_at then
    return new;
  end if;
  raise exception 'Las versiones de configuración nutricional son inmutables.' using errcode='42501';
end;
$$;
revoke all on function public.prevent_nutrition_config_rewrite() from public,anon,authenticated;
create trigger nutrition_config_immutable_rows
  before update or delete on public.nutrition_config
  for each row execute function public.prevent_nutrition_config_rewrite();

create function public.admin_publish_nutrition_config(p_config jsonb, p_expected_latest_version integer)
returns public.nutrition_config
language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_variable
declare
  v_actor uuid := (select auth.uid());
  v_version integer;
  v_latest integer;
  v_activity jsonb;
  v_goals jsonb;
  v_note text;
  v_effective_at timestamptz;
  v_activity_key text;
  v_goal_key text;
  v_goal jsonb;
  v_number numeric;
  v_bound numeric;
  v_saved public.nutrition_config;
begin
  -- All admin mutations use the catalog lock before personal-account locks.
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if v_actor is null or not (select public.current_account_is_active())
    or (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo un administrador activo puede publicar la configuración.' using errcode='42501';
  end if;
  perform public.lock_my_relational_account();

  if p_expected_latest_version is null or p_expected_latest_version < 0
    or jsonb_typeof(p_config) is distinct from 'object'
    or exists(select 1 from jsonb_object_keys(p_config) k where k not in ('activity_factors','goal_adjustments','source_note','effective_at'))
    or jsonb_typeof(p_config->'activity_factors') is distinct from 'object'
    or jsonb_typeof(p_config->'goal_adjustments') is distinct from 'object'
    or jsonb_typeof(p_config->'source_note') is distinct from 'string'
    or jsonb_typeof(p_config->'effective_at') is distinct from 'string' then
    raise exception 'La configuración nutricional no es válida.' using errcode='22023';
  end if;

  v_activity := p_config->'activity_factors';
  v_goals := p_config->'goal_adjustments';
  v_note := p_config->>'source_note';
  if length(trim(v_note)) not between 1 and 2000
    or (select count(*) from jsonb_object_keys(v_activity)) <> 5
    or exists(select 1 from jsonb_object_keys(v_activity) k where k not in ('sedentary','light','moderate','active','very-active'))
    or (select count(*) from jsonb_object_keys(v_goals)) <> 4
    or exists(select 1 from jsonb_object_keys(v_goals) k where k not in ('lose','maintain','gain','gain-muscle')) then
    raise exception 'La configuración nutricional no es válida.' using errcode='22023';
  end if;

  foreach v_activity_key in array array['sedentary','light','moderate','active','very-active'] loop
    if jsonb_typeof(v_activity->v_activity_key) is distinct from 'number' then
      raise exception 'La configuración nutricional no es válida.' using errcode='22023';
    end if;
    v_number := (v_activity->>v_activity_key)::numeric;
    if v_number <= 0 or v_number > 10 or scale(v_number) > 6 then
      raise exception 'La configuración nutricional no es válida.' using errcode='22023';
    end if;
  end loop;

  foreach v_goal_key in array array['lose','maintain','gain','gain-muscle'] loop
    v_goal := v_goals->v_goal_key;
    if jsonb_typeof(v_goal) is distinct from 'object'
      or (select count(*) from jsonb_object_keys(v_goal)) <> 2
      or exists(select 1 from jsonb_object_keys(v_goal) k where k not in ('minimum','maximum'))
      or jsonb_typeof(v_goal->'minimum') is distinct from 'number'
      or jsonb_typeof(v_goal->'maximum') is distinct from 'number' then
      raise exception 'La configuración nutricional no es válida.' using errcode='22023';
    end if;
    v_number := (v_goal->>'minimum')::numeric;
    v_bound := (v_goal->>'maximum')::numeric;
    if v_number <> trunc(v_number) or v_bound <> trunc(v_bound)
      or v_number < -10000 or v_number > 10000 or v_bound < -10000 or v_bound > 10000 or v_number > v_bound then
      raise exception 'La configuración nutricional no es válida.' using errcode='22023';
    end if;
  end loop;

  -- Require an explicit, timezone-bearing ISO value so retries preserve the
  -- originally requested effective date instead of inheriting a new default.
  if p_config->>'effective_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
    raise exception 'La configuración nutricional no es válida.' using errcode='22023';
  end if;
  v_effective_at := (p_config->>'effective_at')::timestamptz;
  if not isfinite(v_effective_at) then
    raise exception 'La configuración nutricional no es válida.' using errcode='22023';
  end if;

  v_version := p_expected_latest_version + 1;
  -- Slot comparison precedes latest-version validation for retry idempotency.
  select n.* into v_saved from public.nutrition_config n where n.config_version=v_version;
  if found then
    if v_saved.activity_factors=v_activity and v_saved.goal_adjustments=v_goals
      and v_saved.source_note=v_note and v_saved.effective_at=v_effective_at and v_saved.updated_by=v_actor then
      return v_saved;
    end if;
    raise exception 'La versión solicitada ya existe con otros datos; recargá la configuración.' using errcode='40001';
  end if;
  select max(n.config_version) into v_latest from public.nutrition_config n;
  if coalesce(v_latest,0) <> p_expected_latest_version then
    raise exception 'La configuración cambió; recargá antes de publicar.' using errcode='40001';
  end if;

  insert into public.nutrition_config(config_version,activity_factors,goal_adjustments,source_note,effective_at,updated_by)
    values(v_version,v_activity,v_goals,v_note,v_effective_at,v_actor) returning * into v_saved;
  insert into public.admin_audit_log(actor_user_id,action,details)
    values(v_actor,'nutrition.config_published',jsonb_build_object('version',v_version,'effective_at',v_effective_at));
  return v_saved;
exception
  when serialization_failure or deadlock_detected then raise;
  when data_exception or check_violation or not_null_violation or foreign_key_violation then
    raise exception 'La configuración nutricional no es válida.' using errcode='22023';
end;
$$;
revoke all on function public.admin_publish_nutrition_config(jsonb,integer) from public,anon;
grant execute on function public.admin_publish_nutrition_config(jsonb,integer) to authenticated;

create function public.get_current_nutrition_config()
returns public.nutrition_config
language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_variable
declare
  v_actor uuid := (select auth.uid());
  v_saved public.nutrition_config;
begin
  if v_actor is null or not (select public.current_account_is_active()) then
    raise exception 'Se requiere una cuenta activa.' using errcode='42501';
  end if;
  perform public.lock_my_relational_account();
  select n.* into v_saved from public.nutrition_config n
    where n.effective_at <= statement_timestamp()
    order by n.effective_at desc,n.config_version desc limit 1;
  if not found then return null; end if;
  return v_saved;
end;
$$;
revoke all on function public.get_current_nutrition_config() from public,anon;
grant execute on function public.get_current_nutrition_config() to authenticated;

create function public.admin_list_nutrition_configs()
returns setof public.nutrition_config
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform public.lock_my_relational_account();
  if (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo un administrador activo puede consultar las versiones.' using errcode='42501';
  end if;
  return query select n.* from public.nutrition_config n order by n.config_version desc;
end;
$$;
revoke all on function public.admin_list_nutrition_configs() from public,anon;
grant execute on function public.admin_list_nutrition_configs() to authenticated;

revoke insert,update,delete on public.nutrition_config from public,anon,authenticated;
grant select on public.nutrition_config to authenticated;


-- Staged from 202611010004_recipe_discovery_rpcs.sql inside the rehearsal transaction.
-- Authenticated discovery returns only public published recipes and the caller's
-- own private recipes, including when the caller has an administrative role.
create function public.search_my_recipes(
  p_search text default null,
  p_meal_shift text default null,
  p_max_minutes integer default null,
  p_difficulty text default null,
  p_dietary_tag_keys text[] default '{}',
  p_pantry_only boolean default false,
  p_portions integer default null,
  p_limit integer default 30,
  p_offset integer default 0
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid; needle text; shift_key text; row_recipe public.recipes; stock jsonb;
  stock_error boolean; item jsonb; items jsonb := '[]'::jsonb; total_count integer;
  result_total integer;
  passed integer := 0; scanned integer := 0;
begin
  actor := public.lock_my_relational_account();
  if p_search is not null and (length(p_search)>120 or length(trim(p_search))=0) then
    raise exception 'El texto de búsqueda no es válido.' using errcode='22023';
  end if;
  if p_meal_shift is not null and p_meal_shift not in ('breakfast','lunch','snack','dinner') then
    raise exception 'El momento de comida no es válido.' using errcode='22023';
  end if;
  if p_max_minutes is not null and p_max_minutes not between 1 and 1440 then raise exception 'El tiempo máximo no es válido.' using errcode='22023'; end if;
  if p_difficulty is not null and p_difficulty not in ('easy','intermediate','advanced') then raise exception 'La dificultad no es válida.' using errcode='22023'; end if;
  if p_portions is not null and p_portions not between 1 and 20 then raise exception 'Las porciones no son válidas.' using errcode='22023'; end if;
  if p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 5000
    or p_dietary_tag_keys is null or cardinality(p_dietary_tag_keys)>20
    or exists(select 1 from unnest(p_dietary_tag_keys) k where k is null or k !~ '^[a-z0-9-]{2,50}$')
    or (select count(distinct k) from unnest(p_dietary_tag_keys) k) <> cardinality(p_dietary_tag_keys)
    or p_pantry_only is null then raise exception 'Los filtros o la página no son válidos.' using errcode='22023'; end if;
  needle := nullif(lower(regexp_replace(regexp_replace(normalize(trim(p_search),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')), '');
  shift_key := p_meal_shift;

  -- Keep filtering before pagination. Pantry-only applies the stock RPC to a
  -- bounded candidate set and refuses ambiguous oversized queries.
  if p_pantry_only then
    for row_recipe in
      select r.* from public.recipes r
      where r.active and not r.is_deleted
        and ((r.recipe_source='official' and r.publication_status='published') or r.owner_user_id=actor)
        and (shift_key is null or exists(select 1 from public.recipe_meal_shifts ms where ms.recipe_id=r.id and ms.meal_shift=shift_key))
        and (p_max_minutes is null or r.total_minutes<=p_max_minutes)
        and (p_difficulty is null or r.difficulty=p_difficulty)
        and (needle is null or strpos(lower(regexp_replace(regexp_replace(normalize(r.title,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0
          or strpos(lower(regexp_replace(regexp_replace(normalize(r.description,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0
          or exists(select 1 from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id
            where ri.recipe_id=r.id and strpos(lower(regexp_replace(regexp_replace(normalize(i.name,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0))
        and (cardinality(p_dietary_tag_keys)=0 or (select count(distinct t.tag_key)
          from public.recipe_dietary_tags rt join public.dietary_tags t on t.id=rt.dietary_tag_id
          where rt.recipe_id=r.id and t.active and t.tag_key=any(p_dietary_tag_keys))=cardinality(p_dietary_tag_keys))
      order by lower(r.title),r.id limit 501
    loop
      scanned := scanned+1;
      if scanned>500 then raise exception 'Hay demasiadas recetas candidatas; agregá filtros.' using errcode='22023'; end if;
      stock_error := false;
      begin
        stock := public.check_my_cooking_stock(row_recipe.id,coalesce(p_portions,row_recipe.portions),null);
      exception when sqlstate '22023' then stock_error := true; stock := null;
      end;
      if not stock_error and jsonb_array_length(coalesce(stock->'ingredients','[]'::jsonb))>0
        and coalesce((stock->>'sufficient')::boolean,false) then
        passed := passed+1;
        if passed>p_offset and passed<=p_offset+p_limit then
          item := public.recipe_discovery_payload(row_recipe,stock);
          items := items||jsonb_build_array(item);
        end if;
      end if;
    end loop;
    total_count := passed;
  else
    select count(*)::integer into total_count from public.recipes r
      where r.active and not r.is_deleted
        and ((r.recipe_source='official' and r.publication_status='published') or r.owner_user_id=actor)
        and (shift_key is null or exists(select 1 from public.recipe_meal_shifts ms where ms.recipe_id=r.id and ms.meal_shift=shift_key))
        and (p_max_minutes is null or r.total_minutes<=p_max_minutes)
        and (p_difficulty is null or r.difficulty=p_difficulty)
        and (needle is null or strpos(lower(regexp_replace(regexp_replace(normalize(r.title,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0
          or strpos(lower(regexp_replace(regexp_replace(normalize(r.description,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0
          or exists(select 1 from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id
            where ri.recipe_id=r.id and strpos(lower(regexp_replace(regexp_replace(normalize(i.name,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0))
        and (cardinality(p_dietary_tag_keys)=0 or (select count(distinct t.tag_key)
          from public.recipe_dietary_tags rt join public.dietary_tags t on t.id=rt.dietary_tag_id
          where rt.recipe_id=r.id and t.active and t.tag_key=any(p_dietary_tag_keys))=cardinality(p_dietary_tag_keys));
    for row_recipe in
      select r.* from public.recipes r
      where r.active and not r.is_deleted
        and ((r.recipe_source='official' and r.publication_status='published') or r.owner_user_id=actor)
        and (shift_key is null or exists(select 1 from public.recipe_meal_shifts ms where ms.recipe_id=r.id and ms.meal_shift=shift_key))
        and (p_max_minutes is null or r.total_minutes<=p_max_minutes)
        and (p_difficulty is null or r.difficulty=p_difficulty)
        and (needle is null or strpos(lower(regexp_replace(regexp_replace(normalize(r.title,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0
          or strpos(lower(regexp_replace(regexp_replace(normalize(r.description,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0
          or exists(select 1 from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id
            where ri.recipe_id=r.id and strpos(lower(regexp_replace(regexp_replace(normalize(i.name,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0))
        and (cardinality(p_dietary_tag_keys)=0 or (select count(distinct t.tag_key)
          from public.recipe_dietary_tags rt join public.dietary_tags t on t.id=rt.dietary_tag_id
          where rt.recipe_id=r.id and t.active and t.tag_key=any(p_dietary_tag_keys))=cardinality(p_dietary_tag_keys))
      order by lower(r.title),r.id offset p_offset limit p_limit
    loop
      stock_error := false;
      begin
        stock := public.check_my_cooking_stock(row_recipe.id,coalesce(p_portions,row_recipe.portions),null);
      exception when sqlstate '22023' then stock_error := true; stock := null;
      end;
      item := public.recipe_discovery_payload(row_recipe,case when stock_error then null else stock end);
      items := items||jsonb_build_array(item);
    end loop;
  end if;
  result_total := total_count;
  return jsonb_build_object('items',items,'total',result_total,'limit',p_limit,'offset',p_offset);
end; $$;

-- Shared payload formatter keeps the list and pantry-only paths consistent.
create function public.recipe_discovery_payload(p_recipe public.recipes,p_stock jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare n integer; ready integer; pct integer; label text; recipe_json jsonb;
begin
  select coalesce(jsonb_agg(t.tag_key order by t.tag_key),'[]'::jsonb) into recipe_json
    from public.recipe_dietary_tags rt join public.dietary_tags t on t.id=rt.dietary_tag_id where rt.recipe_id=p_recipe.id;
  recipe_json := to_jsonb(p_recipe)||jsonb_build_object(
    'meal_shifts',coalesce((select jsonb_agg(ms.meal_shift order by ms.meal_shift) from public.recipe_meal_shifts ms where ms.recipe_id=p_recipe.id),'[]'::jsonb),
    'dietary_tags',recipe_json,
    'ingredients',coalesce((select jsonb_agg(jsonb_build_object('id',ri.id,'ingredient_id',i.id,'name',i.name,'quantity',ri.quantity,'unit_id',u.id,'unit',u.abbreviation,'note',ri.note,'position',ri.position) order by ri.position)
      from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id join public.units u on u.id=ri.unit_id where ri.recipe_id=p_recipe.id),'[]'::jsonb),
    'steps',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'position',s.position,'instruction',s.instruction,'duration_minutes',s.duration_minutes,'temperature',s.temperature,'tip',s.tip,'warning',s.warning,'utensils',to_jsonb(s.utensils),'special_instructions',s.special_instructions,
        'ingredients',coalesce((select jsonb_agg(jsonb_build_object('recipe_ingredient_id',ri.id,'ingredient_position',ri.position,'quantity_override',si.quantity_override) order by ri.position)
          from public.recipe_step_ingredients si join public.recipe_ingredients ri on ri.id=si.recipe_ingredient_id where si.step_id=s.id),'[]'::jsonb)) order by s.position)
      from public.recipe_steps s where s.recipe_id=p_recipe.id),'[]'::jsonb));
  if p_stock is null then pct:=null; label:='Disponibilidad no calculable';
  else
    select count(*)::integer,count(*) filter(where (x->>'sufficient')::boolean)::integer into n,ready from jsonb_array_elements(coalesce(p_stock->'ingredients','[]'::jsonb)) x;
    pct:=case when coalesce(n,0)=0 then 0 when ready=n then 100 else least(99,round(ready::numeric/n*100)::integer) end;
    label:=case when pct=100 then 'Lista para cocinar' when coalesce(ready,0)::numeric/nullif(n,0)>=0.6 then 'Casi lista' else 'Requiere compra' end;
  end if;
  return jsonb_build_object('recipe',recipe_json,'stock',p_stock,'percentage',pct,'label',label);
end; $$;

create function public.get_my_recipe_trends(p_days integer default 30,p_limit integer default 10)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor:=public.lock_my_relational_account();
  if p_days is null or p_days not between 1 and 365 or p_limit is null or p_limit not between 1 and 50 then
    raise exception 'El período o límite de tendencias no es válido.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('recipeId',recipe_id,'cookCount',cook_count,'lastCookedAt',last_cooked_at)
    order by cook_count desc,recipe_id),'[]'::jsonb) into result from (
      select e.recipe_id,count(*)::integer cook_count,max(e.cooked_at) last_cooked_at
      from public.cooking_events e join public.recipes r on r.id=e.recipe_id
      where e.owner_user_id=actor and e.hidden_at is null and e.cooked_at>=now()-make_interval(days=>p_days)
        and r.active and not r.is_deleted
        and ((r.recipe_source='official' and r.publication_status='published') or r.owner_user_id=actor)
      group by e.recipe_id order by count(*) desc,e.recipe_id limit p_limit
    ) ranked;
  return jsonb_build_object('days',p_days,'items',result);
end; $$;

-- DATA_MODEL.md permits aggregate trends over public recipes. No user identity,
-- private recipe, or individual event data leaves this RPC.
create function public.get_recipe_trends(p_days integer default 30,p_limit integer default 10)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor:=public.lock_my_relational_account();
  if p_days is null or p_days not between 1 and 365 or p_limit is null or p_limit not between 1 and 50 then
    raise exception 'El período o límite de tendencias no es válido.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('recipeId',ranked.id,'cookCount',ranked.cook_count,'featured',ranked.featured)
    order by ranked.cook_count desc,ranked.featured desc,ranked.id),'[]'::jsonb) into result
  from (select r.id,coalesce(e.cook_count,0)::integer cook_count,r.featured
    from public.recipes r left join (
      select ev.recipe_id,count(*)::integer cook_count from public.cooking_events ev
      where ev.hidden_at is null and ev.cooked_at>=now()-make_interval(days=>p_days)
      group by ev.recipe_id
    ) e on e.recipe_id=r.id
    where r.recipe_source='official' and r.publication_status='published' and r.active and not r.is_deleted
    order by coalesce(e.cook_count,0) desc,r.featured desc,r.id limit p_limit) ranked;
  return jsonb_build_object('days',p_days,'items',result);
end; $$;

revoke all on function public.search_my_recipes(text,text,integer,text,text[],boolean,integer,integer,integer),
  public.recipe_discovery_payload(public.recipes,jsonb),public.get_my_recipe_trends(integer,integer),
  public.get_recipe_trends(integer,integer) from public,anon;
revoke all on function public.recipe_discovery_payload(public.recipes,jsonb) from authenticated;
grant execute on function public.search_my_recipes(text,text,integer,text,text[],boolean,integer,integer,integer),
  public.get_my_recipe_trends(integer,integer),public.get_recipe_trends(integer,integer) to authenticated;

-- Staged from 202611010005_external_request_rpcs.sql inside the rehearsal transaction.
create index recipe_generation_requests_expiry_idx on public.recipe_generation_requests(expires_at,id);
create index receipt_recognition_requests_expiry_idx on public.receipt_recognition_requests(expires_at,id);

-- External request rows retain only lifecycle metadata. Payloads, prompts, images,
-- provider responses, and OCR text belong outside this table.
create or replace function public._lock_external_request_owner(p_owner uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La operación no es válida.' using errcode='25000';
  end if;
  if p_owner is null then raise exception 'La cuenta no está activa.' using errcode='42501'; end if;
  -- Match the account writer order: global role/status coordination, actor lock,
  -- then Auth and account status rows. Do not use auth.uid() for service actors.
  perform pg_catalog.pg_advisory_xact_lock_shared(74539, 1);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.personal:' || p_owner::text, 0));
  perform 1 from auth.users where id=p_owner for share;
  if not found then raise exception 'La cuenta no está activa.' using errcode='42501'; end if;
  perform 1 from public.account_status where user_id=p_owner for share;
  if not exists (
    select 1 from auth.users u left join public.account_status s on s.user_id=u.id
    where u.id=p_owner and coalesce(s.active,true)
      and (u.banned_until is null or u.banned_until<=pg_catalog.clock_timestamp())
  ) then raise exception 'La cuenta no está activa.' using errcode='42501'; end if;
end;
$$;
revoke all on function public._lock_external_request_owner(uuid) from public, anon, authenticated, service_role;

create or replace function public.begin_external_request(
  p_owner uuid, p_request uuid, p_kind text, p_provider_model text default null
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_found boolean; v_owner uuid; v_status text; v_model text; v_error text; v_created timestamptz; v_expires timestamptz; v_now timestamptz;
begin
  if p_kind is null or p_kind not in ('recipe','receipt') or p_request is null
    or (p_kind='receipt' and p_provider_model is not null)
    or (p_provider_model is not null and (length(p_provider_model)>120 or p_provider_model !~ '^[A-Za-z0-9][A-Za-z0-9._:/+-]{0,119}$')) then
    raise exception 'La solicitud no es válida.' using errcode='22023';
  end if;
  perform public._lock_external_request_owner(p_owner);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.external-request:' || p_request::text, 0));
  v_now:=pg_catalog.clock_timestamp();
  if (p_kind='recipe' and exists(select 1 from public.receipt_recognition_requests where id=p_request))
    or (p_kind='receipt' and exists(select 1 from public.recipe_generation_requests where id=p_request)) then
    raise exception 'La solicitud cambió; iniciá otra solicitud.' using errcode='40001';
  end if;
  if p_kind='recipe' then
    insert into public.recipe_generation_requests(id,owner_user_id,status,provider_model,created_at,expires_at)
      values(p_request,p_owner,'pending',p_provider_model,v_now,v_now+interval '24 hours')
      on conflict(id) do nothing;
    select true,r.owner_user_id,r.status,r.provider_model,r.safe_error_code,r.created_at,r.expires_at
      into v_found,v_owner,v_status,v_model,v_error,v_created,v_expires from public.recipe_generation_requests r where r.id=p_request for update;
  else
    insert into public.receipt_recognition_requests(id,owner_user_id,status,created_at,expires_at)
      values(p_request,p_owner,'pending',v_now,v_now+interval '1 hour')
      on conflict(id) do nothing;
    select true,r.owner_user_id,r.status,null::text,r.safe_error_code,r.created_at,r.expires_at
      into v_found,v_owner,v_status,v_model,v_error,v_created,v_expires from public.receipt_recognition_requests r where r.id=p_request for update;
  end if;
  if not coalesce(v_found,false) or v_owner<>p_owner then raise exception 'La solicitud cambió; iniciá otra solicitud.' using errcode='40001'; end if;
  if v_model is distinct from (case when p_kind='recipe' then p_provider_model else null end) then
    raise exception 'La solicitud cambió; iniciá otra solicitud.' using errcode='40001';
  end if;
  if v_status='pending' and v_expires<=pg_catalog.clock_timestamp() then
    if p_kind='recipe' then update public.recipe_generation_requests set status='expired',safe_error_code=null where id=p_request;
    else update public.receipt_recognition_requests set status='expired',safe_error_code=null where id=p_request; end if;
    v_status:='expired'; v_error:=null;
  end if;
  return pg_catalog.jsonb_build_object('id',p_request,'kind',p_kind,'status',v_status,'provider_model',v_model,'safe_error_code',v_error,'created_at',v_created,'expires_at',v_expires);
end;
$$;

create or replace function public.finish_external_request(
  p_owner uuid, p_request uuid, p_kind text, p_status text, p_safe_error_code text default null
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_owner uuid; v_status text; v_error text; v_expires timestamptz;
begin
  if p_kind is null or p_kind not in ('recipe','receipt') or p_request is null or p_status is null or p_status not in ('completed','failed')
    or (p_safe_error_code is not null and p_safe_error_code not in ('provider_unavailable','provider_timeout','provider_rejected','invalid_provider_response','rate_limited','internal_error'))
    or (p_status='completed' and p_safe_error_code is not null)
    or (p_status='failed' and p_safe_error_code is null) then
    raise exception 'La solicitud no es válida.' using errcode='22023';
  end if;
  perform public._lock_external_request_owner(p_owner);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.external-request:' || p_request::text, 0));
  if (p_kind='recipe' and exists(select 1 from public.receipt_recognition_requests where id=p_request))
    or (p_kind='receipt' and exists(select 1 from public.recipe_generation_requests where id=p_request)) then
    raise exception 'La solicitud no existe.' using errcode='P0002';
  end if;
  if p_kind='recipe' then
    select r.owner_user_id,r.status,r.safe_error_code,r.expires_at into v_owner,v_status,v_error,v_expires from public.recipe_generation_requests r where r.id=p_request for update;
  else
    select r.owner_user_id,r.status,r.safe_error_code,r.expires_at into v_owner,v_status,v_error,v_expires from public.receipt_recognition_requests r where r.id=p_request for update;
  end if;
  if not found or v_owner<>p_owner then raise exception 'La solicitud no existe.' using errcode='P0002'; end if;
  if v_status='expired' then
    return pg_catalog.jsonb_build_object('id',p_request,'kind',p_kind,'status','expired','safe_error_code',null);
  end if;
  if v_expires<=pg_catalog.clock_timestamp() and v_status='pending' then
    if p_kind='recipe' then update public.recipe_generation_requests set status='expired',safe_error_code=null where id=p_request and status='pending';
    else update public.receipt_recognition_requests set status='expired',safe_error_code=null where id=p_request and status='pending'; end if;
    return pg_catalog.jsonb_build_object('id',p_request,'kind',p_kind,'status','expired','safe_error_code',null);
  end if;
  if v_status in ('completed','failed') and v_status=p_status and v_error is not distinct from p_safe_error_code then
    return pg_catalog.jsonb_build_object('id',p_request,'kind',p_kind,'status',v_status,'safe_error_code',v_error);
  end if;
  if v_status<>'pending' then raise exception 'La solicitud ya tiene un resultado distinto.' using errcode='40001'; end if;
  if p_kind='recipe' then update public.recipe_generation_requests set status=p_status,safe_error_code=p_safe_error_code where id=p_request;
  else update public.receipt_recognition_requests set status=p_status,safe_error_code=p_safe_error_code where id=p_request; end if;
  return pg_catalog.jsonb_build_object('id',p_request,'kind',p_kind,'status',p_status,'safe_error_code',p_safe_error_code);
end;
$$;

create or replace function public.get_my_external_request(p_kind text,p_request uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_owner uuid; v_status text; v_model text; v_error text; v_created timestamptz; v_expires timestamptz; actor uuid;
begin
  actor:=auth.uid();
  if actor is null or p_kind is null or p_kind not in ('recipe','receipt') or p_request is null then raise exception 'Se requiere una solicitud válida.' using errcode='42501'; end if;
  perform public._lock_external_request_owner(actor);
  if p_kind='recipe' then
    select r.owner_user_id,r.status,r.provider_model,r.safe_error_code,r.created_at,r.expires_at into v_owner,v_status,v_model,v_error,v_created,v_expires from public.recipe_generation_requests r where r.id=p_request for update;
  else
    select r.owner_user_id,r.status,null::text,r.safe_error_code,r.created_at,r.expires_at into v_owner,v_status,v_model,v_error,v_created,v_expires from public.receipt_recognition_requests r where r.id=p_request for update;
  end if;
  if not found or v_owner<>actor then raise exception 'La solicitud no existe.' using errcode='P0002'; end if;
  if v_expires<=pg_catalog.clock_timestamp() and v_status='pending' then
    if p_kind='recipe' then update public.recipe_generation_requests set status='expired' where id=p_request;
    else update public.receipt_recognition_requests set status='expired' where id=p_request; end if;
    v_status:='expired'; v_error:=null;
  end if;
  return pg_catalog.jsonb_build_object('id',p_request,'kind',p_kind,'status',v_status,'provider_model',v_model,'safe_error_code',v_error,'created_at',v_created,'expires_at',v_expires);
end;
$$;

create or replace function public.discard_my_receipt_request(p_request uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; v_owner uuid; v_status text; v_expires timestamptz;
begin
  actor:=auth.uid();
  if actor is null or p_request is null then raise exception 'Se requiere una solicitud válida.' using errcode='42501'; end if;
  perform public._lock_external_request_owner(actor);
  select r.owner_user_id,r.status,r.expires_at into v_owner,v_status,v_expires from public.receipt_recognition_requests r where r.id=p_request for update;
  if not found or v_owner<>actor then raise exception 'La solicitud no existe.' using errcode='P0002'; end if;
  if v_expires<=pg_catalog.clock_timestamp() and v_status='pending' then
    update public.receipt_recognition_requests set status='expired' where id=p_request; v_status:='expired';
  elsif v_status in ('pending','completed') then
    update public.receipt_recognition_requests set status='discarded',safe_error_code=null where id=p_request; v_status:='discarded';
  end if;
  return pg_catalog.jsonb_build_object('id',p_request,'kind','receipt','status',v_status,'expires_at',v_expires);
end;
$$;

create or replace function public.purge_expired_external_requests(p_limit integer default 100)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare recipe_count integer; receipt_count integer; cutoff timestamptz := pg_catalog.clock_timestamp();
begin
  if p_limit is null or p_limit not between 1 and 1000 then raise exception 'El límite no es válido.' using errcode='22023'; end if;
  with doomed as (
    select id from public.recipe_generation_requests where expires_at<=cutoff order by expires_at,id limit p_limit for update skip locked
  ) delete from public.recipe_generation_requests r using doomed d where r.id=d.id;
  get diagnostics recipe_count = row_count;
  with doomed as (
    select id from public.receipt_recognition_requests where expires_at<=cutoff order by expires_at,id limit p_limit for update skip locked
  ) delete from public.receipt_recognition_requests r using doomed d where r.id=d.id;
  get diagnostics receipt_count = row_count;
  return pg_catalog.jsonb_build_object('recipe_deleted',recipe_count,'receipt_deleted',receipt_count);
end;
$$;

revoke all on function public.begin_external_request(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.finish_external_request(uuid,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.purge_expired_external_requests(integer) from public,anon,authenticated;
grant execute on function public.begin_external_request(uuid,uuid,text,text) to service_role;
grant execute on function public.finish_external_request(uuid,uuid,text,text,text) to service_role;
grant execute on function public.purge_expired_external_requests(integer) to service_role;
revoke all on function public.get_my_external_request(text,uuid) from public,anon,service_role;
revoke all on function public.discard_my_receipt_request(uuid) from public,anon,service_role;
grant execute on function public.get_my_external_request(text,uuid) to authenticated;
grant execute on function public.discard_my_receipt_request(uuid) to authenticated;

revoke insert,update,delete on public.recipe_generation_requests,public.receipt_recognition_requests from public,anon,authenticated,service_role;
grant select on public.recipe_generation_requests,public.receipt_recognition_requests to authenticated;

comment on function public.begin_external_request(uuid,uuid,text,text) is 'Creates an idempotent pending lifecycle record with fixed server TTL; metadata only.';
comment on function public.finish_external_request(uuid,uuid,text,text,text) is 'Service-only terminal transition; does not validate or store generated recipe or OCR output.';
comment on function public.purge_expired_external_requests(integer) is 'Service-only bounded cleanup; request idempotency lasts only until the row is purged.';
comment on function public.get_my_external_request(text,uuid) is 'Returns only the caller-owned request lifecycle metadata.';
comment on function public.discard_my_receipt_request(uuid) is 'Discards only the caller-owned receipt request lifecycle metadata.';


-- Staged from 202611010006_personal_read_rpcs.sql inside the rehearsal transaction.
revoke all on function public.lock_my_relational_account() from service_role;

-- Personal reads use the same account lock protocol as relational writes. Each
-- response is assembled by one SQL statement so its children share a snapshot.
create function public.get_my_profile()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  select jsonb_build_object(
    'profile', (select to_jsonb(p) from public.profiles p where p.user_id=actor),
    'preference_keys', coalesce((
      select jsonb_agg(t.tag_key order by t.tag_key)
      from public.user_dietary_preferences pref
      join public.dietary_tags t on t.id=pref.dietary_tag_id
      where pref.user_id=actor
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

create function public.get_my_favorites(p_limit integer default 30,p_offset integer default 0)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset not between 0 and 5000 then
    raise exception 'La página de favoritos no es válida.' using errcode='22023';
  end if;
  with mine as materialized (
    select f.recipe_id,f.created_at as favorite_created_at,r as recipe,
      (r.id is not null and r.active and not r.is_deleted and
        ((r.recipe_source='official' and r.publication_status='published') or coalesce(r.owner_user_id=actor,false))) as visible
    from public.favorite_recipes f
    left join public.recipes r on r.id=f.recipe_id
    where f.user_id=actor
  ), page as (
    select * from mine order by favorite_created_at desc,recipe_id desc offset p_offset limit p_limit
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'recipe_id',p.recipe_id,'created_at',p.favorite_created_at,'available',p.visible,
      'recipe',case when p.visible then public.recipe_discovery_payload(p.recipe,null)->'recipe' else null end
    ) order by p.favorite_created_at desc,p.recipe_id desc) from page p),'[]'::jsonb),
    'total',(select count(*)::integer from mine),'limit',p_limit,'offset',p_offset
  ) into result;
  return result;
end;
$$;

create function public.get_my_meal_plan(p_week_start date)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_week_start is null or not isfinite(p_week_start) or extract(isodow from p_week_start)<>1 then
    raise exception 'La semana debe comenzar un lunes válido.' using errcode='22023';
  end if;
  select jsonb_build_object(
    'plan',(select to_jsonb(mp) from public.meal_plans mp where mp.owner_user_id=actor and mp.week_start=p_week_start),
    'slots',coalesce((
      select jsonb_agg(
        to_jsonb(s) || jsonb_build_object(
          'available', (r.id is not null and r.active and not r.is_deleted and
            ((r.recipe_source='official' and r.publication_status='published') or coalesce(r.owner_user_id=actor,false))),
          'recipe', case when r.id is not null and r.active and not r.is_deleted and
            ((r.recipe_source='official' and r.publication_status='published') or coalesce(r.owner_user_id=actor,false))
            then public.recipe_discovery_payload(r,null)->'recipe' else null end
        ) order by s.meal_date,
          case s.meal_shift when 'breakfast' then 1 when 'lunch' then 2 when 'snack' then 3 when 'dinner' then 4 end,
          s.position,s.id
      )
      from public.meal_plans mp
      join public.meal_plan_slots s on s.plan_id=mp.id
      left join public.recipes r on r.id=s.recipe_id
      where mp.owner_user_id=actor and mp.week_start=p_week_start
    ),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.get_my_profile() from public,anon,service_role;
revoke all on function public.get_my_favorites(integer,integer) from public,anon,service_role;
revoke all on function public.get_my_meal_plan(date) from public,anon,service_role;
grant execute on function public.get_my_profile() to authenticated;
grant execute on function public.get_my_favorites(integer,integer) to authenticated;
grant execute on function public.get_my_meal_plan(date) to authenticated;


-- Staged from 202611010007_inventory_read_rpcs.sql inside the rehearsal transaction.
-- Inventory read APIs keep ownership checks explicit even though they run as
-- SECURITY DEFINER. Each page and its total are built by one statement.
create function public.get_my_pantry(
  p_search text default null,
  p_category text default null,
  p_status text default 'all',
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb; as_of date := current_date; needle text; category_key text;
begin
  actor := public.lock_my_relational_account();
  if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset not between 0 and 5000
    or p_status is null or p_status not in ('all','ok','low','empty','soon','expired')
    or (p_search is not null and length(p_search)>120)
    or (p_category is not null and length(p_category)>80) then
    raise exception 'Los filtros de despensa no son válidos.' using errcode='22023';
  end if;
  needle := nullif(lower(regexp_replace(normalize(trim(regexp_replace(coalesce(p_search,''),'[[:space:]]+',' ','g')),NFD),U&'[\0300-\036f]','','g')),'');
  category_key := nullif(lower(regexp_replace(normalize(trim(regexp_replace(coalesce(p_category,''),'[[:space:]]+',' ','g')),NFD),U&'[\0300-\036f]','','g')),'');
  with mine as materialized (
    select p.*,
      lower(regexp_replace(regexp_replace(normalize(trim(regexp_replace(p.name,'[[:space:]]+',' ','g')),NFD),U&'[\0300-\036f]','','g'),'[[:space:]]+',' ','g')) as normalized_name,
      lower(regexp_replace(regexp_replace(normalize(trim(regexp_replace(p.category,'[[:space:]]+',' ','g')),NFD),U&'[\0300-\036f]','','g'),'[[:space:]]+',' ','g')) as normalized_category,
      case when p.expiry is null then null else p.expiry-as_of end as days,
      p.quantity=0 as empty,
      (p.minimum>0 and p.quantity>0 and p.quantity<p.minimum) as low,
      (p.expiry is not null and p.expiry between as_of and as_of+3) as soon,
      (p.expiry is not null and p.expiry<as_of) as expired
    from public.pantry_items p where p.user_id=actor
  ), filtered as materialized (
    select m.*, case when m.expired then 'expired' when m.empty then 'empty'
      when m.soon then 'soon' when m.low then 'low' else 'ok' end as display_status
    from mine m
    where (needle is null or strpos(m.normalized_name,needle)>0)
      and (category_key is null or m.normalized_category=category_key)
      and (p_status='all' or (p_status='ok' and not (m.low or m.empty or m.soon or m.expired))
        or (p_status='low' and (m.low or m.empty)) or (p_status='empty' and m.empty)
        or (p_status='soon' and m.soon) or (p_status='expired' and m.expired))
  ), page as (
    select * from filtered order by normalized_name,id offset p_offset limit p_limit
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(p) - 'normalized_name' - 'normalized_category' - 'days' - 'empty' - 'low' - 'soon' - 'expired' - 'display_status'
      || jsonb_build_object('flags',jsonb_build_object('days',p.days,'empty',p.empty,'low',p.low,'soon',p.soon,'expired',p.expired),'status',p.display_status)
      order by p.normalized_name,p.id) from page p),'[]'::jsonb),
    'total',(select count(*)::integer from filtered),'limit',p_limit,'offset',p_offset,'as_of',as_of
  ) into result;
  return result;
end;
$$;

create function public.get_my_shopping_list(
  p_list_id uuid default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; selected_id uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset not between 0 and 5000 then
    raise exception 'La página de compras no es válida.' using errcode='22023';
  end if;
  if p_list_id is null then
    select l.id into selected_id from public.shopping_lists l
      where l.owner_user_id=actor and l.status='active' order by l.updated_at desc,l.id desc limit 1;
  else
    select l.id into selected_id from public.shopping_lists l where l.id=p_list_id and l.owner_user_id=actor;
    if selected_id is null then raise exception 'La lista no existe.' using errcode='P0002'; end if;
  end if;
  with chosen as materialized (
    select l.* from public.shopping_lists l where l.id=selected_id and l.owner_user_id=actor
  ), mine as materialized (
    select i.*,to_jsonb(u) as unit_row from chosen l join public.shopping_items i on i.list_id=l.id
      left join public.units u on u.id=i.unit_id
  ), page as (
    select * from mine order by created_at,id offset p_offset limit p_limit
  )
  select jsonb_build_object(
    'list',(select to_jsonb(l) from chosen l),
    'items',coalesce((select jsonb_agg((to_jsonb(p)-'unit_row') || jsonb_build_object(
      'unit_detail',case when p.unit_row is null then null else p.unit_row end,
      'sources',coalesce((select jsonb_agg(to_jsonb(s) order by s.id) from public.shopping_item_sources s where s.shopping_item_id=p.id),'[]'::jsonb)
    ) order by p.created_at,p.id) from page p),'[]'::jsonb),
    'total',(select count(*)::integer from mine),'limit',p_limit,'offset',p_offset
  ) into result;
  return result;
end;
$$;

create function public.get_my_shopping_lists(
  p_status text default null,
  p_limit integer default 30,
  p_offset integer default 0
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset not between 0 and 5000
    or (p_status is not null and p_status not in ('all','active','archived')) then
    raise exception 'Los filtros de listas no son válidos.' using errcode='22023';
  end if;
  with mine as materialized (
    select l.* from public.shopping_lists l where l.owner_user_id=actor
      and (p_status is null or p_status='all' or l.status=p_status)
  ), page as (
    select * from mine order by updated_at desc,id desc offset p_offset limit p_limit
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(p) order by p.updated_at desc,p.id desc) from page p),'[]'::jsonb),
    'total',(select count(*)::integer from mine),'limit',p_limit,'offset',p_offset
  ) into result;
  return result;
end;
$$;

revoke all on function public.get_my_pantry(text,text,text,integer,integer) from public,anon,service_role;
revoke all on function public.get_my_shopping_list(uuid,integer,integer) from public,anon,service_role;
revoke all on function public.get_my_shopping_lists(text,integer,integer) from public,anon,service_role;
grant execute on function public.get_my_pantry(text,text,text,integer,integer) to authenticated;
grant execute on function public.get_my_shopping_list(uuid,integer,integer) to authenticated;
grant execute on function public.get_my_shopping_lists(text,integer,integer) to authenticated;


-- Staged from 202611010008_dashboard_summary_rpc.sql inside the rehearsal transaction.
-- Dashboard summary composes the existing personal read APIs while holding
-- the same account lock used by relational writers. Nested volatile RPCs may
-- use their own statement snapshots; this follows the app writer lock protocol.
create function public.get_my_dashboard_summary(
  p_day date default current_date,
  p_recent_limit integer default 4
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid;
  result jsonb;
  week_start date;
  plan_payload jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_day is null or not isfinite(p_day) or p_day < date '1900-01-01' or p_day > date '9999-12-31'
    or p_recent_limit is null or p_recent_limit not between 1 and 20 then
    raise exception 'Los parámetros del resumen no son válidos.' using errcode='22023';
  end if;

  week_start := p_day - (extract(isodow from p_day)::integer - 1);
  plan_payload := public.get_my_meal_plan(week_start);

  select jsonb_build_object(
    'as_of', p_day,
    'profile', public.get_my_profile(),
    'pantry', jsonb_build_object(
      'total', count(*),
      'low', count(*) filter (where p.quantity = 0 or (p.minimum > 0 and p.quantity > 0 and p.quantity < p.minimum)),
      'empty', count(*) filter (where p.quantity = 0),
      'soon', count(*) filter (where p.expiry between p_day and p_day + 3),
      'expired', count(*) filter (where p.expiry < p_day)
    ),
    'favorites', jsonb_build_object(
      'total', (select count(*)::integer from public.favorite_recipes f where f.user_id=actor),
      'available', (select count(*)::integer
        from public.favorite_recipes f join public.recipes r on r.id=f.recipe_id
        where f.user_id=actor and r.active and not r.is_deleted
          and ((r.recipe_source='official' and r.publication_status='published')
            or coalesce(r.owner_user_id=actor,false)))
    ),
    'shopping', (select jsonb_build_object(
      'active_list_id', l.id,
      'version', l.version,
      'pending_items', count(i.id) filter (where not i.checked and i.transferred_at is null),
      'checked_items', count(i.id) filter (where i.checked and i.transferred_at is null),
      'transferred_items', count(i.id) filter (where i.transferred_at is not null)
    ) from public.shopping_lists l left join public.shopping_items i on i.list_id=l.id
      where l.owner_user_id=actor and l.status='active' group by l.id,l.version),
    'today_plan', jsonb_build_object(
      'plan', plan_payload->'plan',
      'slots', coalesce((select jsonb_agg(s.value order by s.ordinality)
        from jsonb_array_elements(coalesce(plan_payload->'slots','[]'::jsonb)) with ordinality s(value,ordinality)
        where (s.value->>'meal_date')::date=p_day), '[]'::jsonb)
    ),
    'recent_preparations', public.get_my_cooking_history(p_recent_limit)
  ) into result
  from public.pantry_items p
  where p.user_id=actor;

  result := jsonb_set(result,'{shopping}',coalesce(nullif(result->'shopping','null'::jsonb),
    jsonb_build_object('active_list_id',null,'version',null,'pending_items',0,'checked_items',0,'transferred_items',0)));
  return result;
end;
$$;

revoke all on function public.get_my_dashboard_summary(date,integer) from public,anon,service_role;
grant execute on function public.get_my_dashboard_summary(date,integer) to authenticated;


create schema rename_rehearsal;
create table rename_rehearsal.row_counts(table_name text primary key,row_count bigint not null);
insert into rename_rehearsal.row_counts values ('pantry_items', (select count(*) from public.pantry_items));
insert into rename_rehearsal.row_counts values ('personal_data', (select count(*) from public.personal_data));
insert into rename_rehearsal.row_counts values ('user_roles', (select count(*) from public.user_roles));
insert into rename_rehearsal.row_counts values ('catalog_core', (select count(*) from public.catalog_core));
insert into rename_rehearsal.row_counts values ('shared_recipes', (select count(*) from public.shared_recipes));
insert into rename_rehearsal.row_counts values ('account_status', (select count(*) from public.account_status));
insert into rename_rehearsal.row_counts values ('admin_audit_log', (select count(*) from public.admin_audit_log));
insert into rename_rehearsal.row_counts values ('dietary_tags', (select count(*) from public.dietary_tags));
insert into rename_rehearsal.row_counts values ('nutrition_config', (select count(*) from public.nutrition_config));
insert into rename_rehearsal.row_counts values ('profiles', (select count(*) from public.profiles));
insert into rename_rehearsal.row_counts values ('user_dietary_preferences', (select count(*) from public.user_dietary_preferences));
insert into rename_rehearsal.row_counts values ('categories', (select count(*) from public.categories));
insert into rename_rehearsal.row_counts values ('units', (select count(*) from public.units));
insert into rename_rehearsal.row_counts values ('ingredients', (select count(*) from public.ingredients));
insert into rename_rehearsal.row_counts values ('ingredient_dietary_tags', (select count(*) from public.ingredient_dietary_tags));
insert into rename_rehearsal.row_counts values ('recipes', (select count(*) from public.recipes));
insert into rename_rehearsal.row_counts values ('recipe_meal_shifts', (select count(*) from public.recipe_meal_shifts));
insert into rename_rehearsal.row_counts values ('recipe_dietary_tags', (select count(*) from public.recipe_dietary_tags));
insert into rename_rehearsal.row_counts values ('recipe_ingredients', (select count(*) from public.recipe_ingredients));
insert into rename_rehearsal.row_counts values ('recipe_steps', (select count(*) from public.recipe_steps));
insert into rename_rehearsal.row_counts values ('recipe_step_ingredients', (select count(*) from public.recipe_step_ingredients));
insert into rename_rehearsal.row_counts values ('favorite_recipes', (select count(*) from public.favorite_recipes));
insert into rename_rehearsal.row_counts values ('meal_plans', (select count(*) from public.meal_plans));
insert into rename_rehearsal.row_counts values ('meal_plan_slots', (select count(*) from public.meal_plan_slots));
insert into rename_rehearsal.row_counts values ('pantry_receipts', (select count(*) from public.pantry_receipts));
insert into rename_rehearsal.row_counts values ('shopping_lists', (select count(*) from public.shopping_lists));
insert into rename_rehearsal.row_counts values ('shopping_items', (select count(*) from public.shopping_items));
insert into rename_rehearsal.row_counts values ('shopping_item_sources', (select count(*) from public.shopping_item_sources));
insert into rename_rehearsal.row_counts values ('pantry_receipt_items', (select count(*) from public.pantry_receipt_items));
insert into rename_rehearsal.row_counts values ('cooking_sessions', (select count(*) from public.cooking_sessions));
insert into rename_rehearsal.row_counts values ('cooking_session_steps', (select count(*) from public.cooking_session_steps));
insert into rename_rehearsal.row_counts values ('cooking_events', (select count(*) from public.cooking_events));
insert into rename_rehearsal.row_counts values ('cooking_event_ingredients', (select count(*) from public.cooking_event_ingredients));
insert into rename_rehearsal.row_counts values ('recipe_generation_requests', (select count(*) from public.recipe_generation_requests));
insert into rename_rehearsal.row_counts values ('receipt_recognition_requests', (select count(*) from public.receipt_recognition_requests));
insert into rename_rehearsal.row_counts values ('admin_recipe_write_state', (select count(*) from public.admin_recipe_write_state));
create table rename_rehearsal.relations as
  select oid,relkind,relrowsecurity,relforcerowsecurity from pg_class
  where relnamespace='public'::regnamespace and relkind in ('r','p')
    and relname=any(array['pantry_items','personal_data','user_roles','catalog_core','shared_recipes','account_status','admin_audit_log','dietary_tags','nutrition_config','profiles','user_dietary_preferences','categories','units','ingredients','ingredient_dietary_tags','recipes','recipe_meal_shifts','recipe_dietary_tags','recipe_ingredients','recipe_steps','recipe_step_ingredients','favorite_recipes','meal_plans','meal_plan_slots','pantry_receipts','shopping_lists','shopping_items','shopping_item_sources','pantry_receipt_items','cooking_sessions','cooking_session_steps','cooking_events','cooking_event_ingredients','recipe_generation_requests','receipt_recognition_requests','admin_recipe_write_state']);
create table rename_rehearsal.columns as
  select c.oid,a.attnum,a.attname,a.atttypid,a.atttypmod,a.attnotnull,a.attidentity,a.attgenerated
  from pg_class c join pg_attribute a on a.attrelid=c.oid
  where c.oid in(select oid from rename_rehearsal.relations) and a.attnum>0 and not a.attisdropped;

-- Keep the original migrations immutable. This final cutover renames tables only;
-- columns, RPC names, enum values, JSON keys, and auth.users remain unchanged.
alter table public.pantry_items rename to articulos_despensa;
alter table public.personal_data rename to datos_personales;
alter table public.user_roles rename to roles_usuario;
alter table public.catalog_core rename to catalogo_base;
alter table public.shared_recipes rename to recetas_compartidas;
alter table public.account_status rename to estado_cuenta;
alter table public.admin_audit_log rename to registro_auditoria;

alter table public.dietary_tags rename to etiquetas_dieteticas;
alter table public.nutrition_config rename to configuracion_nutricional;
alter table public.profiles rename to perfiles;
alter table public.user_dietary_preferences rename to preferencias_dieteticas_usuario;
alter table public.categories rename to categorias;
alter table public.units rename to unidades;
alter table public.ingredients rename to ingredientes;
alter table public.ingredient_dietary_tags rename to etiquetas_dieteticas_ingrediente;
alter table public.recipes rename to recetas;
alter table public.recipe_meal_shifts rename to turnos_comida_receta;
alter table public.recipe_dietary_tags rename to etiquetas_dieteticas_receta;
alter table public.recipe_ingredients rename to ingredientes_receta;
alter table public.recipe_steps rename to pasos_receta;
alter table public.recipe_step_ingredients rename to ingredientes_paso_receta;
alter table public.favorite_recipes rename to recetas_favoritas;
alter table public.meal_plans rename to planes_comida;
alter table public.meal_plan_slots rename to turnos_plan_comida;
alter table public.pantry_receipts rename to comprobantes_despensa;
alter table public.shopping_lists rename to listas_compras;
alter table public.shopping_items rename to articulos_compra;
alter table public.shopping_item_sources rename to origenes_articulo_compra;
alter table public.pantry_receipt_items rename to articulos_comprobante_despensa;
alter table public.cooking_sessions rename to sesiones_cocina;
alter table public.cooking_session_steps rename to pasos_sesion_cocina;
alter table public.cooking_events rename to eventos_cocina;
alter table public.cooking_event_ingredients rename to ingredientes_evento_cocina;
alter table public.recipe_generation_requests rename to solicitudes_generacion_receta;
alter table public.receipt_recognition_requests rename to solicitudes_reconocimiento_ticket;
alter table public.admin_recipe_write_state rename to estado_escritura_receta_admin;

-- PL/pgSQL stores relation references as source text. Replace only qualified table
-- references and the two documented trigger-table-name dispatch lists. Function
-- names, argument names, JSON keys, and column names are intentionally untouched.
do $rename_function_bodies$
declare
  routine record;
  definition text;
begin
  for routine in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind in ('f', 'p')
      and p.prosrc is not null
  loop
    definition := pg_get_functiondef(routine.oid);
    definition := regexp_replace(definition, 'public\.pantry_items([^a-z0-9_]|$)', 'public.articulos_despensa\1', 'g');
    definition := regexp_replace(definition, 'public\.personal_data([^a-z0-9_]|$)', 'public.datos_personales\1', 'g');
    definition := regexp_replace(definition, 'public\.user_roles([^a-z0-9_]|$)', 'public.roles_usuario\1', 'g');
    definition := regexp_replace(definition, 'public\.catalog_core([^a-z0-9_]|$)', 'public.catalogo_base\1', 'g');
    definition := regexp_replace(definition, 'public\.shared_recipes([^a-z0-9_]|$)', 'public.recetas_compartidas\1', 'g');
    definition := regexp_replace(definition, 'public\.account_status([^a-z0-9_]|$)', 'public.estado_cuenta\1', 'g');
    definition := regexp_replace(definition, 'public\.admin_audit_log([^a-z0-9_]|$)', 'public.registro_auditoria\1', 'g');
    definition := regexp_replace(definition, 'public\.dietary_tags([^a-z0-9_]|$)', 'public.etiquetas_dieteticas\1', 'g');
    definition := regexp_replace(definition, 'public\.nutrition_config([^a-z0-9_]|$)', 'public.configuracion_nutricional\1', 'g');
    definition := regexp_replace(definition, 'public\.profiles([^a-z0-9_]|$)', 'public.perfiles\1', 'g');
    definition := regexp_replace(definition, 'public\.user_dietary_preferences([^a-z0-9_]|$)', 'public.preferencias_dieteticas_usuario\1', 'g');
    definition := regexp_replace(definition, 'public\.categories([^a-z0-9_]|$)', 'public.categorias\1', 'g');
    definition := regexp_replace(definition, 'public\.units([^a-z0-9_]|$)', 'public.unidades\1', 'g');
    definition := regexp_replace(definition, 'public\.ingredients([^a-z0-9_]|$)', 'public.ingredientes\1', 'g');
    definition := regexp_replace(definition, 'public\.ingredient_dietary_tags([^a-z0-9_]|$)', 'public.etiquetas_dieteticas_ingrediente\1', 'g');
    definition := regexp_replace(definition, 'public\.recipes([^a-z0-9_]|$)', 'public.recetas\1', 'g');
    definition := regexp_replace(definition, 'public\.recipe_meal_shifts([^a-z0-9_]|$)', 'public.turnos_comida_receta\1', 'g');
    definition := regexp_replace(definition, 'public\.recipe_dietary_tags([^a-z0-9_]|$)', 'public.etiquetas_dieteticas_receta\1', 'g');
    definition := regexp_replace(definition, 'public\.recipe_ingredients([^a-z0-9_]|$)', 'public.ingredientes_receta\1', 'g');
    definition := regexp_replace(definition, 'public\.recipe_steps([^a-z0-9_]|$)', 'public.pasos_receta\1', 'g');
    definition := regexp_replace(definition, 'public\.recipe_step_ingredients([^a-z0-9_]|$)', 'public.ingredientes_paso_receta\1', 'g');
    definition := regexp_replace(definition, 'public\.favorite_recipes([^a-z0-9_]|$)', 'public.recetas_favoritas\1', 'g');
    definition := regexp_replace(definition, 'public\.meal_plans([^a-z0-9_]|$)', 'public.planes_comida\1', 'g');
    definition := regexp_replace(definition, 'public\.meal_plan_slots([^a-z0-9_]|$)', 'public.turnos_plan_comida\1', 'g');
    definition := regexp_replace(definition, 'public\.pantry_receipts([^a-z0-9_]|$)', 'public.comprobantes_despensa\1', 'g');
    definition := regexp_replace(definition, 'public\.shopping_lists([^a-z0-9_]|$)', 'public.listas_compras\1', 'g');
    definition := regexp_replace(definition, 'public\.shopping_items([^a-z0-9_]|$)', 'public.articulos_compra\1', 'g');
    definition := regexp_replace(definition, 'public\.shopping_item_sources([^a-z0-9_]|$)', 'public.origenes_articulo_compra\1', 'g');
    definition := regexp_replace(definition, 'public\.pantry_receipt_items([^a-z0-9_]|$)', 'public.articulos_comprobante_despensa\1', 'g');
    definition := regexp_replace(definition, 'public\.cooking_sessions([^a-z0-9_]|$)', 'public.sesiones_cocina\1', 'g');
    definition := regexp_replace(definition, 'public\.cooking_session_steps([^a-z0-9_]|$)', 'public.pasos_sesion_cocina\1', 'g');
    definition := regexp_replace(definition, 'public\.cooking_events([^a-z0-9_]|$)', 'public.eventos_cocina\1', 'g');
    definition := regexp_replace(definition, 'public\.cooking_event_ingredients([^a-z0-9_]|$)', 'public.ingredientes_evento_cocina\1', 'g');
    definition := regexp_replace(definition, 'public\.recipe_generation_requests([^a-z0-9_]|$)', 'public.solicitudes_generacion_receta\1', 'g');
    definition := regexp_replace(definition, 'public\.receipt_recognition_requests([^a-z0-9_]|$)', 'public.solicitudes_reconocimiento_ticket\1', 'g');
    definition := regexp_replace(definition, 'public\.admin_recipe_write_state([^a-z0-9_]|$)', 'public.estado_escritura_receta_admin\1', 'g');

    -- These table-qualified row references are used by ON CONFLICT and RETURNING.
    definition := replace(definition, 'profiles.version+1', 'perfiles.version+1');
    definition := replace(definition, 'meal_plans.version+1', 'planes_comida.version+1');
    definition := replace(definition, 'shopping_items.list_id=', 'articulos_compra.list_id=');
    definition := replace(definition, 'shopping_items.transferred_at', 'articulos_compra.transferred_at');
    definition := replace(definition, 'to_jsonb(categories.*)', 'to_jsonb(categorias.*)');
    definition := replace(definition, 'to_jsonb(units.*)', 'to_jsonb(unidades.*)');
    definition := replace(definition, 'to_jsonb(ingredients.*)', 'to_jsonb(ingredientes.*)');

    definition := replace(definition, 'tg_table_name = ''units''', 'tg_table_name = ''unidades''');
    definition := replace(definition, 'tg_table_name = ''recipe_ingredients''', 'tg_table_name = ''ingredientes_receta''');
    definition := replace(definition, 'tg_table_name = ''recipe_step_ingredients''', 'tg_table_name = ''ingredientes_paso_receta''');
    definition := replace(definition, 'tg_table_name = ''meal_plan_slots''', 'tg_table_name = ''turnos_plan_comida''');
    definition := replace(definition, 'tg_table_name = ''favorite_recipes''', 'tg_table_name = ''recetas_favoritas''');
    definition := replace(definition, 'tg_table_name = ''cooking_sessions''', 'tg_table_name = ''sesiones_cocina''');
    definition := replace(definition, 'tg_table_name = ''shopping_lists''', 'tg_table_name = ''listas_compras''');
    definition := replace(definition, 'tg_table_name = ''shopping_item_sources''', 'tg_table_name = ''origenes_articulo_compra''');
    definition := replace(definition, 'tg_table_name = ''user_roles''', 'tg_table_name = ''roles_usuario''');
    definition := replace(definition, 'tg_table_name = ''account_status''', 'tg_table_name = ''estado_cuenta''');
    definition := replace(definition, 'tg_table_name = ''catalog_core''', 'tg_table_name = ''catalogo_base''');
    definition := replace(definition, 'tg_table_name = ''shared_recipes''', 'tg_table_name = ''recetas_compartidas''');

    if definition <> pg_get_functiondef(routine.oid) then
      execute definition;
    end if;
  end loop;
end;
$rename_function_bodies$;



do $verify_rename$
declare i integer;
begin
  if (select count(*) from rename_rehearsal.relations) <> 36 then raise exception 'Expected 36 existing application tables'; end if;
  if to_regclass('public.pantry_items') is not null or to_regclass('public.articulos_despensa') is null then raise exception 'Rename mismatch: pantry_items'; end if;
if to_regclass('public.personal_data') is not null or to_regclass('public.datos_personales') is null then raise exception 'Rename mismatch: personal_data'; end if;
if to_regclass('public.user_roles') is not null or to_regclass('public.roles_usuario') is null then raise exception 'Rename mismatch: user_roles'; end if;
if to_regclass('public.catalog_core') is not null or to_regclass('public.catalogo_base') is null then raise exception 'Rename mismatch: catalog_core'; end if;
if to_regclass('public.shared_recipes') is not null or to_regclass('public.recetas_compartidas') is null then raise exception 'Rename mismatch: shared_recipes'; end if;
if to_regclass('public.account_status') is not null or to_regclass('public.estado_cuenta') is null then raise exception 'Rename mismatch: account_status'; end if;
if to_regclass('public.admin_audit_log') is not null or to_regclass('public.registro_auditoria') is null then raise exception 'Rename mismatch: admin_audit_log'; end if;
if to_regclass('public.dietary_tags') is not null or to_regclass('public.etiquetas_dieteticas') is null then raise exception 'Rename mismatch: dietary_tags'; end if;
if to_regclass('public.nutrition_config') is not null or to_regclass('public.configuracion_nutricional') is null then raise exception 'Rename mismatch: nutrition_config'; end if;
if to_regclass('public.profiles') is not null or to_regclass('public.perfiles') is null then raise exception 'Rename mismatch: profiles'; end if;
if to_regclass('public.user_dietary_preferences') is not null or to_regclass('public.preferencias_dieteticas_usuario') is null then raise exception 'Rename mismatch: user_dietary_preferences'; end if;
if to_regclass('public.categories') is not null or to_regclass('public.categorias') is null then raise exception 'Rename mismatch: categories'; end if;
if to_regclass('public.units') is not null or to_regclass('public.unidades') is null then raise exception 'Rename mismatch: units'; end if;
if to_regclass('public.ingredients') is not null or to_regclass('public.ingredientes') is null then raise exception 'Rename mismatch: ingredients'; end if;
if to_regclass('public.ingredient_dietary_tags') is not null or to_regclass('public.etiquetas_dieteticas_ingrediente') is null then raise exception 'Rename mismatch: ingredient_dietary_tags'; end if;
if to_regclass('public.recipes') is not null or to_regclass('public.recetas') is null then raise exception 'Rename mismatch: recipes'; end if;
if to_regclass('public.recipe_meal_shifts') is not null or to_regclass('public.turnos_comida_receta') is null then raise exception 'Rename mismatch: recipe_meal_shifts'; end if;
if to_regclass('public.recipe_dietary_tags') is not null or to_regclass('public.etiquetas_dieteticas_receta') is null then raise exception 'Rename mismatch: recipe_dietary_tags'; end if;
if to_regclass('public.recipe_ingredients') is not null or to_regclass('public.ingredientes_receta') is null then raise exception 'Rename mismatch: recipe_ingredients'; end if;
if to_regclass('public.recipe_steps') is not null or to_regclass('public.pasos_receta') is null then raise exception 'Rename mismatch: recipe_steps'; end if;
if to_regclass('public.recipe_step_ingredients') is not null or to_regclass('public.ingredientes_paso_receta') is null then raise exception 'Rename mismatch: recipe_step_ingredients'; end if;
if to_regclass('public.favorite_recipes') is not null or to_regclass('public.recetas_favoritas') is null then raise exception 'Rename mismatch: favorite_recipes'; end if;
if to_regclass('public.meal_plans') is not null or to_regclass('public.planes_comida') is null then raise exception 'Rename mismatch: meal_plans'; end if;
if to_regclass('public.meal_plan_slots') is not null or to_regclass('public.turnos_plan_comida') is null then raise exception 'Rename mismatch: meal_plan_slots'; end if;
if to_regclass('public.pantry_receipts') is not null or to_regclass('public.comprobantes_despensa') is null then raise exception 'Rename mismatch: pantry_receipts'; end if;
if to_regclass('public.shopping_lists') is not null or to_regclass('public.listas_compras') is null then raise exception 'Rename mismatch: shopping_lists'; end if;
if to_regclass('public.shopping_items') is not null or to_regclass('public.articulos_compra') is null then raise exception 'Rename mismatch: shopping_items'; end if;
if to_regclass('public.shopping_item_sources') is not null or to_regclass('public.origenes_articulo_compra') is null then raise exception 'Rename mismatch: shopping_item_sources'; end if;
if to_regclass('public.pantry_receipt_items') is not null or to_regclass('public.articulos_comprobante_despensa') is null then raise exception 'Rename mismatch: pantry_receipt_items'; end if;
if to_regclass('public.cooking_sessions') is not null or to_regclass('public.sesiones_cocina') is null then raise exception 'Rename mismatch: cooking_sessions'; end if;
if to_regclass('public.cooking_session_steps') is not null or to_regclass('public.pasos_sesion_cocina') is null then raise exception 'Rename mismatch: cooking_session_steps'; end if;
if to_regclass('public.cooking_events') is not null or to_regclass('public.eventos_cocina') is null then raise exception 'Rename mismatch: cooking_events'; end if;
if to_regclass('public.cooking_event_ingredients') is not null or to_regclass('public.ingredientes_evento_cocina') is null then raise exception 'Rename mismatch: cooking_event_ingredients'; end if;
if to_regclass('public.recipe_generation_requests') is not null or to_regclass('public.solicitudes_generacion_receta') is null then raise exception 'Rename mismatch: recipe_generation_requests'; end if;
if to_regclass('public.receipt_recognition_requests') is not null or to_regclass('public.solicitudes_reconocimiento_ticket') is null then raise exception 'Rename mismatch: receipt_recognition_requests'; end if;
if to_regclass('public.admin_recipe_write_state') is not null or to_regclass('public.estado_escritura_receta_admin') is null then raise exception 'Rename mismatch: admin_recipe_write_state'; end if;
  if (select row_count from rename_rehearsal.row_counts where table_name='pantry_items') <> (select count(*) from public.articulos_despensa) then raise exception 'Row count mismatch: articulos_despensa'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='personal_data') <> (select count(*) from public.datos_personales) then raise exception 'Row count mismatch: datos_personales'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='user_roles') <> (select count(*) from public.roles_usuario) then raise exception 'Row count mismatch: roles_usuario'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='catalog_core') <> (select count(*) from public.catalogo_base) then raise exception 'Row count mismatch: catalogo_base'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='shared_recipes') <> (select count(*) from public.recetas_compartidas) then raise exception 'Row count mismatch: recetas_compartidas'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='account_status') <> (select count(*) from public.estado_cuenta) then raise exception 'Row count mismatch: estado_cuenta'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='admin_audit_log') <> (select count(*) from public.registro_auditoria) then raise exception 'Row count mismatch: registro_auditoria'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='dietary_tags') <> (select count(*) from public.etiquetas_dieteticas) then raise exception 'Row count mismatch: etiquetas_dieteticas'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='nutrition_config') <> (select count(*) from public.configuracion_nutricional) then raise exception 'Row count mismatch: configuracion_nutricional'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='profiles') <> (select count(*) from public.perfiles) then raise exception 'Row count mismatch: perfiles'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='user_dietary_preferences') <> (select count(*) from public.preferencias_dieteticas_usuario) then raise exception 'Row count mismatch: preferencias_dieteticas_usuario'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='categories') <> (select count(*) from public.categorias) then raise exception 'Row count mismatch: categorias'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='units') <> (select count(*) from public.unidades) then raise exception 'Row count mismatch: unidades'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='ingredients') <> (select count(*) from public.ingredientes) then raise exception 'Row count mismatch: ingredientes'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='ingredient_dietary_tags') <> (select count(*) from public.etiquetas_dieteticas_ingrediente) then raise exception 'Row count mismatch: etiquetas_dieteticas_ingrediente'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='recipes') <> (select count(*) from public.recetas) then raise exception 'Row count mismatch: recetas'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='recipe_meal_shifts') <> (select count(*) from public.turnos_comida_receta) then raise exception 'Row count mismatch: turnos_comida_receta'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='recipe_dietary_tags') <> (select count(*) from public.etiquetas_dieteticas_receta) then raise exception 'Row count mismatch: etiquetas_dieteticas_receta'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='recipe_ingredients') <> (select count(*) from public.ingredientes_receta) then raise exception 'Row count mismatch: ingredientes_receta'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='recipe_steps') <> (select count(*) from public.pasos_receta) then raise exception 'Row count mismatch: pasos_receta'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='recipe_step_ingredients') <> (select count(*) from public.ingredientes_paso_receta) then raise exception 'Row count mismatch: ingredientes_paso_receta'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='favorite_recipes') <> (select count(*) from public.recetas_favoritas) then raise exception 'Row count mismatch: recetas_favoritas'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='meal_plans') <> (select count(*) from public.planes_comida) then raise exception 'Row count mismatch: planes_comida'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='meal_plan_slots') <> (select count(*) from public.turnos_plan_comida) then raise exception 'Row count mismatch: turnos_plan_comida'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='pantry_receipts') <> (select count(*) from public.comprobantes_despensa) then raise exception 'Row count mismatch: comprobantes_despensa'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='shopping_lists') <> (select count(*) from public.listas_compras) then raise exception 'Row count mismatch: listas_compras'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='shopping_items') <> (select count(*) from public.articulos_compra) then raise exception 'Row count mismatch: articulos_compra'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='shopping_item_sources') <> (select count(*) from public.origenes_articulo_compra) then raise exception 'Row count mismatch: origenes_articulo_compra'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='pantry_receipt_items') <> (select count(*) from public.articulos_comprobante_despensa) then raise exception 'Row count mismatch: articulos_comprobante_despensa'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='cooking_sessions') <> (select count(*) from public.sesiones_cocina) then raise exception 'Row count mismatch: sesiones_cocina'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='cooking_session_steps') <> (select count(*) from public.pasos_sesion_cocina) then raise exception 'Row count mismatch: pasos_sesion_cocina'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='cooking_events') <> (select count(*) from public.eventos_cocina) then raise exception 'Row count mismatch: eventos_cocina'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='cooking_event_ingredients') <> (select count(*) from public.ingredientes_evento_cocina) then raise exception 'Row count mismatch: ingredientes_evento_cocina'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='recipe_generation_requests') <> (select count(*) from public.solicitudes_generacion_receta) then raise exception 'Row count mismatch: solicitudes_generacion_receta'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='receipt_recognition_requests') <> (select count(*) from public.solicitudes_reconocimiento_ticket) then raise exception 'Row count mismatch: solicitudes_reconocimiento_ticket'; end if;
if (select row_count from rename_rehearsal.row_counts where table_name='admin_recipe_write_state') <> (select count(*) from public.estado_escritura_receta_admin) then raise exception 'Row count mismatch: estado_escritura_receta_admin'; end if;
  if to_regclass('auth.users') is null then raise exception 'auth.users changed'; end if;
  if exists(select 1 from rename_rehearsal.relations before_row full join
    (select oid,relkind,relrowsecurity,relforcerowsecurity from pg_class where oid in(select oid from rename_rehearsal.relations)) after_row using(oid)
    where before_row.oid is null or after_row.oid is null or
      (before_row.relkind,before_row.relrowsecurity,before_row.relforcerowsecurity) is distinct from
      (after_row.relkind,after_row.relrowsecurity,after_row.relforcerowsecurity)) then raise exception 'Table OID or RLS metadata changed'; end if;
  if exists((select * from rename_rehearsal.columns except select c.oid,a.attnum,a.attname,a.atttypid,a.atttypmod,a.attnotnull,a.attidentity,a.attgenerated from pg_class c join pg_attribute a on a.attrelid=c.oid where c.oid in(select oid from rename_rehearsal.relations) and a.attnum>0 and not a.attisdropped)
    union all (select c.oid,a.attnum,a.attname,a.atttypid,a.atttypmod,a.attnotnull,a.attidentity,a.attgenerated from pg_class c join pg_attribute a on a.attrelid=c.oid where c.oid in(select oid from rename_rehearsal.relations) and a.attnum>0 and not a.attisdropped except select * from rename_rehearsal.columns)) then raise exception 'Table columns changed'; end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and
    p.prosrc ~ 'public\.(pantry_items|personal_data|user_roles|catalog_core|shared_recipes|account_status|admin_audit_log|dietary_tags|nutrition_config|profiles|user_dietary_preferences|categories|units|ingredients|ingredient_dietary_tags|recipes|recipe_meal_shifts|recipe_dietary_tags|recipe_ingredients|recipe_steps|recipe_step_ingredients|favorite_recipes|meal_plans|meal_plan_slots|pantry_receipts|shopping_lists|shopping_items|shopping_item_sources|pantry_receipt_items|cooking_sessions|cooking_session_steps|cooking_events|cooking_event_ingredients|recipe_generation_requests|receipt_recognition_requests|admin_recipe_write_state)([^a-z0-9_]|$)') then raise exception 'Stale qualified relation reference remains'; end if;
end;
$verify_rename$;
-- Install the post-rename recipe read API and exercise it against the staged legacy baseline.
-- Read helpers retain archived ingredient/unit/category references and recipe
-- versions. The established payload helper already returns inactive FK rows.
create function public.recipe_read_payload(p_recipe public.recetas)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_set(public.recipe_discovery_payload(p_recipe,null)->'recipe','{ingredients}',
    coalesce((select jsonb_agg(x.value || jsonb_build_object('category_id',c.id,'category',c.name)
      order by (x.value->>'position')::integer)
      from jsonb_array_elements(public.recipe_discovery_payload(p_recipe,null)->'recipe'->'ingredients') x(value)
      join public.ingredientes i on i.id=(x.value->>'ingredient_id')::uuid
      left join public.categorias c on c.id=i.category_id),'[]'::jsonb));
$$;

create function public.list_known_recipes(p_limit integer default 500,p_offset integer default 0)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_limit is null or p_limit not between 1 and 500 or p_offset is null or p_offset not between 0 and 5000 then
    raise exception 'El límite o desplazamiento no es válido.' using errcode='22023'; end if;
  select coalesce(jsonb_agg(public.recipe_read_payload(q) order by lower(q.title),q.id),'[]'::jsonb)
    into result from (
      select r.* from public.recetas r
      where (r.recipe_source='official' and r.owner_user_id is null and r.publication_status='published')
         or (r.recipe_source in ('user','ai') and r.owner_user_id=actor)
      order by lower(r.title),r.id offset p_offset limit p_limit
    ) q;
  return result;
end; $$;

-- UUID and legacy identifiers are separate named arguments. This keeps UUID
-- parsing deterministic while still supporting historical UUID-shaped keys.
create function public.get_my_recipe_detail(p_recipe_id uuid default null,p_legacy_id text default null,p_include_inactive boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; found_recipe public.recetas;
begin
  actor := public.lock_my_relational_account();
  if p_include_inactive is null or (p_recipe_id is null) = (p_legacy_id is null)
    or p_legacy_id is not null and (length(trim(p_legacy_id))=0 or length(p_legacy_id)>500) then
    raise exception 'Indicá un único identificador de receta válido.' using errcode='22023';
  end if;
  select r.* into found_recipe from public.recetas r
   where (p_recipe_id is not null and r.id=p_recipe_id)
      or (p_legacy_id is not null and r.legacy_id=p_legacy_id);
  if not found then return null; end if;
  if not ((found_recipe.recipe_source='official' and found_recipe.owner_user_id is null and found_recipe.publication_status='published')
       or (found_recipe.recipe_source in ('user','ai') and found_recipe.owner_user_id=actor)) then return null; end if;
  if not p_include_inactive and (not found_recipe.active or found_recipe.is_deleted) then return null; end if;
  return jsonb_build_object('recipe',public.recipe_read_payload(found_recipe),
    'stock',null,'percentage',null,'label','Disponibilidad no calculable');
end; $$;

-- The editor can read official drafts/inactive records with their version.
-- ADMIN does not gain access to another user's private recipe through this API.
create function public.admin_get_recipe(p_recipe_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  if not exists(select 1 from public.roles_usuario ur where ur.user_id=actor and ur.role='ADMIN') then
    raise exception 'Se requiere rol ADMIN.' using errcode='42501';
  end if;
  if p_recipe_id is null then raise exception 'El identificador de receta es obligatorio.' using errcode='22023'; end if;
  select public.admin_recipe_export(p_recipe_id) into result
   from public.recetas r where r.id=p_recipe_id and r.recipe_source='official' and r.owner_user_id is null;
  return result;
end; $$;

revoke all on function public.recipe_read_payload(public.recetas) from public,anon,authenticated;
revoke all on function public.list_known_recipes(integer,integer),
  public.get_my_recipe_detail(uuid,text,boolean),public.admin_get_recipe(uuid) from public,anon;
grant execute on function public.list_known_recipes(integer,integer),
  public.get_my_recipe_detail(uuid,text,boolean),public.admin_get_recipe(uuid) to authenticated;

-- STAGE ONLY: secure known/detail reads, legacy identifiers and editor reads.
do $recipe_read_contract$
declare
  u uuid; other_u uuid; cat uuid:=gen_random_uuid(); unit_id uuid:=gen_random_uuid();
  ing uuid:=gen_random_uuid(); tag uuid:=gen_random_uuid(); active_recipe uuid:=gen_random_uuid();
  inactive_recipe uuid:=gen_random_uuid(); own_private uuid:=gen_random_uuid(); other_private uuid:=gen_random_uuid();
  official_draft uuid:=gen_random_uuid(); own_ai uuid:=gen_random_uuid(); other_ai uuid:=gen_random_uuid();
  uuid_legacy uuid:=gen_random_uuid(); prefix text:=gen_random_uuid()::text; result jsonb; item jsonb;
begin
  select id into u from auth.users order by id limit 1;
  select id into other_u from auth.users where id<>u order by id limit 1;
  if u is null or other_u is null then raise exception 'FAIL: requires two fixture accounts'; end if;
  insert into roles_usuario(user_id,role) values(u,'USER'),(other_u,'USER') on conflict(user_id) do update set role=excluded.role;
  insert into estado_cuenta(user_id,active) values(u,true),(other_u,true) on conflict(user_id) do update set active=true;
  insert into categorias(id,name,normalized_name,active) values(cat,'Archived read category','read-'||cat,false);
  insert into unidades(id,name,abbreviation,dimension,active) values(unit_id,'Archived read unit','aru','mass',false);
  insert into ingredientes(id,name,normalized_name,category_id,base_unit_id,active)
    values(ing,'Archived read ingredient','read-'||ing,cat,unit_id,false);
  insert into etiquetas_dieteticas(id,tag_key,label,active) values(tag,'read-archived','Archived read tag',false);
  insert into recetas(id,legacy_id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
    values(active_recipe,'legacy-active-'||prefix,null,'official','Read active',10,2,'easy','published'),
      (inactive_recipe,uuid_legacy::text,null,'official','Read inactive',10,2,'easy','published'),
      (own_private,'own-draft-'||prefix,u,'user','Own draft',10,2,'easy','draft'),
      (own_ai,'own-ai-'||prefix,u,'ai','Own AI draft',10,2,'easy','draft'),
      (other_private,'other-private-'||prefix,other_u,'user','Other private',10,2,'easy','draft'),
      (other_ai,'other-ai-'||prefix,other_u,'ai','Other AI private',10,2,'easy','draft'),
      (official_draft,'official-draft-'||prefix,null,'official','Official draft',10,2,'easy','draft');
  update recetas set active=false,is_deleted=true where id=inactive_recipe;
  insert into ingredientes_receta(recipe_id,ingredient_id,quantity,unit_id,position)
    values(inactive_recipe,ing,3,unit_id,1);
  insert into etiquetas_dieteticas_receta(recipe_id,dietary_tag_id) values(inactive_recipe,tag);
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result:=public.list_known_recipes(500,0);
  if not (result @> jsonb_build_array(jsonb_build_object('id',inactive_recipe)))
    or not (result @> jsonb_build_array(jsonb_build_object('id',own_private)))
    or not (result @> jsonb_build_array(jsonb_build_object('id',own_ai)))
    or result @> jsonb_build_array(jsonb_build_object('id',other_private))
    or result @> jsonb_build_array(jsonb_build_object('id',other_ai))
    or result @> jsonb_build_array(jsonb_build_object('id',official_draft)) then
    raise exception 'FAIL: known list visibility/archive contract: %',result;
  end if;
  if jsonb_array_length(public.list_known_recipes(1,0))<>1 then raise exception 'FAIL: bounded known-list paging'; end if;
  item:=public.get_my_recipe_detail(active_recipe,null,false);
  if item->'recipe'->>'version' is null then raise exception 'FAIL: detail omitted recipe version'; end if;
  if public.get_my_recipe_detail(inactive_recipe,null,false) is not null then raise exception 'FAIL: inactive recipe visible without include flag'; end if;
  item:=public.get_my_recipe_detail(inactive_recipe,null,true);
  if item->'recipe'->'ingredients'->0->>'ingredient_id' is distinct from ing::text
    or item->'recipe'->'ingredients'->0->>'category' is distinct from 'Archived read category'
    or item->'recipe'->'dietary_tags'->>0 is distinct from 'read-archived' then
    raise exception 'FAIL: archived recipe refs missing from secure detail: %',item;
  end if;
  if public.get_my_recipe_detail(null,'legacy-active-'||prefix,false)->'recipe'->>'id' is distinct from active_recipe::text then raise exception 'FAIL: legacy id lookup'; end if;
  if public.get_my_recipe_detail(null,uuid_legacy::text,true)->'recipe'->>'id' is distinct from inactive_recipe::text then raise exception 'FAIL: UUID-shaped legacy id lookup'; end if;
  if public.get_my_recipe_detail(null,'other-private-'||prefix,true) is not null then raise exception 'FAIL: foreign private detail leak'; end if;
  if public.get_my_recipe_detail(null,'other-ai-'||prefix,true) is not null then raise exception 'FAIL: foreign AI recipe detail leak'; end if;
  if public.get_my_recipe_detail(null,'official-draft-'||prefix,true) is not null then raise exception 'FAIL: official draft personal read'; end if;
  begin perform public.get_my_recipe_detail(active_recipe,null,null); raise exception 'FAIL: NULL inactive flag accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.list_known_recipes(1,5001); raise exception 'FAIL: oversized known-list offset accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.admin_get_recipe(active_recipe); raise exception 'FAIL: USER can read editor API'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  update roles_usuario set role='ADMIN' where user_id=u;
  execute 'set local role authenticated';
  if public.get_my_recipe_detail(null,'other-private-'||prefix,true) is not null then raise exception 'FAIL: ADMIN personal RPC exposed foreign private recipe'; end if;
  if public.get_my_recipe_detail(null,'other-ai-'||prefix,true) is not null then raise exception 'FAIL: ADMIN personal RPC exposed foreign AI recipe'; end if;
  item:=public.admin_get_recipe(official_draft);
  if item->>'version' is null then raise exception 'FAIL: editor read omitted version'; end if;
  if public.admin_get_recipe(other_private) is not null then raise exception 'FAIL: editor API exposed private recipe'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  execute 'set local role anon';
  begin perform public.get_my_recipe_detail(active_recipe,null,false); raise exception 'FAIL: anon detail execute'; exception when insufficient_privilege then null; end;
  begin perform public.list_known_recipes(); raise exception 'FAIL: anon known-list execute'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update estado_cuenta set active=false where user_id=u;
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin perform public.get_my_recipe_detail(active_recipe,null,false); raise exception 'FAIL: inactive account detail'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  raise notice 'PASS: recipe detail UUID/legacy, known archived rows, private isolation, editor versions and permissions';
end;
$recipe_read_contract$;

select 'PASS: recipe read contract rehearsal completed; final ROLLBACK is required' as result;
rollback;
