-- Run the whole script after migration 202610240001_admin_audit_log.sql.
-- Requires at least one active USER and one active ADMIN account.
begin;

do $$
declare
  user_id uuid;
  admin_id uuid;
begin
  select users.id into user_id
  from auth.users as users
  join public.user_roles as roles on roles.user_id = users.id
  left join public.account_status as status on status.user_id = users.id
  where roles.role = 'USER' and coalesce(status.active, true)
    and (users.banned_until is null or users.banned_until <= now())
  order by users.created_at, users.id limit 1;

  select users.id into admin_id
  from auth.users as users
  join public.user_roles as roles on roles.user_id = users.id
  left join public.account_status as status on status.user_id = users.id
  where roles.role = 'ADMIN' and coalesce(status.active, true)
    and (users.banned_until is null or users.banned_until <= now())
  order by users.created_at, users.id limit 1;

  if user_id is null or admin_id is null then
    raise exception 'Se necesita una cuenta activa USER y otra activa ADMIN.';
  end if;
  perform set_config('test.audit_user', user_id::text, true);
  perform set_config('test.audit_admin', admin_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.audit_user'), 'role', 'authenticated')::text, true);

do $$
begin
  begin
    perform count(*) from public.admin_audit_log;
    raise exception 'FAIL: USER can read the audit table directly';
  exception when insufficient_privilege then null;
  end;
  begin
    perform count(*) from public.admin_list_audit_events(1);
    raise exception 'FAIL: USER can read events through the administrator function';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.admin_audit_log(action) values ('user.created');
    raise exception 'FAIL: USER can insert a forged audit event';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.audit_admin'), 'role', 'authenticated')::text, true);

do $$
begin
  perform count(*) from public.admin_list_audit_events(1);
  begin
    delete from public.admin_audit_log;
    raise exception 'FAIL: ADMIN can delete audit events from the client';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
rollback;
select 'PASS: only an active administrator can read audit events, and client accounts cannot alter the history' as result;
