begin;

-- One shared recipe catalog managed by administrators.
create table if not exists public.shared_recipes (
  catalog_key text primary key default 'main' check (catalog_key = 'main'),
  recipes jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  constraint shared_recipes_payload_shape check (jsonb_typeof(recipes) = 'array')
);

alter table public.shared_recipes enable row level security;
revoke all on table public.shared_recipes from anon, authenticated;
grant select, insert, update on table public.shared_recipes to authenticated;

drop policy if exists "Authenticated users can read shared recipes" on public.shared_recipes;
create policy "Authenticated users can read shared recipes"
  on public.shared_recipes for select
  to authenticated
  using (true);

drop policy if exists "Admins can create shared recipes" on public.shared_recipes;
create policy "Admins can create shared recipes"
  on public.shared_recipes for insert
  to authenticated
  with check ((select public.current_app_role()) = 'ADMIN');

drop policy if exists "Admins can update shared recipes" on public.shared_recipes;
create policy "Admins can update shared recipes"
  on public.shared_recipes for update
  to authenticated
  using ((select public.current_app_role()) = 'ADMIN')
  with check ((select public.current_app_role()) = 'ADMIN');

commit;
