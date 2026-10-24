-- Stores per-user profile, favorite recipes, and meal planning data.
-- Each account can only access its own rows through Row Level Security.
create table if not exists public.personal_data (
  user_id uuid not null references auth.users (id) on delete cascade,
  data_key text not null,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, data_key)
);

-- CREATE TABLE IF NOT EXISTS does not update constraints on an existing table.
-- Replace the allowed keys so this migration can be safely rerun after upgrades.
alter table public.personal_data
  drop constraint if exists personal_data_data_key_check;

alter table public.personal_data
  add constraint personal_data_data_key_check
  check (data_key in ('profile', 'favorites', 'meal_plan', 'shopping', 'cooking_progress', 'cooking_history'));

alter table public.personal_data enable row level security;

drop policy if exists "Users can read their own personal data" on public.personal_data;
drop policy if exists "Users can add their own personal data" on public.personal_data;
drop policy if exists "Users can update their own personal data" on public.personal_data;
drop policy if exists "Users can remove their own personal data" on public.personal_data;

create policy "Users can read their own personal data"
  on public.personal_data for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can add their own personal data"
  on public.personal_data for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update their own personal data"
  on public.personal_data for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can remove their own personal data"
  on public.personal_data for delete
  to authenticated
  using ((select auth.uid()) = user_id);
