-- STAGE ONLY: schema 300002 + RPCs 300003/300004/300005 + this stage,
-- inside ONE transaction ending ROLLBACK. Never run this stage alone.
-- Synthetic domain rows only; existing account role/status changes roll back.
do $planning_shopping_tests$
declare
  account_ids uuid[]; actor integer; bad_case integer; function_name text; role_name text; table_name text;
  category_test_id uuid := gen_random_uuid(); unit_mass_id uuid := gen_random_uuid();
  unit_count_id uuid := gen_random_uuid(); unit_kilo_id uuid := gen_random_uuid(); unit_inactive_id uuid := gen_random_uuid();
  unit_other_mass_root_id uuid := gen_random_uuid();
  ingredient_test_id uuid := gen_random_uuid(); recipe_ids uuid[];
  plan_ids uuid[] := array[null::uuid,null::uuid];
  list_ids uuid[] := array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
  item_manual_id uuid := gen_random_uuid(); item_catalog_id uuid := gen_random_uuid();
  receipt_test_id uuid := gen_random_uuid();
  saved_plan public.meal_plans; saved_list public.shopping_lists;
  plan_version bigint; list_version bigint; slots jsonb; bad_slots jsonb;
  manual_item jsonb; catalog_item jsonb; bad_item jsonb;
  before_state jsonb; after_state jsonb; error_detail text; actual bigint;
