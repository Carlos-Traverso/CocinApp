-- STAGE ONLY: transaction ends in ROLLBACK. Uses two existing active test accounts.
do $finish$
declare users uuid[]; cat uuid:=gen_random_uuid(); root_unit uuid:=gen_random_uuid(); sub_unit uuid:=gen_random_uuid(); ing uuid:=gen_random_uuid(); fractional_ing uuid:=gen_random_uuid(); exact_ing uuid:=gen_random_uuid(); recipe uuid:=gen_random_uuid(); ri uuid:=gen_random_uuid(); ri2 uuid:=gen_random_uuid(); step_id uuid:=gen_random_uuid(); sid uuid:=gen_random_uuid(); shortage_sid uuid:=gen_random_uuid(); fractional_recipe uuid:=gen_random_uuid(); fractional_ri uuid:=gen_random_uuid(); fractional_step uuid:=gen_random_uuid(); fractional_sid uuid:=gen_random_uuid(); fractional_lot uuid:=gen_random_uuid(); exact_recipe uuid:=gen_random_uuid(); exact_ri uuid:=gen_random_uuid(); exact_step uuid:=gen_random_uuid(); exact_sid uuid:=gen_random_uuid(); exact_lot uuid:=gen_random_uuid(); lot1 uuid:=gen_random_uuid(); lot2 uuid:=gen_random_uuid(); expired uuid:=gen_random_uuid(); bad_label uuid:=gen_random_uuid(); ingredient_name text:='Finish ingredient '||gen_random_uuid()::text; fractional_name text:='Fractional ingredient '||gen_random_uuid()::text; exact_name text:='Exact scaled ingredient '||gen_random_uuid()::text; ev public.cooking_events; initial_qty numeric;
begin
 select array_agg(id order by id) into users from (select id from auth.users where banned_until is null or banned_until<=now() order by id limit 2) a;
 if cardinality(users)<2 then raise exception 'FAIL: two active test accounts required'; end if;
 insert into public.account_status(user_id,active) select unnest(users),true on conflict(user_id) do update set active=true;
 insert into public.categories(id,name,normalized_name) values(cat,'Finish test','finish-'||cat);
 insert into public.units(id,name,abbreviation,dimension) values(root_unit,'Gram','gf'||substr(cat::text,1,3),'mass');
 insert into public.units(id,name,abbreviation,dimension,base_unit_id,equivalence_multiplier) values(sub_unit,'Kilogram','kf'||substr(cat::text,1,3),'mass',root_unit,1000);
 insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values(ing,ingredient_name,'finish-'||ing,cat,root_unit);
 insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values(fractional_ing,fractional_name,'fractional-'||fractional_ing,cat,root_unit);
 insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values(exact_ing,exact_name,'exact-'||exact_ing,cat,root_unit);
 insert into public.recipes(id,recipe_source,title,total_minutes,portions,difficulty,publication_status) values(recipe,'official','Finish test',5,2,'easy','published');
 insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,position) values(ri,recipe,ing,250,root_unit,1),(ri2,recipe,ing,250,root_unit,2);
 insert into public.recipe_steps(id,recipe_id,position,instruction) values(step_id,recipe,1,'Finish');
 insert into public.recipes(id,recipe_source,title,total_minutes,portions,difficulty,publication_status) values(fractional_recipe,'official','Fractional finish test',5,3,'easy','published');
 insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,position) values(fractional_ri,fractional_recipe,fractional_ing,1,root_unit,1);
 insert into public.recipe_steps(id,recipe_id,position,instruction) values(fractional_step,fractional_recipe,1,'Measure');
 insert into public.recipes(id,recipe_source,title,total_minutes,portions,difficulty,publication_status) values(exact_recipe,'official','Exact scaled finish test',5,3,'easy','published');
 insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,position) values(exact_ri,exact_recipe,exact_ing,3,root_unit,1);
 insert into public.recipe_steps(id,recipe_id,position,instruction) values(exact_step,exact_recipe,1,'Measure');
 insert into public.pantry_items(id,user_id,name,category,quantity,unit,minimum,expiry,ingredient_ref,unit_ref) values
   (lot1,users[1],ingredient_name,'Finish test',0.2,'kf'||substr(cat::text,1,3),0,current_date+2,ing,sub_unit),
   (lot2,users[1],'  '||replace(ingredient_name,' ','   ')||' ','Finish test',400,'gf'||substr(cat::text,1,3),0,null,null,root_unit),
   (expired,users[1],ingredient_name,'Finish test',1000,'gf'||substr(cat::text,1,3),0,current_date-1,ing,root_unit),
   (bad_label,users[1],ingredient_name,'Finish test',1000,'kf'||substr(cat::text,1,3),0,null,ing,root_unit),
   (fractional_lot,users[1],fractional_name,'Finish test',1,'gf'||substr(cat::text,1,3),0,null,fractional_ing,root_unit),
   (exact_lot,users[1],exact_name,'Finish test',1,'gf'||substr(cat::text,1,3),0,null,exact_ing,root_unit);
 perform set_config('request.jwt.claim.sub',users[1]::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true); execute 'set local role authenticated';
 perform public.start_my_cooking_session(sid,recipe,2);
 begin perform public.finish_my_cooking_session(sid,2,true); raise exception 'FAIL: stale first finish accepted'; exception when serialization_failure then null; end;
 select * into ev from public.finish_my_cooking_session(sid,1,true);
 if ev.session_id<>sid or not ev.deduct_stock or (select quantity from public.pantry_items where id=lot1)<>0 or (select quantity from public.pantry_items where id=lot2)<>100 or (select quantity from public.pantry_items where id=expired)<>1000 or (select quantity from public.pantry_items where id=bad_label)<>1000 then raise exception 'FAIL: FIFO exact deduction, expired exclusion, or unit-label mismatch'; end if;
 if (select count(*) from public.cooking_event_ingredients where event_id=ev.id)<>1 or (select quantity_used from public.cooking_event_ingredients where event_id=ev.id)<>500 then raise exception 'FAIL: aggregated consumed history'; end if;
 if (select count(*) from public.cooking_events where session_id=sid)<>1 or (select finished_at from public.cooking_sessions where id=sid) is null then raise exception 'FAIL: finish event/session'; end if;
 begin perform public.finish_my_cooking_session(sid,999,false); raise exception 'FAIL: changed discount decision accepted'; exception when invalid_parameter_value then null; end;
 if (select id from public.finish_my_cooking_session(sid,999,true))<>ev.id then raise exception 'FAIL: stale completed retry did not return original event'; end if;
 perform public.start_my_cooking_session(shortage_sid,recipe,2);
 initial_qty:=(select quantity from public.pantry_items where id=lot2);
 begin perform public.finish_my_cooking_session(shortage_sid,1,true); raise exception 'FAIL: shortage accepted'; exception when invalid_parameter_value then null; end;
 if (select quantity from public.pantry_items where id=lot2)<>initial_qty or exists(select 1 from public.cooking_events where session_id=shortage_sid)
   or (select finished_at from public.cooking_sessions where id=shortage_sid) is not null or (select version from public.cooking_sessions where id=shortage_sid)<>1 then raise exception 'FAIL: shortage did not roll back all changes'; end if;
 perform public.start_my_cooking_session(fractional_sid,fractional_recipe,1);
 begin perform public.finish_my_cooking_session(fractional_sid,1,true); raise exception 'FAIL: unrepresentable fractional deduction accepted'; exception when invalid_parameter_value then null; end;
 if (select quantity from public.pantry_items where id=fractional_lot)<>1 or exists(select 1 from public.cooking_events where session_id=fractional_sid)
   or (select finished_at from public.cooking_sessions where id=fractional_sid) is not null then raise exception 'FAIL: fractional rollback'; end if;
 perform public.start_my_cooking_session(exact_sid,exact_recipe,1);
 select * into ev from public.finish_my_cooking_session(exact_sid,1,true);
 if not ev.deduct_stock or (select quantity from public.pantry_items where id=exact_lot)<>0
   or (select quantity_used from public.cooking_event_ingredients where event_id=ev.id)<>1 then raise exception 'FAIL: exact scaled arithmetic'; end if;
 execute 'reset role';
 insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,portions,requested_portions,client_idempotency_key) values(gen_random_uuid(),users[1],recipe,'{"portions":2,"ingredients":[],"steps":[]}',2,2,gen_random_uuid()) returning id into sid;
 execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub',users[1]::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
 select * into ev from public.finish_my_cooking_session(sid,1,false);
 if ev.deduct_stock or exists(select 1 from public.cooking_event_ingredients where event_id=ev.id) then raise exception 'FAIL: no-deduction history fabricated'; end if;
 execute 'reset role'; perform set_config('request.jwt.claim.sub',users[2]::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',users[2],'role','authenticated')::text,true); execute 'set local role authenticated';
 begin perform public.finish_my_cooking_session(sid,1,false); raise exception 'FAIL: other account finalized session'; exception when no_data_found then null; when insufficient_privilege then null; end;
 execute 'reset role'; raise notice 'PASS: cooking finish, discount persistence, exact lots, event history, account ownership';
end $finish$;
