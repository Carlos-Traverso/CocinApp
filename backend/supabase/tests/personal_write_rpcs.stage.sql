-- STAGE ONLY: schema 202610300002 + RPC migration 202610300003 + this stage,
-- inside ONE transaction ending ROLLBACK. Never execute this stage alone.
-- Synthetic rows only. Existing accounts' temporary role/status changes roll back.
do $personal_rpc_tests$
declare
  users uuid[]; actor integer; role_name text; function_name text; table_name text;
  tag_vegan uuid := gen_random_uuid(); tag_vegetarian uuid := gen_random_uuid();
  tag_inactive uuid := gen_random_uuid(); recipe_ids uuid[];
  complete_profile jsonb := '{"display_name":"Synthetic profile A","birth_date":"1995-02-20","weight_kg":70,"height_cm":175,"metabolic_sex":"female","activity_level":"moderate","goal":"maintain"}';
  invalid_profile jsonb; invalid_preferences text[]; bad_case integer;
  before_profile jsonb; after_profile jsonb; saved public.profiles;
  before_preferences uuid[]; after_preferences uuid[]; error_detail text;
  favorite_result boolean; favorite_retry_result boolean; missing_favorite_result boolean;
begin
  select array_agg(id order by id) into users from (
    select u.id from auth.users u left join public.account_status s on s.user_id=u.id
    where coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now())
    order by u.id limit 2
  ) chosen;
  if coalesce(array_length(users,1),0) <> 2 then
    raise exception 'FAIL: personal RPC rehearsal requires two existing active accounts';
  end if;
  if exists(select 1 from public.profiles) or exists(select 1 from public.user_dietary_preferences)
    or exists(select 1 from public.favorite_recipes) or exists(select 1 from public.recipes)
    or exists(select 1 from public.dietary_tags) then
    raise exception 'FAIL: personal RPC rehearsal requires empty new domain tables';
  end if;
  foreach role_name in array array['anon','authenticated'] loop
    if has_function_privilege(role_name,'public.lock_my_relational_account()','EXECUTE') then
      raise exception 'FAIL: internal account-lock helper is client-executable';
    end if;
    foreach table_name in array array['profiles','user_dietary_preferences','favorite_recipes'] loop
      if has_table_privilege(role_name,format('public.%I',table_name),'INSERT')
        or has_table_privilege(role_name,format('public.%I',table_name),'UPDATE')
        or has_table_privilege(role_name,format('public.%I',table_name),'DELETE') then
        raise exception 'FAIL: personal table has client DML grants';
      end if;
    end loop;
  end loop;
  foreach function_name in array array['public.save_my_profile(jsonb,text[],bigint)','public.set_my_favorite(uuid,boolean)'] loop
    if has_function_privilege('anon',function_name,'EXECUTE')
      or not has_function_privilege('authenticated',function_name,'EXECUTE') then
      raise exception 'FAIL: public RPC execution grants';
    end if;
  end loop;
  insert into public.user_roles(user_id,role) select unnest(users),'USER'
    on conflict(user_id) do update set role='USER';
  insert into public.account_status(user_id,active) select unnest(users),true
    on conflict(user_id) do update set active=true;
  insert into public.dietary_tags(id,tag_key,label,active) values
    (tag_vegan,'vegan','Synthetic vegan',true),
    (tag_vegetarian,'vegetarian','Synthetic vegetarian',true),
    (tag_inactive,'inactive-test','Synthetic inactive',false);
  recipe_ids := array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
  for actor in 1..6 loop
    insert into public.recipes(id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty,publication_status,active,is_deleted)
    values(recipe_ids[actor],case when actor in (3,4) then users[actor-2] else null end,
      case when actor in (3,4) then 'user' else 'official' end,
      'Synthetic RPC recipe',1,1,'easy',case when actor in (2,3,4) then 'draft' else 'published' end,
      actor<>5,actor=6);
  end loop;

  -- Positive controls: RPCs derive ownership from the JWT; no target user input.
  for actor in 1..2 loop
    perform set_config('request.jwt.claim.sub',users[actor]::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',users[actor],'role','authenticated')::text,true);
    execute 'set local role authenticated';
    select * into saved from public.save_my_profile(
      complete_profile || jsonb_build_object('display_name',case when actor=1 then 'Synthetic profile A' else 'Synthetic profile B' end),
      array['vegan','vegetarian'],0);
    if saved.user_id<>users[actor] or saved.version<>1 or saved.weight_kg<>70
      or saved.birth_date<>date '1995-02-20' or (select count(*) from public.profiles)<>1
      or (select count(*) from public.user_dietary_preferences)<>2 then
      raise exception 'FAIL: own profile create or A/B isolation';
    end if;
    -- Keep writes and observations in separate SQL statements: scalar
    -- subquery initplans may run before volatile expressions in one IF.
    favorite_result := public.set_my_favorite(recipe_ids[1],true);
    favorite_retry_result := public.set_my_favorite(recipe_ids[1],true);
    if favorite_result is distinct from true
      or favorite_retry_result is distinct from true
      or (select count(*) from public.favorite_recipes)<>1 then
      raise exception 'FAIL: favorite add retry is not idempotent';
    end if;
    execute 'reset role';
  end loop;

  perform set_config('request.jwt.claim.sub',users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select to_jsonb(p) into before_profile from public.profiles p where user_id=users[1];
  select array_agg(dietary_tag_id order by dietary_tag_id) into before_preferences from public.user_dietary_preferences;

  -- Each rejected input must leave both profile and preference rows unchanged.
  for bad_case in 1..30 loop
    invalid_profile := complete_profile;
    invalid_preferences := array['vegan','vegetarian'];
    case bad_case
      when 1 then invalid_profile := complete_profile || '{"user_id":"00000000-0000-0000-0000-000000000000"}';
      when 2 then invalid_profile := complete_profile || '{"email":"synthetic@example.invalid"}';
      when 3 then invalid_profile := complete_profile || '{"role":"ADMIN"}';
      when 4 then invalid_profile := complete_profile || '{"version":999}';
      when 5 then invalid_profile := complete_profile || '{"weight_kg":"70"}';
      when 6 then invalid_profile := complete_profile || '{"height_cm":"175"}';
      when 7 then invalid_profile := complete_profile || '{"weight_kg":29}';
      when 8 then invalid_profile := complete_profile || '{"height_cm":251}';
      when 9 then invalid_profile := complete_profile || '{"metabolic_sex":"invalid"}';
      when 10 then invalid_profile := complete_profile || '{"activity_level":"invalid"}';
      when 11 then invalid_profile := complete_profile || '{"goal":"invalid"}';
      when 12 then invalid_profile := complete_profile || '{"birth_date":"2026-02-30"}';
      when 13 then invalid_profile := complete_profile || jsonb_build_object('birth_date',to_char(current_date+1,'YYYY-MM-DD'));
      when 14 then invalid_profile := complete_profile || '{"birth_date":"20/02/1995"}';
      when 15 then invalid_profile := complete_profile || '{"display_name":"   "}';
      when 16 then invalid_profile := 'null';
      when 17 then invalid_profile := '[]';
      when 18 then invalid_profile := '"invalid"';
      when 19 then invalid_preferences := array['missing-test'];
      when 20 then invalid_preferences := array['inactive-test'];
      when 21 then invalid_preferences := array['vegan','vegan'];
      when 22 then invalid_preferences := null;
      when 23 then invalid_preferences := array['vegan',null];
      when 24 then invalid_profile := complete_profile || '{"birth_date":123}';
      when 25 then invalid_profile := complete_profile || '{"display_name":null}';
      when 26 then invalid_profile := complete_profile || '{"weight_kg":300.004}';
      when 27 then invalid_profile := complete_profile || '{"weight_kg":29.999}';
      when 28 then invalid_profile := complete_profile || '{"height_cm":250.004}';
      when 29 then invalid_profile := complete_profile || '{"height_cm":99.999}';
      when 30 then invalid_profile := null;
    end case;
    begin
      perform public.save_my_profile(invalid_profile,invalid_preferences,1);
      raise exception 'FAIL: invalid profile input accepted (case %)',bad_case;
    exception when sqlstate '22023' then
      get stacked diagnostics error_detail = pg_exception_detail;
      if coalesce(error_detail,'')<>'' then
        raise exception 'FAIL: profile validation exposes database DETAIL';
      end if;
    end;
    select to_jsonb(p) into after_profile from public.profiles p where user_id=users[1];
    select array_agg(dietary_tag_id order by dietary_tag_id) into after_preferences from public.user_dietary_preferences;
    if after_profile is distinct from before_profile or after_preferences is distinct from before_preferences then
      raise exception 'FAIL: invalid save partially changed profile or preferences';
    end if;
  end loop;
  begin
    perform public.save_my_profile('{"display_name":"Forbidden stale create"}',array[]::text[],0);
    raise exception 'FAIL: stale profile version accepted';
  exception when sqlstate '40001' then null;
  end;
  if (select to_jsonb(p) from public.profiles p where user_id=users[1]) is distinct from before_profile
    or (select array_agg(dietary_tag_id order by dietary_tag_id) from public.user_dietary_preferences) is distinct from before_preferences then
    raise exception 'FAIL: stale save changed data';
  end if;
  select * into saved from public.save_my_profile('{"display_name":"Synthetic partial"}',array['vegetarian'],1);
  if saved.version<>2 or saved.weight_kg is not null or saved.birth_date is not null
    or saved.height_cm is not null or saved.goal is not null or saved.activity_level is not null
    or saved.metabolic_sex is not null or (select count(*) from public.user_dietary_preferences)<>1
    or not exists(select 1 from public.user_dietary_preferences where dietary_tag_id=tag_vegetarian) then
    raise exception 'FAIL: full replacement or partial profile semantics';
  end if;
  select * into saved from public.save_my_profile('{"display_name":"Synthetic partial"}',array[]::text[],2);
  if saved.version<>3 or exists(select 1 from public.user_dietary_preferences) then
    raise exception 'FAIL: empty preferences do not clear previous values';
  end if;
  begin
    perform public.save_my_profile('{"display_name":"Stale overwrite"}',array['vegan'],2);
    raise exception 'FAIL: stale update accepted';
  exception when sqlstate '40001' then null;
  end;

  favorite_result := public.set_my_favorite(recipe_ids[3],true);
  if favorite_result is distinct from true
    or (select count(*) from public.favorite_recipes)<>2 then
    raise exception 'FAIL: own private recipe cannot be favorited';
  end if;
  for actor in 1..5 loop
    begin
      perform public.set_my_favorite(case actor when 1 then recipe_ids[2] when 2 then recipe_ids[4]
        when 3 then recipe_ids[5] when 4 then recipe_ids[6] else gen_random_uuid() end,true);
      raise exception 'FAIL: hidden/unavailable recipe accepted';
    exception when insufficient_privilege then null;
    end;
  end loop;
  if (select count(*) from public.favorite_recipes)<>2 then raise exception 'FAIL: rejected favorite mutated rows'; end if;
  for actor in 1..2 loop
    begin
      perform public.set_my_favorite(case when actor=1 then null else recipe_ids[1] end,
        case when actor=2 then null else true end);
      raise exception 'FAIL: null favorite input accepted';
    exception when sqlstate '22023' then null;
    end;
  end loop;
  foreach table_name in array array['profiles','user_dietary_preferences','favorite_recipes'] loop
    begin
      execute format('delete from public.%I',table_name);
      raise exception 'FAIL: direct personal-table delete allowed';
    exception when insufficient_privilege then null;
    end;
  end loop;
  begin
    perform public.lock_my_relational_account();
    raise exception 'FAIL: internal helper execution allowed';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';

  -- Admin recipe visibility does not authorize favoriting another user's draft.
  update public.user_roles set role='ADMIN' where user_id=users[1];
  execute 'set local role authenticated';
  if public.current_app_role()<>'ADMIN' or not exists(select 1 from public.recipes where id=recipe_ids[4]) then
    raise exception 'FAIL: administrator fixture positive control';
  end if;
  begin
    perform public.set_my_favorite(recipe_ids[4],true);
    raise exception 'FAIL: administrator favorited another account private recipe';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';
  update public.user_roles set role='USER' where user_id=users[1];
  update public.recipes set active=false where id=recipe_ids[1];
  execute 'set local role authenticated';
  favorite_result := public.set_my_favorite(recipe_ids[1],false);
  favorite_retry_result := public.set_my_favorite(recipe_ids[1],false);
  missing_favorite_result := public.set_my_favorite(gen_random_uuid(),false);
  if favorite_result is distinct from false
    or favorite_retry_result is distinct from false
    or missing_favorite_result is distinct from false
    or (select count(*) from public.favorite_recipes)<>1 then
    raise exception 'FAIL: archived favorite removal/retry';
  end if;
  begin
    perform public.set_my_favorite(recipe_ids[1],true);
    raise exception 'FAIL: archived favorite can be added';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';
  if not exists(select 1 from public.favorite_recipes where user_id=users[2] and recipe_id=recipe_ids[1])
    or (select display_name from public.profiles where user_id=users[2])<>'Synthetic profile B'
    or (select version from public.profiles where user_id=users[2])<>1
    or (select count(*) from public.user_dietary_preferences where user_id=users[2])<>2 then
    raise exception 'FAIL: A writes/removal changed B data';
  end if;

  -- Both RPCs require an active claimed identity, even with a valid old JWT.
  update public.account_status set active=false where user_id=users[1];
  for actor in 1..3 loop
    if actor=1 then
      perform set_config('request.jwt.claim.sub',users[1]::text,true);
      perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
      execute 'set local role authenticated';
    else
      perform set_config('request.jwt.claim.sub','',true);
      perform set_config('request.jwt.claims','{}',true);
      if actor=2 then execute 'set local role authenticated'; else execute 'set local role anon'; end if;
    end if;
    begin
      perform public.save_my_profile('{"display_name":"Forbidden caller"}',array[]::text[],3);
      raise exception 'FAIL: inactive/anonymous/unclaimed profile save allowed';
    exception when insufficient_privilege then null;
    end;
    begin
      perform public.set_my_favorite(recipe_ids[3],false);
      raise exception 'FAIL: inactive/anonymous/unclaimed favorite removal allowed';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
  end loop;
  if (select version from public.profiles where user_id=users[1])<>3
    or not exists(select 1 from public.favorite_recipes where user_id=users[1] and recipe_id=recipe_ids[3]) then
    raise exception 'FAIL: unauthorized RPC changed state';
  end if;
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
end;
$personal_rpc_tests$;
select 'PASS: personal write RPCs, profile validation/atomic preferences/version conflicts, favorite ownership/idempotency, A/B isolation, unavailable recipes and inactive/anonymous caller restrictions verified; wrapper ROLLBACK required' as result;
