-- STAGE ONLY: transaction ends in ROLLBACK; all fixture names are randomized.
do $queries$
declare users uuid[]; sid uuid:=gen_random_uuid(); ev public.cooking_events; first_id uuid; hidden_count integer;
 cat uuid:=gen_random_uuid(); root_unit uuid:=gen_random_uuid(); sub_unit uuid:=gen_random_uuid(); ing uuid:=gen_random_uuid(); ing2 uuid:=gen_random_uuid(); recipe uuid:=gen_random_uuid(); private_recipe uuid:=gen_random_uuid(); ambiguous_recipe uuid:=gen_random_uuid();
 recipe_ingredient_a uuid:=gen_random_uuid(); recipe_ingredient_b uuid:=gen_random_uuid(); ambiguous_ri_a uuid:=gen_random_uuid(); ambiguous_ri_b uuid:=gen_random_uuid(); linked_lot uuid:=gen_random_uuid(); manual_lot uuid:=gen_random_uuid(); expired_lot uuid:=gen_random_uuid(); foreign_lot uuid:=gen_random_uuid(); stock_session uuid:=gen_random_uuid(); stock_result jsonb; stock_qty numeric; stock_count integer; stock_name text:='Queries fixture '||gen_random_uuid()::text;
begin
 select array_agg(id order by id) into users from (select id from auth.users where banned_until is null or banned_until<=now() order by id limit 2) u;
 if cardinality(users)<2 then raise exception 'FAIL: two active test accounts required'; end if;
 insert into public.account_status(user_id,active) select unnest(users),true on conflict(user_id) do update set active=true;
 insert into public.categories(id,name,normalized_name) values(cat,'Queries fixture','queries-'||cat);
 insert into public.units(id,name,abbreviation,dimension) values(root_unit,'Queries root','qr'||substr(cat::text,1,3),'mass');
 insert into public.units(id,name,abbreviation,dimension,base_unit_id,equivalence_multiplier) values(sub_unit,'Queries scaled','qs'||substr(cat::text,1,3),'mass',root_unit,1000);
 insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values(ing,stock_name,'queries-'||ing,cat,root_unit);
 insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values(ing2,stock_name,'queries-'||ing2,cat,root_unit);
 insert into public.recipes(id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty,publication_status) values
   (recipe,null,'official','Queries stock fixture',5,2,'easy','published'),(private_recipe,users[2],'user','Private queries fixture',5,2,'easy','draft'),
   (ambiguous_recipe,null,'official','Ambiguous queries fixture',5,2,'easy','published');
 insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,position) values
   (recipe_ingredient_a,recipe,ing,500,root_unit,1),(recipe_ingredient_b,recipe,ing,0.5,sub_unit,2);
 insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,position) values
   (ambiguous_ri_a,ambiguous_recipe,ing,100,root_unit,1),(ambiguous_ri_b,ambiguous_recipe,ing2,100,root_unit,2);
 insert into public.recipe_steps(recipe_id,position,instruction) values(recipe,1,'Measure'),(private_recipe,1,'Measure');
 insert into public.pantry_items(id,user_id,name,category,quantity,unit,minimum,expiry,ingredient_ref,unit_ref) values
   (linked_lot,users[1],stock_name,'Queries fixture',0.5,'qs'||substr(cat::text,1,3),0,current_date+3,ing,sub_unit),
   (manual_lot,users[1],' '||stock_name||' ','Queries fixture',500,'qr'||substr(cat::text,1,3),0,null,null,root_unit),
   (expired_lot,users[1],stock_name,'Queries fixture',1000,'qr'||substr(cat::text,1,3),0,current_date-1,ing,root_unit),
   (foreign_lot,users[2],stock_name,'Queries fixture',1000,'qr'||substr(cat::text,1,3),0,null,ing,root_unit);
 insert into public.user_roles(user_id,role) values(users[1],'ADMIN') on conflict(user_id) do update set role='ADMIN';
 stock_qty:=(select sum(quantity) from public.pantry_items where user_id=users[1]);
 stock_count:=(select count(*) from public.pantry_items where user_id=users[1]);
 insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,portions,requested_portions,client_idempotency_key)
 values(sid,users[1],null,jsonb_build_object('id',gen_random_uuid(),'name','Private archived snapshot','portions',1,'ingredients','[]'::jsonb,'steps','[]'::jsonb),1,1,gen_random_uuid());
 execute 'set local role authenticated';
 perform set_config('request.jwt.claim.sub',users[1]::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
 stock_result:=public.check_my_cooking_stock(recipe,2,null);
 if jsonb_array_length(stock_result->'ingredients')<>1 or (stock_result->'ingredients'->0->>'required')::numeric<>1000
   or (stock_result->'ingredients'->0->>'available')::numeric<>1000 or not (stock_result->>'sufficient')::boolean
   then raise exception 'FAIL: duplicate unit aggregation, manual/catalog matching, expired or foreign exclusion'; end if;
 begin perform public.check_my_cooking_stock(ambiguous_recipe,1,null); raise exception 'FAIL: ambiguous shared manual name counted for multiple catalog IDs'; exception when invalid_parameter_value then null; end;
 stock_result:=public.check_my_cooking_stock(recipe,4,null);
 if (stock_result->'ingredients'->0->>'missing')::numeric<>1000 or (stock_result->>'sufficient')::boolean
   then raise exception 'FAIL: scaled stock shortage'; end if;
 if (select sum(quantity) from public.pantry_items where user_id=users[1])<>stock_qty
   or (select count(*) from public.pantry_items where user_id=users[1])<>stock_count then raise exception 'FAIL: stock query mutated pantry'; end if;
 begin perform public.check_my_cooking_stock(private_recipe,1,null); raise exception 'FAIL: other account private recipe exposed'; exception when no_data_found then null; end;
 perform public.start_my_cooking_session(stock_session,recipe,1);
 perform public.update_my_cooking_session(stock_session,1,'portions',null,2);
 stock_result:=public.check_my_cooking_stock(null,null,stock_session);
 if (stock_result->>'portions')::integer<>2 or (stock_result->'ingredients'->0->>'required')::numeric<>1000
   then raise exception 'FAIL: session query did not use current frozen-session portions'; end if;
 begin perform public.check_my_cooking_stock(null,1,stock_session); raise exception 'FAIL: mismatched session portions accepted'; exception when invalid_parameter_value then null; end;
 select * into ev from public.finish_my_cooking_session(sid,1,false);
 first_id:=ev.id;
 if jsonb_array_length(public.get_my_cooking_history())<>1 then raise exception 'FAIL: own event history read'; end if;
 if not public.hide_my_cooking_history_entry(first_id) then raise exception 'FAIL: first hide did not affect event'; end if;
 if public.hide_my_cooking_history_entry(first_id) then raise exception 'FAIL: repeated hide changed hidden event'; end if;
 if jsonb_array_length(public.get_my_cooking_history())<>0 then raise exception 'FAIL: hidden event still listed'; end if;
 if exists(select 1 from public.cooking_events where id=first_id) then raise exception 'FAIL: hidden event visible to direct select'; end if;
 select * into ev from public.finish_my_cooking_session(sid,999,false);
 if ev.id<>first_id then raise exception 'FAIL: hidden event replay returned a different event'; end if;
 execute 'reset role';
 if (select count(*) from public.cooking_events where session_id=sid)<>1 then raise exception 'FAIL: hidden event replay duplicated/deleted idempotency record'; end if;
 insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,portions,requested_portions,client_idempotency_key)
 values(gen_random_uuid(),users[1],null,'{"portions":1,"ingredients":[],"steps":[]}',1,1,gen_random_uuid()),
 (gen_random_uuid(),users[1],null,'{"portions":1,"ingredients":[],"steps":[]}',1,1,gen_random_uuid());
 -- Finish each as the owner; then clear and ensure the other account cannot hide or read them.
 for sid in select id from public.cooking_sessions where owner_user_id=users[1] and recipe_id is null and not exists(select 1 from public.cooking_events e where e.session_id=cooking_sessions.id) loop
   execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub',users[1]::text,true);
   perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
   perform public.finish_my_cooking_session(sid,1,false); execute 'reset role';
 end loop;
 execute 'set local role authenticated'; perform set_config('request.jwt.claim.sub',users[1]::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
 hidden_count:=public.clear_my_cooking_history();
 if hidden_count<>2 or jsonb_array_length(public.get_my_cooking_history())<>0 then raise exception 'FAIL: clear hides all and only remaining visible own events'; end if;
 execute 'reset role'; perform set_config('request.jwt.claim.sub',users[2]::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',users[2],'role','authenticated')::text,true); execute 'set local role authenticated';
 if jsonb_array_length(public.get_my_cooking_history())<>0 or public.hide_my_cooking_history_entry(first_id) then raise exception 'FAIL: cross-account history access'; end if;
 execute 'reset role'; execute 'set local role anon';
 begin perform public.get_my_cooking_history(); raise exception 'FAIL: anonymous history read accepted'; exception when insufficient_privilege then null; end;
 begin perform public.check_my_cooking_stock(recipe,1,null); raise exception 'FAIL: anonymous stock query accepted'; exception when insufficient_privilege then null; end;
 execute 'reset role'; update public.account_status set active=false where user_id=users[1];
 perform set_config('request.jwt.claim.sub',users[1]::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true); execute 'set local role authenticated';
 begin perform public.get_my_cooking_history(); raise exception 'FAIL: inactive history read accepted'; exception when insufficient_privilege then null; end;
 begin perform public.check_my_cooking_stock(recipe,1,null); raise exception 'FAIL: inactive stock query accepted'; exception when insufficient_privilege then null; end;
 execute 'reset role'; raise notice 'PASS: cooking queries history ownership, soft hide, clear, idempotent finish replay, anonymous and inactive denial';
end $queries$;
