-- LOCAL ONLY: complete the deliberately minimal backfill pantry fixture.
alter table public.pantry_items add column user_id uuid references auth.users(id),
  add column category text default 'Otros', add column minimum numeric(12,3) default 0,
  add column expiry date, add column created_at timestamptz default now(),
  add column updated_at timestamptz default now(), add column source_shopping_ids text[] not null default '{}';
alter table public.pantry_items alter column quantity type numeric(12,3),
  add constraint pantry_quantity_test check(quantity>=0 and quantity<=1000000),
  add constraint pantry_category_test check(length(trim(category)) between 1 and 80),
  add constraint pantry_unit_test check(length(trim(unit)) between 1 and 24);
alter table public.pantry_items enable row level security;
grant select,insert,update,delete on public.pantry_items to authenticated;
create policy pantry_owner_fixture on public.pantry_items for all to authenticated using(user_id=auth.uid() and public.current_account_is_active()) with check(user_id=auth.uid() and public.current_account_is_active());
