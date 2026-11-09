-- STAGE ONLY: nutrition configuration publication and selection.
do $nutrition_config$
declare
  v_admin uuid; v_user uuid; v_fixture uuid := gen_random_uuid(); v_payload jsonb; v_saved public.nutrition_config; v_original public.nutrition_config;
  v_count bigint; v_before bigint; v_future timestamptz := clock_timestamp()+interval '1 day';
  v_past timestamptz := clock_timestamp()-interval '1 day'; v_tie timestamptz := clock_timestamp()-interval '1 hour';
begin
  select u.id into v_admin from auth.users u left join public.account_status s on s.user_id=u.id
    where coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now()) order by u.id limit 1;
  select u.id into v_user from auth.users u left join public.account_status s on s.user_id=u.id
    where u.id<>v_admin and coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now()) order by u.id limit 1;
  if v_admin is null or v_user is null then raise exception 'FAIL: requires two existing active Auth accounts'; end if;
  insert into public.user_roles(user_id,role) values(v_admin,'ADMIN'),(v_user,'USER') on conflict(user_id) do update set role=excluded.role;
  insert into public.account_status(user_id,active) values(v_admin,true),(v_user,true) on conflict(user_id) do update set active=excluded.active;
  insert into auth.users(id) values(v_fixture);
  insert into public.user_roles(user_id,role) values(v_fixture,'ADMIN');
  insert into public.account_status(user_id,active) values(v_fixture,true);
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  select count(*) into v_before from public.admin_audit_log;
  v_payload:=jsonb_build_object('activity_factors','__ACTIVITY_FACTORS__'::jsonb,'goal_adjustments','__GOAL_ADJUSTMENTS__'::jsonb,
    'source_note','Frontend profile.ts product parameters','effective_at',to_char(v_past at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'Z');
  execute 'set local role authenticated';
  v_saved:=public.admin_publish_nutrition_config(v_payload,0);
  if v_saved.config_version<>1 or v_saved.updated_by<>v_admin or v_saved.activity_factors<>v_payload->'activity_factors' then raise exception 'FAIL: version 1 publish or server actor'; end if;
  if public.admin_publish_nutrition_config(v_payload,0) is distinct from v_saved then raise exception 'FAIL: stable publish retry'; end if;
  if (public.get_current_nutrition_config()).config_version<>1 then raise exception 'FAIL: current active config'; end if;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('source_note','different payload'),0); raise exception 'FAIL: occupied slot changed'; exception when serialization_failure then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload,2); raise exception 'FAIL: skipped expected version'; exception when serialization_failure then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload-'source_note',1); raise exception 'FAIL: missing exact key accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('extra',true),1); raise exception 'FAIL: unknown key accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('activity_factors',jsonb_set(v_payload->'activity_factors','{active}','"1.5"'::jsonb)),1); raise exception 'FAIL: string activity factor accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('activity_factors',jsonb_set(v_payload->'activity_factors','{active}','11'::jsonb)),1); raise exception 'FAIL: out-of-range activity factor accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('goal_adjustments',jsonb_set(v_payload->'goal_adjustments','{gain,minimum}','"250"'::jsonb)),1); raise exception 'FAIL: string goal bound accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('goal_adjustments',jsonb_set(v_payload->'goal_adjustments','{gain,minimum}','250.5'::jsonb)),1); raise exception 'FAIL: fractional goal bound accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('goal_adjustments',jsonb_set(v_payload->'goal_adjustments','{gain,maximum}','10001'::jsonb)),1); raise exception 'FAIL: out-of-range goal bound accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('source_note',null),1); raise exception 'FAIL: null source accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('source_note',' '),1); raise exception 'FAIL: blank source accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('source_note',repeat('x',2001)),1); raise exception 'FAIL: oversized source accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('effective_at',null),1); raise exception 'FAIL: null effective_at accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('effective_at','2026-11-01T12:00:00'),1); raise exception 'FAIL: timezone-free effective_at accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload||jsonb_build_object('goal_adjustments',jsonb_set(v_payload->'goal_adjustments','{gain,minimum}','401'::jsonb)),1); raise exception 'FAIL: reversed goal range accepted'; exception when invalid_parameter_value then null; end;
  v_payload:=v_payload||jsonb_build_object('effective_at',to_char(v_future at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'Z','source_note','Future version');
  v_saved:=public.admin_publish_nutrition_config(v_payload,1);
  if v_saved.config_version<>2 or (public.get_current_nutrition_config()).config_version<>1 then raise exception 'FAIL: future version leaked to current selection'; end if;
  if (select count(*) from public.admin_list_nutrition_configs())<>2 then raise exception 'FAIL: admin version history'; end if;
  -- Retry of an older exact request remains idempotent after newer publications.
  if (public.admin_publish_nutrition_config(jsonb_build_object('activity_factors','__ACTIVITY_FACTORS__'::jsonb,'goal_adjustments','__GOAL_ADJUSTMENTS__'::jsonb,'source_note','Frontend profile.ts product parameters','effective_at',to_char(v_past at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'Z'),0)).config_version<>1 then raise exception 'FAIL: old exact retry'; end if;
  v_payload:=v_payload||jsonb_build_object('effective_at',to_char(v_tie at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'Z','source_note','Tie A');
  perform public.admin_publish_nutrition_config(v_payload,2);
  v_payload:=v_payload||jsonb_build_object('source_note','Tie B');
  perform public.admin_publish_nutrition_config(v_payload,3);
  if (public.get_current_nutrition_config()).config_version<>4 then raise exception 'FAIL: effective timestamp tie must choose highest version'; end if;
  execute 'reset role';
  select count(*) into v_count from public.admin_audit_log where action='nutrition.config_published';
  if v_count<>4 or (select count(*) from public.admin_audit_log)-v_before<>4 then raise exception 'FAIL: one audit per created version and none for retries/failures'; end if;
  if has_function_privilege('anon','public.admin_publish_nutrition_config(jsonb,integer)','EXECUTE') then raise exception 'FAIL: anon execute'; end if;
  if has_table_privilege('authenticated','public.nutrition_config','INSERT') or has_table_privilege('authenticated','public.nutrition_config','UPDATE') or has_table_privilege('authenticated','public.nutrition_config','DELETE') then raise exception 'FAIL: direct nutrition config DML granted'; end if;
  if has_table_privilege('authenticated','public.profiles','UPDATE') then raise exception 'FAIL: profile write privilege unexpectedly granted'; end if;
  execute 'set local role authenticated';
  begin update public.nutrition_config set source_note='tampered' where config_version=1; raise exception 'FAIL: history update accepted'; exception when insufficient_privilege then null; end;
  begin delete from public.nutrition_config where config_version=1; raise exception 'FAIL: history delete accepted'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',v_user::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);
  if (select count(*) from public.nutrition_config)<>3 or exists(select 1 from public.nutrition_config where config_version=2)
    or (public.get_current_nutrition_config()).config_version<>4 then raise exception 'FAIL: user RLS must hide future versions and select latest effective version'; end if;
  begin perform public.admin_list_nutrition_configs(); raise exception 'FAIL: USER listed history'; exception when insufficient_privilege then null; end;
  begin perform public.admin_publish_nutrition_config(v_payload,4); raise exception 'FAIL: USER published'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.user_roles set role='USER' where user_id=v_admin;
  perform set_config('request.jwt.claim.sub',v_admin::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin perform public.admin_publish_nutrition_config(v_payload,4); raise exception 'FAIL: same-JWT demoted administrator published'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.user_roles set role='ADMIN' where user_id=v_admin;
  update public.account_status set active=false where user_id=v_admin;
  execute 'set local role authenticated';
  begin perform public.admin_publish_nutrition_config(v_payload,4); raise exception 'FAIL: inactive administrator published'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true); perform set_config('request.jwt.claims','{"role":"anon"}',true);
  execute 'set local role anon';
  begin perform public.get_current_nutrition_config(); raise exception 'FAIL: anonymous current lookup'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  if (select count(*) from public.profiles)<>0 then raise exception 'FAIL: nutrition publishing wrote profile rows'; end if;
  perform set_config('request.jwt.claim.sub',v_fixture::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_fixture,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v_saved:=public.admin_publish_nutrition_config(v_payload,4);
  execute 'reset role';
  v_original:=v_saved;
  delete from auth.users where id=v_fixture;
  select n.* into v_saved from public.nutrition_config n where n.config_version=5;
  if v_saved.updated_by is not null or v_saved.config_version<>v_original.config_version
    or v_saved.activity_factors is distinct from v_original.activity_factors
    or v_saved.goal_adjustments is distinct from v_original.goal_adjustments
    or v_saved.source_note is distinct from v_original.source_note
    or v_saved.effective_at is distinct from v_original.effective_at then
    raise exception 'FAIL: Auth deletion must null only updated_by while preserving immutable config payload';
  end if;
  raise notice 'PASS: nutrition config publication, validation, selection, access, immutability, and audit checks';
end;
$nutrition_config$;
