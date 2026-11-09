-- FULL REHEARSAL: schema and data changes roll back together. No COMMIT.
-- Supabase SQL Editor: choose "Run without RLS" if prompted.
-- Version 20261030-03: private transaction-scoped staging; no TEMP tables.
-- This script enables domain RLS itself. Keep the final ROLLBACK.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

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

-- REHEARSAL ONLY. Requires 202610300002 in a TEST copy, not the live project.
-- The final ROLLBACK preserves both legacy and relational destinations.

set local lock_timeout = '5s';
set local statement_timeout = '90s';
lock table public.catalog_core, public.shared_recipes in share mode;
-- Private staging objects belong to this transaction and disappear on ROLLBACK.
create schema cocinapp_rehearsal;
revoke all on schema cocinapp_rehearsal from public, anon, authenticated;
create function cocinapp_rehearsal.norm(t text) returns text language sql immutable
as $$ select lower(translate(regexp_replace(trim(t), '\s+', ' ', 'g'), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')) $$;
create function cocinapp_rehearsal.key_id(kind text, old_id text) returns uuid language sql immutable
as $$ select md5('cocinapp-v1|' || kind || '|' || old_id)::uuid $$;
do $$ begin
  if exists(select 1 from public.categories) or exists(select 1 from public.units)
    or exists(select 1 from public.ingredients) or exists(select 1 from public.recipes)
    or exists(select 1 from public.dietary_tags) then
    raise exception 'El ensayo requiere destinos relacionales vacíos. No sobrescribe datos nuevos.';
  end if;
  if (select count(*) from public.catalog_core where catalog_key='main') <> 1
    or (select count(*) from public.shared_recipes where catalog_key='main') <> 1 then
    raise exception 'Faltan los catálogos fuente main.';
  end if;
end $$;
create table cocinapp_rehearsal.src_core as select payload from public.catalog_core where catalog_key='main';
create table cocinapp_rehearsal.src_recipes(legacy_id text primary key, body jsonb not null, origin text not null);
insert into cocinapp_rehearsal.src_recipes select x->>'id', x, 'seed'
from jsonb_array_elements($seed$[{"id": "quinoa-bowl", "name": "Bowl de quinoa y verduras", "description": "Verduras asadas, quinoa y aderezo de limón.", "category": "Almuerzo", "minutes": 30, "portions": 2, "difficulty": "Fácil", "ingredients": [{"name": "Quinoa", "quantity": 150, "unit": "g"}, {"name": "Tomates cherry", "quantity": 150, "unit": "g"}, {"name": "Aceite de oliva", "quantity": 30, "unit": "ml"}, {"name": "Limón", "quantity": 1, "unit": "u"}], "steps": ["Cociná la quinoa según el envase.", "Cortá los tomates y mezclalos con aceite de oliva.", "Serví la quinoa con las verduras y terminá con limón."], "stepMeta": [{"durationMinutes": 15, "stepIngredients": [{"name": "Quinoa", "quantity": 150, "unit": "g"}], "utensils": ["Colador fino", "Olla con tapa"], "temperature": "Hervor suave", "tip": "Enjuagá la quinoa antes de cocinarla para quitarle el sabor amargo.", "warning": "Usá el colador fino para no perder los granos."}, {"durationMinutes": 5, "stepIngredients": [{"name": "Tomates cherry", "quantity": 150, "unit": "g"}, {"name": "Aceite de oliva", "quantity": 30, "unit": "ml"}], "utensils": ["Tabla", "Cuchillo", "Bol"], "tip": "Cortá los tomates justo antes de servir para conservar su textura."}, {"durationMinutes": 2, "stepIngredients": [{"name": "Limón", "quantity": 1, "unit": "u"}], "utensils": ["Fuente para servir"], "specialInstructions": "Probá y ajustá el limón justo antes de llevar el plato a la mesa."}], "symbol": "🥗", "color": "green", "featured": true, "dietaryTags": ["Sin TACC", "Vegana", "Vegetariana", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/quinoa-bowl.webp", "imageAlt": "Bowl de quinoa con tomates cherry y verduras asadas servido en cerámica clara"}, {"id": "pumpkin-pasta", "name": "Pasta cremosa de calabaza", "description": "Una salsa suave con salvia y queso rallado.", "category": "Cena", "minutes": 25, "portions": 3, "difficulty": "Intermedia", "ingredients": [{"name": "Pasta", "quantity": 300, "unit": "g"}, {"name": "Calabaza", "quantity": 400, "unit": "g"}, {"name": "Queso rallado", "quantity": 60, "unit": "g"}], "steps": ["Cociná la pasta y reservá un poco del agua.", "Cociná la calabaza hasta que esté tierna y procesala.", "Mezclá la salsa con la pasta y terminá con queso rallado."], "stepMeta": [{"minutes": 10, "tip": "Reservá una taza del agua de cocción para ajustar la textura de la salsa."}, {"minutes": 12, "tip": "Procesá la calabaza caliente con cuidado y agregá líquido de a poco."}], "symbol": "🍝", "color": "gold", "featured": true, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/pumpkin-pasta.webp", "imageAlt": "Pasta cremosa de calabaza con queso rallado y hojas de salvia"}, {"id": "chickpea-salad", "name": "Ensalada tibia de garbanzos", "description": "Garbanzos crocantes, hojas frescas y yogur.", "category": "Almuerzo", "minutes": 20, "portions": 2, "difficulty": "Fácil", "ingredients": [{"name": "Garbanzos", "quantity": 250, "unit": "g"}, {"name": "Hojas verdes", "quantity": 100, "unit": "g"}, {"name": "Yogur", "quantity": 100, "unit": "g"}], "steps": ["Salteá los garbanzos hasta que estén dorados.", "Lavá y escurrí las hojas verdes.", "Serví todo con yogur."], "stepMeta": [{"minutes": 8, "tip": "Secá los garbanzos antes de saltearlos para que doren mejor."}], "symbol": "🥙", "color": "pink", "dietaryTags": ["Sin TACC", "Vegetariana", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/chickpea-salad.webp", "imageAlt": "Ensalada tibia de garbanzos dorados con hojas verdes y yogur"}, {"id": "chicken-rice", "name": "Pollo con arroz integral", "description": "Pollo dorado con arroz y tomates cherry frescos.", "category": "Cena", "minutes": 35, "portions": 2, "difficulty": "Fácil", "ingredients": [{"name": "Pechuga de pollo", "quantity": 300, "unit": "g"}, {"name": "Arroz integral", "quantity": 160, "unit": "g"}, {"name": "Tomates cherry", "quantity": 120, "unit": "g"}, {"name": "Aceite de oliva", "quantity": 20, "unit": "ml"}], "steps": ["Cociná el arroz integral según las indicaciones del envase.", "Cortá el pollo y doralo en una sartén con el aceite de oliva.", "Serví el pollo sobre el arroz y agregá los tomates cortados."], "stepMeta": [{"durationMinutes": 25, "stepIngredients": [{"name": "Arroz integral", "quantity": 160, "unit": "g"}], "utensils": ["Olla con tapa"], "temperature": "Hervor suave", "tip": "Dejá reposar el arroz tapado durante 5 minutos al apagar el fuego."}, {"durationMinutes": 10, "stepIngredients": [{"name": "Pechuga de pollo", "quantity": 300, "unit": "g"}, {"name": "Aceite de oliva", "quantity": 20, "unit": "ml"}], "utensils": ["Tabla para carnes", "Cuchillo", "Sartén"], "temperature": "Fuego medio-alto", "warning": "Lavá manos y utensilios después de manipular pollo crudo."}, {"durationMinutes": 4, "stepIngredients": [{"name": "Tomates cherry", "quantity": 120, "unit": "g"}], "utensils": ["Tabla", "Cuchillo"], "tip": "Agregá los tomates al final para conservar su frescura."}], "symbol": "🍗", "color": "blue", "dietaryTags": ["Sin TACC", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/chicken-rice.webp", "imageAlt": "Pollo dorado con arroz integral y tomates cherry servido en un plato"}, {"id": "yogurt-fruit", "name": "Yogur con banana y avena", "description": "Un desayuno rápido con fruta y avena.", "category": "Desayuno", "minutes": 8, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Yogur", "quantity": 180, "unit": "g"}, {"name": "Banana", "quantity": 1, "unit": "u"}, {"name": "Avena", "quantity": 40, "unit": "g"}], "steps": ["Serví el yogur en un bol.", "Cortá la banana y agregala con la avena."], "stepMeta": [{"tip": "Agregá la avena justo antes de comer para mantener su textura."}], "symbol": "🥣", "color": "pink", "calories": 310, "featured": true, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/yogurt-fruit.webp", "imageAlt": "Bol de yogur con rodajas de banana y avena"}, {"id": "apple-toast", "name": "Tostadas con manzana", "description": "Merienda simple con fruta y queso untable.", "category": "Merienda", "minutes": 10, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Pan integral", "quantity": 2, "unit": "u"}, {"name": "Manzana", "quantity": 1, "unit": "u"}, {"name": "Queso untable", "quantity": 40, "unit": "g"}], "steps": ["Tostá el pan integral.", "Untá el queso y sumá la manzana en láminas."], "symbol": "🍎", "color": "gold", "calories": 285, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/apple-toast.webp", "imageAlt": "Tostadas integrales con queso untable y láminas de manzana"}, {"id": "vegetable-omelette", "name": "Omelette de verduras", "description": "Huevos, espinaca y tomates en una cena simple y completa.", "category": "Cena", "minutes": 15, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Huevos", "quantity": 2, "unit": "u"}, {"name": "Espinaca", "quantity": 80, "unit": "g"}, {"name": "Tomates cherry", "quantity": 80, "unit": "g"}], "steps": ["Batí los huevos.", "Salteá la espinaca y los tomates.", "Agregá los huevos y cociná de ambos lados."], "symbol": "🍳", "color": "gold", "calories": 340, "dietaryTags": ["Sin TACC", "Vegetariana", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/vegetable-omelette.webp", "imageAlt": "Omelette de espinaca y tomates cherry servido en un plato claro"}, {"id": "lentil-stew", "name": "Guiso rápido de lentejas", "description": "Lentejas, tomate y verduras en un plato cálido de todos los días.", "category": "Cena", "minutes": 40, "portions": 4, "difficulty": "Intermedia", "ingredients": [{"name": "Lentejas", "quantity": 400, "unit": "g"}, {"name": "Tomate", "quantity": 2, "unit": "u"}, {"name": "Zanahoria", "quantity": 2, "unit": "u"}], "steps": ["Cortá las verduras.", "Cocinalas con el tomate.", "Sumá las lentejas y cociná hasta integrar."], "symbol": "🍲", "color": "pink", "dietaryTags": ["Sin TACC", "Vegana", "Vegetariana", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/lentil-stew.webp", "imageAlt": "Guiso de lentejas con tomate y zanahoria servido en un cuenco"}, {"id": "avocado-toast", "name": "Tostadas con palta y huevo", "description": "Un desayuno cremoso, fresco y listo en pocos minutos.", "category": "Desayuno", "minutes": 12, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Pan integral", "quantity": 2, "unit": "u"}, {"name": "Palta", "quantity": 1, "unit": "u"}, {"name": "Huevos", "quantity": 1, "unit": "u"}], "steps": ["Tostá el pan.", "Pisá la palta y condimentá.", "Cociná el huevo y servilo sobre las tostadas."], "symbol": "🥑", "color": "green", "calories": 390, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/avocado-toast.webp", "imageAlt": "Tostadas integrales con palta y huevo cocido"}, {"id": "banana-pancakes", "name": "Panqueques de banana y avena", "description": "Panqueques suaves sin harina, ideales para empezar el día.", "category": "Desayuno", "minutes": 18, "portions": 2, "difficulty": "Fácil", "ingredients": [{"name": "Banana", "quantity": 2, "unit": "u"}, {"name": "Avena", "quantity": 100, "unit": "g"}, {"name": "Huevos", "quantity": 2, "unit": "u"}], "steps": ["Procesá la banana, la avena y los huevos.", "Volcá porciones en una sartén caliente.", "Doralos de ambos lados y serví."], "symbol": "🥞", "color": "blue", "calories": 360, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/banana-pancakes.webp", "imageAlt": "Panqueques de banana y avena apilados en un plato"}, {"id": "scrambled-eggs-toast", "name": "Huevos revueltos con tostadas", "description": "Desayuno tibio y rápido con huevos cremosos.", "category": "Desayuno", "minutes": 12, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Huevos", "quantity": 2, "unit": "u"}, {"name": "Pan integral", "quantity": 2, "unit": "u"}, {"name": "Leche", "quantity": 30, "unit": "ml"}], "steps": ["Batí los huevos con la leche.", "Cocinalos a fuego bajo revolviendo.", "Tostá el pan y serví."], "stepMeta": [{"tip": "Batí solo hasta integrar."}, {"minutes": 4, "tip": "Retirá del fuego cuando todavía estén húmedos."}], "symbol": "🍳", "color": "gold", "calories": 330, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/scrambled-eggs-toast.webp", "imageAlt": "Huevos revueltos cremosos con tostadas integrales"}, {"id": "overnight-oats", "name": "Avena nocturna con manzana", "description": "Avena fresca preparada con anticipación.", "category": "Desayuno", "minutes": 10, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Avena", "quantity": 60, "unit": "g"}, {"name": "Leche", "quantity": 180, "unit": "ml"}, {"name": "Manzana", "quantity": 1, "unit": "u"}], "steps": ["Mezclá la avena con la leche.", "Refrigerá la preparación.", "Sumá la manzana antes de servir."], "stepMeta": [{"tip": "Usá un recipiente con tapa."}, {"minutes": 480, "tip": "Dejala reposar durante la noche."}], "symbol": "🥣", "color": "blue", "calories": 350, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/overnight-oats.webp", "imageAlt": "Avena nocturna con leche y manzana servida en un frasco de vidrio"}, {"id": "caprese-sandwich", "name": "Sándwich caprese", "description": "Pan tostado con tomate, queso y hojas frescas.", "category": "Almuerzo", "minutes": 15, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Pan integral", "quantity": 2, "unit": "u"}, {"name": "Tomate", "quantity": 1, "unit": "u"}, {"name": "Queso", "quantity": 80, "unit": "g"}, {"name": "Hojas verdes", "quantity": 30, "unit": "g"}], "steps": ["Cortá el tomate y el queso.", "Armá el sándwich con las hojas.", "Tostalo hasta fundir el queso."], "stepMeta": [{"tip": "Secá el tomate para que el pan conserve su textura."}, {"minutes": 5}], "symbol": "🥪", "color": "green", "calories": 420, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/caprese-sandwich.webp", "imageAlt": "Sándwich caprese tostado con tomate, queso y hojas verdes"}, {"id": "tuna-rice-salad", "name": "Ensalada de arroz y atún", "description": "Almuerzo fresco con arroz, atún y vegetales.", "category": "Almuerzo", "minutes": 25, "portions": 2, "difficulty": "Fácil", "ingredients": [{"name": "Arroz", "quantity": 160, "unit": "g"}, {"name": "Atún", "quantity": 160, "unit": "g"}, {"name": "Tomate", "quantity": 1, "unit": "u"}, {"name": "Aceite de oliva", "quantity": 20, "unit": "ml"}], "steps": ["Cociná el arroz.", "Escurrí el atún y cortá el tomate.", "Mezclá todo con aceite."], "stepMeta": [{"minutes": 15, "tip": "Enfriá el arroz extendido para que quede suelto."}], "symbol": "🐟", "color": "blue", "calories": 480, "dietaryTags": ["Sin TACC", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/tuna-rice-salad.webp", "imageAlt": "Ensalada de arroz con atún y tomate servida en un bol"}, {"id": "vegetable-wrap", "name": "Wrap de verduras y hummus", "description": "Wrap liviano con verduras crocantes.", "category": "Almuerzo", "minutes": 18, "portions": 2, "difficulty": "Fácil", "ingredients": [{"name": "Tortillas", "quantity": 2, "unit": "u"}, {"name": "Garbanzos", "quantity": 180, "unit": "g"}, {"name": "Zanahoria", "quantity": 1, "unit": "u"}, {"name": "Hojas verdes", "quantity": 60, "unit": "g"}], "steps": ["Procesá los garbanzos hasta formar un hummus.", "Cortá la zanahoria y lavá las hojas.", "Rellená y enrollá las tortillas."], "stepMeta": [{"minutes": 5, "tip": "Agregá agua de a cucharadas para ajustar el hummus."}, {"tip": "Doblá los extremos antes de enrollar."}], "symbol": "🌯", "color": "pink", "calories": 390, "dietaryTags": ["Vegana", "Vegetariana", "Sin lactosa", "Sin frutos secos"], "image": "/assets/recipes/vegetable-wrap.webp", "imageAlt": "Wrap cortado con hummus, zanahoria y hojas verdes"}, {"id": "tomato-risotto", "name": "Risotto de tomate", "description": "Arroz cremoso con tomate y queso.", "category": "Cena", "minutes": 38, "portions": 3, "difficulty": "Intermedia", "ingredients": [{"name": "Arroz", "quantity": 240, "unit": "g"}, {"name": "Tomate", "quantity": 3, "unit": "u"}, {"name": "Queso rallado", "quantity": 60, "unit": "g"}], "steps": ["Cociná el tomate hasta obtener una salsa.", "Agregá el arroz y líquido de a poco.", "Terminá con queso rallado."], "stepMeta": [{"minutes": 10, "tip": "Cociná el tomate hasta concentrar su sabor."}, {"minutes": 20, "tip": "Revolvé con frecuencia para liberar el almidón."}], "symbol": "🍚", "color": "pink", "calories": 510, "dietaryTags": ["Sin TACC", "Vegetariana", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/tomato-risotto.webp", "imageAlt": "Risotto cremoso de tomate con queso rallado"}, {"id": "baked-fish-potatoes", "name": "Pescado al horno con papas", "description": "Cena completa de pescado, papas y limón.", "category": "Cena", "minutes": 45, "portions": 2, "difficulty": "Intermedia", "ingredients": [{"name": "Filet de pescado", "quantity": 400, "unit": "g"}, {"name": "Papa", "quantity": 500, "unit": "g"}, {"name": "Limón", "quantity": 1, "unit": "u"}, {"name": "Aceite de oliva", "quantity": 30, "unit": "ml"}], "steps": ["Cortá y condimentá las papas.", "Horneá las papas hasta que empiecen a dorar.", "Sumá el pescado y cociná hasta que esté tierno."], "stepMeta": [{"durationMinutes": 8, "stepIngredients": [{"name": "Papa", "quantity": 500, "unit": "g"}, {"name": "Aceite de oliva", "quantity": 30, "unit": "ml"}], "utensils": ["Tabla", "Cuchillo", "Fuente para horno"], "tip": "Cortá las papas del mismo grosor."}, {"durationMinutes": 25, "utensils": ["Horno", "Fuente para horno"], "temperature": "200 °C", "warning": "Usá guantes térmicos al mover la fuente."}, {"durationMinutes": 15, "stepIngredients": [{"name": "Filet de pescado", "quantity": 400, "unit": "g"}, {"name": "Limón", "quantity": 1, "unit": "u"}], "utensils": ["Fuente para horno", "Tenedor"], "temperature": "200 °C", "tip": "El pescado debe separarse fácilmente con un tenedor."}], "symbol": "🐟", "color": "blue", "calories": 530, "dietaryTags": ["Sin TACC", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/baked-fish-potatoes.webp", "imageAlt": "Filet de pescado al horno con papas doradas y limón"}, {"id": "spinach-pie", "name": "Tarta de espinaca", "description": "Tarta casera de espinaca, huevo y queso.", "category": "Cena", "minutes": 55, "portions": 4, "difficulty": "Intermedia", "ingredients": [{"name": "Espinaca", "quantity": 400, "unit": "g"}, {"name": "Huevos", "quantity": 3, "unit": "u"}, {"name": "Queso", "quantity": 150, "unit": "g"}, {"name": "Masa para tarta", "quantity": 1, "unit": "u"}], "steps": ["Salteá y escurrí la espinaca.", "Mezclá con huevos y queso.", "Rellená la masa y horneá."], "stepMeta": [{"minutes": 8, "tip": "Escurrí muy bien la espinaca."}, {"tip": "Probá el relleno antes de sumar los huevos."}, {"minutes": 35}], "symbol": "🥧", "color": "green", "calories": 460, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/spinach-pie.webp", "imageAlt": "Porción de tarta casera de espinaca, huevo y queso"}, {"id": "pear-yogurt-cup", "name": "Copa de pera y yogur", "description": "Merienda fresca con fruta y avena tostada.", "category": "Merienda", "minutes": 10, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Pera", "quantity": 1, "unit": "u"}, {"name": "Yogur", "quantity": 180, "unit": "g"}, {"name": "Avena", "quantity": 30, "unit": "g"}], "steps": ["Cortá la pera.", "Alterná capas de yogur y fruta.", "Terminá con avena."], "stepMeta": [{"tip": "Conservá la cáscara si está firme y bien lavada."}], "symbol": "🍐", "color": "green", "calories": 270, "dietaryTags": ["Sin TACC", "Vegetariana", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/pear-yogurt-cup.webp", "imageAlt": "Copa de yogur con pera y avena tostada"}, {"id": "cheese-scones", "name": "Scones de queso", "description": "Bocados tibios para acompañar la merienda.", "category": "Merienda", "minutes": 32, "portions": 6, "difficulty": "Intermedia", "ingredients": [{"name": "Harina", "quantity": 250, "unit": "g"}, {"name": "Queso rallado", "quantity": 100, "unit": "g"}, {"name": "Leche", "quantity": 120, "unit": "ml"}], "steps": ["Mezclá harina y queso.", "Agregá leche hasta unir.", "Cortá los scones y horneá."], "stepMeta": [{"tip": "No amases de más."}, {"tip": "La masa debe quedar apenas unida."}, {"minutes": 18}], "symbol": "🧀", "color": "gold", "calories": 240, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/cheese-scones.webp", "imageAlt": "Scones de queso recién horneados servidos en un plato"}, {"id": "banana-smoothie", "name": "Licuado de banana y avena", "description": "Merienda cremosa lista en pocos minutos.", "category": "Merienda", "minutes": 6, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Banana", "quantity": 1, "unit": "u"}, {"name": "Leche", "quantity": 250, "unit": "ml"}, {"name": "Avena", "quantity": 25, "unit": "g"}], "steps": ["Colocá todos los ingredientes en la licuadora.", "Procesá hasta obtener una textura lisa."], "stepMeta": [{"tip": "Usá banana fría para un resultado más fresco."}, {"minutes": 2}], "symbol": "🥤", "color": "pink", "calories": 320, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/banana-smoothie.webp", "imageAlt": "Licuado cremoso de banana y avena servido en un vaso"}, {"id": "roasted-vegetable-soup", "name": "Sopa de verduras asadas", "description": "Sopa suave de calabaza, zanahoria y tomate.", "category": "Cena", "minutes": 50, "portions": 4, "difficulty": "Fácil", "ingredients": [{"name": "Calabaza", "quantity": 500, "unit": "g"}, {"name": "Zanahoria", "quantity": 2, "unit": "u"}, {"name": "Tomate", "quantity": 2, "unit": "u"}, {"name": "Aceite de oliva", "quantity": 25, "unit": "ml"}], "steps": ["Cortá y condimentá las verduras.", "Asalas hasta que estén tiernas.", "Procesá con agua caliente hasta lograr la textura deseada."], "stepMeta": [{"tip": "Cortá piezas similares para una cocción pareja."}, {"minutes": 35}, {"tip": "Agregá el líquido gradualmente."}], "symbol": "🥣", "color": "gold", "calories": 220, "featured": true, "dietaryTags": ["Sin TACC", "Vegana", "Vegetariana", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/roasted-vegetable-soup.webp", "imageAlt": "Sopa de calabaza, zanahoria y tomate asados en un cuenco"}]$seed$::jsonb) x;
-- Remote objects override seed objects exactly as mergeRecipeSeed does.
insert into cocinapp_rehearsal.src_recipes select x->>'id', x, 'remote'
from public.shared_recipes r cross join lateral jsonb_array_elements(r.recipes) x where catalog_key='main'
on conflict(legacy_id) do update set body=excluded.body, origin=excluded.origin;

insert into public.categories(id,legacy_id,name,normalized_name,active,is_deleted)
select cocinapp_rehearsal.key_id('category',x->>'id'),x->>'id',x->>'name',cocinapp_rehearsal.norm(x->>'name'),
  (x->>'active')::boolean,(x->>'isDeleted')::boolean
from cocinapp_rehearsal.src_core cross join lateral jsonb_array_elements(payload->'categories') x;
-- Roots first, then derived units; the trigger requires a root of the same dimension.
insert into public.units(id,legacy_id,name,abbreviation,dimension,active,is_deleted)
select cocinapp_rehearsal.key_id('unit',x->>'id'),x->>'id',x->>'name',x->>'abbreviation',
  case x->>'dimension' when 'masa' then 'mass' when 'volumen' then 'volume' when 'conteo' then 'count' else x->>'dimension' end,
  (x->>'active')::boolean,(x->>'isDeleted')::boolean
from cocinapp_rehearsal.src_core cross join lateral jsonb_array_elements(payload->'units') x
where nullif(x->>'baseUnitId','') is null;
insert into public.units(id,legacy_id,name,abbreviation,dimension,base_unit_id,equivalence_multiplier,active,is_deleted)
select cocinapp_rehearsal.key_id('unit',x->>'id'),x->>'id',x->>'name',x->>'abbreviation',
  case x->>'dimension' when 'masa' then 'mass' when 'volumen' then 'volume' when 'conteo' then 'count' else x->>'dimension' end,
  cocinapp_rehearsal.key_id('unit',x->>'baseUnitId'),(x->>'equivalenceMultiplier')::numeric,
  (x->>'active')::boolean,(x->>'isDeleted')::boolean
from cocinapp_rehearsal.src_core cross join lateral jsonb_array_elements(payload->'units') x
where nullif(x->>'baseUnitId','') is not null;
insert into public.ingredients(id,legacy_id,name,normalized_name,category_id,base_unit_id,active,is_deleted)
select cocinapp_rehearsal.key_id('ingredient',x->>'id'),x->>'id',x->>'name',cocinapp_rehearsal.norm(x->>'name'),
  cocinapp_rehearsal.key_id('category',x->>'categoryId'),cocinapp_rehearsal.key_id('unit',x->>'baseUnitId'),
  (x->>'active')::boolean,(x->>'isDeleted')::boolean
from cocinapp_rehearsal.src_core cross join lateral jsonb_array_elements(payload->'ingredients') x;

create table cocinapp_rehearsal.src_ingredients as
select r.legacy_id, n::integer as position, x,
  case when r.origin='remote' then (select id from public.ingredients where legacy_id=x->>'ingredientId')
    else (select id from public.ingredients where normalized_name=cocinapp_rehearsal.norm(x->>'name')) end as ingredient_id,
  case when r.origin='remote' then (select id from public.units where legacy_id=x->>'unitId')
    else (select id from public.units where abbreviation=x->>'unit') end as unit_id
from cocinapp_rehearsal.src_recipes r cross join lateral jsonb_array_elements(body->'ingredients') with ordinality a(x,n);
-- This public-catalog report identifies mappings requiring review; never invent them.
select legacy_id as recipe_legacy_id, x->>'name' as seed_ingredient_name,
  case when ingredient_id is null then 'missing ingredient' else 'missing unit' end as blocker
from cocinapp_rehearsal.src_ingredients where ingredient_id is null or unit_id is null;
do $$ begin
  if exists(select 1 from cocinapp_rehearsal.src_ingredients where ingredient_id is null or unit_id is null) then
    raise exception 'Hay ingredientes o unidades sin asociación. Revisar el reporte; el ensayo se revierte.';
  end if;
end $$;

insert into public.recipes(id,legacy_id,recipe_source,title,author,description,category_label,total_minutes,
  preparation_minutes,cooking_minutes,portions,difficulty,calories_per_portion,publication_status,
  active,is_deleted,featured,symbol,color,cross_contamination_note,image_path,image_alt,created_at,updated_at)
select cocinapp_rehearsal.key_id('recipe',legacy_id),legacy_id,'official',coalesce(body->>'title',body->>'name'),
  coalesce(body->>'author','CocinAPP'),coalesce(body->>'description',''),coalesce(body->>'category',''),
  (body->>'minutes')::integer,(body->>'preparationMinutes')::integer,(body->>'cookingMinutes')::integer,
  (body->>'portions')::integer,
  case body->>'difficulty' when 'Fácil' then 'easy' when 'Intermedia' then 'intermediate' when 'Avanzada' then 'advanced' else body->>'difficulty' end,
  (body->>'calories')::numeric,coalesce(body->>'status','published'),coalesce((body->>'active')::boolean,true),
  coalesce((body->>'isDeleted')::boolean,false),coalesce((body->>'featured')::boolean,false),
  coalesce(body->>'symbol',''),coalesce(body->>'color','green'),body->>'crossContaminationNote',body->>'image',body->>'imageAlt',
  coalesce((body->>'createdAt')::timestamptz,transaction_timestamp()),coalesce((body->>'updatedAt')::timestamptz,transaction_timestamp())
from cocinapp_rehearsal.src_recipes;
insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,note,position)
select cocinapp_rehearsal.key_id('recipe-ingredient',legacy_id||':'||position),cocinapp_rehearsal.key_id('recipe',legacy_id),
  ingredient_id,(x->>'quantity')::numeric,unit_id,coalesce(x->>'note',''),position from cocinapp_rehearsal.src_ingredients;
insert into public.recipe_steps(id,recipe_id,position,instruction,duration_minutes,temperature,tip,warning,utensils,special_instructions)
select cocinapp_rehearsal.key_id('recipe-step',legacy_id||':'||n),cocinapp_rehearsal.key_id('recipe',legacy_id),n::integer,x #>> '{}',
  coalesce((m->>'durationMinutes')::integer,(m->>'minutes')::integer),m->>'temperature',m->>'tip',m->>'warning',
  coalesce(array(select jsonb_array_elements_text(m->'utensils')),'{}'),m->>'specialInstructions'
from cocinapp_rehearsal.src_recipes cross join lateral jsonb_array_elements(body->'steps') with ordinality a(x,n)
cross join lateral (select body->'stepMeta'->(n::integer-1) as m) metadata;
insert into public.recipe_meal_shifts(recipe_id,meal_shift)
select distinct cocinapp_rehearsal.key_id('recipe',legacy_id),case x when 'Desayuno' then 'breakfast' when 'Almuerzo' then 'lunch' when 'Merienda' then 'snack' when 'Cena' then 'dinner' else x end
from cocinapp_rehearsal.src_recipes cross join lateral jsonb_array_elements_text(coalesce(body->'mealShifts',jsonb_build_array(coalesce(body->>'mealShift',body->>'category')))) x;

insert into public.dietary_tags(tag_key,label) values
 ('gluten-free','Sin TACC'),('vegetarian','Vegetariana'),('vegan','Vegana'),('lactose-free','Sin lactosa'),('nut-free','Sin frutos secos');
create table cocinapp_rehearsal.src_tags as
select legacy_id,x as label,case cocinapp_rehearsal.norm(x) when 'sin tacc' then 'gluten-free'
 when 'vegetariana' then 'vegetarian' when 'vegetariano' then 'vegetarian'
 when 'vegana' then 'vegan' when 'vegano' then 'vegan' when 'sin lactosa' then 'lactose-free'
 when 'sin frutos secos' then 'nut-free' else 'label-'||md5(x) end as tag_key
from cocinapp_rehearsal.src_recipes cross join lateral jsonb_array_elements_text(body->'dietaryTags') x;
insert into public.dietary_tags(tag_key,label) select distinct tag_key,label from cocinapp_rehearsal.src_tags
on conflict(tag_key) do nothing;
insert into public.recipe_dietary_tags(recipe_id,dietary_tag_id)
select distinct cocinapp_rehearsal.key_id('recipe',s.legacy_id),t.id from cocinapp_rehearsal.src_tags s join public.dietary_tags t using(tag_key);

-- Link per-step metadata to ingredients without dropping unresolvable links.
create table cocinapp_rehearsal.src_step_links as
select r.legacy_id, n::integer as step_position, value as old_ingredient_id
from cocinapp_rehearsal.src_recipes r cross join lateral jsonb_array_elements(body->'stepMeta') with ordinality a(m,n)
cross join lateral jsonb_array_elements_text(m->'ingredientIds') value;
do $$ begin
 if exists(select 1 from cocinapp_rehearsal.src_step_links s where not exists(select 1 from cocinapp_rehearsal.src_ingredients i
   join public.ingredients g on g.id=i.ingredient_id where i.legacy_id=s.legacy_id and g.legacy_id=s.old_ingredient_id)) then
   raise exception 'Metadatos de pasos con ingredientes sin resolver.';
 end if;
end $$;
insert into public.recipe_step_ingredients(step_id,recipe_ingredient_id)
select distinct cocinapp_rehearsal.key_id('recipe-step',s.legacy_id||':'||s.step_position),
 cocinapp_rehearsal.key_id('recipe-ingredient',i.legacy_id||':'||i.position)
from cocinapp_rehearsal.src_step_links s join cocinapp_rehearsal.src_ingredients i on i.legacy_id=s.legacy_id
join public.ingredients g on g.id=i.ingredient_id and g.legacy_id=s.old_ingredient_id;

-- Seed step metadata uses named ingredients rather than legacy ingredient IDs.
create table cocinapp_rehearsal.src_seed_steps as
select r.legacy_id,n::integer as step_position,item
from cocinapp_rehearsal.src_recipes r cross join lateral jsonb_array_elements(body->'stepMeta') with ordinality a(m,n)
cross join lateral jsonb_array_elements(m->'stepIngredients') item where origin='seed';
do $$ begin
 if exists(select 1 from cocinapp_rehearsal.src_seed_steps s where (select count(*) from public.recipe_ingredients ri
   join public.ingredients i on i.id=ri.ingredient_id join public.units u on u.id=ri.unit_id
   where ri.recipe_id=cocinapp_rehearsal.key_id('recipe',s.legacy_id)
   and i.normalized_name=cocinapp_rehearsal.norm(s.item->>'name') and u.abbreviation=s.item->>'unit') <> 1) then
   raise exception 'Ingredientes por paso del catálogo incluido sin asociación inequívoca.';
 end if;
end $$;
insert into public.recipe_step_ingredients(step_id,recipe_ingredient_id,quantity_override)
select cocinapp_rehearsal.key_id('recipe-step',s.legacy_id||':'||s.step_position),ri.id,(s.item->>'quantity')::numeric
from cocinapp_rehearsal.src_seed_steps s join public.recipe_ingredients ri on ri.recipe_id=cocinapp_rehearsal.key_id('recipe',s.legacy_id)
join public.ingredients i on i.id=ri.ingredient_id and i.normalized_name=cocinapp_rehearsal.norm(s.item->>'name')
join public.units u on u.id=ri.unit_id and u.abbreviation=s.item->>'unit';


-- Explicit staging RLS avoids SQL Editor appending ALTERs after ROLLBACK.
alter table cocinapp_rehearsal.src_core enable row level security;
alter table cocinapp_rehearsal.src_recipes enable row level security;
alter table cocinapp_rehearsal.src_ingredients enable row level security;
alter table cocinapp_rehearsal.src_tags enable row level security;
alter table cocinapp_rehearsal.src_step_links enable row level security;
alter table cocinapp_rehearsal.src_seed_steps enable row level security;

select 'categories' as dataset,count(*) as converted from public.categories
union all select 'units',count(*) from public.units
union all select 'ingredients',count(*) from public.ingredients
union all select 'recipes',count(*) from public.recipes
union all select 'recipe_ingredients',count(*) from public.recipe_ingredients
union all select 'recipe_steps',count(*) from public.recipe_steps;
-- REHEARSAL ONLY. Requires the relational schema and merged recipe backfill.
-- Run on an isolated copy as the database operator; never as an application user.
-- No legacy rows or pantry quantities are modified. All inserts roll back.

set local timezone = 'UTC';
set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- A consistent source snapshot is required for reconciliation.
lock table public.personal_data in share mode;
lock table public.recipes in share mode;

do $$
declare row_data record; item jsonb; p jsonb; target_recipe uuid; event_id uuid;
  session_id uuid; target_plan uuid; meal_date date; week_start date;
  meal_shift text; cooked_at timestamptz; started_at timestamptz;
  expected_count bigint; actual_count bigint;
begin
  if exists(select 1 from public.profiles)
    or exists(select 1 from public.user_dietary_preferences)
    or exists(select 1 from public.favorite_recipes)
    or exists(select 1 from public.meal_plans)
    or exists(select 1 from public.meal_plan_slots)
    or exists(select 1 from public.shopping_lists)
    or exists(select 1 from public.cooking_sessions)
    or exists(select 1 from public.cooking_events) then
    raise exception 'Destino personal no vacío: se rechaza sobrescribir registros.';
  end if;
  if exists(select 1 from public.personal_data where
    (data_key = 'profile' and jsonb_typeof(value) <> 'object')
    or (data_key <> 'profile' and jsonb_typeof(value) <> 'array')) then
    raise exception 'Formato de documento personal no soportado.';
  end if;
  if exists(select 1 from public.personal_data
    where data_key in ('cooking_progress','shopping') and jsonb_array_length(value) > 0) then
    raise exception 'Hay compras o sesiones activas nuevas: requieren su conversor antes de continuar.';
  end if;
  if exists(select 1 from public.personal_data d
    where not exists(select 1 from auth.users u where u.id = d.user_id)) then
    raise exception 'Documento personal sin cuenta Auth correspondiente.';
  end if;

  -- Stable canonical tag keys. Existing tag rows remain authoritative.
  insert into public.dietary_tags(id, tag_key, label)
  select md5('cocinapp:dietary:' || key)::uuid, key, label
  from (values ('gluten-free','Sin TACC'),('vegetarian','Vegetariana'),
    ('vegan','Vegana'),('lactose-free','Sin lactosa'),('nut-free','Sin frutos secos')) v(key,label)
  on conflict (tag_key) do nothing;

  for row_data in select user_id, value, updated_at from public.personal_data where data_key='profile' loop
    p := row_data.value;
    if jsonb_typeof(p -> 'name') is distinct from 'string'
      or length(trim(p ->> 'name')) not between 1 and 120 then
      raise exception 'Perfil sin nombre válido.';
    end if;
    if exists(select 1 from jsonb_object_keys(p) key where key not in
      ('name','email','birthDate','weightKg','heightCm','metabolicSex','activityLevel','goal','preferences')) then
      raise exception 'Perfil con campos no contemplados por el conversor.';
    end if;
    if (p ? 'weightKg' and jsonb_typeof(p -> 'weightKg') <> 'number')
      or (p ? 'heightCm' and jsonb_typeof(p -> 'heightCm') <> 'number')
      or (p ? 'preferences' and jsonb_typeof(p -> 'preferences') <> 'array') then
      raise exception 'Tipos de campos de perfil incompatibles.';
    end if;
    insert into public.profiles(user_id,display_name,birth_date,weight_kg,height_cm,
      metabolic_sex,activity_level,goal,created_at,updated_at)
    values(row_data.user_id,p ->> 'name',nullif(p ->> 'birthDate','')::date,
      (p ->> 'weightKg')::numeric,(p ->> 'heightCm')::numeric,p ->> 'metabolicSex',
      p ->> 'activityLevel',p ->> 'goal',row_data.updated_at,row_data.updated_at);
    -- Email stays in Auth; no second email source is introduced.
    for item in select value from jsonb_array_elements(coalesce(p -> 'preferences','[]'::jsonb)) loop
      if jsonb_typeof(item) <> 'string' or not exists(select 1 from public.dietary_tags where tag_key=item #>> '{}') then
        raise exception 'Preferencia dietética no reconocida.';
      end if;
      insert into public.user_dietary_preferences(user_id,dietary_tag_id,created_at)
      select row_data.user_id,id,row_data.updated_at from public.dietary_tags where tag_key=item #>> '{}'
      on conflict (user_id,dietary_tag_id) do nothing;
    end loop;
  end loop;

  for row_data in select user_id,value,updated_at from public.personal_data where data_key='favorites' loop
    for item in select value from jsonb_array_elements(row_data.value) loop
      if jsonb_typeof(item) <> 'string' then raise exception 'Favorito con identificador inválido.'; end if;
      select id into target_recipe from public.recipes where legacy_id=item #>> '{}';
      if target_recipe is null then raise exception 'Favorito sin receta migrada.'; end if;
      insert into public.favorite_recipes(user_id,recipe_id,created_at)
      values(row_data.user_id,target_recipe,row_data.updated_at);
    end loop;
  end loop;

  for row_data in select user_id,value,updated_at from public.personal_data where data_key='meal_plan' loop
    for item in select value from jsonb_array_elements(row_data.value) loop
      if jsonb_typeof(item) <> 'object'
        or jsonb_typeof(item -> 'recipeId') is distinct from 'string'
        or jsonb_typeof(item -> 'portions') is distinct from 'number' then
        raise exception 'Asignación del plan con formato inválido.';
      end if;
      meal_date := (item ->> 'date')::date;
      week_start := meal_date - (extract(isodow from meal_date)::integer - 1);
      meal_shift := case item ->> 'meal' when 'Desayuno' then 'breakfast' when 'Almuerzo' then 'lunch'
        when 'Merienda' then 'snack' when 'Cena' then 'dinner' end;
      if meal_date is null or meal_shift is null
        or (item ->> 'portions')::numeric <> trunc((item ->> 'portions')::numeric) then
        raise exception 'Fecha, turno o porciones del plan inválidos.';
      end if;
      target_plan := md5('cocinapp:plan:' || row_data.user_id::text || ':' || week_start::text)::uuid;
      insert into public.meal_plans(id,owner_user_id,week_start,created_at,updated_at)
      values(target_plan,row_data.user_id,week_start,row_data.updated_at,row_data.updated_at)
      on conflict on constraint meal_plans_owner_user_id_week_start_key do nothing;
      select id into target_recipe from public.recipes where legacy_id=item ->> 'recipeId';
      if target_recipe is null then raise exception 'Plan sin receta migrada.'; end if;
      insert into public.meal_plan_slots(id,plan_id,meal_date,meal_shift,recipe_id,portions,created_at)
      values(md5('cocinapp:slot:' || row_data.user_id::text || ':' || meal_date::text || ':' || meal_shift)::uuid,
        target_plan,meal_date,meal_shift,target_recipe,(item ->> 'portions')::integer,row_data.updated_at);
    end loop;
  end loop;

  -- Each legacy history event has its own closed synthetic session. The recipe
  -- snapshot reflects the catalog available during migration, not an invented
  -- historical recipe version. No consumption/stock deductions are fabricated.
  for row_data in select user_id,value,updated_at from public.personal_data where data_key='cooking_history' loop
    for item in select value from jsonb_array_elements(row_data.value) loop
      if jsonb_typeof(item) <> 'object' or nullif(item ->> 'id','') is null
        or jsonb_typeof(item -> 'portions') is distinct from 'number'
        or (item ->> 'portions')::numeric <> trunc((item ->> 'portions')::numeric) then
        raise exception 'Evento de cocina con formato inválido.';
      end if;
      select id into target_recipe from public.recipes where legacy_id=item ->> 'recipeId';
      if target_recipe is null then raise exception 'Historial sin receta migrada.'; end if;
      cooked_at := (item ->> 'cookedAt')::timestamptz;
      started_at := coalesce((item ->> 'sessionStartedAt')::timestamptz,cooked_at);
      if cooked_at is null or started_at > cooked_at then raise exception 'Fechas del historial inválidas.'; end if;
      event_id := md5('cocinapp:history:' || row_data.user_id::text || ':' || (item ->> 'id'))::uuid;
      session_id := md5('cocinapp:history-session:' || row_data.user_id::text || ':' || (item ->> 'id'))::uuid;
      select jsonb_build_object('legacyRecipeId',r.legacy_id,'title',r.title,
        'snapshotOrigin','migration_catalog','legacyEvent',item,
        'ingredients',(select coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb) from public.recipe_ingredients i where i.recipe_id=r.id),
        'steps',(select coalesce(jsonb_agg(to_jsonb(s) order by s.position),'[]'::jsonb) from public.recipe_steps s where s.recipe_id=r.id))
        into p from public.recipes r where r.id=target_recipe;
      insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,portions,
        client_idempotency_key,started_at,finished_at)
      values(session_id,row_data.user_id,target_recipe,p,(item ->> 'portions')::integer,
        session_id,started_at,cooked_at);
      insert into public.cooking_events(id,owner_user_id,session_id,recipe_id,recipe_snapshot,portions,cooked_at)
      values(event_id,row_data.user_id,session_id,target_recipe,p,(item ->> 'portions')::integer,cooked_at);
    end loop;
  end loop;

  -- Empty legacy shopping documents become empty active lists; their rows remain
  -- untouched. Non-empty lists/progress were rejected before inserting anything.
  insert into public.shopping_lists(id,owner_user_id,created_at,updated_at)
  select md5('cocinapp:shopping:' || user_id::text)::uuid,user_id,updated_at,updated_at
  from public.personal_data where data_key='shopping';

  select count(*) into expected_count from public.personal_data where data_key='profile';
  select count(*) into actual_count from public.profiles;
  if expected_count <> actual_count then raise exception 'Reconciliación de perfiles fallida.'; end if;
  select coalesce(sum(jsonb_array_length(value)),0) into expected_count from public.personal_data where data_key='favorites';
  select count(*) into actual_count from public.favorite_recipes;
  if expected_count <> actual_count then raise exception 'Reconciliación de favoritos fallida.'; end if;
  select coalesce(sum(jsonb_array_length(value)),0) into expected_count from public.personal_data where data_key='meal_plan';
  select count(*) into actual_count from public.meal_plan_slots;
  if expected_count <> actual_count then raise exception 'Reconciliación del plan fallida.'; end if;
  select coalesce(sum(jsonb_array_length(value)),0) into expected_count from public.personal_data where data_key='cooking_history';
  select count(*) into actual_count from public.cooking_events;
  if expected_count <> actual_count then raise exception 'Reconciliación del historial fallida.'; end if;
exception when others then
  -- Do not include SQLERRM/DETAIL: database cast errors can contain private values.
  raise exception 'Conversión personal cancelada; datos inválidos, destino ocupado o referencias no migradas. SQLSTATE %.',sqlstate;
end;
$$;

select 'profiles' as dataset,count(*) as converted from public.profiles
union all select 'preferences',count(*) from public.user_dietary_preferences
union all select 'favorites',count(*) from public.favorite_recipes
union all select 'plan_slots',count(*) from public.meal_plan_slots
union all select 'cooking_history',count(*) from public.cooking_events
union all select 'empty_active_shopping_lists',count(*) from public.shopping_lists;

-- REHEARSAL ONLY. Run in an isolated copy after the catalog rehearsal stage.

set local lock_timeout = '5s';
lock table public.pantry_items in share row exclusive mode;
do $$ begin
  if exists(select 1 from public.pantry_items where ingredient_ref is not null or unit_ref is not null) then
    raise exception 'La despensa ya tiene referencias relacionales; se rechaza sobrescribirlas.';
  end if;
end $$;
-- An explicit legacy ID is authoritative; only rows without one use exact
-- normalized names. Never use approximate matching or alter inventory values.
update public.pantry_items p set ingredient_ref=i.id
from public.ingredients i
where (p.ingredient_id is not null and i.legacy_id=p.ingredient_id)
  or (p.ingredient_id is null and i.normalized_name=
    lower(translate(regexp_replace(trim(p.name),'\s+',' ','g'),'áéíóúüñÁÉÍÓÚÜÑ','aeiouunAEIOUUN')));
update public.pantry_items p set unit_ref=u.id
from public.units u where u.abbreviation=p.unit;
select 'pantry_rows' as dataset,count(*) as total from public.pantry_items
union all select 'ingredient_unmatched',count(*) from public.pantry_items where ingredient_ref is null
union all select 'unit_unmatched',count(*) from public.pantry_items where unit_ref is null
union all select 'dimension_mismatch',count(*) from public.pantry_items p
join public.ingredients i on i.id=p.ingredient_ref join public.units b on b.id=i.base_unit_id
join public.units u on u.id=p.unit_ref where b.dimension<>u.dimension;
-- One result table: SQL Editor shows only the last non-empty result set.
select 'catalog' as section, 'categories' as dataset, count(*) as total from public.categories
union all select 'catalog','units',count(*) from public.units
union all select 'catalog','ingredients',count(*) from public.ingredients
union all select 'catalog','recipes',count(*) from public.recipes
union all select 'catalog','recipe_ingredients',count(*) from public.recipe_ingredients
union all select 'catalog','recipe_steps',count(*) from public.recipe_steps
union all select 'personal','profiles',count(*) from public.profiles
union all select 'personal','preferences',count(*) from public.user_dietary_preferences
union all select 'personal','favorites',count(*) from public.favorite_recipes
union all select 'personal','plan_slots',count(*) from public.meal_plan_slots
union all select 'personal','cooking_history',count(*) from public.cooking_events
union all select 'personal','empty_active_shopping_lists',count(*) from public.shopping_lists
union all select 'security','domain_tables_with_rls',count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relrowsecurity and c.relname in ('dietary_tags','nutrition_config','profiles','user_dietary_preferences','categories','units','ingredients','ingredient_dietary_tags','recipes','recipe_meal_shifts','recipe_dietary_tags','recipe_ingredients','recipe_steps','recipe_step_ingredients','favorite_recipes','meal_plans','meal_plan_slots','pantry_receipts','shopping_lists','shopping_items','shopping_item_sources','pantry_receipt_items','cooking_sessions','cooking_session_steps','cooking_events','cooking_event_ingredients','recipe_generation_requests','receipt_recognition_requests')
union all select 'pantry','rows',count(*) from public.pantry_items
union all select 'pantry','ingredient_unmatched',count(*) from public.pantry_items where ingredient_ref is null
union all select 'pantry','unmatched_explicit_id',count(*) from public.pantry_items where ingredient_ref is null and ingredient_id is not null
union all select 'pantry','unmatched_name',count(*) from public.pantry_items where ingredient_ref is null and ingredient_id is null
union all select 'pantry','unit_unmatched',count(*) from public.pantry_items where unit_ref is null
union all select 'pantry','dimension_mismatch',count(*) from public.pantry_items p join public.ingredients i on i.id=p.ingredient_ref join public.units b on b.id=i.base_unit_id join public.units u on u.id=p.unit_ref where b.dimension<>u.dimension;
rollback;
