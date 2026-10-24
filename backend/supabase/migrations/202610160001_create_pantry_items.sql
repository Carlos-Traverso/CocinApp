-- Stores one user's pantry inventory. Row Level Security keeps each account's
-- data private even when requests come directly from the frontend.
create table if not exists public.pantry_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 120),
  category text not null check (length(trim(category)) between 1 and 80),
  quantity numeric(12, 3) not null default 0 check (quantity >= 0 and quantity <= 1000000),
  unit text not null check (length(trim(unit)) between 1 and 24),
  minimum numeric(12, 3) not null default 0 check (minimum >= 0 and minimum <= 1000000),
  expiry date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists pantry_items_user_id_idx
  on public.pantry_items (user_id);

alter table public.pantry_items enable row level security;

create policy "Users can read their own pantry items"
  on public.pantry_items for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can add items to their own pantry"
  on public.pantry_items for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update their own pantry items"
  on public.pantry_items for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can remove items from their own pantry"
  on public.pantry_items for delete
  to authenticated
  using ((select auth.uid()) = user_id);
