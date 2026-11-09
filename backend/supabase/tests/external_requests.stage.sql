-- STAGE ONLY: lifecycle RPC contract and isolation checks; all changes roll back.
do $external_requests$
declare
  a uuid; b uuid; inactive uuid:=gen_random_uuid(); admin uuid:=gen_random_uuid();
  recipe_id uuid:=gen_random_uuid(); receipt_id uuid:=gen_random_uuid(); collision_id uuid:=gen_random_uuid(); cross_kind_id uuid:=gen_random_uuid();
  retry_id uuid:=gen_random_uuid(); discard_id uuid:=gen_random_uuid(); expire_id uuid:=gen_random_uuid();
  purge_r uuid:=gen_random_uuid(); purge_c uuid:=gen_random_uuid(); keep_r uuid:=gen_random_uuid();
  v jsonb; n int; code text;
begin
  select u.id into a from auth.users u left join public.account_status s on s.user_id=u.id
   where coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now()) order by u.id limit 1;
  select u.id into b from auth.users u left join public.account_status s on s.user_id=u.id
   where u.id<>a and coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now()) order by u.id limit 1;
  if a is null or b is null then raise exception 'FAIL: requires two existing active Auth accounts'; end if;
  insert into public.user_roles(user_id,role) values(a,'USER'),(b,'USER') on conflict(user_id) do update set role=excluded.role;
  insert into public.account_status(user_id,active) values(a,true),(b,true) on conflict(user_id) do update set active=true;
  insert into auth.users(id,banned_until) values(inactive,null),(admin,null);
  insert into public.account_status(user_id,active) values(inactive,false),(admin,true);
  insert into public.user_roles(user_id,role) values(admin,'ADMIN');

  -- Explicit owner authority comes from the service call arguments, not auth.uid().
  perform set_config('request.jwt.claim.role','service_role',true);
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  execute 'set local role service_role';
  v:=public.begin_external_request(a,recipe_id,'recipe','model-v1');
  if (v->>'expires_at')::timestamptz-(v->>'created_at')::timestamptz is distinct from interval '24 hours' then raise exception 'FAIL: fixed recipe TTL'; end if;
  if (v->>'status') is distinct from 'pending' or (v->>'provider_model') is distinct from 'model-v1' then raise exception 'FAIL: recipe request begin'; end if;
  if public.begin_external_request(a,recipe_id,'recipe','model-v1') is distinct from v then raise exception 'FAIL: duplicate begin changed lifecycle metadata'; end if;
  begin perform public.begin_external_request(a,gen_random_uuid(),'receipt','model-v1'); raise exception 'FAIL: receipt accepted provider model'; exception when sqlstate '22023' then null; end;
  begin perform public.begin_external_request(a,recipe_id,'recipe','model-v2'); raise exception 'FAIL: changed model accepted'; exception when sqlstate '40001' then null; end;
  perform public.begin_external_request(a,collision_id,'recipe',null);
  begin perform public.begin_external_request(b,collision_id,'recipe',null); raise exception 'FAIL: cross-owner collision accepted'; exception when sqlstate '40001' then null; end;
  perform public.begin_external_request(a,cross_kind_id,'receipt',null);
  begin perform public.begin_external_request(a,cross_kind_id,'recipe',null); raise exception 'FAIL: cross-kind collision accepted'; exception when sqlstate '40001' then null; end;
  perform public.begin_external_request(a,receipt_id,'receipt',null);
  v:=public.finish_external_request(a,recipe_id,'recipe','completed',null);
  if (v->>'status') is distinct from 'completed' then raise exception 'FAIL: finish transition'; end if;
  if public.finish_external_request(a,recipe_id,'recipe','completed',null) is distinct from v then raise exception 'FAIL: identical finish retry changed response'; end if;
  begin perform public.finish_external_request(a,recipe_id,'recipe','failed','internal_error'); raise exception 'FAIL: terminal result changed'; exception when sqlstate '40001' then null; end;
  begin perform public.finish_external_request(a,receipt_id,'receipt','failed','provider_secret'); raise exception 'FAIL: unapproved error code accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.finish_external_request(a,receipt_id,'receipt','failed',null); raise exception 'FAIL: failed request omitted safe code'; exception when sqlstate '22023' then null; end;
  begin perform public.finish_external_request(a,receipt_id,'receipt','completed','internal_error'); raise exception 'FAIL: completed request accepted error code'; exception when sqlstate '22023' then null; end;
  perform public.finish_external_request(a,receipt_id,'receipt','completed',null);
  v:=public.finish_external_request(a,cross_kind_id,'receipt','failed','provider_timeout');
  if public.finish_external_request(a,cross_kind_id,'receipt','failed','provider_timeout') is distinct from v then raise exception 'FAIL: failed replay'; end if;
  perform public.begin_external_request(a,retry_id,'recipe',null);
  perform public.begin_external_request(a,discard_id,'receipt',null);
  perform public.begin_external_request(a,expire_id,'recipe',null);
  perform public.begin_external_request(a,purge_r,'recipe',null);
  perform public.begin_external_request(a,purge_c,'receipt',null);
  perform public.begin_external_request(a,keep_r,'recipe',null);
  begin perform public.purge_expired_external_requests(0); raise exception 'FAIL: invalid purge limit'; exception when sqlstate '22023' then null; end;
  begin perform public.purge_expired_external_requests(1001); raise exception 'FAIL: oversized purge limit'; exception when sqlstate '22023' then null; end;
  begin perform public.get_my_external_request('recipe',recipe_id); raise exception 'FAIL: service role got owner read'; exception when insufficient_privilege then null; end;
  execute 'reset role';

  -- Authenticated callers may read only their own row, even with ADMIN and inactive state.
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v:=public.get_my_external_request('recipe',recipe_id);
  if (v->>'status') is distinct from 'completed' or (v->>'provider_model') is distinct from 'model-v1' then raise exception 'FAIL: owner read'; end if;
  begin perform public.get_my_external_request('recipe',receipt_id); raise exception 'FAIL: wrong kind read'; exception when sqlstate 'P0002' then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',admin::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin perform public.get_my_external_request('recipe',recipe_id); raise exception 'FAIL: ADMIN read another owner'; exception when sqlstate 'P0002' then null; end;
  execute 'reset role';
  update public.account_status set active=false where user_id=a;
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin perform public.get_my_external_request('recipe',recipe_id); raise exception 'FAIL: inactive owner read'; exception when sqlstate '42501' then null; end;
  execute 'reset role';
  update public.account_status set active=true where user_id=a;

  -- Direct table writes remain unavailable to authenticated and service callers.
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin insert into public.recipe_generation_requests(id,owner_user_id,status,expires_at) values(gen_random_uuid(),a,'pending',now()+interval '1 day'); raise exception 'FAIL: authenticated direct DML'; exception when insufficient_privilege then null; end;
  begin perform public.begin_external_request(a,gen_random_uuid(),'recipe',null); raise exception 'FAIL: authenticated service function'; exception when insufficient_privilege then null; end;
  begin perform public.discard_my_receipt_request(gen_random_uuid()); raise exception 'FAIL: unknown receipt accepted'; exception when sqlstate 'P0002' then null; end;
  v:=public.discard_my_receipt_request(receipt_id);
  if (v->>'status') is distinct from 'discarded' or public.discard_my_receipt_request(receipt_id) is distinct from v then raise exception 'FAIL: completed preview discard/replay'; end if;
  v:=public.discard_my_receipt_request(discard_id);
  if (v->>'status') is distinct from 'discarded' then raise exception 'FAIL: receipt discard'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.role','service_role',true);
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  execute 'set local role service_role';
  begin insert into public.recipe_generation_requests(id,owner_user_id,status,expires_at) values(gen_random_uuid(),a,'pending',now()+interval '1 day'); raise exception 'FAIL: service direct DML'; exception when insufficient_privilege then null; end;
  begin perform public.finish_external_request(a,discard_id,'receipt','completed',null); raise exception 'FAIL: discarded request finished'; exception when sqlstate '40001' then null; end;
  execute 'reset role';

  -- Test fixture timestamps are changed only by the privileged rehearsal owner.
  update public.recipe_generation_requests set expires_at=now()-interval '1 minute' where id in(expire_id,purge_r,keep_r);
  update public.receipt_recognition_requests set expires_at=now()-interval '1 minute' where id=purge_c;
  update public.recipe_generation_requests set expires_at=now()-interval '1 minute' where id=retry_id;
  update public.recipe_generation_requests set status='completed' where id=retry_id;
  update public.recipe_generation_requests set expires_at=now()+interval '1 day' where id=keep_r;
  perform set_config('request.jwt.claim.role','service_role',true);
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  execute 'set local role service_role';
  v:=public.begin_external_request(a,purge_r,'recipe',null);
  if (v->>'status') is distinct from 'expired' then raise exception 'FAIL: begin lazy expiry'; end if;
  v:=public.finish_external_request(a,expire_id,'recipe','completed',null);
  if (v->>'status') is distinct from 'expired' then raise exception 'FAIL: expired pending was not finalized expired'; end if;
  if public.finish_external_request(a,expire_id,'recipe','completed',null) is distinct from v then raise exception 'FAIL: expired finish replay'; end if;
  v:=public.begin_external_request(a,expire_id,'recipe',null);
  if (v->>'status') is distinct from 'expired' then raise exception 'FAIL: expired ID restarted'; end if;
  v:=public.finish_external_request(a,retry_id,'recipe','completed',null);
  if (v->>'status') is distinct from 'completed' then raise exception 'FAIL: terminal retry rejected after TTL'; end if;
  begin perform public.begin_external_request(inactive,gen_random_uuid(),'recipe',null); raise exception 'FAIL: inactive owner service call'; exception when sqlstate '42501' then null; end;
  v:=public.purge_expired_external_requests(1);
  if (v->>'recipe_deleted')::int>1 or (v->>'receipt_deleted')::int>1 then raise exception 'FAIL: purge exceeded per-table bound'; end if;
  if public.purge_expired_external_requests(100)->>'recipe_deleted' is null then raise exception 'FAIL: purge response'; end if;
  execute 'reset role';
  if exists(select 1 from public.recipe_generation_requests where id in(expire_id,purge_r,retry_id)) or exists(select 1 from public.receipt_recognition_requests where id=purge_c) then raise exception 'FAIL: expiry purge retained expired metadata'; end if;
  if not exists(select 1 from public.recipe_generation_requests where id=keep_r) then raise exception 'FAIL: future row purged'; end if;
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  execute 'set local role anon';
  begin perform public.get_my_external_request('recipe',recipe_id); raise exception 'FAIL: anonymous owner read'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  raise notice 'PASS: external request lifecycle, safe metadata, TTL, retries, discard, cleanup, and authorization';
end
$external_requests$;
