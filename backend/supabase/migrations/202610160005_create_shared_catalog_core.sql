begin;

-- Shared administrator-managed categories, units, and ingredients.
-- Recipes remain in the existing local catalog until their own migration.
create table if not exists public.catalog_core (
  catalog_key text primary key default 'main' check (catalog_key = 'main'),
  payload jsonb not null default '{"categories": [], "units": [], "ingredients": []}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint catalog_core_payload_shape check (
    jsonb_typeof(payload) = 'object'
    and jsonb_typeof(payload -> 'categories') = 'array'
    and jsonb_typeof(payload -> 'units') = 'array'
    and jsonb_typeof(payload -> 'ingredients') = 'array'
  )
);

alter table public.catalog_core enable row level security;
revoke all on table public.catalog_core from anon, authenticated;
grant select, insert, update on table public.catalog_core to authenticated;

drop policy if exists "Authenticated users can read shared catalog" on public.catalog_core;
create policy "Authenticated users can read shared catalog"
  on public.catalog_core for select
  to authenticated
  using (true);

drop policy if exists "Admins can create shared catalog" on public.catalog_core;
create policy "Admins can create shared catalog"
  on public.catalog_core for insert
  to authenticated
  with check ((select public.current_app_role()) = 'ADMIN');

drop policy if exists "Admins can update shared catalog" on public.catalog_core;
create policy "Admins can update shared catalog"
  on public.catalog_core for update
  to authenticated
  using ((select public.current_app_role()) = 'ADMIN')
  with check ((select public.current_app_role()) = 'ADMIN');

commit;
