-- STAGE ONLY; runs in one transaction with ROLLBACK. Requires two active synthetic-domain accounts.
do $cooking_resume_read_tests$
declare
  users uuid[];
  recipe uuid := gen_random_uuid();
  other_recipe uuid := gen_random_uuid();
  legacy_recipe uuid := gen_random_uuid();
  sid_old uuid := gen_random_uuid();
  sid_new uuid := gen_random_uuid();
  sid_finished uuid := gen_random_uuid();
  sid_other uuid := gen_random_uuid();
  chosen jsonb;
  before_count integer;
begin
  select array_agg(id order by id) into users
    from (select id from auth.users where banned_until is null or banned_until <= now() order by id limit 2) a;
  if cardinality(users) < 2 then raise exception 'FAIL: two active test accounts required'; end if;
  insert into public.estado_cuenta(user_id,active) select unnest(users),true
    on conflict(user_id) do update set active=true;
  insert into public.roles_usuario(user_id,role) values(users[2],'ADMIN')
    on conflict(user_id) do update set role='ADMIN';

  insert into public.recetas(id,legacy_id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
    values
      (recipe,'resume-'||recipe,'official','Resume read test',5,2,'easy','published'),
      (other_recipe,'other-'||other_recipe,'official','Other resume test',5,2,'easy','published');
  insert into public.sesiones_cocina(id,owner_user_id,recipe_id,recipe_snapshot,portions,client_idempotency_key,started_at)
    values
      (sid_old,users[1],recipe,jsonb_build_object('id',recipe,'name','Old snapshot','steps',jsonb_build_array(jsonb_build_object('instruction','old'))),2,sid_old,'2026-10-01 10:00:00+00'),
      (sid_new,users[1],recipe,jsonb_build_object('id',recipe,'name','New snapshot','steps',jsonb_build_array(jsonb_build_object('instruction','new'))),3,sid_new,'2026-10-01 11:00:00+00'),
      (sid_finished,users[1],recipe,jsonb_build_object('id',recipe,'name','Finished snapshot','steps','[]'::jsonb),2,sid_finished,'2026-10-01 12:00:00+00'),
      (sid_other,users[2],other_recipe,jsonb_build_object('id',other_recipe,'name','Other owner','steps','[]'::jsonb),2,sid_other,'2026-10-01 13:00:00+00');
  update public.sesiones_cocina set finished_at=clock_timestamp() where id=sid_finished;
  insert into public.pasos_sesion_cocina(session_id,step_position,timer_state,remaining_ms)
    values(sid_old,1,'paused',1250),(sid_new,1,'paused',750);

  perform set_config('request.jwt.claim.sub',users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  chosen:=public.get_my_open_cooking_session(p_recipe_id=>recipe);
  if chosen->>'id'<>sid_new::text or chosen->'recipe_snapshot'->>'name'<>'New snapshot'
     or chosen->>'version' is null or chosen->'steps'->0->>'timer_state'<>'paused'
     or (chosen->'steps'->0->>'remaining_ms')::bigint<>750 then
    raise exception 'FAIL: latest open session or canonical snapshot/timer payload';
  end if;
  chosen:=public.get_my_open_cooking_session(p_legacy_recipe_id=>'resume-'||recipe);
  if chosen->>'id'<>sid_new::text then raise exception 'FAIL: explicit legacy ID lookup'; end if;
  if public.get_my_open_cooking_session(p_recipe_id=>gen_random_uuid()) is not null
     or public.get_my_open_cooking_session(p_legacy_recipe_id=>'missing-'||recipe) is not null then
    raise exception 'FAIL: missing recipe/session must return NULL';
  end if;
  begin
    perform public.get_my_open_cooking_session();
    raise exception 'FAIL: missing identifier accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.get_my_open_cooking_session(recipe,'resume-'||recipe);
    raise exception 'FAIL: ambiguous identifiers accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.get_my_open_cooking_session(p_legacy_recipe_id=>repeat('x',501));
    raise exception 'FAIL: overlong legacy identifier accepted';
  exception when invalid_parameter_value then null; end;

  execute 'reset role';
  select count(*) into before_count from public.sesiones_cocina where id in (sid_old,sid_new,sid_finished,sid_other);
  perform set_config('request.jwt.claim.sub',users[2]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[2],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if public.get_my_open_cooking_session(p_recipe_id=>recipe) is not null then
    raise exception 'FAIL: ADMIN saw another user cooking session';
  end if;
  execute 'reset role';
  if before_count<>4 or (select count(*) from public.sesiones_cocina where id in (sid_old,sid_new,sid_finished,sid_other))<>4
     or (select finished_at from public.sesiones_cocina where id=sid_old) is not null
     or (select finished_at from public.sesiones_cocina where id=sid_finished) is null then
    raise exception 'FAIL: lookup changed or closed cooking sessions';
  end if;

  update public.recetas set active=false,is_deleted=true where id=recipe;
  perform set_config('request.jwt.claim.sub',users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  chosen:=public.get_my_open_cooking_session(p_legacy_recipe_id=>'resume-'||recipe);
  if chosen->>'id'<>sid_new::text or chosen->'recipe_snapshot'->>'name'<>'New snapshot' then
    raise exception 'FAIL: archived recipe session snapshot was not resumable';
  end if;
  execute 'reset role';

  -- Anonymous callers have no execute grant; inactive accounts are denied by the account lock.
  execute 'set local role anon';
  begin
    perform public.get_my_open_cooking_session(p_recipe_id=>recipe);
    raise exception 'FAIL: anonymous cooking resume allowed';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.estado_cuenta set active=false where user_id=users[1];
  perform set_config('request.jwt.claim.sub',users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin
    perform public.get_my_open_cooking_session(p_recipe_id=>recipe);
    raise exception 'FAIL: inactive cooking resume allowed';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  raise notice 'PASS: cooking resume lookup, deterministic selection, payload, archive, namespace, and isolation checks';
end $cooking_resume_read_tests$;