begin
  select array_agg(id order by id) into account_ids from (
    select u.id from auth.users u left join public.account_status s on s.user_id=u.id
    where coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now())
    order by u.id limit 2
  ) chosen;
  if coalesce(cardinality(account_ids),0)<>2 then
    raise exception 'FAIL: planning/shopping rehearsal requires two existing active accounts';
  end if;
  if exists(select 1 from public.recipes) or exists(select 1 from public.categories)
    or exists(select 1 from public.meal_plans) or exists(select 1 from public.shopping_lists) then
    raise exception 'FAIL: planning/shopping rehearsal requires empty new domain tables';
  end if;
  foreach role_name in array array['anon','authenticated'] loop
    if has_function_privilege(role_name,'public.lock_my_active_shopping_list(uuid,bigint)','EXECUTE') then
      raise exception 'FAIL: shopping lock helper is client-executable';
    end if;
    foreach table_name in array array['meal_plans','meal_plan_slots','shopping_lists','shopping_items','shopping_item_sources'] loop
      if has_table_privilege(role_name,format('public.%I',table_name),'INSERT')
        or has_table_privilege(role_name,format('public.%I',table_name),'UPDATE')
        or has_table_privilege(role_name,format('public.%I',table_name),'DELETE') then
        raise exception 'FAIL: direct planner/shopping DML granted';
      end if;
    end loop;
  end loop;
  foreach function_name in array array[
    'public.save_my_meal_plan(date,jsonb,bigint)',
    'public.create_my_shopping_list(uuid,text,uuid)',
    'public.put_my_shopping_item(uuid,jsonb,bigint)',
    'public.set_my_shopping_checked(uuid,uuid[],boolean,bigint)',
    'public.remove_my_shopping_item(uuid,uuid,bigint)'
  ] loop
    if has_function_privilege('anon',function_name,'EXECUTE')
      or not has_function_privilege('authenticated',function_name,'EXECUTE') then
      raise exception 'FAIL: planner/shopping RPC execution grants';
    end if;
  end loop;
  insert into public.user_roles(user_id,role) select unnest(account_ids),'USER'
    on conflict(user_id) do update set role='USER';
  insert into public.account_status(user_id,active) select unnest(account_ids),true
    on conflict(user_id) do update set active=true;
  insert into public.categories(id,name,normalized_name) values(category_test_id,'Synthetic category','synthetic-category');
  insert into public.units(id,name,abbreviation,dimension,active) values
    (unit_mass_id,'Synthetic mass','test-g','mass',true),
    (unit_count_id,'Synthetic count','test-u','count',true),
    (unit_inactive_id,'Synthetic inactive','test-inactive','mass',false),
    (unit_other_mass_root_id,'Synthetic incompatible mass root','test-mass-other','mass',true);
  insert into public.units(id,name,abbreviation,dimension,base_unit_id,equivalence_multiplier)
    values(unit_kilo_id,'Synthetic kilogram','test-kg','mass',unit_mass_id,1000);
  insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id)
    values(ingredient_test_id,'Synthetic ingredient','synthetic-ingredient',category_test_id,unit_mass_id);
  recipe_ids := array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
  for actor in 1..6 loop
    insert into public.recipes(id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty,publication_status,active,is_deleted)
    values(recipe_ids[actor],case when actor in(3,4) then account_ids[actor-2] else null end,
      case when actor in(3,4) then 'user' else 'official' end,'Synthetic planning recipe',1,1,'easy',
      case when actor in(2,3,4) then 'draft' else 'published' end,actor<>5,actor=6);
  end loop;

  -- Each account creates the same week, but can read only its own plan/list.
  for actor in 1..2 loop
    perform set_config('request.jwt.claim.sub',account_ids[actor]::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',account_ids[actor],'role','authenticated')::text,true);
    execute 'set local role authenticated';
    slots := jsonb_build_array(jsonb_build_object('meal_date','2026-10-26','meal_shift','lunch','recipe_id',recipe_ids[actor+2],'portions',2.0));
    select * into saved_plan from public.save_my_meal_plan(date '2026-10-26',slots,0);
    plan_ids[actor] := saved_plan.id;
    if saved_plan.version<>1 or saved_plan.owner_user_id<>account_ids[actor]
      or (select count(*) from public.meal_plans)<>1 or (select count(*) from public.meal_plan_slots)<>1 then
      raise exception 'FAIL: planner create/A-B isolation';
    end if;
    select * into saved_list from public.create_my_shopping_list(list_ids[actor],'Synthetic list',plan_ids[actor]);
    if saved_list.version<>1 or saved_list.owner_user_id<>account_ids[actor]
      or (select count(*) from public.shopping_lists)<>1 then raise exception 'FAIL: shopping list create/A-B isolation'; end if;
    execute 'reset role';
  end loop;
  perform set_config('request.jwt.claim.sub',account_ids[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',account_ids[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select * into saved_list from public.create_my_shopping_list(list_ids[1],'Synthetic list',plan_ids[1]);
  if saved_list.version<>1 or (select count(*) from public.shopping_lists where status='active')<>1 then
    raise exception 'FAIL: list creation retry changed state';
  end if;
  before_state := jsonb_build_object('plan',(select to_jsonb(p) from public.meal_plans p),
    'slots',(select jsonb_agg(to_jsonb(s) order by s.id) from public.meal_plan_slots s));
  for bad_case in 1..18 loop
    bad_slots := jsonb_build_array(jsonb_build_object('meal_date','2026-10-26','meal_shift','lunch','recipe_id',recipe_ids[1],'portions',2));
    case bad_case
      when 1 then bad_slots := null;
      when 2 then bad_slots := '{}';
      when 3 then bad_slots := '[null]';
      when 4 then bad_slots := jsonb_build_array((bad_slots->0)||jsonb_build_object('owner_user_id',account_ids[2]));
      when 5 then bad_slots := jsonb_build_array((bad_slots->0)||'{"meal_date":"2026-11-02"}');
      when 6 then bad_slots := jsonb_build_array((bad_slots->0)||'{"meal_date":"2026-10-25"}');
      when 7 then bad_slots := jsonb_build_array((bad_slots->0)||'{"meal_date":"2026-02-30"}');
      when 8 then bad_slots := jsonb_build_array((bad_slots->0)||'{"meal_shift":"invalid"}');
      when 9 then bad_slots := jsonb_build_array((bad_slots->0)||'{"portions":0}');
      when 10 then bad_slots := jsonb_build_array((bad_slots->0)||'{"portions":21}');
      when 11 then bad_slots := jsonb_build_array((bad_slots->0)||'{"portions":1.2}');
      when 12 then bad_slots := jsonb_build_array((bad_slots->0)||'{"position":0}');
      when 13 then bad_slots := jsonb_build_array((bad_slots->0)||'{"position":101}');
      when 14 then bad_slots := bad_slots||bad_slots;
      when 15 then bad_slots := jsonb_build_array((bad_slots->0)||'{"recipe_id":"invalid-uuid"}');
      when 16 then bad_slots := jsonb_build_array((bad_slots->0)||'{"portions":"2"}');
      when 17 then bad_slots := jsonb_build_array((bad_slots->0)||'{"position":1.2}');
      when 18 then select jsonb_agg(bad_slots->0) into bad_slots from generate_series(1,141);
    end case;
    begin
      perform public.save_my_meal_plan(date '2026-10-26',bad_slots,1);
      raise exception 'FAIL: invalid planning input accepted';
    exception when invalid_parameter_value then
      get stacked diagnostics error_detail=PG_EXCEPTION_DETAIL;
      if coalesce(error_detail,'')<>'' then raise exception 'FAIL: planner error exposed DETAIL'; end if;
    end;
    after_state := jsonb_build_object('plan',(select to_jsonb(p) from public.meal_plans p),
      'slots',(select jsonb_agg(to_jsonb(s) order by s.id) from public.meal_plan_slots s));
    if after_state is distinct from before_state then raise exception 'FAIL: rejected plan changed state'; end if;
  end loop;
  begin perform public.save_my_meal_plan(date '2026-10-27','[]',0); raise exception 'FAIL: non-Monday accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.save_my_meal_plan(null,'[]',0); raise exception 'FAIL: null week accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.save_my_meal_plan(date '2026-10-26','[]',0); raise exception 'FAIL: stale create accepted';
  exception when serialization_failure then null; end;
  for actor in 2..6 loop
    if actor=3 then continue; end if;
    begin
      perform public.save_my_meal_plan(date '2026-10-26',jsonb_build_array(jsonb_build_object(
        'meal_date','2026-10-26','meal_shift','lunch','recipe_id',recipe_ids[actor],'portions',2)),1);
      raise exception 'FAIL: unavailable or foreign recipe planned';
    exception when insufficient_privilege then null; end;
  end loop;
  select * into saved_plan from public.save_my_meal_plan(date '2026-10-26','[]',1);
  if saved_plan.id<>plan_ids[1] or saved_plan.version<>2 or exists(select 1 from public.meal_plan_slots) then
    raise exception 'FAIL: empty week replacement';
  end if;
  select * into saved_plan from public.save_my_meal_plan(date '2026-10-26',jsonb_build_array(
    jsonb_build_object('meal_date','2026-10-26','meal_shift','lunch','recipe_id',recipe_ids[1],'portions',2,'position',1),
    jsonb_build_object('meal_date','2026-10-26','meal_shift','lunch','recipe_id',recipe_ids[3],'portions',1,'position',2)),2);
  plan_version := saved_plan.version;
  if plan_version<>3 or (select count(*) from public.meal_plan_slots)<>2 then raise exception 'FAIL: multiple plan positions'; end if;

  manual_item := jsonb_build_object('id',item_manual_id,'name_snapshot','Synthetic manual purchase','quantity',2,
    'unit_id',unit_count_id,'source','manual','sources',jsonb_build_array(jsonb_build_object('source','manual')));
  catalog_item := jsonb_build_object('id',item_catalog_id,'ingredient_id',ingredient_test_id,'name_snapshot','Ignored client label',
    'category_snapshot','Ignored category','quantity',1.5,'unit_id',unit_kilo_id,'note','Synthetic note','checked',false,
    'source','plan','sources',jsonb_build_array(jsonb_build_object('source','plan','plan_id',plan_ids[1])));
  select * into saved_list from public.put_my_shopping_item(list_ids[1],manual_item,1);
  list_version := saved_list.version;
  select * into saved_list from public.put_my_shopping_item(list_ids[1],catalog_item,list_version);
  list_version := saved_list.version;
  if list_version<>3 or (select count(*) from public.shopping_items)<>2
    or not exists(select 1 from public.shopping_items where id=item_catalog_id and name_snapshot='Synthetic ingredient' and category_snapshot='Synthetic category')
    or (select count(*) from public.shopping_item_sources)<>2 then raise exception 'FAIL: item save or catalog snapshots'; end if;
  before_state := jsonb_build_object('list',(select to_jsonb(l) from public.shopping_lists l),
    'items',(select jsonb_agg(to_jsonb(i) order by i.id) from public.shopping_items i),
    'sources',(select jsonb_agg(to_jsonb(s) order by s.id) from public.shopping_item_sources s));
  for bad_case in 1..21 loop
    bad_item := manual_item;
    case bad_case
      when 1 then bad_item := null;
      when 2 then bad_item := '[]';
      when 3 then bad_item := manual_item||jsonb_build_object('owner_user_id',account_ids[2]);
      when 4 then bad_item := manual_item||'{"transferred_at":"2026-10-30T00:00:00Z"}';
      when 5 then bad_item := manual_item||'{"checked":"true"}';
      when 6 then bad_item := manual_item||'{"quantity":0}';
      when 7 then bad_item := manual_item||'{"quantity":1000000.00001}';
      when 8 then bad_item := manual_item||'{"quantity":"2"}';
      when 9 then bad_item := manual_item||'{"name_snapshot":" "}';
      when 10 then bad_item := manual_item||jsonb_build_object('note',repeat('x',1001));
      when 11 then bad_item := manual_item||'{"source":"unknown"}';
      when 12 then bad_item := manual_item||'{"sources":[]}';
      when 13 then bad_item := manual_item||'{"sources":[{"source":"recipe"}]}';
      when 14 then bad_item := manual_item||jsonb_build_object('sources',jsonb_build_array(jsonb_build_object('source','manual','recipe_id',recipe_ids[1])));
      when 15 then bad_item := manual_item||jsonb_build_object('source','plan','sources',jsonb_build_array(jsonb_build_object('source','plan')));
      when 16 then bad_item := manual_item||jsonb_build_object('unit_id',unit_inactive_id);
      when 17 then bad_item := catalog_item||jsonb_build_object('unit_id',unit_count_id);
      when 18 then bad_item := manual_item||'{"id":"invalid-uuid"}';
      when 19 then bad_item := manual_item||'{"sources":[{"source":"manual","user_id":"forbidden"}]}';
      when 20 then bad_item := manual_item||'{"source":"recipe","sources":[{"source":"manual"}]}';
      when 21 then bad_item := catalog_item||jsonb_build_object('unit_id',unit_other_mass_root_id);
    end case;
    begin
      perform public.put_my_shopping_item(list_ids[1],bad_item,list_version);
      raise exception 'FAIL: invalid shopping item accepted';
    exception when invalid_parameter_value then
      get stacked diagnostics error_detail=PG_EXCEPTION_DETAIL;
      if coalesce(error_detail,'')<>'' then raise exception 'FAIL: shopping error exposed DETAIL'; end if;
    end;
    after_state := jsonb_build_object('list',(select to_jsonb(l) from public.shopping_lists l),
      'items',(select jsonb_agg(to_jsonb(i) order by i.id) from public.shopping_items i),
      'sources',(select jsonb_agg(to_jsonb(s) order by s.id) from public.shopping_item_sources s));
    if after_state is distinct from before_state then raise exception 'FAIL: rejected item changed rows or sources'; end if;
  end loop;
  begin perform public.put_my_shopping_item(list_ids[1],manual_item,1); raise exception 'FAIL: stale item save accepted';
  exception when serialization_failure then null; end;
  begin perform public.put_my_shopping_item(list_ids[2],manual_item,1); raise exception 'FAIL: other account list writable';
  exception when insufficient_privilege then null; end;
  begin perform public.create_my_shopping_list(gen_random_uuid(),'Foreign plan',plan_ids[2]); raise exception 'FAIL: other account plan linked';
  exception when insufficient_privilege then null; end;
  begin
    perform public.put_my_shopping_item(list_ids[1],manual_item||jsonb_build_object('source','plan',
      'sources',jsonb_build_array(jsonb_build_object('source','plan','plan_id',plan_ids[2]))),list_version);
    raise exception 'FAIL: other account source plan linked';
  exception when insufficient_privilege then null; end;
  for actor in 2..6 loop
    if actor=3 then continue; end if;
    begin
      perform public.put_my_shopping_item(list_ids[1],manual_item||jsonb_build_object('source','recipe',
        'sources',jsonb_build_array(jsonb_build_object('source','recipe','recipe_id',recipe_ids[actor]))),list_version);
      raise exception 'FAIL: unavailable source recipe linked';
    exception when insufficient_privilege then null; end;
  end loop;
  -- Keep a real multi-source positive control as well as rejected source links.
  select * into saved_list from public.put_my_shopping_item(list_ids[1],manual_item||jsonb_build_object(
    'sources',jsonb_build_array(jsonb_build_object('source','manual'),
      jsonb_build_object('source','recipe','recipe_id',recipe_ids[1]),
      jsonb_build_object('source','plan','plan_id',plan_ids[1]))),list_version);
  list_version := saved_list.version;
  if (select count(*) from public.shopping_item_sources where shopping_item_id=item_manual_id)<>3 then
    raise exception 'FAIL: valid source replacement';
  end if;
  execute 'reset role';
  update public.user_roles set role='ADMIN' where user_id=account_ids[1];
  execute 'set local role authenticated';
  if public.current_app_role()<>'ADMIN' or not exists(select 1 from public.recipes where id=recipe_ids[4]) then
    raise exception 'FAIL: administrator recipe positive control';
  end if;
  begin
    perform public.save_my_meal_plan(date '2026-10-26',jsonb_build_array(jsonb_build_object(
      'meal_date','2026-10-26','meal_shift','lunch','recipe_id',recipe_ids[4],'portions',2)),plan_version);
    raise exception 'FAIL: administrator planned another account private recipe';
  exception when insufficient_privilege then null; end;
  begin
    perform public.put_my_shopping_item(list_ids[1],manual_item||jsonb_build_object('source','recipe',
      'sources',jsonb_build_array(jsonb_build_object('source','recipe','recipe_id',recipe_ids[4]))),list_version);
    raise exception 'FAIL: administrator linked another account private recipe';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.user_roles set role='USER' where user_id=account_ids[1];
  execute 'set local role authenticated';
  select * into saved_list from public.set_my_shopping_checked(list_ids[1],array[item_manual_id,item_catalog_id],true,list_version);
  list_version := saved_list.version;
  if (select count(*) from public.shopping_items where checked)<>2 then raise exception 'FAIL: batch check'; end if;
  select * into saved_list from public.set_my_shopping_checked(list_ids[1],array[item_manual_id,item_catalog_id],true,list_version);
  if saved_list.version<>list_version then raise exception 'FAIL: no-op batch check changed version'; end if;
  execute 'reset role';

  -- Trusted fixture simulates an already transferred item; its ledger must survive deletion.
  insert into public.pantry_receipts(id,owner_user_id,idempotency_key) values(receipt_test_id,account_ids[1],gen_random_uuid());
  insert into public.pantry_receipt_items(receipt_id,original_shopping_item_id,shopping_item_id,quantity_added,unit_abbreviation_snapshot)
    values(receipt_test_id,item_catalog_id,item_catalog_id,1.5,'test-kg');
  update public.shopping_items set transferred_at=now() where id=item_catalog_id;
  execute 'set local role authenticated';
  begin perform public.put_my_shopping_item(list_ids[1],catalog_item,list_version); raise exception 'FAIL: transferred item editable';
  exception when invalid_parameter_value then null; end;
  begin perform public.set_my_shopping_checked(list_ids[1],array[item_catalog_id],false,list_version); raise exception 'FAIL: transferred item unchecked';
  exception when invalid_parameter_value then null; end;
  select * into saved_list from public.remove_my_shopping_item(list_ids[1],item_catalog_id,list_version);
  list_version := saved_list.version;
  if exists(select 1 from public.shopping_items where id=item_catalog_id)
    or not exists(select 1 from public.pantry_receipt_items where original_shopping_item_id=item_catalog_id and shopping_item_id is null) then
    raise exception 'FAIL: transferred item deletion lost ledger';
  end if;
  select * into saved_list from public.remove_my_shopping_item(list_ids[1],item_catalog_id,list_version);
  if saved_list.version<>list_version then raise exception 'FAIL: item delete retry changed version'; end if;
  begin perform public.put_my_shopping_item(list_ids[1],catalog_item,list_version); raise exception 'FAIL: historical item identity reused';
  exception when invalid_parameter_value then null; end;
  select * into saved_list from public.create_my_shopping_list(list_ids[3],'Replacement list',null);
  if saved_list.status<>'active' or saved_list.version<>1 then raise exception 'FAIL: replacement list create'; end if;
  select * into saved_list from public.create_my_shopping_list(list_ids[1],'Synthetic list',plan_ids[1]);
  if saved_list.status<>'archived' or (select count(*) from public.shopping_lists where status='active')<>1
    or not exists(select 1 from public.shopping_lists where id=list_ids[3] and status='active') then
    raise exception 'FAIL: old list retry reactivated archived list';
  end if;
  begin perform public.put_my_shopping_item(list_ids[1],manual_item,list_version); raise exception 'FAIL: archived list writable';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  if not exists(select 1 from public.meal_plans where id=plan_ids[2] and owner_user_id=account_ids[2] and version=1)
    or (select count(*) from public.meal_plan_slots where plan_id=plan_ids[2])<>1
    or not exists(select 1 from public.shopping_lists where id=list_ids[2] and status='active' and version=1) then
    raise exception 'FAIL: A operations changed B plan/list';
  end if;

  update public.account_status set active=false where user_id=account_ids[1];
  for actor in 1..3 loop
    if actor=1 then
      perform set_config('request.jwt.claim.sub',account_ids[1]::text,true);
      perform set_config('request.jwt.claims',jsonb_build_object('sub',account_ids[1],'role','authenticated')::text,true);
      execute 'set local role authenticated';
    else
      perform set_config('request.jwt.claim.sub','',true); perform set_config('request.jwt.claims','{}',true);
      if actor=2 then execute 'set local role authenticated'; else execute 'set local role anon'; end if;
    end if;
    begin perform public.save_my_meal_plan(date '2026-10-26','[]',plan_version); raise exception 'FAIL: unauthorized planner save';
    exception when insufficient_privilege then null; end;
    begin perform public.create_my_shopping_list(gen_random_uuid(),'Forbidden list',null); raise exception 'FAIL: unauthorized list create';
    exception when insufficient_privilege then null; end;
    begin perform public.put_my_shopping_item(list_ids[3],manual_item,1); raise exception 'FAIL: unauthorized item save';
    exception when insufficient_privilege then null; end;
    begin perform public.set_my_shopping_checked(list_ids[3],array[item_manual_id],true,1); raise exception 'FAIL: unauthorized item check';
    exception when insufficient_privilege then null; end;
    begin perform public.remove_my_shopping_item(list_ids[3],item_manual_id,1); raise exception 'FAIL: unauthorized item delete';
    exception when insufficient_privilege then null; end;
    execute 'reset role';
  end loop;
  if (select version from public.meal_plans where id=plan_ids[1])<>plan_version
    or (select count(*) from public.shopping_lists where owner_user_id=account_ids[1])<>2 then
    raise exception 'FAIL: unauthorized calls changed state';
  end if;
  perform set_config('request.jwt.claim.sub','',true); perform set_config('request.jwt.claims','{}',true);
end;
$planning_shopping_tests$;
select 'PASS: planning/shopping RPC ownership, atomic validation, versions, one active list, source links, unit compatibility, checked states, transfer-ledger preservation and inactive/anonymous restrictions verified; wrapper ROLLBACK required' as result;
