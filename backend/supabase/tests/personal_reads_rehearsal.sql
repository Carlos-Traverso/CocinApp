-- PERSONAL READS REHEARSAL: run the whole file as postgres; preserve final ROLLBACK.
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

-- STAGE ONLY: schema 002, RPC stack through recipe discovery, personal read 006,
-- and this stage in one transaction. The wrapper must end in ROLLBACK.
do $personal_reads$
declare
  v_users uuid[]; synthetic uuid := gen_random_uuid();
  tag_active uuid := gen_random_uuid(); tag_inactive uuid := gen_random_uuid();
  r_official uuid := gen_random_uuid(); r_own uuid := gen_random_uuid();
  r_foreign uuid := gen_random_uuid(); r_inactive uuid := gen_random_uuid(); r_deleted uuid := gen_random_uuid();
  r_unpublished uuid := gen_random_uuid();
  p_main uuid := gen_random_uuid(); p_empty uuid := gen_random_uuid();
  week_start date := date '2026-11-02'; result jsonb; item jsonb; ids uuid[];
  routine text; table_name text; before_profile jsonb; before_preferences jsonb;
  before_plan jsonb; before_slots jsonb; bad_date date;
begin
  select array_agg(id order by id) into v_users from (
    select u.id from auth.users u left join public.account_status s on s.user_id=u.id
    where coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now())
    order by u.id limit 2
  ) picked;
  if coalesce(array_length(v_users,1),0) is distinct from 2 then
    raise exception 'FAIL: personal reads rehearsal requires two existing active accounts';
  end if;
  insert into auth.users(id) values(synthetic);
  -- Auth triggers may create a profile; remove only this synthetic account's row
  -- so the blank-default assertion exercises the RPC's empty state.
  delete from public.profiles where user_id=synthetic;
  insert into public.user_roles(user_id,role) values(v_users[1],'USER'),(v_users[2],'USER'),(synthetic,'USER')
    on conflict(user_id) do update set role=excluded.role;
  insert into public.account_status(user_id,active) values(v_users[1],true),(v_users[2],true),(synthetic,true)
    on conflict(user_id) do update set active=true;
  insert into public.dietary_tags(id,tag_key,label,active) values
    (tag_active,'reads-active','Reads active',true),(tag_inactive,'reads-retired','Reads retired',true);

  insert into public.recipes(id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
    values(r_official,null,'official','Personal reads published',15,2,'easy','published'),
      (r_own,v_users[1],'user','Personal reads own private',20,2,'easy','draft'),
      (r_foreign,v_users[1],'user','Personal reads reassigned private',25,2,'easy','draft'),
      (r_inactive,null,'official','Personal reads inactive',10,1,'easy','published'),
      (r_deleted,null,'official','Personal reads deleted',10,1,'easy','published'),
      (r_unpublished,null,'official','Personal reads unpublished',10,1,'easy','published');
  update public.recipes set active=false where id=r_inactive;
  update public.recipes set is_deleted=true where id=r_deleted;
  insert into public.favorite_recipes(user_id,recipe_id,created_at) values
    (v_users[1],r_official,'2026-01-01 00:00:00+00'),(v_users[1],r_own,'2026-01-01 00:00:00+00'),
    (v_users[1],r_foreign,'2026-01-01 00:00:00+00'),(v_users[1],r_inactive,'2026-01-02 00:00:00+00'),
    (v_users[1],r_deleted,'2026-01-03 00:00:00+00'),(v_users[1],r_unpublished,'2026-01-01 00:00:00+00');

  -- The normal write path establishes a versioned profile and both live and
  -- retired preferences. Reads must retain previously saved inactive keys.
  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.save_my_profile('{"display_name":"Reads profile","weight_kg":72.5}',array['reads-active','reads-retired'],0);
  execute 'reset role';
  update public.dietary_tags set active=false where id=tag_inactive;

  insert into public.meal_plans(id,owner_user_id,week_start) values(p_main,v_users[1],week_start),(p_empty,v_users[2],week_start);
  insert into public.meal_plan_slots(id,plan_id,meal_date,meal_shift,recipe_id,portions,position) values
    (gen_random_uuid(),p_main,week_start+1,'dinner',r_official,2,2),
    (gen_random_uuid(),p_main,week_start,'snack',r_inactive,1,1),
    (gen_random_uuid(),p_main,week_start,'breakfast',r_official,1,2),
    (gen_random_uuid(),p_main,week_start,'breakfast',r_official,1,1),
    (gen_random_uuid(),p_main,week_start,'lunch',r_foreign,2,1),
    (gen_random_uuid(),p_main,week_start,'lunch',r_unpublished,1,2);
  -- Start as visible so fixture link validation succeeds, then model the recipe
  -- becoming private after the saved plan (and favorite) already references it.
  update public.recipes set owner_user_id=v_users[2] where id=r_foreign;
  update public.recipes set publication_status='draft' where id=r_unpublished;

  foreach routine in array array['public.get_my_profile()','public.get_my_favorites(integer,integer)','public.get_my_meal_plan(date)'] loop
    if has_function_privilege('anon',routine,'EXECUTE') or has_function_privilege('service_role',routine,'EXECUTE')
      or not has_function_privilege('authenticated',routine,'EXECUTE') then
      raise exception 'FAIL: personal read execution grants for %',routine;
    end if;
  end loop;
  if has_function_privilege('anon','public.lock_my_relational_account()','EXECUTE')
    or has_function_privilege('authenticated','public.lock_my_relational_account()','EXECUTE')
    or has_function_privilege('service_role','public.lock_my_relational_account()','EXECUTE') then
    raise exception 'FAIL: account lock helper is executable by clients or service role';
  end if;

  -- Synthetic account: profile row is null and keys are an empty JSON array.
  perform set_config('request.jwt.claim.sub',synthetic::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',synthetic,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result:=public.get_my_profile();
  if result->'profile' is distinct from 'null'::jsonb or result->'preference_keys' is distinct from '[]'::jsonb then
    raise exception 'FAIL: synthetic account blank profile defaults: %',result;
  end if;
  result:=public.get_my_favorites();
  if result->'items' is distinct from '[]'::jsonb or (result->>'total')::integer is distinct from 0
    or (result->>'limit')::integer is distinct from 30 or (result->>'offset')::integer is distinct from 0 then
    raise exception 'FAIL: synthetic account blank favorites defaults: %',result;
  end if;
  result:=public.get_my_meal_plan(week_start);
  if result->'plan' is distinct from 'null'::jsonb or result->'slots' is distinct from '[]'::jsonb then
    raise exception 'FAIL: missing plan defaults: %',result;
  end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result:=public.get_my_profile();
  if result->'profile'->>'user_id' is distinct from v_users[1]::text
    or (result->'profile'->>'version')::bigint is distinct from 1
    or result->'profile'->>'display_name' is distinct from 'Reads profile'
    or result->'preference_keys' is distinct from '["reads-active","reads-retired"]'::jsonb then
    raise exception 'FAIL: profile, version, or saved inactive preferences changed in read: %',result;
  end if;
  execute 'reset role';
  select to_jsonb(p) into before_profile from public.profiles p where user_id=v_users[1];
  select coalesce(jsonb_agg(jsonb_build_object('tag_key',t.tag_key,'created_at',pref.created_at) order by t.tag_key),'[]'::jsonb)
    into before_preferences from public.user_dietary_preferences pref join public.dietary_tags t on t.id=pref.dietary_tag_id where pref.user_id=v_users[1];
  execute 'set local role authenticated';
  result:=public.get_my_favorites(30,0);
  if (result->>'total')::integer is distinct from 6 or (result->>'limit')::integer is distinct from 30
    or (result->>'offset')::integer is distinct from 0 or jsonb_array_length(result->'items') is distinct from 6 then
    raise exception 'FAIL: favorites total and response metadata';
  end if;
  item:=result->'items'->0;
  if item->>'recipe_id' is distinct from r_deleted::text or item->>'available' is distinct from 'false'
    or item->'recipe' is distinct from 'null'::jsonb then raise exception 'FAIL: deleted favorite remains hidden: %',item; end if;
  item:=result->'items'->1;
  if item->>'recipe_id' is distinct from r_inactive::text or item->>'available' is distinct from 'false'
    or item->'recipe' is distinct from 'null'::jsonb then raise exception 'FAIL: inactive favorite remains hidden: %',item; end if;
  if not exists(select 1 from jsonb_array_elements(result->'items') x where x->>'recipe_id'=r_unpublished::text
    and x->>'available'='false' and x->'recipe'='null'::jsonb) then
    raise exception 'FAIL: unpublished official favorite remains listed but hidden';
  end if;
  -- Equal created_at entries must use recipe_id DESC, including across pages.
  result:=public.get_my_favorites(1,2);
  if (result->>'total')::integer is distinct from 6 or jsonb_array_length(result->'items') is distinct from 1
    or result->'items'->0->>'recipe_id' is distinct from greatest(r_official,r_own,r_foreign,r_unpublished)::text then
    raise exception 'FAIL: stable favorite tie ordering/page or total-before-page';
  end if;
  if (select count(*) from jsonb_array_elements(public.get_my_favorites(100,0)->'items') x
      where x->>'available'='true' and x->'recipe' is not null and x->'recipe'<>'null'::jsonb)<>2
    or (select count(*) from jsonb_array_elements(public.get_my_favorites(100,0)->'items') x
      where x->>'available'='false' and x->'recipe'='null'::jsonb)<>4 then
    raise exception 'FAIL: favorite visibility payloads, including foreign private recipe isolation';
  end if;
  execute 'reset role';
  update public.user_roles set role='ADMIN' where user_id=v_users[1];
  execute 'set local role authenticated';
  if public.current_app_role() is distinct from 'ADMIN' then raise exception 'FAIL: admin fixture'; end if;
  result:=public.get_my_favorites(100,0);
  if exists(select 1 from jsonb_array_elements(result->'items') x where x->>'recipe_id'=r_foreign::text
    and (x->>'available'<>'false' or x->'recipe'<>'null'::jsonb)) then
    raise exception 'FAIL: admin read exposes foreign private favorite';
  end if;
  execute 'reset role';
  update public.user_roles set role='USER' where user_id=v_users[1];
  execute 'set local role authenticated';

  result:=public.get_my_meal_plan(week_start);
  if result->'plan'->>'id' is distinct from p_main::text or (result->'plan'->>'version')::bigint is distinct from 1
    or jsonb_array_length(result->'slots') is distinct from 6 then raise exception 'FAIL: existing plan/version/slot response'; end if;
  ids:=array(select (x->>'id')::uuid from jsonb_array_elements(result->'slots') x);
  -- Canonical order: date, breakfast/lunch/snack/dinner, position, id.
  if result->'slots'->0->>'meal_shift' is distinct from 'breakfast'
    or (result->'slots'->0->>'position')::integer is distinct from 1
    or result->'slots'->1->>'meal_shift' is distinct from 'breakfast'
    or result->'slots'->2->>'meal_shift' is distinct from 'lunch'
    or result->'slots'->3->>'meal_shift' is distinct from 'lunch'
    or result->'slots'->4->>'meal_shift' is distinct from 'snack'
    or result->'slots'->5->>'meal_shift' is distinct from 'dinner' then
    raise exception 'FAIL: meal plan slot canonical order: %',result->'slots';
  end if;
  if result->'slots'->2->>'available' is distinct from 'false'
    or result->'slots'->2->'recipe' is distinct from 'null'::jsonb
    or result->'slots'->3->>'available' is distinct from 'false'
    or result->'slots'->3->'recipe' is distinct from 'null'::jsonb then
    raise exception 'FAIL: private foreign or unpublished official slot recipe leaked';
  end if;
  select to_jsonb(mp) into before_plan from public.meal_plans mp where id=p_main;
  select coalesce(jsonb_agg(to_jsonb(s) order by s.meal_date,s.meal_shift,s.position,s.id),'[]'::jsonb)
    into before_slots from public.meal_plan_slots s where plan_id=p_main;
  result:=public.get_my_meal_plan(week_start);
  if result->'plan' is distinct from before_plan or result->'slots' is null then raise exception 'FAIL: repeated snapshot plan read'; end if;
  execute 'reset role';

  -- A second account's profile, favorites and already-existing empty plan are isolated.
  perform set_config('request.jwt.claim.sub',v_users[2]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[2],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result:=public.get_my_profile();
  if result->'profile' is distinct from 'null'::jsonb or result->'preference_keys' is distinct from '[]'::jsonb then raise exception 'FAIL: user profiles are not isolated'; end if;
  result:=public.get_my_favorites();
  if (result->>'total')::integer is distinct from 0 or result->'items' is distinct from '[]'::jsonb then raise exception 'FAIL: user favorites are not isolated'; end if;
  result:=public.get_my_meal_plan(week_start);
  if result->'plan'->>'id' is distinct from p_empty::text or (result->'plan'->>'version')::bigint is distinct from 1
    or result->'slots' is distinct from '[]'::jsonb then raise exception 'FAIL: existing empty plan/version not preserved'; end if;
  execute 'reset role';

  -- Validation: limits and offsets, including NULL, and finite Monday dates.
  foreach routine in array array['get_my_favorites'] loop
    foreach table_name in array array['0,0','101,0','1,-1','1,5001','NULL,0','1,NULL'] loop
      begin execute format('select public.%I(%s)',routine,table_name); raise exception 'FAIL: accepted favorite bounds %',table_name;
      exception when sqlstate '22023' then null; end;
    end loop;
  end loop;
  foreach table_name in array array['NULL','date ''2026-11-03''','date ''infinity''','date ''-infinity'''] loop
    begin execute format('select public.get_my_meal_plan(%s)',table_name); raise exception 'FAIL: accepted invalid week %',table_name;
    exception when sqlstate '22023' then null; end;
  end loop;
  execute 'reset role';

  -- Read RPCs reject anonymous, missing-identity, inactive, banned, and service_role callers.
  perform set_config('request.jwt.claim.sub','',true); perform set_config('request.jwt.claims','{"role":"anon"}',true);
  execute 'set local role anon';
  begin perform public.get_my_profile(); raise exception 'FAIL: anon profile read'; exception when insufficient_privilege then null; end;
  begin perform public.get_my_favorites(); raise exception 'FAIL: anon favorites read'; exception when insufficient_privilege then null; end;
  begin perform public.get_my_meal_plan(week_start); raise exception 'FAIL: anon plan read'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true); execute 'set local role authenticated';
  begin perform public.get_my_profile(); raise exception 'FAIL: missing identity read'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  execute 'reset role';
  update public.account_status set active=false where user_id=v_users[1];
  perform set_config('request.jwt.claim.sub',v_users[1]::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin perform public.get_my_profile(); raise exception 'FAIL: inactive profile read'; exception when insufficient_privilege then null; end;
  begin perform public.get_my_favorites(); raise exception 'FAIL: inactive favorites read'; exception when insufficient_privilege then null; end;
  begin perform public.get_my_meal_plan(week_start); raise exception 'FAIL: inactive plan read'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.account_status set active=true where user_id=v_users[1];
  update auth.users set banned_until=now()+interval '1 day' where id=v_users[1];
  execute 'set local role authenticated';
  begin perform public.get_my_profile(); raise exception 'FAIL: banned profile read'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update auth.users set banned_until=null where id=v_users[1];
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  execute 'set local role service_role';
  begin perform public.get_my_profile(); raise exception 'FAIL: service_role profile read'; exception when insufficient_privilege then null; end;
  execute 'reset role';

  if (select to_jsonb(p) from public.profiles p where user_id=v_users[1]) is distinct from before_profile
    or (select coalesce(jsonb_agg(jsonb_build_object('tag_key',t.tag_key,'created_at',pref.created_at) order by t.tag_key),'[]'::jsonb)
        from public.user_dietary_preferences pref join public.dietary_tags t on t.id=pref.dietary_tag_id where pref.user_id=v_users[1]) is distinct from before_preferences
    or (select to_jsonb(mp) from public.meal_plans mp where id=p_main) is distinct from before_plan
    or (select coalesce(jsonb_agg(to_jsonb(s) order by s.meal_date,s.meal_shift,s.position,s.id),'[]'::jsonb) from public.meal_plan_slots s where plan_id=p_main) is distinct from before_slots then
    raise exception 'FAIL: personal read RPCs changed persistent profile/preferences/plan/slots';
  end if;
  perform set_config('request.jwt.claim.sub','',true); perform set_config('request.jwt.claims','{}',true);
  raise notice 'PASS: personal read RPC snapshots, ownership, stable pagination, hidden recipes, blank defaults, validation, and caller permissions';
end;
$personal_reads$;
select 'PASS: personal read RPC rehearsal complete; wrapper ROLLBACK required' as result;

rollback;
