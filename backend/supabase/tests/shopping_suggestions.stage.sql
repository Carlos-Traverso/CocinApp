-- STAGE ONLY, run using the complete generated rollback rehearsal.
do $tests$
declare
  a uuid; b uuid; cat uuid:=gen_random_uuid(); grams uuid:=gen_random_uuid(); kilos uuid:=gen_random_uuid(); cups uuid:=gen_random_uuid();
  ingredient uuid:=gen_random_uuid(); recipe uuid:=gen_random_uuid(); plan uuid:=gen_random_uuid();
  suggestions jsonb; repeat_result jsonb; before_count bigint; rejected boolean;
begin
  select id into a from auth.users where banned_until is null order by id limit 1;
  select id into b from auth.users where banned_until is null and id<>a order by id limit 1;
  if a is null or b is null then raise exception 'FAIL: requires two existing active Auth accounts'; end if;
  -- This preview scans the actor's full pantry. Clear it only inside this
  -- rollback wrapper to isolate fixtures; the final ROLLBACK restores all rows.
  delete from public.pantry_items where user_id=a;
  insert into public.account_status(user_id,active) values(a,true),(b,true)
    on conflict(user_id) do update set active=true;
  insert into public.categories(id,name,normalized_name) values(cat,'Suggestion test','suggestion-test');
  insert into public.units(id,name,abbreviation,dimension) values(grams,'Test gram','s-g','mass');
  insert into public.units(id,name,abbreviation,dimension,base_unit_id,equivalence_multiplier) values(kilos,'Test kilo','s-kg','mass',grams,1000);
  insert into public.units(id,name,abbreviation,dimension) values(cups,'Test cup','s-cup','volume');
  insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id)
    values(ingredient,'Suggestion ingredient','suggestion-ingredient',cat,grams);
  insert into public.recipes(id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
    values(recipe,'official','Suggestion recipe',1,2,'easy','published');
  insert into public.recipe_ingredients(recipe_id,ingredient_id,quantity,unit_id,position) values(recipe,ingredient,0.5,kilos,1);
  insert into public.meal_plans(id,owner_user_id,week_start) values(plan,a,'2026-10-26');
  insert into public.meal_plan_slots(plan_id,meal_date,meal_shift,recipe_id,portions,position)
    values(plan,'2026-10-26','lunch',recipe,2,1),(plan,'2026-10-27','dinner',recipe,4,1);
  insert into public.favorite_recipes(user_id,recipe_id) values(a,recipe);
  insert into public.pantry_items(id,user_id,name,category,quantity,unit,minimum,expiry,ingredient_ref,unit_ref) values
    ('00000000-0000-0000-0000-000000000101',a,'Suggestion ingredient','Suggestion test',0.2,'s-kg',0.4,null,ingredient,kilos),
    ('00000000-0000-0000-0000-000000000102',a,'Suggestion ingredient','Suggestion test',999,'s-g',0,'2026-10-01',ingredient,grams),
    (gen_random_uuid(),b,'Suggestion ingredient','Suggestion test',999,'s-kg',0,null,ingredient,kilos),
    (gen_random_uuid(),a,'Manual oats','Suggestion test',0,'s-g',50,null,null,grams),
    (gen_random_uuid(),a,U&'Caf\00e9','Suggestion test',0,'s-g',20,null,null,grams),
    (gen_random_uuid(),a,U&'Cafe\0301','Suggestion test',0.5,'s-g',10,null,null,grams);
  select count(*) into before_count from public.pantry_items;
  if has_function_privilege('anon','public.suggest_my_shopping(text,uuid,date)','EXECUTE')
    or not has_function_privilege('authenticated','public.suggest_my_shopping(text,uuid,date)','EXECUTE') then
    raise exception 'FAIL: suggestion execution grants'; end if;
  perform set_config('request.jwt.claim.sub',a::text,true);
  execute 'set local role authenticated';
  suggestions:=public.suggest_my_shopping('plan',plan,'2026-10-30');
  if jsonb_array_length(suggestions)<>1 or (suggestions->0->>'quantity')::numeric<>1300
    or suggestions->0->'sources'<>jsonb_build_array(jsonb_build_object('source','plan','plan_id',plan)) then
    raise exception 'FAIL: portions, repeated slots, conversion, expired stock, isolation or provenance'; end if;
  repeat_result:=public.suggest_my_shopping('plan',plan,'2026-10-30');
  if repeat_result<>suggestions then raise exception 'FAIL: repeat preview'; end if;
  suggestions:=public.suggest_my_shopping('favorites',null,'2026-10-30');
  if (suggestions->0->>'quantity')::numeric<>300 then raise exception 'FAIL: favorites base portions'; end if;
  execute 'reset role';
  update public.pantry_items set unit_ref=grams where user_id=a and ingredient_ref=ingredient and unit='s-kg';
  rejected:=false;
  execute 'set local role authenticated';
  begin perform public.suggest_my_shopping('favorites',null,'2026-10-30');
    exception when sqlstate '22023' then rejected:=true; end;
  if not rejected then raise exception 'FAIL: unit_ref/text or incompatible stock unit accepted'; end if;
  execute 'reset role';
  update public.pantry_items set unit_ref=cups,unit='s-cup' where user_id=a and ingredient_ref=ingredient and unit='s-kg';
  rejected:=false;
  execute 'set local role authenticated';
  begin perform public.suggest_my_shopping('favorites',null,'2026-10-30');
    exception when sqlstate '22023' then rejected:=true; end;
  if not rejected then raise exception 'FAIL: incompatible stock dimension accepted'; end if;
  execute 'reset role';
  update public.pantry_items set unit_ref=kilos,unit='s-kg' where user_id=a and ingredient_ref=ingredient and unit in ('s-kg','s-cup');
  execute 'set local role authenticated';
  suggestions:=public.suggest_my_shopping('pantry',null,'2026-10-30');
  if jsonb_array_length(suggestions)<>3
    or not exists(select 1 from jsonb_array_elements(suggestions) x where x->>'name_snapshot'='Manual oats'
      and x->'ingredient_id'='null'::jsonb and (x->>'quantity')::numeric=50)
    or not exists(select 1 from jsonb_array_elements(suggestions) x join public.units u on u.id=(x->>'unit_id')::uuid
      where x->>'ingredient_id'=ingredient::text and u.id in (grams,kilos)
        and (x->>'quantity')::numeric*coalesce(u.equivalence_multiplier,1)=200)
    or (select count(*) from jsonb_array_elements(suggestions) x where normalize(lower(x->>'name_snapshot'),NFD)=normalize(lower(U&'Caf\00e9'),NFD))<>1
    or not exists(select 1 from jsonb_array_elements(suggestions) x where normalize(lower(x->>'name_snapshot'),NFD)=normalize(lower(U&'Caf\00e9'),NFD)
      and (x->>'quantity')::numeric=19.5) then raise exception 'FAIL: restock minimum, conversion, manual preservation or NFD grouping'; end if;
  -- Reverse which equivalent stock row sorts first. The output unit can change,
  -- but the converted restock amount must remain 200 g.
  execute 'reset role';
  update public.pantry_items set id='00000000-0000-0000-0000-000000000103'
    where id='00000000-0000-0000-0000-000000000101';
  update public.pantry_items set id='00000000-0000-0000-0000-000000000101'
    where id='00000000-0000-0000-0000-000000000102';
  update public.pantry_items set id='00000000-0000-0000-0000-000000000102'
    where id='00000000-0000-0000-0000-000000000103';
  execute 'set local role authenticated';
  suggestions:=public.suggest_my_shopping('pantry',null,'2026-10-30');
  if not exists(select 1 from jsonb_array_elements(suggestions) x join public.units u on u.id=(x->>'unit_id')::uuid
    where x->>'ingredient_id'=ingredient::text and u.id in (grams,kilos)
      and (x->>'quantity')::numeric*coalesce(u.equivalence_multiplier,1)=200) then
    raise exception 'FAIL: restock conversion depends on equivalent stock row ordering'; end if;
  begin perform public.suggest_my_shopping('plan',null,'2026-10-30'); raise exception 'FAIL: invalid plan accepted';
    exception when sqlstate '22023' then null; end;
  begin perform public.suggest_my_shopping('pantry',plan,'2026-10-30'); raise exception 'FAIL: unexpected plan accepted';
    exception when sqlstate '22023' then null; end;
  execute 'reset role';
  if (select count(*) from public.pantry_items)<>before_count or exists(select 1 from public.shopping_lists) then
    raise exception 'FAIL: preview changed inventory or shopping'; end if;
  perform set_config('request.jwt.claim.sub',b::text,true);
  execute 'set local role authenticated';
  if public.suggest_my_shopping('favorites',null,'2026-10-30')<>'[]'::jsonb then raise exception 'FAIL: favorite isolation'; end if;
  begin perform public.suggest_my_shopping('plan',plan,'2026-10-30'); raise exception 'FAIL: foreign plan accepted';
    exception when sqlstate '42501' then null; end;
  execute 'reset role';
  update public.account_status set active=false where user_id=b;
  execute 'set local role authenticated';
  begin perform public.suggest_my_shopping('pantry',null,'2026-10-30'); raise exception 'FAIL: inactive account accepted';
    exception when sqlstate '42501' then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',a::text,true);
  update public.units set active=false where id=kilos;
  execute 'set local role authenticated';
  begin perform public.suggest_my_shopping('favorites',null,'2026-10-30'); raise exception 'FAIL: inactive unit accepted';
    exception when sqlstate '22023' then null; end;
  execute 'reset role';
  raise notice 'PASS: shopping suggestions, unit validation, NFD grouping, stock conversion, portions, expiry, manual restock, isolation and no writes; wrapper ROLLBACK required';
end;
$tests$;
