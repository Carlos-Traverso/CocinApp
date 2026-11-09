-- STAGE ONLY: recipe discovery and trends checks inside the rehearsal rollback.
do $recipe_discovery$
declare
  v_user uuid; v_other uuid;
  v_admin uuid := gen_random_uuid(); v_cat uuid:=gen_random_uuid(); v_g uuid:=gen_random_uuid(); v_kg uuid:=gen_random_uuid();
  v_ing uuid:=gen_random_uuid(); v_badcat uuid:=gen_random_uuid(); v_bading uuid:=gen_random_uuid(); v_tag uuid:=gen_random_uuid(); v_tag2 uuid:=gen_random_uuid();
  v_ready uuid:=gen_random_uuid(); v_partial uuid:=gen_random_uuid(); v_private uuid:=gen_random_uuid();
  v_other_private uuid:=gen_random_uuid(); v_draft uuid:=gen_random_uuid(); v_inactive uuid:=gen_random_uuid();
  v_deleted uuid:=gen_random_uuid(); v_badref uuid:=gen_random_uuid(); v_hidden uuid:=gen_random_uuid();
  v_prefix text := gen_random_uuid()::text;
  v_session uuid; v_result jsonb; v_item jsonb; v_event uuid;
begin
  -- Two existing fixture accounts are independently active. Admin visibility remains owner-scoped.
  select u.id into v_user from auth.users u left join public.account_status s on s.user_id=u.id
    where coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now()) order by u.id limit 1;
  select u.id into v_other from auth.users u left join public.account_status s on s.user_id=u.id
    where u.id<>v_user and coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now()) order by u.id limit 1;
  if v_user is null or v_other is null then raise exception 'FAIL: requires two existing active Auth accounts'; end if;
  insert into public.user_roles(user_id,role) values(v_user,'USER'),(v_other,'USER') on conflict(user_id) do update set role=excluded.role;
  insert into public.account_status(user_id,active) values(v_user,true),(v_other,true) on conflict(user_id) do update set active=true;
  insert into auth.users(id) values(v_admin);
  insert into public.user_roles(user_id,role) values(v_admin,'ADMIN');
  insert into public.account_status(user_id,active) values(v_admin,true);
  insert into public.categories(id,name,normalized_name) values(v_cat,v_prefix||' Discovery category','discovery-'||v_cat);
  insert into public.units(id,name,abbreviation,dimension) values(v_g,v_prefix||' Discovery gram','dg'||substr(v_g::text,1,3),'mass');
  insert into public.units(id,name,abbreviation,dimension,base_unit_id,equivalence_multiplier)
    values(v_kg,v_prefix||' Discovery kilogram','dk'||substr(v_kg::text,1,3),'mass',v_g,1000);
  insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id)
    values(v_ing,v_prefix||' Café % especial','discovery-'||v_ing,v_cat,v_g);
  insert into public.categories(id,name,normalized_name) values(v_badcat,v_prefix||' Unavailable category','unavailable-'||v_badcat);
  insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id)
    values(v_bading,'Unavailable reference','unavailable-'||v_bading,v_badcat,v_g);
  insert into public.dietary_tags(id,tag_key,label) values(v_tag,'discover-test',v_prefix||' Discovery test');
  insert into public.dietary_tags(id,tag_key,label) values(v_tag2,'discover-second',v_prefix||' Discovery second');
  insert into public.recipes(id,owner_user_id,recipe_source,title,description,total_minutes,portions,difficulty,publication_status)
    values(v_ready,null,'official',v_prefix||' Discovery Café % especial','literal % title and NFD search',20,4,'easy','published'),
      (v_partial,null,'official',v_prefix||' Discovery Cocción parcial',v_prefix||' Tiene Café % especial',30,4,'intermediate','published'),
      (v_private,v_user,'user',v_prefix||' Discovery Mi receta privada','owner only',15,2,'easy','draft');
  insert into public.recipes(id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
    values(v_other_private,v_other,'user',v_prefix||' Discovery Privada ajena',12,2,'easy','draft'),
      (v_draft,null,'official',v_prefix||' Discovery Oficial borrador',10,2,'easy','draft'),
      (v_inactive,null,'official',v_prefix||' Discovery Oficial inactiva',10,2,'easy','published'),
      (v_deleted,null,'official',v_prefix||' Discovery Oficial eliminada',10,2,'easy','published'),
      (v_badref,null,'official',v_prefix||' Discovery Referencia rota',10,2,'easy','published');
  update public.recipes set active=false where id=v_inactive;
  update public.recipes set is_deleted=true where id=v_deleted;
  insert into public.recipe_ingredients(recipe_id,ingredient_id,quantity,unit_id,position)
    values(v_ready,v_ing,500,v_g,1),(v_partial,v_ing,1000,v_g,1),(v_badref,v_bading,200,v_g,1);
  insert into public.recipe_meal_shifts values(v_ready,'dinner'),(v_partial,'dinner');
  insert into public.recipe_dietary_tags values(v_ready,v_tag),(v_partial,v_tag);
  insert into public.recipe_dietary_tags values(v_ready,v_tag2);
  insert into public.pantry_items(user_id,name,unit,quantity,expiry,ingredient_ref,unit_ref,category,minimum)
    values(v_user,v_prefix||' Café % especial','dk'||substr(v_kg::text,1,3),0.5,current_date+1,v_ing,v_kg,'Discovery',0),
      (v_user,v_prefix||' Café % especial','dg'||substr(v_g::text,1,3),1000,current_date-1,v_ing,v_g,'Discovery',0),
      (v_other,v_prefix||' Café % especial','dg'||substr(v_g::text,1,3),10000,current_date+1,v_ing,v_g,'Discovery',0);
  -- Force invalid catalogue resolution while preserving a recipe row that search can still return.
  update public.categories set active=false where id=v_badcat;
  insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_version,recipe_snapshot,portions,client_idempotency_key,finished_at)
    values(gen_random_uuid(),v_user,v_ready,1,'{"name":"discovery","portions":4,"ingredients":[]}'::jsonb,4,gen_random_uuid(),now()) returning id into v_session;
  insert into public.cooking_events(owner_user_id,session_id,recipe_id,recipe_snapshot,portions,cooked_at)
    values(v_user,v_session,v_ready,'{"name":"ready"}',4,now()-interval '2 days') returning id into v_event;
  insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_version,recipe_snapshot,portions,client_idempotency_key,finished_at)
    values(gen_random_uuid(),v_user,v_ready,1,'{"name":"discovery","portions":4,"ingredients":[]}'::jsonb,4,gen_random_uuid(),now()) returning id into v_session;
  insert into public.cooking_events(owner_user_id,session_id,recipe_id,recipe_snapshot,portions,cooked_at,hidden_at)
    values(v_user,v_session,v_ready,'{"name":"hidden"}',4,now()-interval '1 day',now());
  insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_version,recipe_snapshot,portions,client_idempotency_key,finished_at)
    values(gen_random_uuid(),v_other,v_ready,1,'{"name":"discovery","portions":4,"ingredients":[]}'::jsonb,4,gen_random_uuid(),now()) returning id into v_session;
  insert into public.cooking_events(owner_user_id,session_id,recipe_id,recipe_snapshot,portions,cooked_at)
    values(v_other,v_session,v_ready,'{"name":"foreign"}',4,now()-interval '1 day');
  perform set_config('request.jwt.claim.sub',v_user::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v_result:=public.search_my_recipes(v_prefix,null,null,null,'{}',false,null,50,0);
  if (v_result->>'total')::int is distinct from 4 then raise exception 'FAIL: visibility must include published official plus own private only: %',v_result; end if;
  if exists(select 1 from jsonb_array_elements(v_result->'items') x where x->'recipe'->>'id' in (v_other_private::text,v_draft::text,v_inactive::text,v_deleted::text)) then raise exception 'FAIL: hidden recipe leaked'; end if;
  v_result:=public.search_my_recipes(v_prefix||' CAFÉ %',null,null,null,'{}',false,null,50,0);
  if (v_result->>'total')::int is distinct from 2 then raise exception 'FAIL: NFD accent normalization or literal percent search: %',v_result; end if;
  v_result:=public.search_my_recipes(v_prefix||' Café', 'dinner',20,'easy',array['discover-test'],false,2,50,0);
  if (v_result->>'total')::int is distinct from 1 or v_result->'items'->0->'recipe'->>'id' is distinct from v_ready::text then raise exception 'FAIL: combined exact filters or all-tag filter'; end if;
  v_item:=v_result->'items'->0;
  if (v_item->>'percentage')::int is distinct from 100 or v_item->>'label' is distinct from 'Lista para cocinar' then raise exception 'FAIL: stock conversion/expiry/foreign exclusion/portion scaling: %',v_item; end if;
  v_result:=public.search_my_recipes(null,null,null,null,array['discover-test','discover-second'],false,null,50,0);
  if (v_result->>'total')::int is distinct from 1 or v_result->'items'->0->'recipe'->>'id' is distinct from v_ready::text then raise exception 'FAIL: dietary filters must require every selected tag'; end if;
  v_result:=public.search_my_recipes(null,null,null,null,array['discover-test','missing-tag'],false,null,50,0);
  if (v_result->>'total')::int is distinct from 0 then raise exception 'FAIL: unknown dietary tag should match no recipes'; end if;
  begin perform public.search_my_recipes(null,null,null,null,array['discover-test','discover-test'],false,null,30,0); raise exception 'FAIL: duplicate dietary keys accepted'; exception when sqlstate '22023' then null; end;
  v_result:=public.search_my_recipes(v_prefix,null,null,null,'{}',true,4,1,0);
  if (v_result->>'total')::int is distinct from 1 or jsonb_array_length(v_result->'items') is distinct from 1 then raise exception 'FAIL: pantry-only filtering must precede count and pagination'; end if;
  v_result:=public.search_my_recipes(v_prefix,null,null,null,'{}',false,null,1,1);
  if (v_result->>'total')::int is distinct from 4 or jsonb_array_length(v_result->'items') is distinct from 1 or (v_result->>'offset')::int is distinct from 1 then raise exception 'FAIL: count-before-page pagination'; end if;
  v_result:=public.search_my_recipes(v_prefix,null,null,null,'{}',false,20,50,0);
  if (select count(*) from jsonb_array_elements(v_result->'items') x where x->>'percentage'='0')<1 then raise exception 'FAIL: insufficient percent must be zero'; end if;
  if exists(select 1 from jsonb_array_elements(public.search_my_recipes(v_prefix,null,null,null,'{}',true,null,50,0)->'items') x where x->'recipe'->>'id'=v_partial::text) then raise exception 'FAIL: pantry-only included empty/insufficient recipe'; end if;
  v_result:=public.search_my_recipes(v_prefix||' Discovery Referencia rota',null,null,null,'{}',false,null,50,0);
  if (v_result->>'total')::int is distinct from 1 or (v_result->'items'->0->>'percentage') is not null or (v_result->'items'->0->>'stock') is not null then raise exception 'FAIL: invalid catalogue reference should yield unavailable stock'; end if;
  begin perform public.search_my_recipes(null,'brunch',null,null,'{}',false,null,30,0); raise exception 'FAIL: invalid meal shift accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.search_my_recipes(null,null,0,null,'{}',false,null,30,0); raise exception 'FAIL: invalid max minutes accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.search_my_recipes(v_prefix,null,null,null,'{}',false,21,30,0); raise exception 'FAIL: invalid portions accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.search_my_recipes(v_prefix,null,null,null,'{}',false,null,0,0); raise exception 'FAIL: invalid limit accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.get_my_recipe_trends(0,10); raise exception 'FAIL: invalid trend bounds accepted'; exception when sqlstate '22023' then null; end;
  v_result:=public.get_my_recipe_trends(30,10);
  if (v_result->'items'->0->>'recipeId') is distinct from v_ready::text or (v_result->'items'->0->>'cookCount')::int is distinct from 1 then raise exception 'FAIL: own trends must exclude hidden and foreign events'; end if;
  v_result:=public.get_recipe_trends(30,10);
  if v_result->'items'->0->>'recipeId' is distinct from v_ready::text or (v_result->'items'->0->>'cookCount')::int is distinct from 2
    or (v_result->'items'->0->>'featured') is null or (v_result->'items'->0 ? 'owner_user_id') then raise exception 'FAIL: public trends aggregate official cooks without identities'; end if;
  if exists(select 1 from jsonb_array_elements(v_result->'items') x where x->>'recipeId' in (v_private::text,v_other_private::text,v_draft::text,v_inactive::text,v_deleted::text)) then raise exception 'FAIL: nonpublic recipe in global trends'; end if;
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  execute 'reset role';
  update public.user_roles set role='ADMIN' where user_id=v_admin;
  execute 'set local role authenticated';
  -- Synthetic ADMIN can access official recipes and own recipes only, never another private recipe.
  v_result:=public.search_my_recipes(v_prefix,null,null,null,'{}',false,null,50,0);
  if (v_result->>'total')::int is distinct from 3 or exists(select 1 from jsonb_array_elements(v_result->'items') x where x->'recipe'->>'id'=v_other_private::text) then raise exception 'FAIL: ADMIN private recipe isolation'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true); perform set_config('request.jwt.claims','{"role":"anon"}',true);
  execute 'set local role anon';
  begin perform public.search_my_recipes(); raise exception 'FAIL: anon search execute'; exception when insufficient_privilege then null; end;
  begin perform public.get_my_recipe_trends(); raise exception 'FAIL: anon trends execute'; exception when insufficient_privilege then null; end;
  begin perform public.get_recipe_trends(); raise exception 'FAIL: anonymous global trends'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.account_status set active=false where user_id=v_user;
  perform set_config('request.jwt.claim.sub',v_user::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin perform public.search_my_recipes(); raise exception 'FAIL: inactive account search'; exception when insufficient_privilege then null; end;
  begin perform public.get_recipe_trends(); raise exception 'FAIL: inactive global trends'; exception when insufficient_privilege then null; end;
  begin perform public.get_my_recipe_trends(); raise exception 'FAIL: inactive personal trends'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  insert into public.recipes(recipe_source,title,total_minutes,portions,difficulty,publication_status)
    select 'official','Overflow candidate '||g,5,1,'easy','published' from generate_series(1,501) g;
  perform set_config('request.jwt.claim.sub',v_other::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_other,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin perform public.search_my_recipes('Overflow candidate',null,null,null,'{}',true,null,50,0); raise exception 'FAIL: pantry-only accepted more than 500 candidates'; exception when sqlstate '22023' then null; end;
  execute 'reset role';
  raise notice 'PASS: recipe discovery filters, visibility, pantry stock, trends, bounds, and permissions';
end;
$recipe_discovery$;
