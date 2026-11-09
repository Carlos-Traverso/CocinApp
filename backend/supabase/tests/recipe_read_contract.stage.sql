-- STAGE ONLY: secure known/detail reads, legacy identifiers and editor reads.
do $recipe_read_contract$
declare
  u uuid; other_u uuid; cat uuid:=gen_random_uuid(); unit_id uuid:=gen_random_uuid();
  ing uuid:=gen_random_uuid(); tag uuid:=gen_random_uuid(); active_recipe uuid:=gen_random_uuid();
  inactive_recipe uuid:=gen_random_uuid(); own_private uuid:=gen_random_uuid(); other_private uuid:=gen_random_uuid();
  official_draft uuid:=gen_random_uuid(); own_ai uuid:=gen_random_uuid(); other_ai uuid:=gen_random_uuid();
  uuid_legacy uuid:=gen_random_uuid(); prefix text:=gen_random_uuid()::text; result jsonb; item jsonb;
begin
  select id into u from auth.users order by id limit 1;
  select id into other_u from auth.users where id<>u order by id limit 1;
  if u is null or other_u is null then raise exception 'FAIL: requires two fixture accounts'; end if;
  insert into user_roles(user_id,role) values(u,'USER'),(other_u,'USER') on conflict(user_id) do update set role=excluded.role;
  insert into account_status(user_id,active) values(u,true),(other_u,true) on conflict(user_id) do update set active=true;
  insert into categories(id,name,normalized_name,active) values(cat,'Archived read category','read-'||cat,false);
  insert into units(id,name,abbreviation,dimension,active) values(unit_id,'Archived read unit','aru','mass',false);
  insert into ingredients(id,name,normalized_name,category_id,base_unit_id,active)
    values(ing,'Archived read ingredient','read-'||ing,cat,unit_id,false);
  insert into dietary_tags(id,tag_key,label,active) values(tag,'read-archived','Archived read tag',false);
  insert into recipes(id,legacy_id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
    values(active_recipe,'legacy-active-'||prefix,null,'official','Read active',10,2,'easy','published'),
      (inactive_recipe,uuid_legacy::text,null,'official','Read inactive',10,2,'easy','published'),
      (own_private,'own-draft-'||prefix,u,'user','Own draft',10,2,'easy','draft'),
      (own_ai,'own-ai-'||prefix,u,'ai','Own AI draft',10,2,'easy','draft'),
      (other_private,'other-private-'||prefix,other_u,'user','Other private',10,2,'easy','draft'),
      (other_ai,'other-ai-'||prefix,other_u,'ai','Other AI private',10,2,'easy','draft'),
      (official_draft,'official-draft-'||prefix,null,'official','Official draft',10,2,'easy','draft');
  update recipes set active=false,is_deleted=true where id=inactive_recipe;
  insert into recipe_ingredients(recipe_id,ingredient_id,quantity,unit_id,position)
    values(inactive_recipe,ing,3,unit_id,1);
  insert into recipe_dietary_tags(recipe_id,dietary_tag_id) values(inactive_recipe,tag);
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result:=public.list_known_recipes(500,0);
  if not (result @> jsonb_build_array(jsonb_build_object('id',inactive_recipe)))
    or not (result @> jsonb_build_array(jsonb_build_object('id',own_private)))
    or not (result @> jsonb_build_array(jsonb_build_object('id',own_ai)))
    or result @> jsonb_build_array(jsonb_build_object('id',other_private))
    or result @> jsonb_build_array(jsonb_build_object('id',other_ai))
    or result @> jsonb_build_array(jsonb_build_object('id',official_draft)) then
    raise exception 'FAIL: known list visibility/archive contract: %',result;
  end if;
  if jsonb_array_length(public.list_known_recipes(1,0))<>1 then raise exception 'FAIL: bounded known-list paging'; end if;
  item:=public.get_my_recipe_detail(active_recipe,null,false);
  if item->'recipe'->>'version' is null then raise exception 'FAIL: detail omitted recipe version'; end if;
  if public.get_my_recipe_detail(inactive_recipe,null,false) is not null then raise exception 'FAIL: inactive recipe visible without include flag'; end if;
  item:=public.get_my_recipe_detail(inactive_recipe,null,true);
  if item->'recipe'->'ingredients'->0->>'ingredient_id' is distinct from ing::text
    or item->'recipe'->'ingredients'->0->>'category' is distinct from 'Archived read category'
    or item->'recipe'->'dietary_tags'->>0 is distinct from 'read-archived' then
    raise exception 'FAIL: archived recipe refs missing from secure detail: %',item;
  end if;
  if public.get_my_recipe_detail(null,'legacy-active-'||prefix,false)->'recipe'->>'id' is distinct from active_recipe::text then raise exception 'FAIL: legacy id lookup'; end if;
  if public.get_my_recipe_detail(null,uuid_legacy::text,true)->'recipe'->>'id' is distinct from inactive_recipe::text then raise exception 'FAIL: UUID-shaped legacy id lookup'; end if;
  if public.get_my_recipe_detail(null,'other-private-'||prefix,true) is not null then raise exception 'FAIL: foreign private detail leak'; end if;
  if public.get_my_recipe_detail(null,'other-ai-'||prefix,true) is not null then raise exception 'FAIL: foreign AI recipe detail leak'; end if;
  if public.get_my_recipe_detail(null,'official-draft-'||prefix,true) is not null then raise exception 'FAIL: official draft personal read'; end if;
  begin perform public.get_my_recipe_detail(active_recipe,null,null); raise exception 'FAIL: NULL inactive flag accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.list_known_recipes(1,5001); raise exception 'FAIL: oversized known-list offset accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.admin_get_recipe(active_recipe); raise exception 'FAIL: USER can read editor API'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  update user_roles set role='ADMIN' where user_id=u;
  execute 'set local role authenticated';
  if public.get_my_recipe_detail(null,'other-private-'||prefix,true) is not null then raise exception 'FAIL: ADMIN personal RPC exposed foreign private recipe'; end if;
  if public.get_my_recipe_detail(null,'other-ai-'||prefix,true) is not null then raise exception 'FAIL: ADMIN personal RPC exposed foreign AI recipe'; end if;
  item:=public.admin_get_recipe(official_draft);
  if item->>'version' is null then raise exception 'FAIL: editor read omitted version'; end if;
  if public.admin_get_recipe(other_private) is not null then raise exception 'FAIL: editor API exposed private recipe'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  execute 'set local role anon';
  begin perform public.get_my_recipe_detail(active_recipe,null,false); raise exception 'FAIL: anon detail execute'; exception when insufficient_privilege then null; end;
  begin perform public.list_known_recipes(); raise exception 'FAIL: anon known-list execute'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update account_status set active=false where user_id=u;
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin perform public.get_my_recipe_detail(active_recipe,null,false); raise exception 'FAIL: inactive account detail'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  raise notice 'PASS: recipe detail UUID/legacy, known archived rows, private isolation, editor versions and permissions';
end;
$recipe_read_contract$;
