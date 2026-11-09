-- STAGE ONLY: concatenate after 202610300002 DDL, inside ONE BEGIN/ROLLBACK.
-- Run as database operator. Uses existing active accounts, never creates Auth users.
-- Synthetic domain data and temporary role/status changes MUST roll back.
-- This stage tests the initial SELECT-only client surface, not future write RPCs.
do $permissions$
declare
  users uuid[]; owner_id uuid; actor integer; mode integer; tbl text; privilege text;
  role_name text; actual bigint; expected bigint; recipe_ids uuid[];
  category_id uuid := gen_random_uuid(); unit_id uuid := gen_random_uuid(); ingredient_id uuid := gen_random_uuid(); tag_id uuid := gen_random_uuid();
  plan_id uuid; list_id uuid; item_id uuid; receipt_id uuid; session_id uuid; event_id uuid; step_id uuid; line_id uuid;
  tables text[] := array['dietary_tags','nutrition_config','profiles','user_dietary_preferences','categories','units','ingredients','ingredient_dietary_tags','recipes','recipe_meal_shifts','recipe_dietary_tags','recipe_ingredients','recipe_steps','recipe_step_ingredients','favorite_recipes','meal_plans','meal_plan_slots','pantry_receipts','shopping_lists','shopping_items','shopping_item_sources','pantry_receipt_items','cooking_sessions','cooking_session_steps','cooking_events','cooking_event_ingredients','recipe_generation_requests','receipt_recognition_requests'];
  private_tables text[] := array['profiles','user_dietary_preferences','favorite_recipes','meal_plans','meal_plan_slots','pantry_receipts','shopping_lists','shopping_items','shopping_item_sources','pantry_receipt_items','cooking_sessions','cooking_session_steps','cooking_events','cooking_event_ingredients','recipe_generation_requests','receipt_recognition_requests'];
  recipe_children text[] := array['recipe_meal_shifts','recipe_dietary_tags','recipe_ingredients','recipe_steps','recipe_step_ingredients'];
