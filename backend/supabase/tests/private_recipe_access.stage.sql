-- STAGE ONLY: verify direct table reads follow the private recipe contract.
do $private_recipe_access$
declare
  reader uuid; owner_id uuid;
  private_recipe uuid := gen_random_uuid();
  ai_recipe uuid := gen_random_uuid();
  official_draft uuid := gen_random_uuid();
  private_legacy_id text := 'O''Brien-' || gen_random_uuid();
begin
  select id into reader from auth.users order by id limit 1;
  select id into owner_id from auth.users where id <> reader order by id limit 1;
  if reader is null or owner_id is null then raise exception 'FAIL: requires two fixture accounts'; end if;

  insert into public.user_roles(user_id,role) values(reader,'USER'),(owner_id,'USER')
    on conflict(user_id) do update set role=excluded.role;
  insert into public.account_status(user_id,active) values(reader,true),(owner_id,true)
    on conflict(user_id) do update set active=true;
  insert into public.recipes(id,legacy_id,owner_user_id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
    values(private_recipe,private_legacy_id,owner_id,'user','Private recipe',10,2,'easy','draft'),
      (ai_recipe,null,owner_id,'ai','Private AI recipe',10,2,'easy','draft'),
      (official_draft,null,null,'official','Official draft',10,2,'easy','draft');
  insert into public.recipe_steps(recipe_id,position,instruction)
    values(private_recipe,1,'Private step'),(ai_recipe,1,'Private AI step'),(official_draft,1,'Official step');

  perform set_config('request.jwt.claim.sub',reader::text,true);
  set local role authenticated;
  if exists(select 1 from public.recipes where id in (private_recipe,ai_recipe,official_draft))
    or exists(select 1 from public.recipe_steps where recipe_id in (private_recipe,ai_recipe,official_draft))
    or public.get_my_recipe_detail(null,private_legacy_id,true) is not null then
    raise exception 'FAIL: regular user read another account''s recipe or an official draft';
  end if;

  reset role;
  update public.user_roles set role='ADMIN' where user_id=reader;
  set local role authenticated;
  if exists(select 1 from public.recipes where id in (private_recipe,ai_recipe))
    or exists(select 1 from public.recipe_steps where recipe_id in (private_recipe,ai_recipe))
    or public.recipe_is_visible(private_recipe) or public.recipe_is_manageable(ai_recipe) then
    raise exception 'FAIL: administrator read another account''s private recipe';
  end if;
  if not exists(select 1 from public.recipes where id=official_draft)
    or not exists(select 1 from public.recipe_steps where recipe_id=official_draft) then
    raise exception 'FAIL: administrator lost access to the official draft';
  end if;

  reset role;
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  set local role authenticated;
  if (select count(*) from public.recipes where id in (private_recipe,ai_recipe)) <> 2
    or (select count(*) from public.recipe_steps where recipe_id in (private_recipe,ai_recipe)) <> 2
    or public.get_my_recipe_detail(null,private_legacy_id,true)->'recipe'->>'id' is distinct from private_recipe::text then
    raise exception 'FAIL: owner lost access to their recipes or literal legacy identifier';
  end if;
  reset role;
end;
$private_recipe_access$;
