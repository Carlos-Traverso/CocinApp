-- PERSONAL RPC REHEARSAL: run whole file as postgres. Keep final ROLLBACK.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';

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
-- STAGE ONLY: schema 202610300002 + RPC migration 202610300003 + this stage,
-- inside ONE transaction ending ROLLBACK. Never execute this stage alone.
-- Synthetic rows only. Existing accounts' temporary role/status changes roll back.
do $personal_rpc_tests$
declare
  users uuid[]; actor integer; role_name text; function_name text; table_name text;
  tag_vegan uuid := gen_random_uuid(); tag_vegetarian uuid := gen_random_uuid();
  tag_inactive uuid := gen_random_uuid(); recipe_ids uuid[];
  complete_profile jsonb := '{"display_name":"Synthetic profile A","birth_date":"1995-02-20","weight_kg":70,"height_cm":175,"metabolic_sex":"female","activity_level":"moderate","goal":"maintain"}';
  invalid_profile jsonb; invalid_preferences text[]; bad_case integer;
  before_profile jsonb; after_profile jsonb; saved public.profiles;
  before_preferences uuid[]; after_preferences uuid[]; error_detail text;
  favorite_result boolean; favorite_retry_result boolean; missing_favorite_result boolean;
begin
  select array_agg(id order by id) into users from (
    select u.id from auth.users u left join public.account_status s on s.user_id=u.id
    where coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now())
    order by u.id limit 2
  ) chosen;
  if coalesce(array_length(users,1),0) <> 2 then
    raise exception 'FAIL: personal RPC rehearsal requires two existing active accounts';
  end if;
  if exists(select 1 from public.profiles) or exists(select 1 from public.user_dietary_preferences)
    or exists(select 1 from public.favorite_recipes) or exists(select 1 from public.recipes)
    or exists(select 1 from public.dietary_tags) then
    raise exception 'FAIL: personal RPC rehearsal requires empty new domain tables';
  end if;
  foreach role_name in array array['anon','authenticated'] loop
    if has_function_privilege(role_name,'public.lock_my_relational_account()','EXECUTE') then
      raise exception 'FAIL: internal account-lock helper is client-executable';
    end if;
    foreach table_name in array array['profiles','user_dietary_preferences','favorite_recipes'] loop
      if has_table_privilege(role_name,format('public.%I',table_name),'INSERT')
        or has_table_privilege(role_name,format('public.%I',table_name),'UPDATE')
        or has_table_privilege(role_name,format('public.%I',table_name),'DELETE') then
        raise exception 'FAIL: personal table has client DML grants';
      end if;
    end loop;
  end loop;
  foreach function_name in array array['public.save_my_profile(jsonb,text[],bigint)','public.set_my_favorite(uuid,boolean)'] loop
    if has_function_privilege('anon',function_name,'EXECUTE')
      or not has_function_privilege('authenticated',function_name,'EXECUTE') then
      raise exception 'FAIL: public RPC execution grants';
    end if;
  end loop;
  insert into public.user_roles(user_id,role) select unnest(users),'USER'
    on conflict(user_id) do update set role='USER';
  insert into public.account_status(user_id,active) select unnest(users),true
    on conflict(user_id) do update set active=true;
  insert into public.dietary_tags(id,tag_key,label,active) values
    (tag_vegan,'vegan','Synthetic vegan',true),
    (tag_vegetarian,'vegetarian','Synthetic vegetarian',true),
    (tag_inactive,'inactive-test','Synthetic inactive',false);
  recipe_ids := array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
  for actor in 1..6 loop
    insert into public.recipes(id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty,publication_status,active,is_deleted)
    values(recipe_ids[actor],case when actor in (3,4) then users[actor-2] else null end,
      case when actor in (3,4) then 'user' else 'official' end,
      'Synthetic RPC recipe',1,1,'easy',case when actor in (2,3,4) then 'draft' else 'published' end,
      actor<>5,actor=6);
  end loop;

  -- Positive controls: RPCs derive ownership from the JWT; no target user input.
  for actor in 1..2 loop
    perform set_config('request.jwt.claim.sub',users[actor]::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',users[actor],'role','authenticated')::text,true);
    execute 'set local role authenticated';
    select * into saved from public.save_my_profile(
      complete_profile || jsonb_build_object('display_name',case when actor=1 then 'Synthetic profile A' else 'Synthetic profile B' end),
      array['vegan','vegetarian'],0);
    if saved.user_id<>users[actor] or saved.version<>1 or saved.weight_kg<>70
      or saved.birth_date<>date '1995-02-20' or (select count(*) from public.profiles)<>1
      or (select count(*) from public.user_dietary_preferences)<>2 then
      raise exception 'FAIL: own profile create or A/B isolation';
    end if;
    -- Keep writes and observations in separate SQL statements: scalar
    -- subquery initplans may run before volatile expressions in one IF.
    favorite_result := public.set_my_favorite(recipe_ids[1],true);
    favorite_retry_result := public.set_my_favorite(recipe_ids[1],true);
    if favorite_result is distinct from true
      or favorite_retry_result is distinct from true
      or (select count(*) from public.favorite_recipes)<>1 then
      raise exception 'FAIL: favorite add retry is not idempotent';
    end if;
    execute 'reset role';
  end loop;

  perform set_config('request.jwt.claim.sub',users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select to_jsonb(p) into before_profile from public.profiles p where user_id=users[1];
  select array_agg(dietary_tag_id order by dietary_tag_id) into before_preferences from public.user_dietary_preferences;

  -- Each rejected input must leave both profile and preference rows unchanged.
  for bad_case in 1..30 loop
    invalid_profile := complete_profile;
    invalid_preferences := array['vegan','vegetarian'];
    case bad_case
      when 1 then invalid_profile := complete_profile || '{"user_id":"00000000-0000-0000-0000-000000000000"}';
      when 2 then invalid_profile := complete_profile || '{"email":"synthetic@example.invalid"}';
      when 3 then invalid_profile := complete_profile || '{"role":"ADMIN"}';
      when 4 then invalid_profile := complete_profile || '{"version":999}';
      when 5 then invalid_profile := complete_profile || '{"weight_kg":"70"}';
      when 6 then invalid_profile := complete_profile || '{"height_cm":"175"}';
      when 7 then invalid_profile := complete_profile || '{"weight_kg":29}';
      when 8 then invalid_profile := complete_profile || '{"height_cm":251}';
      when 9 then invalid_profile := complete_profile || '{"metabolic_sex":"invalid"}';
      when 10 then invalid_profile := complete_profile || '{"activity_level":"invalid"}';
      when 11 then invalid_profile := complete_profile || '{"goal":"invalid"}';
      when 12 then invalid_profile := complete_profile || '{"birth_date":"2026-02-30"}';
      when 13 then invalid_profile := complete_profile || jsonb_build_object('birth_date',to_char(current_date+1,'YYYY-MM-DD'));
      when 14 then invalid_profile := complete_profile || '{"birth_date":"20/02/1995"}';
      when 15 then invalid_profile := complete_profile || '{"display_name":"   "}';
      when 16 then invalid_profile := 'null';
      when 17 then invalid_profile := '[]';
      when 18 then invalid_profile := '"invalid"';
      when 19 then invalid_preferences := array['missing-test'];
      when 20 then invalid_preferences := array['inactive-test'];
      when 21 then invalid_preferences := array['vegan','vegan'];
      when 22 then invalid_preferences := null;
      when 23 then invalid_preferences := array['vegan',null];
      when 24 then invalid_profile := complete_profile || '{"birth_date":123}';
      when 25 then invalid_profile := complete_profile || '{"display_name":null}';
      when 26 then invalid_profile := complete_profile || '{"weight_kg":300.004}';
      when 27 then invalid_profile := complete_profile || '{"weight_kg":29.999}';
      when 28 then invalid_profile := complete_profile || '{"height_cm":250.004}';
      when 29 then invalid_profile := complete_profile || '{"height_cm":99.999}';
      when 30 then invalid_profile := null;
    end case;
    begin
      perform public.save_my_profile(invalid_profile,invalid_preferences,1);
      raise exception 'FAIL: invalid profile input accepted (case %)',bad_case;
    exception when sqlstate '22023' then
      get stacked diagnostics error_detail = pg_exception_detail;
      if coalesce(error_detail,'')<>'' then
        raise exception 'FAIL: profile validation exposes database DETAIL';
      end if;
    end;
    select to_jsonb(p) into after_profile from public.profiles p where user_id=users[1];
    select array_agg(dietary_tag_id order by dietary_tag_id) into after_preferences from public.user_dietary_preferences;
    if after_profile is distinct from before_profile or after_preferences is distinct from before_preferences then
      raise exception 'FAIL: invalid save partially changed profile or preferences';
    end if;
  end loop;
  begin
    perform public.save_my_profile('{"display_name":"Forbidden stale create"}',array[]::text[],0);
    raise exception 'FAIL: stale profile version accepted';
  exception when sqlstate '40001' then null;
  end;
  if (select to_jsonb(p) from public.profiles p where user_id=users[1]) is distinct from before_profile
    or (select array_agg(dietary_tag_id order by dietary_tag_id) from public.user_dietary_preferences) is distinct from before_preferences then
    raise exception 'FAIL: stale save changed data';
  end if;
  select * into saved from public.save_my_profile('{"display_name":"Synthetic partial"}',array['vegetarian'],1);
  if saved.version<>2 or saved.weight_kg is not null or saved.birth_date is not null
    or saved.height_cm is not null or saved.goal is not null or saved.activity_level is not null
    or saved.metabolic_sex is not null or (select count(*) from public.user_dietary_preferences)<>1
    or not exists(select 1 from public.user_dietary_preferences where dietary_tag_id=tag_vegetarian) then
    raise exception 'FAIL: full replacement or partial profile semantics';
  end if;
  select * into saved from public.save_my_profile('{"display_name":"Synthetic partial"}',array[]::text[],2);
  if saved.version<>3 or exists(select 1 from public.user_dietary_preferences) then
    raise exception 'FAIL: empty preferences do not clear previous values';
  end if;
  begin
    perform public.save_my_profile('{"display_name":"Stale overwrite"}',array['vegan'],2);
    raise exception 'FAIL: stale update accepted';
  exception when sqlstate '40001' then null;
  end;

  favorite_result := public.set_my_favorite(recipe_ids[3],true);
  if favorite_result is distinct from true
    or (select count(*) from public.favorite_recipes)<>2 then
    raise exception 'FAIL: own private recipe cannot be favorited';
  end if;
  for actor in 1..5 loop
    begin
      perform public.set_my_favorite(case actor when 1 then recipe_ids[2] when 2 then recipe_ids[4]
        when 3 then recipe_ids[5] when 4 then recipe_ids[6] else gen_random_uuid() end,true);
      raise exception 'FAIL: hidden/unavailable recipe accepted';
    exception when insufficient_privilege then null;
    end;
  end loop;
  if (select count(*) from public.favorite_recipes)<>2 then raise exception 'FAIL: rejected favorite mutated rows'; end if;
  for actor in 1..2 loop
    begin
      perform public.set_my_favorite(case when actor=1 then null else recipe_ids[1] end,
        case when actor=2 then null else true end);
      raise exception 'FAIL: null favorite input accepted';
    exception when sqlstate '22023' then null;
    end;
  end loop;
  foreach table_name in array array['profiles','user_dietary_preferences','favorite_recipes'] loop
    begin
      execute format('delete from public.%I',table_name);
      raise exception 'FAIL: direct personal-table delete allowed';
    exception when insufficient_privilege then null;
    end;
  end loop;
  begin
    perform public.lock_my_relational_account();
    raise exception 'FAIL: internal helper execution allowed';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';

  -- Admin recipe visibility does not authorize favoriting another user's draft.
  update public.user_roles set role='ADMIN' where user_id=users[1];
  execute 'set local role authenticated';
  if public.current_app_role()<>'ADMIN' or not exists(select 1 from public.recipes where id=recipe_ids[4]) then
    raise exception 'FAIL: administrator fixture positive control';
  end if;
  begin
    perform public.set_my_favorite(recipe_ids[4],true);
    raise exception 'FAIL: administrator favorited another account private recipe';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';
  update public.user_roles set role='USER' where user_id=users[1];
  update public.recipes set active=false where id=recipe_ids[1];
  execute 'set local role authenticated';
  favorite_result := public.set_my_favorite(recipe_ids[1],false);
  favorite_retry_result := public.set_my_favorite(recipe_ids[1],false);
  missing_favorite_result := public.set_my_favorite(gen_random_uuid(),false);
  if favorite_result is distinct from false
    or favorite_retry_result is distinct from false
    or missing_favorite_result is distinct from false
    or (select count(*) from public.favorite_recipes)<>1 then
    raise exception 'FAIL: archived favorite removal/retry';
  end if;
  begin
    perform public.set_my_favorite(recipe_ids[1],true);
    raise exception 'FAIL: archived favorite can be added';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';
  if not exists(select 1 from public.favorite_recipes where user_id=users[2] and recipe_id=recipe_ids[1])
    or (select display_name from public.profiles where user_id=users[2])<>'Synthetic profile B'
    or (select version from public.profiles where user_id=users[2])<>1
    or (select count(*) from public.user_dietary_preferences where user_id=users[2])<>2 then
    raise exception 'FAIL: A writes/removal changed B data';
  end if;

  -- Both RPCs require an active claimed identity, even with a valid old JWT.
  update public.account_status set active=false where user_id=users[1];
  for actor in 1..3 loop
    if actor=1 then
      perform set_config('request.jwt.claim.sub',users[1]::text,true);
      perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
      execute 'set local role authenticated';
    else
      perform set_config('request.jwt.claim.sub','',true);
      perform set_config('request.jwt.claims','{}',true);
      if actor=2 then execute 'set local role authenticated'; else execute 'set local role anon'; end if;
    end if;
    begin
      perform public.save_my_profile('{"display_name":"Forbidden caller"}',array[]::text[],3);
      raise exception 'FAIL: inactive/anonymous/unclaimed profile save allowed';
    exception when insufficient_privilege then null;
    end;
    begin
      perform public.set_my_favorite(recipe_ids[3],false);
      raise exception 'FAIL: inactive/anonymous/unclaimed favorite removal allowed';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
  end loop;
  if (select version from public.profiles where user_id=users[1])<>3
    or not exists(select 1 from public.favorite_recipes where user_id=users[1] and recipe_id=recipe_ids[3]) then
    raise exception 'FAIL: unauthorized RPC changed state';
  end if;
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
end;
$personal_rpc_tests$;
select 'PASS: personal write RPCs, profile validation/atomic preferences/version conflicts, favorite ownership/idempotency, A/B isolation, unavailable recipes and inactive/anonymous caller restrictions verified; wrapper ROLLBACK required' as result;

rollback;
