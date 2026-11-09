-- STAGE ONLY: schema 002 + migrations 003..007 + migration 202610310001,
-- inside ONE transaction ending ROLLBACK. Synthetic accounts only.
do $pantry_rpc_tests$
declare
  users uuid[]; item_id uuid:=gen_random_uuid(); saved public.pantry_items;
  batch_a uuid:=gen_random_uuid(); batch_b uuid:=gen_random_uuid(); batch_data jsonb; batch_output jsonb;
  list_id uuid:=gen_random_uuid(); shopping_item_id uuid:=gen_random_uuid(); receipt_key uuid:=gen_random_uuid();
  category_id uuid:=gen_random_uuid(); unit_id uuid:=gen_random_uuid();
begin
  select array_agg(id order by id) into users from (select id from auth.users
    where banned_until is null or banned_until<=now() order by id limit 2) eligible;
  if cardinality(users)<2 then raise exception 'FAIL: two active test accounts required'; end if;
  insert into public.account_status(user_id,active) select unnest(users),true
    on conflict(user_id) do update set active=true,updated_at=clock_timestamp();
  insert into public.categories(id,name,normalized_name) values(category_id,'Otros','pantry-rpc-otros-'||category_id::text);
  insert into public.units(id,name,abbreviation,dimension) values(unit_id,'Gramo','g','mass');
  perform set_config('request.jwt.claim.sub',users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';

  batch_data:=jsonb_build_array(
    jsonb_build_object('expected_version',0,'item',jsonb_build_object('id',batch_a,'name','Lentejas','category','Otros','quantity',1,'unit','g','minimum',0,'expiry',null)),
    jsonb_build_object('expected_version',0,'item',jsonb_build_object('id',batch_b,'name','Harina','category','No existe','quantity',1,'unit','g','minimum',0,'expiry',null)));
  begin
    perform public.put_my_pantry_items(batch_data);
    raise exception 'FAIL: invalid batch was accepted';
  exception when invalid_parameter_value then null; end;
  if exists(select 1 from public.pantry_items where id=batch_a) then raise exception 'FAIL: invalid batch partially committed'; end if;
  batch_data:=jsonb_set(batch_data,'{1,item,category}','"Otros"'::jsonb);
  batch_output:=public.put_my_pantry_items(batch_data);
  if jsonb_array_length(batch_output)<>2 then raise exception 'FAIL: batch did not return two rows: %',batch_output; end if;
  batch_output:=public.put_my_pantry_items(batch_data);
  if jsonb_array_length(batch_output)<>2 then raise exception 'FAIL: batch retry did not return two rows: %',batch_output; end if;
  if (select count(*) from public.pantry_items where id in (batch_a,batch_b))<>2 then raise exception 'FAIL: batch retry duplicated or omitted rows'; end if;

  select * into saved from public.put_my_pantry_item(jsonb_build_object('id',item_id,'name','Arroz  integral',
    'category','Otros','quantity',0,'unit','g','minimum',0,'expiry',null,'ingredient_id','legacy-unmatched-42'),0);
  if saved.user_id<>users[1] or saved.version<>1 or saved.quantity<>0 or saved.expiry is not null
    or saved.ingredient_ref is not null or saved.ingredient_id<>'legacy-unmatched-42' or saved.unit_ref<>unit_id then raise exception 'FAIL: pantry create/nullable fields'; end if;
  select * into saved from public.put_my_pantry_item(jsonb_build_object('id',item_id,'name','Arroz integral',
    'category','Otros','quantity',0,'unit','g','minimum',0,'expiry',null),0);
  if saved.version<>1 then raise exception 'FAIL: stable UUID create retry changed item'; end if;

  begin
    perform public.put_my_pantry_item(jsonb_build_object('id',item_id,'name','Arroz integral','category','Otros',
      'quantity',1,'unit','g','minimum',0,'expiry',null),0);
    raise exception 'FAIL: create retry payload mismatch accepted';
  exception when serialization_failure then null; end;
  begin
    perform public.put_my_pantry_item(jsonb_build_object('id',gen_random_uuid(),'name','Arroz integral','category','Otros',
      'quantity',1.12345,'unit','g','minimum',0,'expiry',null),0);
    raise exception 'FAIL: over-precision quantity accepted';
  exception when invalid_parameter_value then null; end;

  select * into saved from public.put_my_pantry_item(jsonb_build_object('id',item_id,'name','Arroz integral',
    'category','Otros','quantity',1.2345,'unit','g','minimum',0.25,'expiry',''),1);
  if saved.version<>2 or saved.quantity<>1.2345 or saved.expiry is not null
    or saved.ingredient_id<>'legacy-unmatched-42' then raise exception 'FAIL: pantry update/legacy identifier preservation'; end if;

  execute 'reset role';
  update public.shopping_lists set status='archived' where owner_user_id=users[1] and status='active';
  insert into public.shopping_lists(id,owner_user_id,name) values(list_id,users[1],'Pantry RPC version test');
  insert into public.shopping_items(id,list_id,name_snapshot,category_snapshot,quantity,unit_id,checked,source)
    values(shopping_item_id,list_id,'Arroz integral','Otros',1,unit_id,true,'manual');
  perform set_config('request.jwt.claim.sub',users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.transfer_my_shopping_to_pantry(list_id,array[shopping_item_id],receipt_key,1);
  if (select version from public.pantry_items where id=item_id)<>3
    or (select quantity from public.pantry_items where id=item_id)<>2.2345 then
    raise exception 'FAIL: actual shopping transfer did not advance pantry version';
  end if;
  begin
    perform public.put_my_pantry_item(jsonb_build_object('id',item_id,'name','Stale','category','Otros',
      'quantity',1,'unit','g','minimum',0,'expiry',null),2);
    raise exception 'FAIL: stale pantry write accepted';
  exception when serialization_failure then null; end;

  execute 'reset role';
  perform set_config('request.jwt.claim.sub',users[2]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[2],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin
    perform public.put_my_pantry_item(jsonb_build_object('id',item_id,'name','Robo','category','Otros',
      'quantity',1,'unit','g','minimum',0,'expiry',null),3);
    raise exception 'FAIL: stale account write accepted';
  exception when serialization_failure then null; end;
  begin
    if public.delete_my_pantry_item(item_id,3) then raise exception 'FAIL: cross-account pantry deletion succeeded'; end if;
  exception when others then
    if sqlerrm='FAIL: cross-account pantry deletion succeeded' then raise; end if;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin
    delete from public.pantry_items where id=item_id;
    raise exception 'FAIL: direct pantry delete privilege remains';
  exception when insufficient_privilege then null; end;
  if not public.delete_my_pantry_item(item_id,3) or public.delete_my_pantry_item(item_id,3) then
    raise exception 'FAIL: versioned pantry delete/idempotent missing row';
  end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
end;
$pantry_rpc_tests$;
select 'PASS: pantry CRUD/batch confirmation, stable retries, validation, transfer/version conflicts, account isolation, and direct-write revocation verified; wrapper ROLLBACK required' as result;
