-- STAGE ONLY: verifies relational profile names and both actor/target search paths.
-- The runner wraps this script in a rollback-only transaction.
do $admin_audit_names$
declare
  actor uuid;
  target uuid;
  event_id uuid := gen_random_uuid();
  found_event record;
begin
  select id into actor from auth.users
    where email is not null and (banned_until is null or banned_until <= now())
    order by created_at desc limit 1;
  select id into target from auth.users
    where email is not null and id is distinct from actor and (banned_until is null or banned_until <= now())
    order by created_at desc limit 1;
  if actor is null or target is null then
    raise exception 'FAIL: rehearsal requires two existing, unbanned Auth accounts';
  end if;

  insert into public.roles_usuario(user_id, role) values(actor, 'ADMIN')
    on conflict(user_id) do update set role = excluded.role;
  insert into public.estado_cuenta(user_id, active) values(actor, true)
    on conflict(user_id) do update set active = excluded.active;
  insert into public.perfiles(user_id, display_name, version)
    values(actor, 'Relational Actor', 1), (target, 'Relational Target', 1)
    on conflict(user_id) do update set display_name = excluded.display_name;
  insert into public.registro_auditoria(id, actor_user_id, target_user_id, action, details)
    values(event_id, actor, target, 'user.name_updated', '{}'::jsonb);

  perform set_config('request.jwt.claim.sub', actor::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', actor, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  select * into found_event from public.admin_search_audit_events('Relational Actor', 200) where id = event_id;
  if found_event.id is null or found_event.actor_name is distinct from 'Relational Actor'
    or found_event.target_name is distinct from 'Relational Target' then
    raise exception 'FAIL: profile display names were not returned for actor and target';
  end if;
  if not exists(select 1 from public.admin_search_audit_events('Relational Target', 200) where id = event_id) then
    raise exception 'FAIL: audit search did not match target profile display name';
  end if;
  execute 'reset role';
end;
$admin_audit_names$;

select 'PASS: admin audit search prefers relational actor and target names' as result;
