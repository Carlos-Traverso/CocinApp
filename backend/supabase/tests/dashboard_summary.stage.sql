-- STAGE ONLY: dashboard read contract, installed after migrations 006-008.
do $dashboard_summary$
declare
  actor uuid := gen_random_uuid(); other_actor uuid := gen_random_uuid(); blank_actor uuid := gen_random_uuid();
  tag_id uuid := gen_random_uuid(); official_id uuid := gen_random_uuid(); own_id uuid := gen_random_uuid();
  foreign_id uuid := gen_random_uuid(); inactive_id uuid := gen_random_uuid(); unpublished_id uuid := gen_random_uuid();
  plan_id uuid := gen_random_uuid(); list_id uuid := gen_random_uuid(); unit_id uuid := gen_random_uuid();
  session_id uuid := gen_random_uuid(); event_id uuid := gen_random_uuid(); event_two uuid := gen_random_uuid(); hidden_event uuid := gen_random_uuid();
  foreign_plan uuid := gen_random_uuid(); foreign_list uuid := gen_random_uuid(); foreign_session uuid := gen_random_uuid();
  foreign_event uuid := gen_random_uuid();
  target_day date := date_trunc('week',current_date)::date+1; result jsonb; profile_before jsonb; pantry_before jsonb;
  bad text; routine text; n int;
