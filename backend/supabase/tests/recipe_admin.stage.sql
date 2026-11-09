-- STAGE ONLY: recipe RPC coverage inside the rehearsal's final rollback.
do $recipe_admin$
declare
  admin_id uuid; v_owner_id uuid; cat uuid:=gen_random_uuid(); gram uuid:=gen_random_uuid(); ing uuid:=gen_random_uuid(); tag uuid:=gen_random_uuid();
  recipe_uuid uuid:=gen_random_uuid(); copy_id uuid:=gen_random_uuid(); occupied_id uuid:=gen_random_uuid(); private_id uuid:=gen_random_uuid(); ai_id uuid:=gen_random_uuid();
  payload jsonb; saved jsonb; copy_saved jsonb; audit_before bigint; collision_audit bigint; version_before bigint; session_id uuid:=gen_random_uuid(); session_row public.cooking_sessions;
begin
  select id into admin_id from auth.users where banned_until is null or banned_until<=now() order by id limit 1;
  if admin_id is null then raise exception 'FAIL: rehearsal requires an existing active Auth account'; end if;
  v_owner_id:=admin_id;
  insert into public.user_roles(user_id,role) values(admin_id,'ADMIN') on conflict(user_id) do update set role='ADMIN';
  insert into public.account_status(user_id,active) values(admin_id,true) on conflict(user_id) do update set active=true;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
  insert into public.categories(id,name,normalized_name) values(cat,'Recipe test','recipe-'||cat);
  insert into public.units(id,name,abbreviation,dimension) values(gram,'Recipe gram','r'||substr(gram::text,1,3),'mass');
  insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values(ing,'Recipe ingredient','recipe-'||ing,cat,gram);
  insert into public.dietary_tags(id,tag_key,label) values(tag,'recipe-test','Recipe test');
  insert into public.recipes(id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
    values(occupied_id,'official','Pre-existing duplicate target',5,1,'easy','draft');
  payload:=jsonb_build_object(
    'title','Complete test recipe','author','CocinAPP','description','A complete round trip','category_label','Platos principales',
    'meal_shifts',jsonb_build_array('lunch','dinner'),'total_minutes',35,'preparation_minutes',12,'cooking_minutes',23,
    'portions',4,'difficulty','intermediate','calories_per_portion',321.5,'dietary_tags',jsonb_build_array('recipe-test'),
    'featured',true,'symbol','R','color','gold','cross_contamination_note','Use a clean board',
    'image_path','recipes/test.webp','image_alt','A plated test recipe','publication_status','published','active',true,
    'ingredients',jsonb_build_array(jsonb_build_object('ingredient_id',ing,'quantity',125.5,'unit_id',gram,'note','finely chopped')),
    'steps',jsonb_build_array(
      jsonb_build_object('instruction','Prepare ingredients.','duration_minutes',5,'temperature','room temperature','tip','Use a sharp knife','warning','Take care','utensils',jsonb_build_array('knife','bowl'),'special_instructions','Keep chilled','ingredients',jsonb_build_array(jsonb_build_object('ingredient_position',1,'quantity_override',100))),
      jsonb_build_object('instruction','Cook until ready.','duration_minutes',23,'utensils',jsonb_build_array('pan'),'ingredients',jsonb_build_array())
    ));
  select count(*) into audit_before from public.admin_audit_log;
  execute 'set local role authenticated';
  saved:=public.admin_save_recipe(recipe_uuid,payload,0);
  if saved->>'id'<>recipe_uuid::text or saved->>'version'<>'1' or saved->>'title'<>'Complete test recipe'
    or saved->>'preparation_minutes'<>'12' or saved->>'cooking_minutes'<>'23' or saved->>'category_label'<>'Platos principales'
    or saved->>'total_minutes'<>'35' or (saved->>'calories_per_portion')::numeric<>321.5 or saved->>'difficulty'<>'intermediate'
    or saved->>'publication_status'<>'published' or saved->>'active'<>'true' or saved->>'featured'<>'true'
    or saved->>'symbol'<>'R' or saved->>'color'<>'gold' or saved->>'image_path'<>'recipes/test.webp'
    or saved->>'image_alt'<>'A plated test recipe' or saved->>'cross_contamination_note'<>'Use a clean board'
    or saved->'meal_shifts'<>'["dinner", "lunch"]'::jsonb or saved->'dietary_tags'<>'["recipe-test"]'::jsonb
    or saved->'ingredients'->0->>'note'<>'finely chopped' or (saved->'ingredients'->0->>'quantity')::numeric<>125.5
    or saved->'steps'->0->>'instruction'<>'Prepare ingredients.' or saved->'steps'->0->>'duration_minutes'<>'5'
    or saved->'steps'->0->>'temperature'<>'room temperature' or saved->'steps'->0->>'tip'<>'Use a sharp knife'
    or saved->'steps'->0->>'warning'<>'Take care'
    or saved->'steps'->0->'utensils'<>'["knife", "bowl"]'::jsonb
    or saved->'steps'->0->>'special_instructions'<>'Keep chilled'
    or saved->'steps'->0->'ingredients'->0->>'ingredient_position'<>'1'
    or (saved->'steps'->0->'ingredients'->0->>'quantity_override')::numeric<>100 then raise exception 'FAIL: full recipe create/export round trip'; end if;
  if public.admin_save_recipe(recipe_uuid,payload,0)<>saved then raise exception 'FAIL: create replay was not idempotent'; end if;
  execute 'reset role';
  collision_audit:=(select count(*) from public.admin_audit_log);
  execute 'set local role authenticated';
  begin
    perform public.admin_duplicate_recipe(recipe_uuid,occupied_id,0);
    raise exception 'FAIL: duplicate overwrote a pre-existing recipe target';
  exception when serialization_failure then null; end;
  execute 'reset role';
  if (select title from public.recipes where id=occupied_id)<>'Pre-existing duplicate target'
    or (select count(*) from public.admin_audit_log)<>collision_audit
    or exists(select 1 from public.admin_recipe_write_state where recipe_id=occupied_id and duplicate_source_id is not null) then
    raise exception 'FAIL: duplicate target collision changed recipe, idempotency state, or audit'; end if;
  execute 'set local role authenticated';
  begin
    perform public.admin_save_recipe(recipe_uuid,payload||jsonb_build_object('title','Changed replay'),0);
    raise exception 'FAIL: changed create replay accepted';
  exception when serialization_failure then null; end;
  -- An invalid nested reference must leave the parent, all child rows, and audit unchanged.
  version_before:=(saved->>'version')::bigint;
  begin
    perform public.admin_save_recipe(recipe_uuid,jsonb_set(payload,'{steps,0,ingredients,0,ingredient_position}','99'::jsonb),1);
    raise exception 'FAIL: invalid nested ingredient reference accepted';
  exception when invalid_parameter_value then null; end;
  execute 'reset role';
  if (select version from public.recipes where id=recipe_uuid)<>version_before
    or (select count(*) from public.recipe_ingredients ri where ri.recipe_id=recipe_uuid)<>1
    or (select count(*) from public.recipe_steps s where s.recipe_id=recipe_uuid)<>2
    or (select quantity from public.recipe_ingredients ri where ri.recipe_id=recipe_uuid and ri.position=1)<>125.5
    or (select instruction from public.recipe_steps s where s.recipe_id=recipe_uuid and s.position=1)<>'Prepare ingredients.'
    or (select count(*) from public.admin_audit_log)-audit_before<>1 then raise exception 'FAIL: failed nested save partially mutated recipe or audit'; end if;
  -- Unknown keys and invalid root references are rejected precisely.
  begin perform public.admin_save_recipe(gen_random_uuid(),payload||jsonb_build_object('unknown','x'),0); raise exception 'FAIL: unknown recipe key accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_save_recipe(gen_random_uuid(),jsonb_set(payload,'{title}','null'::jsonb),0); raise exception 'FAIL: null required field accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_save_recipe(gen_random_uuid(),jsonb_set(jsonb_set(payload,'{title}',to_jsonb('Fractional '||gen_random_uuid()::text)),'{total_minutes}','35.5'::jsonb),0); raise exception 'FAIL: fractional minutes accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_save_recipe(gen_random_uuid(),jsonb_set(jsonb_set(payload,'{title}',to_jsonb('Bad unit '||gen_random_uuid()::text)),'{ingredients,0,unit_id}',to_jsonb(gen_random_uuid()::text)),0); raise exception 'FAIL: missing ingredient unit accepted'; exception when invalid_parameter_value then null; end;
  -- Stable ids preserve foreign keys and cooking snapshots across an edit.
  execute 'set local role authenticated';
  select * into session_row from public.start_my_cooking_session(session_id,recipe_uuid,2);
  if session_row.recipe_id<>recipe_uuid or session_row.recipe_version<>1 or session_row.recipe_snapshot->>'name'<>'Complete test recipe' then raise exception 'FAIL: cooking snapshot/version fixture'; end if;
  payload:=jsonb_set(payload,'{title}','"Edited recipe"'::jsonb);
  saved:=public.admin_save_recipe(recipe_uuid,payload,1);
  if saved->>'version'<>'2' or saved->>'id'<>recipe_uuid::text or (select cs.recipe_id from public.cooking_sessions cs where cs.id=session_id)<>recipe_uuid
    or (select cs.recipe_version from public.cooking_sessions cs where cs.id=session_id)<>1
    or (select cs.recipe_snapshot->>'name' from public.cooking_sessions cs where cs.id=session_id)<>'Complete test recipe' then raise exception 'FAIL: edit changed identity/FK or cooking snapshot'; end if;
  begin perform public.admin_save_recipe(recipe_uuid,payload,1); raise exception 'FAIL: stale recipe edit accepted'; exception when serialization_failure then null; end;
  saved:=public.admin_duplicate_recipe(recipe_uuid,copy_id,0);
  if saved->>'id'<>copy_id::text or saved->>'version'<>'1' or saved->>'publication_status'<>'draft' or saved->>'featured'<>'false'
    or saved->>'title' not like 'Copia%de Edited recipe' or jsonb_array_length(saved->'ingredients')<>1 or jsonb_array_length(saved->'steps')<>2 then raise exception 'FAIL: duplicate fidelity/defaults'; end if;
  if public.admin_duplicate_recipe(recipe_uuid,copy_id,0)<>saved then raise exception 'FAIL: duplicate retry changed target'; end if;
  payload:=jsonb_set(payload,'{title}','"Source edited after duplication"'::jsonb);
  saved:=public.admin_save_recipe(recipe_uuid,payload,2);
  if saved->>'version'<>'3' then raise exception 'FAIL: source edit after duplication'; end if;
  copy_saved:=public.admin_duplicate_recipe(recipe_uuid,copy_id,0);
  if copy_saved->>'title' not like 'Copia%de Edited recipe' or copy_saved->>'version'<>'1' then raise exception 'FAIL: duplicate retry followed source edits'; end if;
  payload:=jsonb_set(payload,'{title}','"Copy edited independently"'::jsonb);
  copy_saved:=public.admin_save_recipe(copy_id,payload,1);
  if copy_saved->>'version'<>'2' then raise exception 'FAIL: target edit after duplicate'; end if;
  if public.admin_duplicate_recipe(recipe_uuid,copy_id,0)<>copy_saved then raise exception 'FAIL: duplicate retry overwrote target edits'; end if;
  begin perform public.admin_duplicate_recipe(occupied_id,copy_id,0); raise exception 'FAIL: duplicate target replayed from another source'; exception when serialization_failure then null; end;
  saved:=public.admin_set_recipe_flags(recipe_uuid,3,false,false,null,null);
  if saved->>'version'<>'4' or saved->>'active'<>'false' or saved->>'featured'<>'false' then raise exception 'FAIL: recipe flags'; end if;
  if public.admin_set_recipe_flags(recipe_uuid,4,false,false,null,null)<>saved then raise exception 'FAIL: no-op flags not stable'; end if;
  saved:=public.admin_set_recipe_flags(recipe_uuid,4,null,null,true,null);
  if saved->>'version'<>'5' or saved->>'is_deleted'<>'true' or saved->>'active'<>'false' then raise exception 'FAIL: archive'; end if;
  payload:=jsonb_set(payload,'{title}','"Archived recipe edit"'::jsonb);
  saved:=public.admin_save_recipe(recipe_uuid,payload,5);
  if saved->>'version'<>'6' or saved->>'is_deleted'<>'true' or saved->>'active'<>'false' then raise exception 'FAIL: content edit implicitly restored archived recipe'; end if;
  execute 'reset role';
  update public.recipes set title='Archived recipe edit',active=true,is_deleted=false where id=occupied_id;
  collision_audit:=(select count(*) from public.admin_audit_log);
  execute 'set local role authenticated';
  begin
    perform public.admin_set_recipe_flags(recipe_uuid,6,null,null,null,true);
    raise exception 'FAIL: restore accepted an active official title collision';
  exception when unique_violation then null; end;
  execute 'reset role';
  if (select version from public.recipes where id=recipe_uuid)<>6
    or not (select is_deleted from public.recipes where id=recipe_uuid)
    or (select active from public.recipes where id=recipe_uuid)
    or (select count(*) from public.admin_audit_log)<>collision_audit then raise exception 'FAIL: colliding restore changed recipe version/state or audit'; end if;
  delete from public.recipes where id=occupied_id;
  execute 'set local role authenticated';
  saved:=public.admin_set_recipe_flags(recipe_uuid,6,null,null,null,true);
  if saved->>'version'<>'7' or saved->>'is_deleted'<>'false' then raise exception 'FAIL: restore'; end if;
  -- Owned USER and AI recipes cannot be modified through official catalog RPCs.
  execute 'reset role';
  insert into public.recipes(id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty) values
    (private_id,v_owner_id,'user','Private recipe',1,1,'easy'),(ai_id,v_owner_id,'ai','AI recipe',1,1,'easy');
  execute 'set local role authenticated';
  begin perform public.admin_save_recipe(private_id,payload,1); raise exception 'FAIL: USER recipe modified'; exception when insufficient_privilege then null; end;
  begin perform public.admin_save_recipe(ai_id,payload,1); raise exception 'FAIL: AI recipe modified'; exception when insufficient_privilege then null; end;
  begin perform public.admin_duplicate_recipe(private_id,gen_random_uuid(),0); raise exception 'FAIL: private USER recipe duplicated'; exception when insufficient_privilege then null; end;
  begin perform public.admin_duplicate_recipe(ai_id,gen_random_uuid(),0); raise exception 'FAIL: AI recipe duplicated'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  if (select count(*) from public.admin_audit_log)-audit_before<>9
    or (select count(*) from public.admin_audit_log where action='catalog.recipe_saved' and details->>'entity_id' in (recipe_uuid::text,copy_id::text))<>5
    or (select count(*) from public.admin_audit_log where action='catalog.recipe_duplicated' and details->>'entity_id'=copy_id::text)<>1
    or (select count(*) from public.admin_audit_log where action='catalog.recipe_flags_changed' and details->>'entity_id'=recipe_uuid::text)<>3 then
    raise exception 'FAIL: effective recipe save/duplicate/flags must each write exactly one audit row'; end if;
  if has_function_privilege('anon','public.admin_save_recipe(uuid,jsonb,bigint)','EXECUTE')
    or has_function_privilege('public','public.admin_duplicate_recipe(uuid,uuid,bigint)','EXECUTE')
    or has_table_privilege('anon','public.admin_recipe_write_state','SELECT')
    or has_table_privilege('authenticated','public.admin_recipe_write_state','SELECT')
    or (select not relrowsecurity from pg_class where oid='public.admin_recipe_write_state'::regclass) then raise exception 'FAIL: recipe admin RPC/state exposed'; end if;
  update public.user_roles ur set role='USER' where ur.user_id=admin_id;
  execute 'set local role authenticated';
  begin perform public.admin_save_recipe(gen_random_uuid(),payload,0); raise exception 'FAIL: USER was authorized'; exception when insufficient_privilege then null; end;
  begin perform public.admin_duplicate_recipe(recipe_uuid,gen_random_uuid(),0); raise exception 'FAIL: USER duplicate was authorized'; exception when insufficient_privilege then null; end;
  begin perform public.admin_set_recipe_flags(recipe_uuid,7,false,null,null,null); raise exception 'FAIL: USER flags were authorized'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.user_roles ur set role='ADMIN' where ur.user_id=admin_id;
  update public.account_status s set active=false where s.user_id=admin_id;
  execute 'set local role authenticated';
  begin perform public.admin_save_recipe(gen_random_uuid(),payload,0); raise exception 'FAIL: inactive same-JWT admin was authorized'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.account_status s set active=true where s.user_id=admin_id;
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','',true);
  execute 'set local role authenticated';
  begin perform public.admin_save_recipe(gen_random_uuid(),payload,0); raise exception 'FAIL: anonymous was authorized'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  raise notice 'PASS: recipe create/update/duplicate/flags/round-trip/rollback/FK/snapshot/authorization';
end;
$recipe_admin$;
