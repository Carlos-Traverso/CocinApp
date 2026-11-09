-- STAGE ONLY: admin profile name RPC, after the Spanish table-name cutover.
-- Reuses two Auth accounts already present in the rehearsal database.
do $admin_profile_names$
declare
  actor uuid; target uuid; target_email text; expected_fallback text;
  tag uuid := gen_random_uuid(); retired_tag uuid := gen_random_uuid();
  before_users bigint; before_audit bigint; saved_version bigint; listed record; failed boolean;
begin
  select id into actor from auth.users
    where email is not null and (banned_until is null or banned_until<=now())
    order by created_at desc limit 1;
  select id,email into target,target_email from auth.users
    where email is not null and id is distinct from actor and (banned_until is null or banned_until<=now())
    order by created_at desc limit 1;
  if actor is null or target is null then
    raise exception 'FAIL: rehearsal requires two existing, unbanned Auth accounts with email';
  end if;

  -- Isolate the fixture's required roles and active states inside the outer
  -- rollback-only rehearsal transaction.
  insert into public.roles_usuario(user_id,role) values(actor,'ADMIN'),(target,'USER')
    on conflict(user_id) do update set role=excluded.role;
  insert into public.estado_cuenta(user_id,active) values(actor,true),(target,true)
    on conflict(user_id) do update set active=excluded.active;
  insert into public.etiquetas_dieteticas(id,tag_key,label,active) values
    (tag,'profile-test','Profile test',true),(retired_tag,'profile-retired','Retired profile test',false);
  delete from public.perfiles where user_id in (actor,target);
  insert into public.perfiles(user_id,display_name,weight_kg,goal,version)
    values(target,'Before',73.25,'maintain',7);
  delete from public.preferencias_dieteticas_usuario where user_id=target;
  insert into public.preferencias_dieteticas_usuario(user_id,dietary_tag_id) values(target,tag),(target,retired_tag);
  select count(*) into before_users from auth.users;
  select count(*) into before_audit from public.registro_auditoria where action='user.name_updated';

  -- Deny anon and the existing non-admin account.
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  execute 'set local role anon';
  failed:=false;
  begin perform public.admin_set_profile_name(target,'Blocked'); exception when insufficient_privilege then failed:=true; end;
  if not failed then raise exception 'FAIL: anon name update was allowed'; end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',target::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',target,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  failed:=false;
  begin perform public.admin_set_profile_name(actor,'Blocked'); exception when insufficient_privilege then failed:=true; end;
  if not failed then raise exception 'FAIL: USER name update was allowed'; end if;

  -- Existing retired preferences remain saveable; new inactive keys do not.
  perform public.save_my_profile('{"display_name":"Before","weight_kg":73.25,"goal":"maintain"}',
    array['profile-test','profile-retired'],7);
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  failed:=false;
  begin perform public.save_my_profile('{"display_name":"New profile"}',array['profile-retired'],0);
  exception when invalid_parameter_value then failed:=true; end;
  if not failed then raise exception 'FAIL: new inactive preference was accepted'; end if;
  execute 'reset role';

  -- Read-only fixture checks run as the migration owner, because authenticated
  -- users cannot inspect another account's private profile or preferences.
  select version into saved_version from public.perfiles where user_id=target;
  if saved_version is distinct from 8 then raise exception 'FAIL: existing profile save version'; end if;

  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.admin_set_profile_name(target,'After');
  execute 'reset role';
  select version into saved_version from public.perfiles where user_id=target;
  if saved_version is distinct from 9 then raise exception 'FAIL: existing profile version did not increment'; end if;
  if (select weight_kg from public.perfiles where user_id=target) is distinct from 73.25
    or (select goal from public.perfiles where user_id=target) is distinct from 'maintain'
    or (select count(*) from public.preferencias_dieteticas_usuario where user_id=target) is distinct from 2 then
    raise exception 'FAIL: private profile fields or preferences changed';
  end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.admin_set_profile_name(target,'After');
  execute 'reset role';
  select version into saved_version from public.perfiles where user_id=target;
  if saved_version is distinct from 9 then raise exception 'FAIL: same-name retry incremented version'; end if;
  if (select count(*) from public.registro_auditoria where action='user.name_updated') is distinct from before_audit+1 then
    raise exception 'FAIL: retry produced an audit event';
  end if;

  -- The directory uses Auth metadata only while the relational row is missing.
  delete from public.perfiles where user_id=target;
  select coalesce(nullif(trim(coalesce(raw_user_meta_data->>'name',raw_user_meta_data->>'full_name')),''),
    split_part(email,'@',1)) into expected_fallback from auth.users where id=target;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select * into listed from public.admin_list_users() where email=target_email;
  if listed.display_name is distinct from expected_fallback or listed.role is distinct from 'USER' or listed.active is distinct from true then
    raise exception 'FAIL: metadata fallback or directory return contract';
  end if;
  execute 'reset role';

  -- Creation for an existing Auth account starts at version 1; a later rename
  -- increments it. The function never creates an Auth user.
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.admin_set_profile_name(target,'Created relational row');
  execute 'reset role';
  select version into saved_version from public.perfiles where user_id=target;
  if saved_version is distinct from 1 then raise exception 'FAIL: missing profile was not created at version 1'; end if;
  if (select count(*) from auth.users) is distinct from before_users then raise exception 'FAIL: name update inserted an Auth user'; end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.admin_set_profile_name(target,'Created profile changed');
  execute 'reset role';
  select version into saved_version from public.perfiles where user_id=target;
  if saved_version is distinct from 2 then raise exception 'FAIL: changed new profile version'; end if;

  -- The target user's stale editor must conflict with the two admin renames.
  perform set_config('request.jwt.claim.sub',target::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',target,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  failed:=false;
  begin
    perform public.save_my_profile('{"display_name":"stale"}',array[]::text[],1);
  exception when serialization_failure then failed:=true;
  end;
  if not failed then raise exception 'FAIL: stale own-profile save did not return 40001'; end if;
  execute 'reset role';

  -- Both role revocation and account inactivity revoke RPC authority.
  update public.roles_usuario set role='USER' where user_id=actor;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  failed:=false;
  begin perform public.admin_set_profile_name(target,'Revoked'); exception when insufficient_privilege then failed:=true; end;
  if not failed then raise exception 'FAIL: revoked administrator remained authorized'; end if;
  execute 'reset role';
  update public.roles_usuario set role='ADMIN' where user_id=actor;
  update public.estado_cuenta set active=false where user_id=actor;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  failed:=false;
  begin perform public.admin_set_profile_name(target,'Inactive actor'); exception when insufficient_privilege then failed:=true; end;
  if not failed then raise exception 'FAIL: inactive administrator remained authorized'; end if;
  execute 'reset role';
end;
$admin_profile_names$;

select 'PASS: admin profile names verified; full script includes ROLLBACK' as result;