begin
  insert into auth.users(id) values(actor),(other_actor),(blank_actor);
  delete from public.profiles where user_id in (actor,other_actor,blank_actor);
  insert into public.user_roles(user_id,role) values(actor,'USER'),(other_actor,'USER'),(blank_actor,'USER')
    on conflict(user_id) do update set role=excluded.role;
  insert into public.account_status(user_id,active) values(actor,true),(other_actor,true),(blank_actor,true)
    on conflict(user_id) do update set active=true;
  insert into public.dietary_tags(id,tag_key,label) values(tag_id,'dash-test','Dashboard test');
  insert into public.recipes(id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
    values(official_id,null,'official','Dashboard official',15,2,'easy','published'),
      (own_id,actor,'user','Dashboard own',20,2,'easy','draft'),
      (foreign_id,actor,'user','Dashboard reassigned',25,2,'easy','draft'),
      (inactive_id,null,'official','Dashboard inactive',10,1,'easy','published'),
      (unpublished_id,null,'official','Dashboard unpublished',10,1,'easy','published');
  update public.recipes set active=false where id=inactive_id;
  insert into public.favorite_recipes(user_id,recipe_id,created_at) values
    (actor,official_id,'2026-01-01'),(actor,own_id,'2026-01-01'),(actor,foreign_id,'2026-01-01'),
    (actor,inactive_id,'2026-01-02'),(actor,unpublished_id,'2026-01-01');
  -- Establish valid links before making the referenced recipe unavailable.
  insert into public.meal_plans(id,owner_user_id,week_start) values(plan_id,actor,date_trunc('week',target_day)::date);
  insert into public.meal_plan_slots(plan_id,meal_date,meal_shift,recipe_id,portions,position) values
    (plan_id,target_day,'dinner',official_id,2,1),(plan_id,target_day,'lunch',unpublished_id,1,1),
    (plan_id,target_day-1,'breakfast',own_id,1,1),
    (plan_id,target_day+1,'lunch',unpublished_id,1,1);
  update public.recipes set owner_user_id=other_actor where id=foreign_id;
  update public.recipes set publication_status='draft' where id=unpublished_id;
  insert into public.units(id,name,abbreviation,dimension) values(unit_id,'Dashboard unit','dash-'||substr(unit_id::text,1,8),'mass');
  insert into public.pantry_items(user_id,name,category,quantity,unit,minimum,expiry)
    select actor,'Dashboard normal '||g,'Test',10,'g',1,target_day+4 from generate_series(1,101) g;
  insert into public.pantry_items(user_id,name,category,quantity,unit,minimum,expiry) values
    (actor,'Dashboard zero','Test',0,'g',1,null),
    (actor,'Dashboard low','Test',1,'g',2,null),
    (actor,'Dashboard soon start','Test',4,'g',1,target_day),
    (actor,'Dashboard soon end','Test',4,'g',1,target_day+3),
    (actor,'Dashboard expired','Test',4,'g',1,target_day-1),
    (actor,'Dashboard overlap','Test',0,'g',1,target_day-1);
  insert into public.shopping_lists(id,owner_user_id,status) values(list_id,actor,'active');
  insert into public.shopping_items(list_id,name_snapshot,quantity,unit_id,source,checked,transferred_at) values
    (list_id,'pending',1,unit_id,'manual',false,null),(list_id,'checked',1,unit_id,'manual',true,null),
    (list_id,'transferred',1,unit_id,'manual',false,now());
  insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,portions,client_idempotency_key,finished_at)
    values(session_id,actor,inactive_id,'{"title":"Saved snapshot"}',2,gen_random_uuid(),now());
  insert into public.cooking_events(id,owner_user_id,session_id,recipe_id,recipe_snapshot,portions,cooked_at)
    values(event_id,actor,session_id,inactive_id,'{"title":"Saved snapshot"}',2,now()+interval '1 day');
  insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,portions,client_idempotency_key,finished_at)
    values(event_two,actor,official_id,'{"title":"Second snapshot"}',1,gen_random_uuid(),now());
  insert into public.cooking_events(id,owner_user_id,session_id,recipe_id,recipe_snapshot,portions,cooked_at)
    values(event_two,actor,event_two,official_id,'{"title":"Second snapshot"}',1,now()+interval '1 day');
  insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,portions,client_idempotency_key,finished_at)
    values(hidden_event,actor,official_id,'{"title":"Hidden snapshot"}',1,gen_random_uuid(),now());
  insert into public.cooking_events(id,owner_user_id,session_id,recipe_id,recipe_snapshot,portions,cooked_at,hidden_at)
    values(hidden_event,actor,hidden_event,official_id,'{"title":"Hidden snapshot"}',1,now()+interval '2 days',now());
  insert into public.pantry_items(user_id,name,category,quantity,unit,minimum,expiry) values
    (other_actor,'Foreign pantry','Other',0,'g',1,target_day);
  insert into public.favorite_recipes(user_id,recipe_id) values(other_actor,official_id);
  insert into public.meal_plans(id,owner_user_id,week_start) values(foreign_plan,other_actor,date_trunc('week',target_day)::date);
  insert into public.shopping_lists(id,owner_user_id,status) values(foreign_list,other_actor,'active');
  insert into public.shopping_items(list_id,name_snapshot,quantity,unit_id,source) values(foreign_list,'Foreign item',1,unit_id,'manual');
  insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,portions,client_idempotency_key,finished_at)
    values(foreign_session,other_actor,official_id,'{"title":"Foreign snapshot"}',1,gen_random_uuid(),now());
  insert into public.cooking_events(id,owner_user_id,session_id,recipe_id,recipe_snapshot,portions,cooked_at)
    values(foreign_event,other_actor,foreign_session,official_id,'{"title":"Foreign snapshot"}',1,now());
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.save_my_profile('{"display_name":"Dashboard profile"}',array['dash-test'],0);
  execute 'reset role';
  select to_jsonb(p) into profile_before from public.profiles p where user_id=actor;
  select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]'::jsonb) into pantry_before from public.pantry_items p where user_id=actor;

  foreach routine in array array['public.get_my_dashboard_summary(date,integer)'] loop
    if has_function_privilege('anon',routine,'EXECUTE') or has_function_privilege('service_role',routine,'EXECUTE')
      or not has_function_privilege('authenticated',routine,'EXECUTE') then raise exception 'FAIL: dashboard grants for %',routine; end if;
  end loop;
  if has_function_privilege('anon','public.lock_my_relational_account()','EXECUTE')
    or has_function_privilege('authenticated','public.lock_my_relational_account()','EXECUTE')
    or has_function_privilege('service_role','public.lock_my_relational_account()','EXECUTE') then raise exception 'FAIL: lock helper exposed'; end if;

  perform set_config('request.jwt.claim.sub',blank_actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',blank_actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result:=public.get_my_dashboard_summary(target_day,4);
  if result->'profile'->'profile' is distinct from 'null'::jsonb or result->'profile'->'preference_keys' is distinct from '[]'::jsonb
    or result->'pantry' is distinct from '{"total":0,"low":0,"empty":0,"soon":0,"expired":0}'::jsonb
    or result->'favorites' is distinct from '{"total":0,"available":0}'::jsonb
    or result->'shopping'->'active_list_id' is distinct from 'null'::jsonb
    or result->'shopping'->>'version' is not null or result->'shopping'->>'pending_items' is distinct from '0'
    or result->'shopping'->>'checked_items' is distinct from '0' or result->'shopping'->>'transferred_items' is distinct from '0'
    or result->'today_plan'->'plan' is distinct from 'null'::jsonb or result->'today_plan'->'slots' is distinct from '[]'::jsonb
    or result->'recent_preparations' is distinct from '[]'::jsonb then raise exception 'FAIL: blank dashboard %',result; end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result:=public.get_my_dashboard_summary(target_day,4);
  if result->>'as_of' is distinct from target_day::text then raise exception 'FAIL: as_of'; end if;
  if result->'pantry'->>'total' is distinct from '107' or result->'pantry'->>'low' is distinct from '3'
    or result->'pantry'->>'empty' is distinct from '2' or result->'pantry'->>'soon' is distinct from '2'
    or result->'pantry'->>'expired' is distinct from '2' then raise exception 'FAIL: full pantry metrics %',result->'pantry'; end if;
  if result->'favorites'->>'total' is distinct from '5' or result->'favorites'->>'available' is distinct from '2'
    then raise exception 'FAIL: favorites counts %',result->'favorites'; end if;
  if result->'shopping'->>'active_list_id' is distinct from list_id::text or result->'shopping'->>'version' is null
    or result->'shopping'->>'pending_items' is distinct from '1' or result->'shopping'->>'checked_items' is distinct from '1'
    or result->'shopping'->>'transferred_items' is distinct from '1' then raise exception 'FAIL: shopping metrics %',result->'shopping'; end if;
  if jsonb_array_length(result->'today_plan'->'slots')<>2 or result->'today_plan'->'slots'->0->>'meal_date' is distinct from target_day::text
    or result->'today_plan'->'slots'->0->>'available' is distinct from 'false'
    or result->'today_plan'->'slots'->1->>'available' is distinct from 'true'
    or result->'today_plan'->'slots'->0->'recipe' is distinct from 'null'::jsonb
    then raise exception 'FAIL: requested day slots retain unavailable recipes %',result->'today_plan'; end if;
  if result->'profile'->'profile'->>'display_name' is distinct from 'Dashboard profile'
    or (result->'profile'->'profile'->>'version')::bigint is distinct from 1
    or result->'profile'->'preference_keys' is distinct from '["dash-test"]'::jsonb
    then raise exception 'FAIL: embedded profile/preference snapshot %',result->'profile'; end if;
  if jsonb_array_length(result->'recent_preparations')<>2
    or result->'recent_preparations'->0->>'id' is distinct from greatest(event_id,event_two)::text
    or not exists(select 1 from jsonb_array_elements(result->'recent_preparations') e where e->>'id'=event_id::text and e->'recipe_snapshot'->>'title'='Saved snapshot')
    then raise exception 'FAIL: own visible history snapshot %',result->'recent_preparations'; end if;
  -- Future cooked_at is retained because this is a history snapshot, independent of the displayed calendar day.
  if (select to_jsonb(p) from public.profiles p where user_id=actor) is distinct from profile_before
    or (select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]'::jsonb) from public.pantry_items p where user_id=actor) is distinct from pantry_before
    then raise exception 'FAIL: dashboard read mutated profile or pantry'; end if;
  execute 'reset role';

  result:=public.get_my_dashboard_summary(target_day,1);
  if jsonb_array_length(result->'recent_preparations')<>1
    or result->'recent_preparations'->0->>'id' is distinct from greatest(event_id,event_two)::text
    then raise exception 'FAIL: recent history limit/order %',result->'recent_preparations'; end if;
  result:=public.get_my_dashboard_summary(date_trunc('week',target_day)::date+6,1);
  if result->'today_plan'->'plan'->>'id' is distinct from plan_id::text
    or result->'today_plan'->'plan'->>'version' is distinct from '1'
    or result->'today_plan'->'slots' is distinct from '[]'::jsonb then raise exception 'FAIL: empty requested day preserves plan/version %',result->'today_plan'; end if;
  update public.user_roles set role='ADMIN' where user_id=actor;
  execute 'set local role authenticated';
  result:=public.get_my_dashboard_summary(target_day,1);
  if result->'pantry'->>'total' is distinct from '107' or result->'favorites'->>'total' is distinct from '5'
    or jsonb_array_length(result->'recent_preparations')<>1 then raise exception 'FAIL: ADMIN summary must remain own-only %',result; end if;
  execute 'reset role'; update public.user_roles set role='USER' where user_id=actor;

  foreach bad in array array['NULL,4','date ''infinity'',4','date ''-infinity'',4','date ''0001-01-01'',4','date ''10000-01-01'',4','current_date,NULL','current_date,0','current_date,21'] loop
    begin execute format('select public.get_my_dashboard_summary(%s)',bad); raise exception 'FAIL: accepted dashboard args %',bad;
    exception when sqlstate '22023' then null; end;
  end loop;
  perform set_config('request.jwt.claim.sub','',true); perform set_config('request.jwt.claims','{"role":"anon"}',true);
  execute 'set local role anon';
  begin perform public.get_my_dashboard_summary(); raise exception 'FAIL: anon dashboard'; exception when insufficient_privilege then null; end;
  execute 'reset role'; perform set_config('request.jwt.claims','{}',true); execute 'set local role authenticated';
  begin perform public.get_my_dashboard_summary(); raise exception 'FAIL: missing identity'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.account_status set active=false where user_id=actor;
  perform set_config('request.jwt.claim.sub',actor::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin perform public.get_my_dashboard_summary(); raise exception 'FAIL: inactive dashboard'; exception when insufficient_privilege then null; end;
  execute 'reset role'; update public.account_status set active=true where user_id=actor;
  update auth.users set banned_until=now()+interval '1 day' where id=actor;
  execute 'set local role authenticated';
  begin perform public.get_my_dashboard_summary(); raise exception 'FAIL: banned dashboard'; exception when insufficient_privilege then null; end;
  execute 'reset role'; update auth.users set banned_until=null where id=actor;
  perform set_config('request.jwt.claims','{"role":"service_role"}',true); execute 'set local role service_role';
  begin perform public.get_my_dashboard_summary(); raise exception 'FAIL: service_role dashboard'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  raise notice 'PASS: dashboard summary ownership, full pantry counts, status overlaps, day plan, history snapshots, validation and caller permissions';
end;
$dashboard_summary$;
select 'PASS: dashboard summary verified; full script includes ROLLBACK' as result;
