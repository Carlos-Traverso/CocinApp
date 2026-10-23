begin;

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'USER' check (role in ('USER', 'ADMIN')),
  updated_at timestamptz not null default now()
);

alter table public.user_roles enable row level security;
revoke all on table public.user_roles from anon, authenticated;
grant select on table public.user_roles to authenticated;

drop policy if exists "Users can read their own role" on public.user_roles;
create policy "Users can read their own role"
  on public.user_roles for select to authenticated
  using ((select auth.uid()) = user_id);

-- Missing rows mean USER. Only the SQL Editor / trusted server can assign roles.
-- User-editable auth metadata is never consulted for authorization.
create or replace function public.current_app_role()
returns text
language sql stable security invoker
set search_path = ''
as $$
  select coalesce(
    (select role from public.user_roles where user_id = (select auth.uid())),
    'USER'
  );
$$;

revoke all on function public.current_app_role() from public, anon;
grant execute on function public.current_app_role() to authenticated;

commit;
