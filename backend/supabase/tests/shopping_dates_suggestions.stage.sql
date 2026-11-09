-- STAGE ONLY. Run inside the generated rehearsal transaction and finish with ROLLBACK.
do $tests$
declare
  a uuid; b uuid; cat uuid:=gen_random_uuid(); grams uuid:=gen_random_uuid(); kilos uuid:=gen_random_uuid();
  ingredient uuid:=gen_random_uuid(); recipe uuid:=gen_random_uuid(); plan_one uuid:=gen_random_uuid(); plan_two uuid:=gen_random_uuid();
  result jsonb; before_pantry bigint; before_lists bigint; rejected boolean;
begin
  select id into a from auth.users where banned_until is null order by id limit 1;
  select id into b from auth.users where banned_until is null and id<>a order by id limit 1;
  if a is null or b is null then raise exception 'FAIL: requires two existing active Auth accounts'; end if;
  delete from public.pantry_items where user_id=a;
  insert into public.account_status(user_id,active) values(a,true),(b,true)
    on conflict(user_id) do update set active=true;
  insert into public.categories(id,name,normalized_name) values(cat,'Date suggestion test','date-suggestion-test');
  insert into public.units(id,name,abbreviation,dimension) values(grams,'Date test gram','ds-g','mass');
  insert into public.units(id,name,abbreviation,dimension,base_unit_id,equivalence_multiplier)
    values(kilos,'Date test kilo','ds-kg','mass',grams,1000);
  insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id)
    values(ingredient,'Date test ingredient','date-test-ingredient',cat,grams);
  insert into public.recipes(id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
    values(recipe,'official','Date test recipe',1,2,'easy','published');
  insert into public.recipe_ingredients(recipe_id,ingredient_id,quantity,unit_id,position)
    values(recipe,ingredient,0.5,kilos,1);
  insert into public.meal_plans(id,owner_user_id,week_start) values(plan_one,a,'2026-10-26'),(plan_two,a,'2026-11-02');
  insert into public.meal_plan_slots(plan_id,meal_date,meal_shift,recipe_id,portions,position) values
    (plan_one,'2026-10-26','lunch',recipe,2,1),
    (plan_one,'2026-10-27','dinner',recipe,20,1), -- must be excluded: same week, unselected day
    (plan_two,'2026-11-02','lunch',recipe,4,1);
  insert into public.pantry_items(id,user_id,name,category,quantity,unit,minimum,expiry,ingredient_ref,unit_ref)
    values(gen_random_uuid(),a,'Date test ingredient','Date suggestion test',0.2,'ds-kg',0,null,ingredient,kilos),
      (gen_random_uuid(),b,'Date test ingredient','Date suggestion test',99,'ds-kg',0,null,ingredient,kilos);
  select count(*) into before_pantry from public.pantry_items;
  select count(*) into before_lists from public.shopping_lists;
  if has_function_privilege('anon','public.suggest_my_shopping_for_dates(date[],date)','EXECUTE')
    or not has_function_privilege('authenticated','public.suggest_my_shopping_for_dates(date[],date)','EXECUTE') then
    raise exception 'FAIL: date suggestion grants'; end if;

  perform set_config('request.jwt.claim.sub',a::text,true);
  execute 'set local role authenticated';
  result:=public.suggest_my_shopping_for_dates(array['2026-10-26'::date,'2026-11-02'::date],'2026-10-30');
  if jsonb_array_length(result)<>1 or (result->0->>'quantity')::numeric<>1300
    or result->0->>'source'<>'plan'
    or jsonb_array_length(result->0->'sources')<>2
    or not exists(select 1 from jsonb_array_elements(result->0->'sources') x where x->>'plan_id'=plan_one::text)
    or not exists(select 1 from jsonb_array_elements(result->0->'sources') x where x->>'plan_id'=plan_two::text) then
    raise exception 'FAIL: dates across weeks, partial-week exclusion, portions, conversion, or one-time pantry subtraction'; end if;
  result:=public.suggest_my_shopping_for_dates(array['2026-10-27'::date],'2026-10-30');
  if jsonb_array_length(result)<>1 or (result->0->>'quantity')::numeric<>4800 then
    raise exception 'FAIL: explicitly selected same-week slot portions were not included'; end if;
  if public.suggest_my_shopping_for_dates(array['2026-10-28'::date],'2026-10-30')<>'[]'::jsonb then
    raise exception 'FAIL: date without a selected plan slot returned suggestions'; end if;
  rejected:=false;
  begin perform public.suggest_my_shopping_for_dates(array[]::date[],'2026-10-30'); exception when sqlstate '22023' then rejected:=true; end;
  if not rejected then raise exception 'FAIL: empty dates accepted'; end if;
  rejected:=false;
  begin perform public.suggest_my_shopping_for_dates(array['2026-10-26'::date,'2026-10-26'::date],'2026-10-30'); exception when sqlstate '22023' then rejected:=true; end;
  if not rejected then raise exception 'FAIL: duplicate dates accepted'; end if;
  rejected:=false;
  begin perform public.suggest_my_shopping_for_dates(null::date[],'2026-10-30'); exception when sqlstate '22023' then rejected:=true; end;
  if not rejected then raise exception 'FAIL: NULL dates accepted'; end if;
  rejected:=false;
  begin perform public.suggest_my_shopping_for_dates(array[null::date],'2026-10-30'); exception when sqlstate '22023' then rejected:=true; end;
  if not rejected then raise exception 'FAIL: NULL date element accepted'; end if;
  rejected:=false;
  begin perform public.suggest_my_shopping_for_dates(array_fill('2026-10-26'::date,array[43]),'2026-10-30'); exception when sqlstate '22023' then rejected:=true; end;
  if not rejected then raise exception 'FAIL: over-limit dates accepted'; end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',b::text,true);
  execute 'set local role authenticated';
  if public.suggest_my_shopping_for_dates(array['2026-10-26'::date,'2026-11-02'::date],'2026-10-30')<>'[]'::jsonb then
    raise exception 'FAIL: another account plan leaked into preview'; end if;
  execute 'reset role';
  update public.account_status set active=false where user_id=b;
  execute 'set local role authenticated';
  rejected:=false;
  begin perform public.suggest_my_shopping_for_dates(array['2026-10-26'::date],'2026-10-30'); exception when sqlstate '42501' then rejected:=true; end;
  if not rejected then raise exception 'FAIL: inactive account accepted'; end if;
  execute 'reset role';
  if (select count(*) from public.pantry_items)<>before_pantry or (select count(*) from public.shopping_lists)<>before_lists then
    raise exception 'FAIL: suggestions changed pantry or shopping lists'; end if;
  raise notice 'PASS: selected dates, cross-week aggregation, single pantry subtraction, validation, account isolation and no writes; wrapper ROLLBACK required';
end;
$tests$;
