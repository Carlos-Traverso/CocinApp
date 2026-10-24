-- Keep optional pantry links used by shopping and ingredient catalog flows.
alter table public.pantry_items
  add column if not exists ingredient_id text,
  add column if not exists source_shopping_ids text[] not null default '{}';
