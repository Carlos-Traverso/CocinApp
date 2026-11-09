-- Synthetic rows only; the wrapper rolls back everything, including Auth status.
do $tests$
declare
  accounts uuid[]; a uuid; b uuid;
  list_id uuid:=gen_random_uuid(); foreign_list uuid:=gen_random_uuid();
  category_id uuid:=gen_random_uuid(); gram uuid:=gen_random_uuid(); kilo uuid:=gen_random_uuid();
  ingredient_id uuid:=gen_random_uuid(); manual uuid:=gen_random_uuid(); catalog_item uuid:=gen_random_uuid();
  retry_key uuid:=gen_random_uuid(); stock_id uuid:=gen_random_uuid(); receipt public.pantry_receipts;
  saved public.shopping_lists; version_before bigint; before_qty numeric; other_key uuid;
begin
  select array_agg(id order by id) into accounts from (select id from auth.users where banned_until is null or banned_until<=now() order by id limit 2) q;
  if cardinality(accounts)<>2 then raise exception 'Two existing active Auth accounts required'; end if;
  a:=accounts[1]; b:=accounts[2];
  insert into public.account_status(user_id,active) values(a,true),(b,true) on conflict(user_id) do update set active=true;
  insert into public.user_roles(user_id,role) values(a,'USER'),(b,'USER') on conflict(user_id) do update set role='USER';
  update public.shopping_lists set status='archived' where owner_user_id in(a,b) and status='active';
  insert into public.categories(id,name,normalized_name) values(category_id,'Transfer synthetic','transfer synthetic');
  insert into public.units(id,name,abbreviation,dimension) values(gram,'Transfer gram','tx-g','mass');
  insert into public.units(id,name,abbreviation,dimension,base_unit_id,equivalence_multiplier) values(kilo,'Transfer kilogram','tx-kg','mass',gram,1000);
  insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values(ingredient_id,'Transfer ingredient','transfer ingredient',category_id,gram);
  insert into public.pantry_items(id,user_id,name,category,quantity,unit,minimum,ingredient_ref,unit_ref)
    values(stock_id,a,'Transfer ingredient','Transfer synthetic',50,'tx-g',0,ingredient_id,gram);
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.create_my_shopping_list(foreign_list,'Foreign synthetic',null);
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  saved:=public.create_my_shopping_list(list_id,'Transfer synthetic',null);
  saved:=public.put_my_shopping_item(list_id,jsonb_build_object('id',manual,'name_snapshot','Manual synthetic','category_snapshot','Transfer synthetic','quantity',0.0001,'unit_id',gram,'checked',true,'source','manual','sources','[{"source":"manual"}]'::jsonb),saved.version);
  saved:=public.put_my_shopping_item(list_id,jsonb_build_object('id',catalog_item,'ingredient_id',ingredient_id,'quantity',1.5,'unit_id',kilo,'checked',false,'source','manual','sources','[{"source":"manual"}]'::jsonb),saved.version);
  begin perform public.transfer_my_shopping_to_pantry(foreign_list,array[manual],retry_key,1); raise exception 'FAIL foreign list'; exception when insufficient_privilege then null; end;
  begin perform public.transfer_my_shopping_to_pantry(list_id,array[manual,manual],retry_key,saved.version); raise exception 'FAIL duplicate'; exception when invalid_parameter_value then null; end;
  begin perform public.transfer_my_shopping_to_pantry(list_id,array[manual,catalog_item],retry_key,saved.version); raise exception 'FAIL unchecked'; exception when invalid_parameter_value then null; end;
  if exists(select 1 from public.pantry_receipts where idempotency_key=retry_key) then raise exception 'FAIL failed batch receipt'; end if;
  execute 'reset role';
  if (select quantity from public.pantry_items where id=stock_id)<>50 or exists(select 1 from public.pantry_items where user_id=a and name='Manual synthetic') then raise exception 'FAIL partial batch'; end if;
  execute 'set local role authenticated';
  saved:=public.set_my_shopping_checked(list_id,array[catalog_item],true,saved.version);
  version_before:=saved.version;
  receipt:=public.transfer_my_shopping_to_pantry(list_id,array[catalog_item,manual],retry_key,saved.version);
  if receipt.resulting_list_version<>version_before+1 or (select count(*) from public.pantry_receipt_items where receipt_id=receipt.id)<>2 then raise exception 'FAIL receipt or version'; end if;
  if (public.transfer_my_shopping_to_pantry(list_id,array[manual,catalog_item],retry_key,1)).id<>receipt.id then raise exception 'FAIL retry'; end if;
  begin perform public.transfer_my_shopping_to_pantry(list_id,array[manual],retry_key,receipt.resulting_list_version); raise exception 'FAIL key mismatch'; exception when invalid_parameter_value then null; end;
  begin perform public.transfer_my_shopping_to_pantry(list_id,array[manual],gen_random_uuid(),receipt.resulting_list_version); raise exception 'FAIL second transfer'; exception when invalid_parameter_value then null; end;
  execute 'reset role';
  if (select quantity from public.pantry_items where id=stock_id)<>1550
    or not exists(select 1 from public.pantry_items where user_id=a and name='Manual synthetic' and ingredient_ref is null and quantity=0.0001)
    or not exists(select 1 from public.pantry_receipt_items where receipt_id=receipt.id and original_shopping_item_id=catalog_item and quantity_added=1500 and purchased_quantity=1.5 and purchased_unit_abbreviation_snapshot='tx-kg' and unit_abbreviation_snapshot='tx-g') then raise exception 'FAIL conversion, manual preservation or snapshots'; end if;
  begin update public.units set equivalence_multiplier=2000 where id=kilo; raise exception 'FAIL shopping conversion mutable'; exception when invalid_parameter_value or check_violation then null; end;
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if exists(select 1 from public.pantry_receipts where id=receipt.id) or exists(select 1 from public.pantry_receipt_items where receipt_id=receipt.id) then raise exception 'FAIL receipt isolation'; end if;
  begin perform public.transfer_my_shopping_to_pantry(list_id,array[manual],retry_key,1); raise exception 'FAIL B transfer A'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  saved:=public.remove_my_shopping_item(list_id,catalog_item,receipt.resulting_list_version);
  saved:=public.create_my_shopping_list(gen_random_uuid(),'Replacement synthetic',null);
  if (public.transfer_my_shopping_to_pantry(list_id,array[manual,catalog_item],retry_key,1)).id<>receipt.id then raise exception 'FAIL retry after removal/archive'; end if;
  execute 'reset role';
  update public.account_status set active=false where user_id=a;
  execute 'set local role authenticated';
  begin perform public.transfer_my_shopping_to_pantry(list_id,array[manual,catalog_item],retry_key,1); raise exception 'FAIL inactive retry'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true); perform set_config('request.jwt.claims','{}',true);
  execute 'set local role anon';
  begin perform public.transfer_my_shopping_to_pantry(list_id,array[manual],retry_key,1); raise exception 'FAIL anonymous'; exception when insufficient_privilege then null; end;
  execute 'reset role';
end;
$tests$;
select 'PASS: transfer atomicity, manual stock, exact conversion, snapshots, retry, isolation, archive/removal and authorization; wrapper ROLLBACK required' as result;
