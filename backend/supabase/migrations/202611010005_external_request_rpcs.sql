begin;

create index recipe_generation_requests_expiry_idx on public.recipe_generation_requests(expires_at,id);
create index receipt_recognition_requests_expiry_idx on public.receipt_recognition_requests(expires_at,id);

-- External request rows retain only lifecycle metadata. Payloads, prompts, images,
-- provider responses, and OCR text belong outside this table.
create or replace function public._lock_external_request_owner(p_owner uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La operación no es válida.' using errcode='25000';
  end if;
  if p_owner is null then raise exception 'La cuenta no está activa.' using errcode='42501'; end if;
  -- Match the account writer order: global role/status coordination, actor lock,
  -- then Auth and account status rows. Do not use auth.uid() for service actors.
  perform pg_catalog.pg_advisory_xact_lock_shared(74539, 1);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.personal:' || p_owner::text, 0));
  perform 1 from auth.users where id=p_owner for share;
  if not found then raise exception 'La cuenta no está activa.' using errcode='42501'; end if;
  perform 1 from public.account_status where user_id=p_owner for share;
  if not exists (
    select 1 from auth.users u left join public.account_status s on s.user_id=u.id
    where u.id=p_owner and coalesce(s.active,true)
      and (u.banned_until is null or u.banned_until<=pg_catalog.clock_timestamp())
  ) then raise exception 'La cuenta no está activa.' using errcode='42501'; end if;
end;
$$;
revoke all on function public._lock_external_request_owner(uuid) from public, anon, authenticated, service_role;

create or replace function public.begin_external_request(
  p_owner uuid, p_request uuid, p_kind text, p_provider_model text default null
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_found boolean; v_owner uuid; v_status text; v_model text; v_error text; v_created timestamptz; v_expires timestamptz; v_now timestamptz;
begin
  if p_kind is null or p_kind not in ('recipe','receipt') or p_request is null
    or (p_kind='receipt' and p_provider_model is not null)
    or (p_provider_model is not null and (length(p_provider_model)>120 or p_provider_model !~ '^[A-Za-z0-9][A-Za-z0-9._:/+-]{0,119}$')) then
    raise exception 'La solicitud no es válida.' using errcode='22023';
  end if;
  perform public._lock_external_request_owner(p_owner);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.external-request:' || p_request::text, 0));
  v_now:=pg_catalog.clock_timestamp();
  if (p_kind='recipe' and exists(select 1 from public.receipt_recognition_requests where id=p_request))
    or (p_kind='receipt' and exists(select 1 from public.recipe_generation_requests where id=p_request)) then
    raise exception 'La solicitud cambió; iniciá otra solicitud.' using errcode='40001';
  end if;
  if p_kind='recipe' then
    insert into public.recipe_generation_requests(id,owner_user_id,status,provider_model,created_at,expires_at)
      values(p_request,p_owner,'pending',p_provider_model,v_now,v_now+interval '24 hours')
      on conflict(id) do nothing;
    select true,r.owner_user_id,r.status,r.provider_model,r.safe_error_code,r.created_at,r.expires_at
      into v_found,v_owner,v_status,v_model,v_error,v_created,v_expires from public.recipe_generation_requests r where r.id=p_request for update;
  else
    insert into public.receipt_recognition_requests(id,owner_user_id,status,created_at,expires_at)
      values(p_request,p_owner,'pending',v_now,v_now+interval '1 hour')
      on conflict(id) do nothing;
    select true,r.owner_user_id,r.status,null::text,r.safe_error_code,r.created_at,r.expires_at
      into v_found,v_owner,v_status,v_model,v_error,v_created,v_expires from public.receipt_recognition_requests r where r.id=p_request for update;
  end if;
  if not coalesce(v_found,false) or v_owner<>p_owner then raise exception 'La solicitud cambió; iniciá otra solicitud.' using errcode='40001'; end if;
  if v_model is distinct from (case when p_kind='recipe' then p_provider_model else null end) then
    raise exception 'La solicitud cambió; iniciá otra solicitud.' using errcode='40001';
  end if;
  if v_status='pending' and v_expires<=pg_catalog.clock_timestamp() then
    if p_kind='recipe' then update public.recipe_generation_requests set status='expired',safe_error_code=null where id=p_request;
    else update public.receipt_recognition_requests set status='expired',safe_error_code=null where id=p_request; end if;
    v_status:='expired'; v_error:=null;
  end if;
  return pg_catalog.jsonb_build_object('id',p_request,'kind',p_kind,'status',v_status,'provider_model',v_model,'safe_error_code',v_error,'created_at',v_created,'expires_at',v_expires);
end;
$$;

create or replace function public.finish_external_request(
  p_owner uuid, p_request uuid, p_kind text, p_status text, p_safe_error_code text default null
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_owner uuid; v_status text; v_error text; v_expires timestamptz;
begin
  if p_kind is null or p_kind not in ('recipe','receipt') or p_request is null or p_status is null or p_status not in ('completed','failed')
    or (p_safe_error_code is not null and p_safe_error_code not in ('provider_unavailable','provider_timeout','provider_rejected','invalid_provider_response','rate_limited','internal_error'))
    or (p_status='completed' and p_safe_error_code is not null)
    or (p_status='failed' and p_safe_error_code is null) then
    raise exception 'La solicitud no es válida.' using errcode='22023';
  end if;
  perform public._lock_external_request_owner(p_owner);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.external-request:' || p_request::text, 0));
  if (p_kind='recipe' and exists(select 1 from public.receipt_recognition_requests where id=p_request))
    or (p_kind='receipt' and exists(select 1 from public.recipe_generation_requests where id=p_request)) then
    raise exception 'La solicitud no existe.' using errcode='P0002';
  end if;
  if p_kind='recipe' then
    select r.owner_user_id,r.status,r.safe_error_code,r.expires_at into v_owner,v_status,v_error,v_expires from public.recipe_generation_requests r where r.id=p_request for update;
  else
    select r.owner_user_id,r.status,r.safe_error_code,r.expires_at into v_owner,v_status,v_error,v_expires from public.receipt_recognition_requests r where r.id=p_request for update;
  end if;
  if not found or v_owner<>p_owner then raise exception 'La solicitud no existe.' using errcode='P0002'; end if;
  if v_status='expired' then
    return pg_catalog.jsonb_build_object('id',p_request,'kind',p_kind,'status','expired','safe_error_code',null);
  end if;
  if v_expires<=pg_catalog.clock_timestamp() and v_status='pending' then
    if p_kind='recipe' then update public.recipe_generation_requests set status='expired',safe_error_code=null where id=p_request and status='pending';
    else update public.receipt_recognition_requests set status='expired',safe_error_code=null where id=p_request and status='pending'; end if;
    return pg_catalog.jsonb_build_object('id',p_request,'kind',p_kind,'status','expired','safe_error_code',null);
  end if;
  if v_status in ('completed','failed') and v_status=p_status and v_error is not distinct from p_safe_error_code then
    return pg_catalog.jsonb_build_object('id',p_request,'kind',p_kind,'status',v_status,'safe_error_code',v_error);
  end if;
  if v_status<>'pending' then raise exception 'La solicitud ya tiene un resultado distinto.' using errcode='40001'; end if;
  if p_kind='recipe' then update public.recipe_generation_requests set status=p_status,safe_error_code=p_safe_error_code where id=p_request;
  else update public.receipt_recognition_requests set status=p_status,safe_error_code=p_safe_error_code where id=p_request; end if;
  return pg_catalog.jsonb_build_object('id',p_request,'kind',p_kind,'status',p_status,'safe_error_code',p_safe_error_code);
end;
$$;

create or replace function public.get_my_external_request(p_kind text,p_request uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_owner uuid; v_status text; v_model text; v_error text; v_created timestamptz; v_expires timestamptz; actor uuid;
begin
  actor:=auth.uid();
  if actor is null or p_kind is null or p_kind not in ('recipe','receipt') or p_request is null then raise exception 'Se requiere una solicitud válida.' using errcode='42501'; end if;
  perform public._lock_external_request_owner(actor);
  if p_kind='recipe' then
    select r.owner_user_id,r.status,r.provider_model,r.safe_error_code,r.created_at,r.expires_at into v_owner,v_status,v_model,v_error,v_created,v_expires from public.recipe_generation_requests r where r.id=p_request for update;
  else
    select r.owner_user_id,r.status,null::text,r.safe_error_code,r.created_at,r.expires_at into v_owner,v_status,v_model,v_error,v_created,v_expires from public.receipt_recognition_requests r where r.id=p_request for update;
  end if;
  if not found or v_owner<>actor then raise exception 'La solicitud no existe.' using errcode='P0002'; end if;
  if v_expires<=pg_catalog.clock_timestamp() and v_status='pending' then
    if p_kind='recipe' then update public.recipe_generation_requests set status='expired' where id=p_request;
    else update public.receipt_recognition_requests set status='expired' where id=p_request; end if;
    v_status:='expired'; v_error:=null;
  end if;
  return pg_catalog.jsonb_build_object('id',p_request,'kind',p_kind,'status',v_status,'provider_model',v_model,'safe_error_code',v_error,'created_at',v_created,'expires_at',v_expires);
end;
$$;

create or replace function public.discard_my_receipt_request(p_request uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; v_owner uuid; v_status text; v_expires timestamptz;
begin
  actor:=auth.uid();
  if actor is null or p_request is null then raise exception 'Se requiere una solicitud válida.' using errcode='42501'; end if;
  perform public._lock_external_request_owner(actor);
  select r.owner_user_id,r.status,r.expires_at into v_owner,v_status,v_expires from public.receipt_recognition_requests r where r.id=p_request for update;
  if not found or v_owner<>actor then raise exception 'La solicitud no existe.' using errcode='P0002'; end if;
  if v_expires<=pg_catalog.clock_timestamp() and v_status='pending' then
    update public.receipt_recognition_requests set status='expired' where id=p_request; v_status:='expired';
  elsif v_status in ('pending','completed') then
    update public.receipt_recognition_requests set status='discarded',safe_error_code=null where id=p_request; v_status:='discarded';
  end if;
  return pg_catalog.jsonb_build_object('id',p_request,'kind','receipt','status',v_status,'expires_at',v_expires);
end;
$$;

create or replace function public.purge_expired_external_requests(p_limit integer default 100)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare recipe_count integer; receipt_count integer; cutoff timestamptz := pg_catalog.clock_timestamp();
begin
  if p_limit is null or p_limit not between 1 and 1000 then raise exception 'El límite no es válido.' using errcode='22023'; end if;
  with doomed as (
    select id from public.recipe_generation_requests where expires_at<=cutoff order by expires_at,id limit p_limit for update skip locked
  ) delete from public.recipe_generation_requests r using doomed d where r.id=d.id;
  get diagnostics recipe_count = row_count;
  with doomed as (
    select id from public.receipt_recognition_requests where expires_at<=cutoff order by expires_at,id limit p_limit for update skip locked
  ) delete from public.receipt_recognition_requests r using doomed d where r.id=d.id;
  get diagnostics receipt_count = row_count;
  return pg_catalog.jsonb_build_object('recipe_deleted',recipe_count,'receipt_deleted',receipt_count);
end;
$$;

revoke all on function public.begin_external_request(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.finish_external_request(uuid,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.purge_expired_external_requests(integer) from public,anon,authenticated;
grant execute on function public.begin_external_request(uuid,uuid,text,text) to service_role;
grant execute on function public.finish_external_request(uuid,uuid,text,text,text) to service_role;
grant execute on function public.purge_expired_external_requests(integer) to service_role;
revoke all on function public.get_my_external_request(text,uuid) from public,anon,service_role;
revoke all on function public.discard_my_receipt_request(uuid) from public,anon,service_role;
grant execute on function public.get_my_external_request(text,uuid) to authenticated;
grant execute on function public.discard_my_receipt_request(uuid) to authenticated;

revoke insert,update,delete on public.recipe_generation_requests,public.receipt_recognition_requests from public,anon,authenticated,service_role;
grant select on public.recipe_generation_requests,public.receipt_recognition_requests to authenticated;

comment on function public.begin_external_request(uuid,uuid,text,text) is 'Creates an idempotent pending lifecycle record with fixed server TTL; metadata only.';
comment on function public.finish_external_request(uuid,uuid,text,text,text) is 'Service-only terminal transition; does not validate or store generated recipe or OCR output.';
comment on function public.purge_expired_external_requests(integer) is 'Service-only bounded cleanup; request idempotency lasts only until the row is purged.';
comment on function public.get_my_external_request(text,uuid) is 'Returns only the caller-owned request lifecycle metadata.';
comment on function public.discard_my_receipt_request(uuid) is 'Discards only the caller-owned receipt request lifecycle metadata.';

commit;
