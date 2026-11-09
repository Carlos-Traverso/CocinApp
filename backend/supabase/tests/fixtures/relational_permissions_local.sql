-- LOCAL ONLY: simulated Auth, actual application helper definitions below.
alter table auth.users add column banned_until timestamptz, add column created_at timestamptz default now();
insert into auth.users(id) values('22222222-2222-2222-2222-222222222222');
create or replace function auth.uid() returns uuid language sql stable as $$
 select coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid
$$;
grant usage on schema auth to authenticated, anon;
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
begin;

-- Application access is managed transactionally without writing Auth internals.
create table if not exists public.account_status (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.account_status enable row level security;
revoke all on table public.account_status from public, anon, authenticated;
grant select on table public.account_status to authenticated;
drop policy if exists "Users can read their own account status" on public.account_status;
create policy "Users can read their own account status"
  on public.account_status for select to authenticated
  using (user_id = (select auth.uid()));

-- Preserve existing bans. New accounts without a status row are active by default.
insert into public.account_status(user_id, active)
  select id, (banned_until is null or banned_until <= now()) from auth.users
  on conflict (user_id) do nothing;

create or replace function public.current_account_is_active()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from auth.users as users
    left join public.account_status as status on status.user_id = users.id
    where users.id = (select auth.uid())
      and coalesce(status.active, true)
      and (users.banned_until is null or users.banned_until <= now())
  );
$$;
revoke all on function public.current_account_is_active() from public, anon;
grant execute on function public.current_account_is_active() to authenticated;

commit;
create or replace function public.current_app_role()
returns text
language sql stable security invoker
set search_path = ''
as $$
  select case when public.current_account_is_active() then coalesce(
    (select role from public.user_roles where user_id = (select auth.uid())),
    'USER'
  ) else 'USER' end;
$$;
revoke all on function public.current_app_role() from public, anon;
grant execute on function public.current_app_role() to authenticated;
