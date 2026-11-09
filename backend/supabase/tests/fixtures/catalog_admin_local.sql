-- LOCAL ISOLATED DATABASE ONLY. Add-on after the shared relational bootstrap.
-- Models the real admin audit table shape/action constraint; no Auth or helper mocks.
create table public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default clock_timestamp(),
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null check (action in (
    'user.created','user.name_updated','user.role_changed','user.activated','user.deactivated',
    'catalog.core_saved','catalog.recipes_saved'
  )),
  target_user_id uuid references auth.users(id) on delete set null,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object')
);
alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from public, anon, authenticated;
