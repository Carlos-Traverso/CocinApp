begin;

create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default clock_timestamp(),
  actor_user_id uuid references auth.users (id) on delete set null,
  action text not null check (action in (
    'user.created',
    'user.name_updated',
    'user.role_changed',
    'user.activated',
    'user.deactivated',
    'catalog.core_saved',
    'catalog.recipes_saved'
  )),
  target_user_id uuid references auth.users (id) on delete set null,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object')
);

create index if not exists admin_audit_log_occurred_at_idx
  on public.admin_audit_log (occurred_at desc, id desc);
create index if not exists admin_audit_log_actor_idx
  on public.admin_audit_log (actor_user_id, occurred_at desc);

alter table public.admin_audit_log enable row level security;
revoke all on table public.admin_audit_log from public, anon, authenticated;
grant insert on table public.admin_audit_log to service_role;

create or replace function public.capture_admin_audit_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_action text;
  event_target uuid;
  event_details jsonb := '{}'::jsonb;
begin
  if tg_table_name = 'user_roles' then
    if tg_op = 'UPDATE' and old.role is not distinct from new.role then return new; end if;
    event_action := 'user.role_changed';
    event_target := new.user_id;
    event_details := jsonb_build_object(
      'old_role', case when tg_op = 'INSERT' then null else old.role end,
      'new_role', new.role
    );
  elsif tg_table_name = 'account_status' then
    if tg_op = 'UPDATE' and old.active is not distinct from new.active then return new; end if;
    event_action := case when new.active then 'user.activated' else 'user.deactivated' end;
    event_target := new.user_id;
    event_details := jsonb_build_object('active', new.active);
  elsif tg_table_name = 'catalog_core' then
    if tg_op = 'UPDATE' and old.payload is not distinct from new.payload then return new; end if;
    event_action := 'catalog.core_saved';
    event_details := jsonb_build_object('version', new.version);
  elsif tg_table_name = 'shared_recipes' then
    if tg_op = 'UPDATE' and old.recipes is not distinct from new.recipes then return new; end if;
    event_action := 'catalog.recipes_saved';
    event_details := jsonb_build_object('version', new.version);
  else
    return new;
  end if;

  insert into public.admin_audit_log(actor_user_id, action, target_user_id, details)
  values ((select auth.uid()), event_action, event_target, event_details);
  return new;
end;
$$;
revoke all on function public.capture_admin_audit_event() from public, anon, authenticated;

drop trigger if exists admin_audit_user_roles on public.user_roles;
create trigger admin_audit_user_roles
  after insert or update on public.user_roles
  for each row execute function public.capture_admin_audit_event();

drop trigger if exists admin_audit_account_status on public.account_status;
create trigger admin_audit_account_status
  after insert or update on public.account_status
  for each row execute function public.capture_admin_audit_event();

drop trigger if exists admin_audit_catalog_core on public.catalog_core;
create trigger admin_audit_catalog_core
  after insert or update on public.catalog_core
  for each row execute function public.capture_admin_audit_event();

drop trigger if exists admin_audit_shared_recipes on public.shared_recipes;
create trigger admin_audit_shared_recipes
  after insert or update on public.shared_recipes
  for each row execute function public.capture_admin_audit_event();

create or replace function public.admin_list_audit_events(p_limit integer default 100)
returns table (
  id uuid,
  occurred_at timestamptz,
  actor_email text,
  action text,
  target_email text,
  details jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or (select public.current_app_role()) <> 'ADMIN'
    or not (select public.current_account_is_active()) then
    raise exception 'Solo un administrador activo puede consultar el historial.' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception 'El límite debe estar entre 1 y 200.' using errcode = '22023';
  end if;

  return query
  select events.id,
    events.occurred_at,
    actor.email::text,
    events.action,
    target.email::text,
    events.details
  from public.admin_audit_log as events
  left join auth.users as actor on actor.id = events.actor_user_id
  left join auth.users as target on target.id = events.target_user_id
  order by events.occurred_at desc, events.id desc
  limit p_limit;
end;
$$;
revoke all on function public.admin_list_audit_events(integer) from public, anon;
grant execute on function public.admin_list_audit_events(integer) to authenticated;

commit;
