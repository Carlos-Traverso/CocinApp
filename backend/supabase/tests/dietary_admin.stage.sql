-- STAGE ONLY: dietary administration RPC coverage in rollback-only rehearsal.
do $dietary_admin$
declare
  v_admin_id uuid; v_user_id uuid;
  v_cat_id uuid:=gen_random_uuid(); v_unit_id uuid:=gen_random_uuid(); v_ingredient_id uuid:=gen_random_uuid();
  v_tag_id uuid:=gen_random_uuid(); v_tag2_id uuid:=gen_random_uuid(); v_recipe_id uuid:=gen_random_uuid();
  v_tag_payload jsonb; saved jsonb; links jsonb; v_initial_audit bigint; v_before_audit bigint; v_before_version bigint;
begin
  select u.id into v_admin_id from auth.users u left join public.account_status s on s.user_id=u.id
    where coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now()) order by u.id limit 1;
  select u.id into v_user_id from auth.users u left join public.account_status s on s.user_id=u.id
    where u.id<>v_admin_id and coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now()) order by u.id limit 1;
  if v_admin_id is null or v_user_id is null then raise exception 'FAIL: rehearsal requires two existing active Auth accounts'; end if;
  insert into public.user_roles(user_id,role) values(v_admin_id,'ADMIN'),(v_user_id,'USER') on conflict(user_id) do update set role=excluded.role;
  insert into public.account_status(user_id,active) values(v_admin_id,true),(v_user_id,true) on conflict(user_id) do update set active=true;
  insert into public.categories(id,name,normalized_name) values(v_cat_id,'Dietary RPC test','dietary-'||v_cat_id);
  insert into public.units(id,name,abbreviation,dimension) values(v_unit_id,'Dietary gram','d'||substr(v_unit_id::text,1,3),'mass');
  insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values(v_ingredient_id,'Dietary RPC ingredient','dietary-'||v_ingredient_id,v_cat_id,v_unit_id);
  insert into public.profiles(user_id,display_name) values(v_user_id,'Dietary user fixture');
  insert into public.recipes(id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
    values(v_recipe_id,'official','Dietary tag reference fixture',5,1,'easy','draft');

  perform set_config('request.jwt.claim.sub',v_admin_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_admin_id,'role','authenticated')::text,true);
  select count(*) into v_initial_audit from public.admin_audit_log;
  v_tag_payload:=jsonb_build_object('id',v_tag_id,'tag_key','dietary-'||substr(v_tag_id::text,1,12),'label','RPC test tag','description','Test description','active',true);
  execute 'set local role authenticated';
  saved:=public.admin_put_dietary_tag(v_tag_payload,0);
  if saved->>'id'<>v_tag_id::text or saved->>'version'<>'1' or saved->>'label'<>'RPC test tag' then raise exception 'FAIL: dietary tag create'; end if;
  if public.admin_put_dietary_tag(v_tag_payload,0)<>saved then raise exception 'FAIL: stable dietary tag create replay'; end if;
  if public.admin_put_dietary_tag(v_tag_payload,1)<>saved then raise exception 'FAIL: dietary tag no-op changed'; end if;
  execute 'reset role';
  insert into public.user_dietary_preferences(user_id,dietary_tag_id) values(v_user_id,v_tag_id);
  insert into public.recipe_dietary_tags(recipe_id,dietary_tag_id) values(v_recipe_id,v_tag_id);
  execute 'set local role authenticated';
  begin perform public.admin_put_dietary_tag(v_tag_payload||jsonb_build_object('label','stale'),0); raise exception 'FAIL: changed create replay accepted'; exception when serialization_failure then null; end;
  begin perform public.admin_put_dietary_tag(v_tag_payload||jsonb_build_object('other','x'),0); raise exception 'FAIL: unknown tag field accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_put_dietary_tag(v_tag_payload||jsonb_build_object('description',null),0); raise exception 'FAIL: null tag description accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_put_dietary_tag(v_tag_payload||jsonb_build_object('label','  '),0); raise exception 'FAIL: blank tag label accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_put_dietary_tag(v_tag_payload||jsonb_build_object('tag_key','Bad Key'),0); raise exception 'FAIL: malformed tag key accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_put_dietary_tag(v_tag_payload||jsonb_build_object('description',repeat('x',2001)),0); raise exception 'FAIL: oversized tag description accepted'; exception when invalid_parameter_value then null; end;
  v_tag_payload:=v_tag_payload||jsonb_build_object('label','RPC test tag edited');
  saved:=public.admin_put_dietary_tag(v_tag_payload,1);
  if saved->>'version'<>'2' then raise exception 'FAIL: dietary tag edit version'; end if;
  begin perform public.admin_put_dietary_tag(v_tag_payload||jsonb_build_object('tag_key','other-key'),2); raise exception 'FAIL: dietary stable key changed'; exception when invalid_parameter_value then null; end;
  saved:=public.admin_put_dietary_tag(v_tag_payload||jsonb_build_object('active',false),2);
  if saved->>'version'<>'3' or saved->>'active'<>'false' then raise exception 'FAIL: dietary tag deactivation'; end if;
  execute 'reset role';
  if (select count(*) from public.user_dietary_preferences where user_id=v_user_id and dietary_tag_id=v_tag_id)<>1
    or (select count(*) from public.recipe_dietary_tags where dietary_tag_id=v_tag_id)<>1 then raise exception 'FAIL: tag deactivation altered preferences or recipe tags'; end if;
  execute 'set local role authenticated';
  saved:=public.admin_put_dietary_tag(v_tag_payload||jsonb_build_object('active',true),3);
  if saved->>'version'<>'4' or saved->>'active'<>'true' then raise exception 'FAIL: dietary tag reactivation'; end if;
  execute 'reset role';
  if (select count(*) from public.user_dietary_preferences where user_id=v_user_id and dietary_tag_id=v_tag_id)<>1
    or (select count(*) from public.recipe_dietary_tags where dietary_tag_id=v_tag_id)<>1 then raise exception 'FAIL: tag lifecycle altered preferences or recipe tags'; end if;
  insert into public.dietary_tags(id,tag_key,label,description) values(v_tag2_id,'dietary-'||substr(v_tag2_id::text,1,12),'Second test tag','');
  links:=jsonb_build_array(
    jsonb_build_object('tag_key',v_tag_payload->>'tag_key','compatibility','contains','note','Round trip note'),
    jsonb_build_object('tag_key','dietary-'||substr(v_tag2_id::text,1,12),'compatibility','unknown','note',''));
  execute 'set local role authenticated';
  saved:=public.admin_save_ingredient_dietary_tags(v_ingredient_id,links,1);
  if saved->>'version'<>'2' or jsonb_array_length(saved->'tags')<>2
     or not exists(select 1 from jsonb_array_elements(saved->'tags') x where x->>'tag_key'=v_tag_payload->>'tag_key' and x->>'note'='Round trip note') then raise exception 'FAIL: ingredient dietary link roundtrip'; end if;
  if public.admin_save_ingredient_dietary_tags(v_ingredient_id,links,2)<>saved then raise exception 'FAIL: link no-op changed'; end if;
  links:=jsonb_build_array(jsonb_build_object('tag_key',v_tag_payload->>'tag_key','compatibility','suitable','note','Updated note'));
  saved:=public.admin_save_ingredient_dietary_tags(v_ingredient_id,links,2);
  if saved->>'version'<>'3' or jsonb_array_length(saved->'tags')<>1 or saved->'tags'->0->>'compatibility'<>'suitable' then raise exception 'FAIL: full replacement semantics'; end if;
  begin perform public.admin_save_ingredient_dietary_tags(v_ingredient_id,links||links,3); raise exception 'FAIL: duplicate links accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_save_ingredient_dietary_tags(v_ingredient_id,jsonb_build_array(jsonb_build_object('tag_key','missing-tag','compatibility','unknown','note','')),3); raise exception 'FAIL: unknown tag accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_save_ingredient_dietary_tags(v_ingredient_id,jsonb_build_array(jsonb_build_object('tag_key',v_tag_payload->>'tag_key','compatibility','infer-from-name','note','')),3); raise exception 'FAIL: invalid compatibility accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_save_ingredient_dietary_tags(v_ingredient_id,jsonb_build_array(jsonb_build_object('tag_key',v_tag_payload->>'tag_key','compatibility','unknown','note',repeat('x',1001))),3); raise exception 'FAIL: oversized note accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_save_ingredient_dietary_tags(v_ingredient_id,'{}'::jsonb,3); raise exception 'FAIL: non-array links accepted'; exception when invalid_parameter_value then null; end;
  -- Each invalid operation must roll back all child writes and leave parent version/audit unchanged.
  execute 'reset role';
  v_before_version:=(select version from public.ingredients where id=v_ingredient_id);
  v_before_audit:=(select count(*) from public.admin_audit_log);
  execute 'set local role authenticated';
  begin perform public.admin_save_ingredient_dietary_tags(v_ingredient_id,jsonb_build_array(
    jsonb_build_object('tag_key',v_tag_payload->>'tag_key','compatibility','unknown','note',''),
    jsonb_build_object('tag_key','not-present','compatibility','unknown','note','')),v_before_version);
    raise exception 'FAIL: invalid second link accepted'; exception when invalid_parameter_value then null; end;
  execute 'reset role';
  if (select version from public.ingredients where id=v_ingredient_id)<>v_before_version
    or (select count(*) from public.ingredient_dietary_tags where ingredient_id=v_ingredient_id)<>1
    or (select count(*) from public.admin_audit_log)<>v_before_audit then raise exception 'FAIL: invalid replacement partially mutated links/version/audit'; end if;
  execute 'set local role authenticated';
  saved:=public.admin_save_ingredient_dietary_tags(v_ingredient_id,'[]'::jsonb,v_before_version);
  if saved->>'version'<>(v_before_version+1)::text or jsonb_array_length(saved->'tags')<>0 then raise exception 'FAIL: empty replacement did not remove links'; end if;
  -- Restore a link, archive ingredient, permit exact retention and removal only.
  saved:=public.admin_save_ingredient_dietary_tags(v_ingredient_id,jsonb_build_array(jsonb_build_object('tag_key',v_tag_payload->>'tag_key','compatibility','contains','note','Keep')),v_before_version+1);
  execute 'reset role';
  perform public.admin_put_ingredient(jsonb_build_object('id',v_ingredient_id,'name','Dietary RPC ingredient','category_id',v_cat_id,'base_unit_id',v_unit_id,'active',false,'is_deleted',true),5);
  execute 'set local role authenticated';
  saved:=public.admin_save_ingredient_dietary_tags(v_ingredient_id,jsonb_build_array(jsonb_build_object('tag_key',v_tag_payload->>'tag_key','compatibility','contains','note','Keep')),6);
  if saved->>'version'<>'6' then raise exception 'FAIL: exact inactive link retention should be no-op'; end if;
  begin perform public.admin_save_ingredient_dietary_tags(v_ingredient_id,jsonb_build_array(jsonb_build_object('tag_key',v_tag_payload->>'tag_key','compatibility','suitable','note','Changed')),6); raise exception 'FAIL: inactive ingredient link modification accepted'; exception when invalid_parameter_value then null; end;
  saved:=public.admin_save_ingredient_dietary_tags(v_ingredient_id,'[]'::jsonb,6);
  if saved->>'version'<>'7' then raise exception 'FAIL: inactive ingredient link removal'; end if;
  execute 'reset role';
  saved:=public.admin_put_ingredient(jsonb_build_object('id',v_ingredient_id,'name','Dietary RPC ingredient','category_id',v_cat_id,'base_unit_id',v_unit_id,'active',true,'is_deleted',false),7);
  if saved->>'version'<>'8' then raise exception 'FAIL: ingredient core version did not advance across link edits'; end if;
  execute 'set local role authenticated';
  begin perform public.admin_save_ingredient_dietary_tags(v_ingredient_id,'[]'::jsonb,2); raise exception 'FAIL: stale parent version accepted'; exception when serialization_failure then null; end;
  execute 'reset role';
  if (select count(*) from public.admin_audit_log where actor_user_id=v_admin_id and action='catalog.dietary_tag_saved'
      and details ?& array['entity_id','version'] and (details-'entity_id'-'version')='{}'::jsonb)<>4
     or (select count(*) from public.admin_audit_log where actor_user_id=v_admin_id and action='catalog.ingredient_dietary_tags_saved'
      and details ?& array['entity_id','version'] and (details-'entity_id'-'version')='{}'::jsonb)<>5
     or (select count(*) from public.admin_audit_log)-v_initial_audit<>11 then raise exception 'FAIL: expected exactly one correctly scoped audit event per effective dietary mutation'; end if;
  if has_function_privilege('anon','public.admin_put_dietary_tag(jsonb,bigint)','EXECUTE')
     or has_function_privilege('anon','public.admin_save_ingredient_dietary_tags(uuid,jsonb,bigint)','EXECUTE') then raise exception 'FAIL: dietary RPC public/anon execute'; end if;
  if (select count(*) from public.admin_audit_log)-v_before_audit<2 then raise exception 'FAIL: effective dietary mutations were not audited'; end if;
  -- USER, same-JWT demotion, inactive admin, and anonymous caller are rejected.
  perform set_config('request.jwt.claim.sub',v_user_id::text,true);
  execute 'set local role authenticated';
  begin perform public.admin_put_dietary_tag(v_tag_payload,4); raise exception 'FAIL: USER was authorized'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',v_admin_id::text,true);
  update public.user_roles set role='USER' where user_roles.user_id=v_admin_id;
  execute 'set local role authenticated';
  begin perform public.admin_put_dietary_tag(v_tag_payload,4); raise exception 'FAIL: same-JWT demoted admin authorized'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.user_roles set role='ADMIN' where user_roles.user_id=v_admin_id;
  update public.account_status set active=false where account_status.user_id=v_admin_id;
  execute 'set local role authenticated';
  begin perform public.admin_put_dietary_tag(v_tag_payload,4); raise exception 'FAIL: inactive admin authorized'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.account_status set active=true where account_status.user_id=v_admin_id;
  perform set_config('request.jwt.claim.sub','',true);
  execute 'set local role anon';
  begin perform public.admin_put_dietary_tag(v_tag_payload,4); raise exception 'FAIL: anonymous caller authorized'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  raise notice 'PASS: dietary tag and ingredient-link versioning/replacement/audit/authorization';
end;
$dietary_admin$;
