-- STAGE ONLY; runs in one transaction with ROLLBACK. Requires two active synthetic-domain accounts.
do $cooking_session_tests$
declare users uuid[]; cat uuid:=gen_random_uuid(); unit_id uuid:=gen_random_uuid(); ing uuid:=gen_random_uuid(); recipe uuid:=gen_random_uuid(); ri uuid:=gen_random_uuid(); step1 uuid:=gen_random_uuid(); step2 uuid:=gen_random_uuid(); sid uuid:=gen_random_uuid(); saved public.cooking_sessions; payload jsonb;
begin
  select array_agg(id order by id) into users from (select id from auth.users where banned_until is null or banned_until<=now() order by id limit 2) a;
  if cardinality(users)<2 then raise exception 'FAIL: two active test accounts required'; end if;
  insert into public.account_status(user_id,active) select unnest(users),true on conflict(user_id) do update set active=true;
  insert into public.categories(id,name,normalized_name) values(cat,'Test','cooking-'||cat);
  insert into public.units(id,name,abbreviation,dimension) values(unit_id,'Gram','gc'||substr(cat::text,1,3),'mass');
  insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values(ing,'Test ingredient','cooking-'||ing,cat,unit_id);
  insert into public.recipes(id,recipe_source,title,total_minutes,portions,difficulty,publication_status) values(recipe,'official','Session test',5,2,'easy','published');
  insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,position) values(ri,recipe,ing,3,unit_id,1);
  insert into public.recipe_steps(id,recipe_id,position,instruction,duration_minutes,tip) values
    (step1,recipe,1,'Stir',2,'Use a spoon'),(step2,recipe,2,'Serve',null,null);
  insert into public.recipe_step_ingredients(step_id,recipe_ingredient_id,quantity_override) values(step1,ri,1.5);
  perform set_config('request.jwt.claim.sub',users[1]::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true); execute 'set local role authenticated';
  select * into saved from public.start_my_cooking_session(sid,recipe,2);
  if saved.owner_user_id<>users[1] or saved.version<>1 or saved.current_step<>0 or jsonb_array_length(saved.recipe_snapshot->'steps')<>2
    or saved.recipe_snapshot->'ingredients'->0->>'name'<>'Test ingredient'
    or saved.recipe_snapshot->'ingredients'->0->>'unitId'<>unit_id::text
    or saved.recipe_snapshot->'ingredients'->0->>'unitRootId'<>unit_id::text
    or (saved.recipe_snapshot->'ingredients'->0->>'unitFactor')::numeric<>1
    or saved.recipe_snapshot->'steps'->0->'stepIngredients'->0->>'ingredientId'<>ing::text
    or (saved.recipe_snapshot->'steps'->0->'stepIngredients'->0->>'quantity')::numeric<>1.5 then raise exception 'FAIL: start snapshot'; end if;
  begin perform public.start_my_cooking_session(gen_random_uuid(),recipe,null); raise exception 'FAIL: NULL portions accepted on start'; exception when invalid_parameter_value then null; end;
  if (select id from public.start_my_cooking_session(sid,recipe,2))<>sid then raise exception 'FAIL: start retry'; end if;
  begin perform public.start_my_cooking_session(sid,recipe,3); raise exception 'FAIL: mismatched start retry accepted'; exception when unique_violation then null; end;
  execute 'reset role'; update public.recipes set title='Changed after session start' where id=recipe;
  perform set_config('request.jwt.claim.sub',users[1]::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true); execute 'set local role authenticated';
  payload:=public.get_my_cooking_session(sid);
  if jsonb_array_length(payload->'steps')<>2 or payload->'recipe_snapshot'->>'name'<>'Session test' then raise exception 'FAIL: resume or immutable snapshot'; end if;
  select * into saved from public.update_my_cooking_session(sid,1,'timer_start',0);
  if saved.version<>2 then raise exception 'FAIL: timer start version'; end if;
  begin perform public.update_my_cooking_session(sid,1,'move',1); raise exception 'FAIL: stale version accepted'; exception when serialization_failure then null; end;
  select * into saved from public.update_my_cooking_session(sid,2,'move',1);
  if saved.version<>3 or (select timer_state from public.cooking_session_steps where session_id=sid and step_position=1)<>'paused' then raise exception 'FAIL: moving away did not pause timer'; end if;
  select * into saved from public.update_my_cooking_session(sid,3,'move',0);
  select * into saved from public.update_my_cooking_session(sid,4,'timer_resume',0);
  if saved.version<>5 then raise exception 'FAIL: timer resume version'; end if;
  select * into saved from public.update_my_cooking_session(sid,5,'portions',null,4);
  if saved.version<>6 or saved.portions<>4 then raise exception 'FAIL: portions progress'; end if;
  if (select id from public.start_my_cooking_session(sid,recipe,2))<>sid then raise exception 'FAIL: retry after portion update'; end if;
  begin perform public.update_my_cooking_session(sid,6,'portions',null,0); raise exception 'FAIL: invalid portions accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.update_my_cooking_session(sid,6,'portions',null,null); raise exception 'FAIL: NULL portions accepted on update'; exception when invalid_parameter_value then null; end;
  begin perform public.update_my_cooking_session(sid,6,null,0); raise exception 'FAIL: NULL action accepted'; exception when invalid_parameter_value then null; end;
  execute 'reset role'; update public.cooking_session_steps set timer_deadline_at=clock_timestamp()-interval '1 second' where session_id=sid and step_position=1;
  perform set_config('request.jwt.claim.sub',users[1]::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true); execute 'set local role authenticated';
  payload:=public.get_my_cooking_session(sid);
  if (payload->'steps'->0->>'remaining_ms')::bigint<>0 then raise exception 'FAIL: elapsed deadline not derived on resume'; end if;
  select * into saved from public.update_my_cooking_session(sid,6,'timer_pause',0);
  if (select timer_state from public.cooking_session_steps where session_id=sid and step_position=1)<>'finished' then raise exception 'FAIL: elapsed timer pause'; end if;
  select * into saved from public.update_my_cooking_session(sid,7,'move',1);
  select * into saved from public.update_my_cooking_session(sid,8,'complete',1);
  if (select completed_at from public.cooking_session_steps where session_id=sid and step_position=2) is null then raise exception 'FAIL: completion not saved'; end if;
  perform set_config('request.jwt.claim.sub',users[2]::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',users[2],'role','authenticated')::text,true);
  begin perform public.get_my_cooking_session(sid); raise exception 'FAIL: other user session read'; exception when no_data_found then null; when insufficient_privilege then null; end;
  begin insert into public.cooking_sessions(owner_user_id,recipe_snapshot,portions,client_idempotency_key) values(users[2],'{}',1,gen_random_uuid()); raise exception 'FAIL: direct session DML allowed'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  raise notice 'PASS: cooking session start, snapshot, version, timer, portions, completion, and owner checks';
end $cooking_session_tests$;
