-- STAGE ONLY: after relational schema and catalog admin migration, rollback.
do $catalog_admin$
declare
  admin_id uuid;
  v_user_id uuid;
  category_id uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  unit_id uuid := 'dddddddd-dddd-dddd-dddd-dddddddddddd';
  ingredient_id uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  replacement_category uuid := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
  converted_unit uuid := 'abababab-abab-abab-abab-abababababab';
  legacy_unit uuid := 'acacacac-acac-acac-acac-acacacacacac';
  saved jsonb; before_audit bigint;
begin
  select u.id into admin_id from auth.users u left join public.account_status s on s.user_id=u.id
    where coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now()) order by u.id limit 1;
  select u.id into v_user_id from auth.users u left join public.account_status s on s.user_id=u.id
    where u.id<>admin_id and coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now()) order by u.id limit 1;
  if admin_id is null or v_user_id is null then raise exception 'FAIL: rehearsal requires two existing active Auth accounts'; end if;
  insert into public.user_roles(user_id,role) values(admin_id,'ADMIN'),(v_user_id,'USER')
    on conflict(user_id) do update set role=excluded.role;
  insert into public.account_status(user_id,active) values(admin_id,true),(v_user_id,true)
    on conflict(user_id) do update set active=true;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  insert into public.units(id,name,abbreviation,dimension,base_unit_id,equivalence_multiplier,active,is_deleted)
    values(legacy_unit,'Legacy import unit','legacy','mass',null,null,true,false);
  if (select normalized_name from public.units where id=legacy_unit)<>'legacy import unit' then raise exception 'FAIL: legacy unit backfill normalization'; end if;
  delete from public.units where id=legacy_unit;
  select count(*) into before_audit from public.admin_audit_log;
  saved:=public.admin_put_category(jsonb_build_object('id',category_id,'name','Carnes y proteínas','active',true,'is_deleted',false),0);
  if saved->>'version' <> '1' then raise exception 'FAIL: category create version'; end if;
  if public.admin_put_category(jsonb_build_object('id',category_id,'name','Carnes y proteínas','active',true,'is_deleted',false),0)<>saved then raise exception 'FAIL: stable create replay'; end if;
  saved:=public.admin_put_unit(jsonb_build_object('id',unit_id,'name','Gramos','abbreviation','g','dimension','mass','base_unit_id',null,'equivalence_multiplier',null,'active',true,'is_deleted',false),0);
  if saved->>'version'<>'1' then raise exception 'FAIL: unit create'; end if;
  saved:=public.admin_put_unit(jsonb_build_object('id',converted_unit,'name','Kilogramos','abbreviation','kg','dimension','mass','base_unit_id',unit_id,'equivalence_multiplier',1000.000000,'active',true,'is_deleted',false),0);
  if saved->>'version'<>'1' then raise exception 'FAIL: conversion unit create'; end if;
  if (public.admin_put_unit(jsonb_build_object('id',converted_unit,'name','Kilogramos','abbreviation','kg','dimension','mass','base_unit_id',unit_id,'equivalence_multiplier',1000,'active',true,'is_deleted',false),0))->>'version'<>'1' then raise exception 'FAIL: unit create retry was not idempotent'; end if;
  begin
    perform public.admin_put_unit(jsonb_build_object('id',gen_random_uuid(),'name','Gramo duplicado','abbreviation','G','dimension','mass','base_unit_id',null,'equivalence_multiplier',null),0);
    raise exception 'FAIL: duplicate unit abbreviation accepted';
  exception when unique_violation then null; end;
  insert into public.pantry_items(user_id,name,category,quantity,unit,minimum,unit_ref)
    values(admin_id,'Audit fixture','Otros',1,'kg',0,converted_unit);
  begin
    perform public.admin_put_unit(jsonb_build_object('id',converted_unit,'name','Kilogramos','abbreviation','kg','dimension','mass','base_unit_id',unit_id,'equivalence_multiplier',500,'active',true,'is_deleted',false),1);
    raise exception 'FAIL: referenced unit conversion changed';
  exception when check_violation or invalid_parameter_value then null; end;
  saved:=public.admin_put_unit(jsonb_build_object('id',converted_unit,'name','Kilogramos','abbreviation','kg','dimension','mass','base_unit_id',unit_id,'equivalence_multiplier',1000,'active',false,'is_deleted',true),1);
  if saved->>'version'<>'2' or saved->>'is_deleted'<>'true' then raise exception 'FAIL: referenced unit archive'; end if;
  saved:=public.admin_put_unit(jsonb_build_object('id',converted_unit,'name','Kilogramos','abbreviation','kg','dimension','mass','base_unit_id',unit_id,'equivalence_multiplier',1000,'active',true,'is_deleted',false),2);
  if saved->>'version'<>'3' or saved->>'is_deleted'<>'false' then raise exception 'FAIL: referenced unit restore'; end if;
  saved:=public.admin_put_ingredient(jsonb_build_object('id',ingredient_id,'name','Pechúga de pollo','category_id',category_id,'base_unit_id',unit_id,'active',true,'is_deleted',false),0);
  if saved->>'version'<>'1' then raise exception 'FAIL: ingredient create'; end if;
  begin
    perform public.admin_put_ingredient(jsonb_build_object('id','ffffffff-ffff-ffff-ffff-ffffffffffff','name','Pechuga de pollo','category_id',category_id,'base_unit_id',unit_id),0);
    raise exception 'FAIL: accent-insensitive duplicate accepted';
  exception when unique_violation then null; end;
  saved:=public.admin_put_category(jsonb_build_object('id',category_id,'name','Carnes','active',true,'is_deleted',false),1);
  if saved->>'version'<>'2' then raise exception 'FAIL: category update version'; end if;
  if public.admin_put_category(jsonb_build_object('id',category_id,'name','Carnes','active',true,'is_deleted',false),2)->>'version'<>'2' then raise exception 'FAIL: no-op update changed version'; end if;
  begin
    perform public.admin_put_category(jsonb_build_object('id',category_id,'name','Conflicto','active',true,'is_deleted',false),1);
    raise exception 'FAIL: stale update accepted';
  exception when sqlstate '40001' then null; end;
  saved:=public.admin_put_ingredient(jsonb_build_object('id',ingredient_id,'name','Pechúga de pollo','category_id',category_id,'base_unit_id',unit_id,'active',false,'is_deleted',true),1);
  if saved->>'version'<>'2' or saved->>'is_deleted'<>'true' then raise exception 'FAIL: soft delete'; end if;
  perform public.admin_put_category(jsonb_build_object('id',category_id,'name','Carnes','active',false,'is_deleted',true),2);
  perform public.admin_put_category(jsonb_build_object('id',replacement_category,'name','Carnes','active',true,'is_deleted',false),0);
  begin
    perform public.admin_put_category(jsonb_build_object('id',category_id,'name','Carnes','active',true,'is_deleted',false),3);
    raise exception 'FAIL: restore collision accepted';
  exception when unique_violation then null; end;
  begin
    perform public.admin_put_category(jsonb_build_object('id',gen_random_uuid(),'name',null),0);
    raise exception 'FAIL: null required field accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' or sqlerrm not like '%datos del catálogo%' then raise; end if;
  end;
  if (select count(*) from public.admin_audit_log)-before_audit<>10 then raise exception 'FAIL: failed mutation wrote an audit row'; end if;
  if has_function_privilege('anon','public.admin_put_category(jsonb,bigint)','EXECUTE') then
    raise exception 'FAIL: catalog mutation is executable by anon/public';
  end if;
  if (select count(*) from public.admin_audit_log)-before_audit<>10 then raise exception 'FAIL: expected exactly one audit per effective mutation'; end if;
  perform set_config('request.jwt.claim.sub',v_user_id::text,true);
  begin
    perform public.admin_put_category(jsonb_build_object('id',gen_random_uuid(),'name','Unauthorized'),0);
    raise exception 'FAIL: USER was authorized';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  update public.user_roles set role='USER' where user_id=admin_id;
  begin
    perform public.admin_put_category(jsonb_build_object('id',gen_random_uuid(),'name','Revoked'),0);
    raise exception 'FAIL: revoked same-JWT admin was authorized';
  exception when insufficient_privilege then null; end;
  update public.user_roles set role='ADMIN' where user_id=admin_id;
  update public.account_status set active=false where user_id=admin_id;
  begin
    perform public.admin_put_category(jsonb_build_object('id',gen_random_uuid(),'name','Inactive'),0);
    raise exception 'FAIL: inactive admin was authorized';
  exception when insufficient_privilege then null; end;
  update public.account_status set active=true where user_id=admin_id;
  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform public.admin_put_category(jsonb_build_object('id',gen_random_uuid(),'name','Anonymous'),0);
    raise exception 'FAIL: anonymous was authorized';
  exception when insufficient_privilege then null; end;
  raise notice 'PASS: catalog admin versioning/replay/normalization/restore/audit/authorization';
end;
$catalog_admin$;
