-- STAGE ONLY: schema 002, RPC stack through recipe discovery, personal read 006,
-- and this stage in one transaction. The wrapper must end in ROLLBACK.
do $personal_reads$
declare
  v_users uuid[]; synthetic uuid := gen_random_uuid();
  tag_active uuid := gen_random_uuid(); tag_inactive uuid := gen_random_uuid();
  r_official uuid := gen_random_uuid(); r_own uuid := gen_random_uuid();
  r_foreign uuid := gen_random_uuid(); r_inactive uuid := gen_random_uuid(); r_deleted uuid := gen_random_uuid();
  r_unpublished uuid := gen_random_uuid();
  p_main uuid := gen_random_uuid(); p_empty uuid := gen_random_uuid();
  week_start date := date '2026-11-02'; result jsonb; item jsonb; ids uuid[];
  routine text; table_name text; before_profile jsonb; before_preferences jsonb;
  before_plan jsonb; before_slots jsonb; bad_date date;
begin
  select array_agg(id order by id) into v_users from (
    select u.id from auth.users u left join public.account_status s on s.user_id=u.id
    where coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now())
    order by u.id limit 2
  ) picked;
  if coalesce(array_length(v_users,1),0) is distinct from 2 then
    raise exception 'FAIL: personal reads rehearsal requires two existing active accounts';
  end if;
  insert into auth.users(id) values(synthetic);
  -- Auth triggers may create a profile; remove only this synthetic account's row
  -- so the blank-default assertion exercises the RPC's empty state.
  delete from public.profiles where user_id=synthetic;
  insert into public.user_roles(user_id,role) values(v_users[1],'USER'),(v_users[2],'USER'),(synthetic,'USER')
    on conflict(user_id) do update set role=excluded.role;
  insert into public.account_status(user_id,active) values(v_users[1],true),(v_users[2],true),(synthetic,true)
    on conflict(user_id) do update set active=true;
  insert into public.dietary_tags(id,tag_key,label,active) values
    (tag_active,'reads-active','Reads active',true),(tag_inactive,'reads-retired','Reads retired',true);

  insert into public.recipes(id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
    values(r_official,null,'official','Personal reads published',15,2,'easy','published'),
      (r_own,v_users[1],'user','Personal reads own private',20,2,'easy','draft'),
      (r_foreign,v_users[1],'user','Personal reads reassigned private',25,2,'easy','draft'),
      (r_inactive,null,'official','Personal reads inactive',10,1,'easy','published'),
      (r_deleted,null,'official','Personal reads deleted',10,1,'easy','published'),
      (r_unpublished,null,'official','Personal reads unpublished',10,1,'easy','published');
  update public.recipes set active=false where id=r_inactive;
  update public.recipes set is_deleted=true where id=r_deleted;
  insert into public.favorite_recipes(user_id,recipe_id,created_at) values
    (v_users[1],r_official,'2026-01-01 00:00:00+00'),(v_users[1],r_own,'2026-01-01 00:00:00+00'),
    (v_users[1],r_foreign,'2026-01-01 00:00:00+00'),(v_users[1],r_inactive,'2026-01-02 00:00:00+00'),
    (v_users[1],r_deleted,'2026-01-03 00:00:00+00'),(v_users[1],r_unpublished,'2026-01-01 00:00:00+00');

  -- The normal write path establishes a versioned profile and both live and
  -- retired preferences. Reads must retain previously saved inactive keys.
  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.save_my_profile('{"display_name":"Reads profile","weight_kg":72.5}',array['reads-active','reads-retired'],0);
  execute 'reset role';
  update public.dietary_tags set active=false where id=tag_inactive;

  insert into public.meal_plans(id,owner_user_id,week_start) values(p_main,v_users[1],week_start),(p_empty,v_users[2],week_start);
  insert into public.meal_plan_slots(id,plan_id,meal_date,meal_shift,recipe_id,portions,position) values
    (gen_random_uuid(),p_main,week_start+1,'dinner',r_official,2,2),
    (gen_random_uuid(),p_main,week_start,'snack',r_inactive,1,1),
    (gen_random_uuid(),p_main,week_start,'breakfast',r_official,1,2),
    (gen_random_uuid(),p_main,week_start,'breakfast',r_official,1,1),
    (gen_random_uuid(),p_main,week_start,'lunch',r_foreign,2,1),
    (gen_random_uuid(),p_main,week_start,'lunch',r_unpublished,1,2);
  -- Start as visible so fixture link validation succeeds, then model the recipe
  -- becoming private after the saved plan (and favorite) already references it.
  update public.recipes set owner_user_id=v_users[2] where id=r_foreign;
  update public.recipes set publication_status='draft' where id=r_unpublished;

  foreach routine in array array['public.get_my_profile()','public.get_my_favorites(integer,integer)','public.get_my_meal_plan(date)'] loop
    if has_function_privilege('anon',routine,'EXECUTE') or has_function_privilege('service_role',routine,'EXECUTE')
      or not has_function_privilege('authenticated',routine,'EXECUTE') then
      raise exception 'FAIL: personal read execution grants for %',routine;
    end if;
  end loop;
  if has_function_privilege('anon','public.lock_my_relational_account()','EXECUTE')
    or has_function_privilege('authenticated','public.lock_my_relational_account()','EXECUTE')
    or has_function_privilege('service_role','public.lock_my_relational_account()','EXECUTE') then
    raise exception 'FAIL: account lock helper is executable by clients or service role';
  end if;

  -- Synthetic account: profile row is null and keys are an empty JSON array.
  perform set_config('request.jwt.claim.sub',synthetic::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',synthetic,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result:=public.get_my_profile();
  if result->'profile' is distinct from 'null'::jsonb or result->'preference_keys' is distinct from '[]'::jsonb then
    raise exception 'FAIL: synthetic account blank profile defaults: %',result;
  end if;
  result:=public.get_my_favorites();
  if result->'items' is distinct from '[]'::jsonb or (result->>'total')::integer is distinct from 0
    or (result->>'limit')::integer is distinct from 30 or (result->>'offset')::integer is distinct from 0 then
    raise exception 'FAIL: synthetic account blank favorites defaults: %',result;
  end if;
  result:=public.get_my_meal_plan(week_start);
  if result->'plan' is distinct from 'null'::jsonb or result->'slots' is distinct from '[]'::jsonb then
    raise exception 'FAIL: missing plan defaults: %',result;
  end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result:=public.get_my_profile();
  if result->'profile'->>'user_id' is distinct from v_users[1]::text
    or (result->'profile'->>'version')::bigint is distinct from 1
    or result->'profile'->>'display_name' is distinct from 'Reads profile'
    or result->'preference_keys' is distinct from '["reads-active","reads-retired"]'::jsonb then
    raise exception 'FAIL: profile, version, or saved inactive preferences changed in read: %',result;
  end if;
  execute 'reset role';
  select to_jsonb(p) into before_profile from public.profiles p where user_id=v_users[1];
  select coalesce(jsonb_agg(jsonb_build_object('tag_key',t.tag_key,'created_at',pref.created_at) order by t.tag_key),'[]'::jsonb)
    into before_preferences from public.user_dietary_preferences pref join public.dietary_tags t on t.id=pref.dietary_tag_id where pref.user_id=v_users[1];
  execute 'set local role authenticated';
  result:=public.get_my_favorites(30,0);
  if (result->>'total')::integer is distinct from 6 or (result->>'limit')::integer is distinct from 30
    or (result->>'offset')::integer is distinct from 0 or jsonb_array_length(result->'items') is distinct from 6 then
    raise exception 'FAIL: favorites total and response metadata';
  end if;
  item:=result->'items'->0;
  if item->>'recipe_id' is distinct from r_deleted::text or item->>'available' is distinct from 'false'
    or item->'recipe' is distinct from 'null'::jsonb then raise exception 'FAIL: deleted favorite remains hidden: %',item; end if;
  item:=result->'items'->1;
  if item->>'recipe_id' is distinct from r_inactive::text or item->>'available' is distinct from 'false'
    or item->'recipe' is distinct from 'null'::jsonb then raise exception 'FAIL: inactive favorite remains hidden: %',item; end if;
  if not exists(select 1 from jsonb_array_elements(result->'items') x where x->>'recipe_id'=r_unpublished::text
    and x->>'available'='false' and x->'recipe'='null'::jsonb) then
    raise exception 'FAIL: unpublished official favorite remains listed but hidden';
  end if;
  -- Equal created_at entries must use recipe_id DESC, including across pages.
  result:=public.get_my_favorites(1,2);
  if (result->>'total')::integer is distinct from 6 or jsonb_array_length(result->'items') is distinct from 1
    or result->'items'->0->>'recipe_id' is distinct from greatest(r_official,r_own,r_foreign,r_unpublished)::text then
    raise exception 'FAIL: stable favorite tie ordering/page or total-before-page';
  end if;
  if (select count(*) from jsonb_array_elements(public.get_my_favorites(100,0)->'items') x
      where x->>'available'='true' and x->'recipe' is not null and x->'recipe'<>'null'::jsonb)<>2
    or (select count(*) from jsonb_array_elements(public.get_my_favorites(100,0)->'items') x
      where x->>'available'='false' and x->'recipe'='null'::jsonb)<>4 then
    raise exception 'FAIL: favorite visibility payloads, including foreign private recipe isolation';
  end if;
  execute 'reset role';
  update public.user_roles set role='ADMIN' where user_id=v_users[1];
  execute 'set local role authenticated';
  if public.current_app_role() is distinct from 'ADMIN' then raise exception 'FAIL: admin fixture'; end if;
  result:=public.get_my_favorites(100,0);
  if exists(select 1 from jsonb_array_elements(result->'items') x where x->>'recipe_id'=r_foreign::text
    and (x->>'available'<>'false' or x->'recipe'<>'null'::jsonb)) then
    raise exception 'FAIL: admin read exposes foreign private favorite';
  end if;
  execute 'reset role';
  update public.user_roles set role='USER' where user_id=v_users[1];
  execute 'set local role authenticated';

  result:=public.get_my_meal_plan(week_start);
  if result->'plan'->>'id' is distinct from p_main::text or (result->'plan'->>'version')::bigint is distinct from 1
    or jsonb_array_length(result->'slots') is distinct from 6 then raise exception 'FAIL: existing plan/version/slot response'; end if;
  ids:=array(select (x->>'id')::uuid from jsonb_array_elements(result->'slots') x);
  -- Canonical order: date, breakfast/lunch/snack/dinner, position, id.
  if result->'slots'->0->>'meal_shift' is distinct from 'breakfast'
    or (result->'slots'->0->>'position')::integer is distinct from 1
    or result->'slots'->1->>'meal_shift' is distinct from 'breakfast'
    or result->'slots'->2->>'meal_shift' is distinct from 'lunch'
    or result->'slots'->3->>'meal_shift' is distinct from 'lunch'
    or result->'slots'->4->>'meal_shift' is distinct from 'snack'
    or result->'slots'->5->>'meal_shift' is distinct from 'dinner' then
    raise exception 'FAIL: meal plan slot canonical order: %',result->'slots';
  end if;
  if result->'slots'->2->>'available' is distinct from 'false'
    or result->'slots'->2->'recipe' is distinct from 'null'::jsonb
    or result->'slots'->3->>'available' is distinct from 'false'
    or result->'slots'->3->'recipe' is distinct from 'null'::jsonb then
    raise exception 'FAIL: private foreign or unpublished official slot recipe leaked';
  end if;
  select to_jsonb(mp) into before_plan from public.meal_plans mp where id=p_main;
  select coalesce(jsonb_agg(to_jsonb(s) order by s.meal_date,s.meal_shift,s.position,s.id),'[]'::jsonb)
    into before_slots from public.meal_plan_slots s where plan_id=p_main;
  result:=public.get_my_meal_plan(week_start);
  if result->'plan' is distinct from before_plan or result->'slots' is null then raise exception 'FAIL: repeated snapshot plan read'; end if;
  execute 'reset role';

  -- A second account's profile, favorites and already-existing empty plan are isolated.
  perform set_config('request.jwt.claim.sub',v_users[2]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[2],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result:=public.get_my_profile();
  if result->'profile' is distinct from 'null'::jsonb or result->'preference_keys' is distinct from '[]'::jsonb then raise exception 'FAIL: user profiles are not isolated'; end if;
  result:=public.get_my_favorites();
  if (result->>'total')::integer is distinct from 0 or result->'items' is distinct from '[]'::jsonb then raise exception 'FAIL: user favorites are not isolated'; end if;
  result:=public.get_my_meal_plan(week_start);
  if result->'plan'->>'id' is distinct from p_empty::text or (result->'plan'->>'version')::bigint is distinct from 1
    or result->'slots' is distinct from '[]'::jsonb then raise exception 'FAIL: existing empty plan/version not preserved'; end if;
  execute 'reset role';

  -- Validation: limits and offsets, including NULL, and finite Monday dates.
  foreach routine in array array['get_my_favorites'] loop
    foreach table_name in array array['0,0','101,0','1,-1','1,5001','NULL,0','1,NULL'] loop
      begin execute format('select public.%I(%s)',routine,table_name); raise exception 'FAIL: accepted favorite bounds %',table_name;
      exception when sqlstate '22023' then null; end;
    end loop;
  end loop;
  foreach table_name in array array['NULL','date ''2026-11-03''','date ''infinity''','date ''-infinity'''] loop
    begin execute format('select public.get_my_meal_plan(%s)',table_name); raise exception 'FAIL: accepted invalid week %',table_name;
    exception when sqlstate '22023' then null; end;
  end loop;
  execute 'reset role';

  -- Read RPCs reject anonymous, missing-identity, inactive, banned, and service_role callers.
  perform set_config('request.jwt.claim.sub','',true); perform set_config('request.jwt.claims','{"role":"anon"}',true);
  execute 'set local role anon';
  begin perform public.get_my_profile(); raise exception 'FAIL: anon profile read'; exception when insufficient_privilege then null; end;
  begin perform public.get_my_favorites(); raise exception 'FAIL: anon favorites read'; exception when insufficient_privilege then null; end;
  begin perform public.get_my_meal_plan(week_start); raise exception 'FAIL: anon plan read'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true); execute 'set local role authenticated';
  begin perform public.get_my_profile(); raise exception 'FAIL: missing identity read'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  execute 'reset role';
  update public.account_status set active=false where user_id=v_users[1];
  perform set_config('request.jwt.claim.sub',v_users[1]::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin perform public.get_my_profile(); raise exception 'FAIL: inactive profile read'; exception when insufficient_privilege then null; end;
  begin perform public.get_my_favorites(); raise exception 'FAIL: inactive favorites read'; exception when insufficient_privilege then null; end;
  begin perform public.get_my_meal_plan(week_start); raise exception 'FAIL: inactive plan read'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.account_status set active=true where user_id=v_users[1];
  update auth.users set banned_until=now()+interval '1 day' where id=v_users[1];
  execute 'set local role authenticated';
  begin perform public.get_my_profile(); raise exception 'FAIL: banned profile read'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update auth.users set banned_until=null where id=v_users[1];
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  execute 'set local role service_role';
  begin perform public.get_my_profile(); raise exception 'FAIL: service_role profile read'; exception when insufficient_privilege then null; end;
  execute 'reset role';

  if (select to_jsonb(p) from public.profiles p where user_id=v_users[1]) is distinct from before_profile
    or (select coalesce(jsonb_agg(jsonb_build_object('tag_key',t.tag_key,'created_at',pref.created_at) order by t.tag_key),'[]'::jsonb)
        from public.user_dietary_preferences pref join public.dietary_tags t on t.id=pref.dietary_tag_id where pref.user_id=v_users[1]) is distinct from before_preferences
    or (select to_jsonb(mp) from public.meal_plans mp where id=p_main) is distinct from before_plan
    or (select coalesce(jsonb_agg(to_jsonb(s) order by s.meal_date,s.meal_shift,s.position,s.id),'[]'::jsonb) from public.meal_plan_slots s where plan_id=p_main) is distinct from before_slots then
    raise exception 'FAIL: personal read RPCs changed persistent profile/preferences/plan/slots';
  end if;
  perform set_config('request.jwt.claim.sub','',true); perform set_config('request.jwt.claims','{}',true);
  raise notice 'PASS: personal read RPC snapshots, ownership, stable pagination, hidden recipes, blank defaults, validation, and caller permissions';
end;
$personal_reads$;
select 'PASS: personal read RPC rehearsal complete; wrapper ROLLBACK required' as result;
