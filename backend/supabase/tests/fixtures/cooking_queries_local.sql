-- LOCAL ISOLATED DATABASE ONLY. Not a Supabase deployment script.
begin;

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

commit;