begin
  select array_agg(id order by id) into users from (
    select u.id from auth.users u left join public.account_status s on s.user_id=u.id
    where coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now()) order by u.id limit 2
  ) chosen;
  if coalesce(array_length(users,1),0)<>2 then
    raise exception 'FAIL: permission rehearsal requires two existing active Auth accounts';
  end if;
  foreach tbl in array tables loop
    execute format('select count(*) from public.%I',tbl) into actual;
    if actual<>0 then raise exception 'FAIL: permission rehearsal requires empty new domain tables'; end if;
    if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=tbl and c.relrowsecurity) then
      raise exception 'FAIL: missing RLS on domain table %',tbl;
    end if;
    foreach role_name in array array['anon','authenticated'] loop
      foreach privilege in array array['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
        if has_table_privilege(role_name,format('public.%I',tbl),privilege) then
          raise exception 'FAIL: client role % has forbidden % on %',role_name,privilege,tbl;
        end if;
      end loop;
    end loop;
    if has_table_privilege('anon',format('public.%I',tbl),'SELECT') then
      raise exception 'FAIL: anonymous SELECT granted on %',tbl;
    end if;
  end loop;
  insert into public.user_roles(user_id,role) select unnest(users),'USER' on conflict(user_id) do update set role='USER';
  insert into public.account_status(user_id,active) select unnest(users),true on conflict(user_id) do update set active=true;
  insert into public.categories(id,name,normalized_name) values(category_id,'Permission fixture','permission-fixture');
  insert into public.units(id,name,abbreviation,dimension) values(unit_id,'Permission unit','test-u','count');
  insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values(ingredient_id,'Permission ingredient','permission-fixture',category_id,unit_id);
  insert into public.dietary_tags(id,tag_key,label) values(tag_id,'permission-test','Permission test');
  insert into public.ingredient_dietary_tags values(ingredient_id,tag_id,'unknown','');
  insert into public.nutrition_config(config_version,activity_factors,goal_adjustments,source_note) values(1,'{}','{}','Permission fixture');
  recipe_ids:=array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
  for actor in 1..4 loop
    insert into public.recipes(id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
      values(recipe_ids[actor],case when actor>2 then users[actor-2] else null end,case when actor>2 then 'user' else 'official' end,'Permission fixture',1,1,'easy',case when actor=1 then 'published' else 'draft' end);
    step_id:=gen_random_uuid(); line_id:=gen_random_uuid();
    insert into public.recipe_meal_shifts values(recipe_ids[actor],'lunch');
    insert into public.recipe_dietary_tags values(recipe_ids[actor],tag_id);
    insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,position) values(line_id,recipe_ids[actor],ingredient_id,1,unit_id,1);
    insert into public.recipe_steps(id,recipe_id,position,instruction) values(step_id,recipe_ids[actor],1,'Permission fixture');
    insert into public.recipe_step_ingredients values(step_id,line_id,1);
  end loop;
  foreach owner_id in array users loop
    plan_id:=gen_random_uuid(); list_id:=gen_random_uuid(); item_id:=gen_random_uuid(); receipt_id:=gen_random_uuid(); session_id:=gen_random_uuid(); event_id:=gen_random_uuid();
    insert into public.profiles(user_id,display_name) values(owner_id,'Permission fixture');
    insert into public.user_dietary_preferences(user_id,dietary_tag_id) values(owner_id,tag_id);
    insert into public.favorite_recipes(user_id,recipe_id) values(owner_id,recipe_ids[1]);
    insert into public.meal_plans(id,owner_user_id,week_start) values(plan_id,owner_id,date '2026-10-26');
    insert into public.meal_plan_slots(plan_id,meal_date,meal_shift,recipe_id,portions) values(plan_id,date '2026-10-26','lunch',recipe_ids[1],1);
    insert into public.shopping_lists(id,owner_user_id,plan_id) values(list_id,owner_id,plan_id);
    insert into public.shopping_items(id,list_id,ingredient_id,name_snapshot,quantity,unit_id,source) values(item_id,list_id,ingredient_id,'Permission fixture',1,unit_id,'manual');
    insert into public.shopping_item_sources(shopping_item_id,source,plan_id) values(item_id,'plan',plan_id);
    insert into public.pantry_receipts(id,owner_user_id,idempotency_key) values(receipt_id,owner_id,gen_random_uuid());
    insert into public.pantry_receipt_items(receipt_id,original_shopping_item_id,shopping_item_id,quantity_added,unit_abbreviation_snapshot) values(receipt_id,item_id,item_id,1,'test-u');
    insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,portions,client_idempotency_key) values(session_id,owner_id,recipe_ids[1],'{}',1,gen_random_uuid());
    insert into public.cooking_session_steps(session_id,step_position,remaining_ms,timer_deadline_at,timer_state) values(session_id,1,60000,now()+interval '1 minute','running');
    insert into public.cooking_events(id,owner_user_id,session_id,recipe_id,recipe_snapshot,portions) values(event_id,owner_id,session_id,recipe_ids[1],'{}',1);
    insert into public.cooking_event_ingredients(event_id,ingredient_id,name_snapshot,quantity_used,unit_abbreviation_snapshot) values(event_id,ingredient_id,'Permission fixture',1,'test-u');
    insert into public.recipe_generation_requests(owner_user_id,status) values(owner_id,'pending');
    insert into public.receipt_recognition_requests(owner_user_id,status) values(owner_id,'pending');
  end loop;
  -- Positive and negative controls for two users, then an administrator.
  for mode in 1..3 loop
    actor:=case when mode=1 then 1 else 2 end;
    if mode=3 then update public.user_roles set role='ADMIN' where user_id=users[2]; end if;
    perform set_config('request.jwt.claim.sub',users[actor]::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',users[actor],'role','authenticated')::text,true);
    execute 'set local role authenticated';
    if auth.uid() is distinct from users[actor] or not public.current_account_is_active()
      or public.current_app_role() is distinct from (case when mode=3 then 'ADMIN' else 'USER' end) then
      raise exception 'FAIL: role/identity positive control failed';
    end if;
    foreach tbl in array private_tables loop
      execute format('select count(*) from public.%I',tbl) into actual;
      if actual<>1 then raise exception 'FAIL: cross-account isolation or own-row visibility on %',tbl; end if;
      execute format('select count(*) from public.%I t where %s',tbl,
        case tbl
          when 'profiles' then 't.user_id=auth.uid()'
          when 'user_dietary_preferences' then 't.user_id=auth.uid()'
          when 'favorite_recipes' then 't.user_id=auth.uid()'
          when 'meal_plan_slots' then 'exists(select 1 from public.meal_plans p where p.id=t.plan_id and p.owner_user_id=auth.uid())'
          when 'shopping_items' then 'exists(select 1 from public.shopping_lists l where l.id=t.list_id and l.owner_user_id=auth.uid())'
          when 'shopping_item_sources' then 'exists(select 1 from public.shopping_items i join public.shopping_lists l on l.id=i.list_id where i.id=t.shopping_item_id and l.owner_user_id=auth.uid())'
          when 'pantry_receipt_items' then 'exists(select 1 from public.pantry_receipts r where r.id=t.receipt_id and r.owner_user_id=auth.uid())'
          when 'cooking_session_steps' then 'exists(select 1 from public.cooking_sessions s where s.id=t.session_id and s.owner_user_id=auth.uid())'
          when 'cooking_event_ingredients' then 'exists(select 1 from public.cooking_events e where e.id=t.event_id and e.owner_user_id=auth.uid())'
          else 't.owner_user_id=auth.uid()' end) into actual;
      if actual<>1 then raise exception 'FAIL: own-row positive control on %',tbl; end if;
    end loop;
    if not exists(select 1 from public.profiles where user_id=users[actor])
      or exists(select 1 from public.profiles where user_id=users[3-actor]) then
      raise exception 'FAIL: visible private row belongs to wrong account';
    end if;
    expected:=case when mode=3 then 4 else 2 end;
    if (select count(*) from public.recipes)<>expected then raise exception 'FAIL: recipe visibility count'; end if;
    if not exists(select 1 from public.recipes where id=recipe_ids[1])
      or not exists(select 1 from public.recipes where id=recipe_ids[actor+2]) then raise exception 'FAIL: official or own private recipe missing'; end if;
    if mode<3 and exists(select 1 from public.recipes where id in(recipe_ids[2],recipe_ids[5-actor])) then raise exception 'FAIL: draft or other private recipe exposed'; end if;
    foreach tbl in array recipe_children loop
      execute format('select count(*) from public.%I',tbl) into actual;
      if actual<>expected then raise exception 'FAIL: recipe child visibility on %',tbl; end if;
    end loop;
    -- Real write attempt: privilege introspection alone is not the only assertion.
    begin
      insert into public.profiles(user_id,display_name) values(users[actor],'Forbidden write');
      raise exception 'FAIL: direct client write allowed';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
  end loop;
  -- Same JWT after administrator demotion: admin-only recipes disappear.
  -- The previous phase left B's claims in place; only the trusted role row changes.
  update public.user_roles set role='USER' where user_id=users[2];
  execute 'set local role authenticated';
  if auth.uid() is distinct from users[2] or public.current_app_role()<>'USER' then
    raise exception 'FAIL: same-JWT admin demotion control';
  end if;
  if (select count(*) from public.recipes)<>2
    or exists(select 1 from public.recipes where id in(recipe_ids[2],recipe_ids[3])) then
    raise exception 'FAIL: demoted administrator retains restricted recipe visibility';
  end if;
  foreach tbl in array recipe_children loop
    execute format('select count(*) from public.%I',tbl) into actual;
    if actual<>2 then raise exception 'FAIL: demoted administrator retains recipe child access on %',tbl; end if;
  end loop;
  execute 'reset role';
  -- Revocation: same identity after status change, across a new SQL statement.
  update public.account_status set active=false where user_id=users[1];
  perform set_config('request.jwt.claim.sub',users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if public.current_account_is_active() then raise exception 'FAIL: inactive identity control'; end if;
  foreach tbl in array tables loop
    execute format('select count(*) from public.%I',tbl) into actual;
    if actual<>0 then raise exception 'FAIL: inactive account reads %',tbl; end if;
  end loop;
  execute 'reset role';
  -- Anonymous role has no SELECT, even on the shared master tables.
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
  execute 'set local role anon';
  foreach tbl in array tables loop
    begin
      execute format('select count(*) from public.%I',tbl) into actual;
      raise exception 'FAIL: anonymous read allowed on %',tbl;
    exception when insufficient_privilege then null;
    end;
  end loop;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
end;
$permissions$;
select 'PASS: 28 domain tables protected; A/B isolation, admin private-data isolation, recipe children, same-JWT admin demotion, inactive account, anonymous reads and direct-write restrictions verified; outer ROLLBACK still required' as result;
