-- STAGE ONLY: inventory read RPC integration/security contract. The generated
-- wrapper includes all required migrations and ends with ROLLBACK.
do $inventory_reads$
declare
  eligible_users uuid[]; v_users uuid[] := array[gen_random_uuid(),gen_random_uuid()];
  blank_user uuid := gen_random_uuid(); unit_g uuid := gen_random_uuid(); source_a uuid := gen_random_uuid();
  active_list uuid := gen_random_uuid(); archived_list uuid := gen_random_uuid(); other_list uuid := gen_random_uuid();
  item_a uuid := gen_random_uuid(); item_b uuid := gen_random_uuid();
  p_empty uuid := gen_random_uuid(); p_low uuid := gen_random_uuid(); p_soon uuid := gen_random_uuid();
  p_expired uuid := gen_random_uuid(); p_overlap uuid := gen_random_uuid(); p_ok uuid := gen_random_uuid();
  p_zero_min uuid := gen_random_uuid(); p_equal uuid := gen_random_uuid(); p_unicode uuid := gen_random_uuid();
  result jsonb; entry jsonb; routine text; bad text; pantry_before jsonb; lists_before jsonb; items_before jsonb;
begin
  select array_agg(id order by id) into eligible_users from (
    select u.id from auth.users u left join public.account_status s on s.user_id=u.id
    where coalesce(s.active,true) and (u.banned_until is null or u.banned_until<=now()) order by u.id limit 2
  ) a;
  if coalesce(array_length(eligible_users,1),0) <> 2 then raise exception 'FAIL: inventory reads requires two existing active accounts'; end if;
  insert into auth.users(id) values(v_users[1]),(v_users[2]),(blank_user);
  delete from public.profiles where user_id in (v_users[1],v_users[2],blank_user);
  insert into public.user_roles(user_id,role) values(v_users[1],'USER'),(v_users[2],'USER'),(blank_user,'USER')
    on conflict(user_id) do update set role=excluded.role;
  insert into public.account_status(user_id,active) values(v_users[1],true),(v_users[2],true),(blank_user,true)
    on conflict(user_id) do update set active=true;
  insert into public.units(id,name,abbreviation,dimension) values(unit_g,'Inventory test gram','inventory-g-'||substr(unit_g::text,1,8),'mass');

  -- Include every status boundary plus overlapping expired/low and literal search metacharacters.
  insert into public.pantry_items(id,user_id,name,category,quantity,unit,minimum,expiry) values
    (p_empty,v_users[1],'Empty stock','Test',0,'g',5,null),
    (p_low,v_users[1],'Low stock','Test',2.1255,'g',5,null),
    (p_soon,v_users[1],'Soon stock','Test',8,'g',2,current_date+3),
    (p_expired,v_users[1],'Expired stock','Test',8,'g',2,current_date-1),
    (p_overlap,v_users[1],'Expired low','Test',1,'g',4,current_date-1),
    (p_ok,v_users[1],'Okay stock','Test',5,'g',5,current_date+4),
    (p_zero_min,v_users[1],'Zero minimum','Test',0,'g',0,null),
    (p_equal,v_users[1],'Boundary equal','Test',4,'g',4,current_date),
    (p_unicode,v_users[1],U&'Cafe\0301 100%_special','Test',1.2345,'g',2,null);
  insert into public.shopping_lists(id,owner_user_id,name,status) values
    (active_list,v_users[1],'Reads active','active'),(archived_list,v_users[1],'Reads archive','archived'),
    (other_list,v_users[2],'Reads other','active');
  insert into public.shopping_items(id,list_id,name_snapshot,quantity,unit_id,source,created_at) values
    (item_a,active_list,'First',1,unit_g,'manual','2026-01-01'),(item_b,active_list,'Second',2,unit_g,'manual','2026-01-02');
  insert into public.shopping_item_sources(id,shopping_item_id,source) values(source_a,item_a,'manual');
  update public.units set active=false where id=unit_g;
  select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]'::jsonb) into pantry_before from public.pantry_items p;
  select coalesce(jsonb_agg(to_jsonb(l) order by l.id),'[]'::jsonb) into lists_before from public.shopping_lists l;
  select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]'::jsonb) into items_before from public.shopping_items i;

  foreach routine in array array[
    'public.get_my_pantry(text,text,text,integer,integer)',
    'public.get_my_shopping_list(uuid,integer,integer)',
    'public.get_my_shopping_lists(text,integer,integer)'] loop
    if has_function_privilege('anon',routine,'EXECUTE') or has_function_privilege('service_role',routine,'EXECUTE')
      or not has_function_privilege('authenticated',routine,'EXECUTE') then raise exception 'FAIL: grants for %',routine; end if;
  end loop;

  perform set_config('request.jwt.claim.sub',blank_user::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',blank_user,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result:=public.get_my_pantry();
  if result->'items' is distinct from '[]'::jsonb or (result->>'total')::int is distinct from 0
    or result->>'as_of' is distinct from current_date::text then raise exception 'FAIL: blank pantry defaults %',result; end if;
  result:=public.get_my_shopping_list();
  if result->'list' is distinct from 'null'::jsonb or result->'items' is distinct from '[]'::jsonb then raise exception 'FAIL: blank list defaults %',result; end if;
  result:=public.get_my_shopping_lists();
  if result->'items' is distinct from '[]'::jsonb or (result->>'total')::int is distinct from 0 then raise exception 'FAIL: blank lists'; end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result:=public.get_my_pantry(null,null,'all',100,0);
  if (result->>'total')::int is distinct from 9 or jsonb_array_length(result->'items') is distinct from 9
    or result->>'as_of' is distinct from current_date::text then raise exception 'FAIL: pantry total/page/as_of %',result; end if;
  select x into entry from jsonb_array_elements(result->'items') x where x->>'id'=p_empty::text;
  if entry->'flags'->>'empty' is distinct from 'true' or entry->>'status' is distinct from 'empty' then raise exception 'FAIL: empty status %',entry; end if;
  select x into entry from jsonb_array_elements(result->'items') x where x->>'id'=p_low::text;
  if entry->'flags'->>'low' is distinct from 'true' or entry->>'status' is distinct from 'low' then raise exception 'FAIL: low status %',entry; end if;
  select x into entry from jsonb_array_elements(result->'items') x where x->>'id'=p_soon::text;
  if entry->'flags'->>'soon' is distinct from 'true' or entry->>'status' is distinct from 'soon' then raise exception 'FAIL: soon inclusive boundary %',entry; end if;
  select x into entry from jsonb_array_elements(result->'items') x where x->>'id'=p_expired::text;
  if entry->'flags'->>'expired' is distinct from 'true' or entry->>'status' is distinct from 'expired' then raise exception 'FAIL: expired boundary %',entry; end if;
  select x into entry from jsonb_array_elements(result->'items') x where x->>'id'=p_overlap::text;
  if entry->'flags'->>'expired' is distinct from 'true' or entry->'flags'->>'low' is distinct from 'true'
    or entry->>'status' is distinct from 'expired' then raise exception 'FAIL: overlapping flags and display priority %',entry; end if;
  select x into entry from jsonb_array_elements(result->'items') x where x->>'id'=p_zero_min::text;
  if entry->'flags'->>'low' is distinct from 'false' or entry->>'status' is distinct from 'empty' then raise exception 'FAIL: zero minimum status %',entry; end if;
  select x into entry from jsonb_array_elements(result->'items') x where x->>'id'=p_equal::text;
  if entry->'flags'->>'low' is distinct from 'false' or entry->'flags'->>'soon' is distinct from 'true' then raise exception 'FAIL: equality and day zero boundary %',entry; end if;
  if (select count(*) from jsonb_array_elements(public.get_my_pantry(null,null,'low',100,0)->'items'))<>5 then
    raise exception 'FAIL: low filter must include empty/overlap'; end if;
  if (select count(*) from jsonb_array_elements(public.get_my_pantry(null,null,'expired',100,0)->'items'))<>2 then raise exception 'FAIL: expired filter'; end if;
  if (select count(*) from jsonb_array_elements(public.get_my_pantry(null,null,'empty',100,0)->'items'))<>2 then raise exception 'FAIL: empty filter'; end if;
  if (select count(*) from jsonb_array_elements(public.get_my_pantry(null,null,'ok',100,0)->'items'))<>1 then raise exception 'FAIL: ok filter'; end if;
  if (select count(*) from jsonb_array_elements(public.get_my_pantry(null,null,'soon',100,0)->'items'))<>2 then raise exception 'FAIL: soon filter'; end if;
  if (select count(*) from jsonb_array_elements(public.get_my_pantry(U&'  CAFE\0301   100%_SPECIAL  ',null,'all',100,0)->'items'))<>1 then
    raise exception 'FAIL: NFD/casefold/whitespace/literal wildcard search'; end if;
  if (select count(*) from jsonb_array_elements(public.get_my_pantry(null,' test ','all',100,0)->'items'))<>9
    or (select count(*) from jsonb_array_elements(public.get_my_pantry(null,E'\t \n','all',100,0)->'items'))<>9
    or (select count(*) from jsonb_array_elements(public.get_my_pantry('', '', 'all',100,0)->'items'))<>9 then raise exception 'FAIL: normalized/exact category and empty filters'; end if;
  result:=public.get_my_pantry(null,null,'all',2,1);
  if jsonb_array_length(result->'items')<>2 or (result->>'total')::int<>9
    or (result->>'limit')::int<>2 or (result->>'offset')::int<>1 then raise exception 'FAIL: stable pantry paging metadata'; end if;
  if not exists(select 1 from jsonb_array_elements(result->'items') x where x->>'quantity'='1.2345' or x->>'quantity'='2.1255') then
    raise exception 'FAIL: pantry decimal precision'; end if;

  result:=public.get_my_shopping_list(active_list,100,0);
  if result->'list'->>'id' is distinct from active_list::text or jsonb_array_length(result->'items')<>2
    or result->'items'->0->>'id' is distinct from item_a::text or result->'items'->1->>'id' is distinct from item_b::text
    or result->'items'->0->'unit_detail'->>'id' is distinct from unit_g::text
    or result->'items'->0->'unit_detail'->>'active' is distinct from 'false'
    or jsonb_array_length(result->'items'->0->'sources')<>1
    or result->'items'->0->'sources'->0->>'id' is distinct from source_a::text then raise exception 'FAIL: ordered shopping list/unit/source snapshot %',result; end if;
  if public.get_my_shopping_list()->'list'->>'id' is distinct from active_list::text then raise exception 'FAIL: implicit active list'; end if;
  if public.get_my_shopping_list(archived_list)->'list'->>'status' is distinct from 'archived' then raise exception 'FAIL: own archived list readable'; end if;
  if (select (public.get_my_shopping_lists('all',100,0)->>'total')::int)<>2
    or (select (public.get_my_shopping_lists('active',100,0)->>'total')::int)<>1
    or (select (public.get_my_shopping_lists('archived',100,0)->>'total')::int)<>1 then raise exception 'FAIL: list status filters'; end if;
  begin perform public.get_my_shopping_list(other_list); raise exception 'FAIL: foreign list accepted'; exception when no_data_found then null; end;
  execute 'reset role';

  update public.user_roles set role='ADMIN' where user_id=v_users[1];
  execute 'set local role authenticated';
  if (public.get_my_shopping_lists('all',100,0)->>'total')::int<>2 then raise exception 'FAIL: admin leaked foreign list'; end if;
  execute 'reset role'; update public.user_roles set role='USER' where user_id=v_users[1];

  foreach bad in array array['0,0','101,0','1,-1','1,5001','NULL,0','1,NULL'] loop
    begin execute format('select public.get_my_pantry(null,null,''all'',%s)',bad); raise exception 'FAIL: accepted pantry bounds %',bad; exception when sqlstate '22023' then null; end;
    begin execute format('select public.get_my_shopping_list(null,%s)',bad); raise exception 'FAIL: accepted list bounds %',bad; exception when sqlstate '22023' then null; end;
    begin execute format('select public.get_my_shopping_lists(null,%s)',bad); raise exception 'FAIL: accepted lists bounds %',bad; exception when sqlstate '22023' then null; end;
  end loop;
  foreach bad in array array['bogus',''] loop
    begin execute format('select public.get_my_pantry(null,null,%L)',bad); raise exception 'FAIL: accepted pantry status %',bad; exception when sqlstate '22023' then null; end;
    begin execute format('select public.get_my_shopping_lists(%L)',bad); raise exception 'FAIL: accepted lists status %',bad; exception when sqlstate '22023' then null; end;
  end loop;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true); perform set_config('request.jwt.claims','{"role":"anon"}',true);
  execute 'set local role anon';
  begin perform public.get_my_pantry(); raise exception 'FAIL: anon pantry'; exception when insufficient_privilege then null; end;
  begin perform public.get_my_shopping_lists(); raise exception 'FAIL: anon lists'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true); execute 'set local role authenticated';
  begin perform public.get_my_pantry(); raise exception 'FAIL: missing identity'; exception when insufficient_privilege then null; end;
  execute 'reset role';
  update public.account_status set active=false where user_id=v_users[1];
  perform set_config('request.jwt.claim.sub',v_users[1]::text,true); perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin perform public.get_my_pantry(); raise exception 'FAIL: inactive account'; exception when insufficient_privilege then null; end;
  execute 'reset role'; update public.account_status set active=true where user_id=v_users[1];
  update auth.users set banned_until=now()+interval '1 day' where id=v_users[1];
  execute 'set local role authenticated';
  begin perform public.get_my_shopping_lists(); raise exception 'FAIL: banned account'; exception when insufficient_privilege then null; end;
  execute 'reset role'; update auth.users set banned_until=null where id=v_users[1];
  perform set_config('request.jwt.claim.sub','',true); perform set_config('request.jwt.claims','{}',true);
  if (select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]'::jsonb) from public.pantry_items p) is distinct from pantry_before
    or (select coalesce(jsonb_agg(to_jsonb(l) order by l.id),'[]'::jsonb) from public.shopping_lists l) is distinct from lists_before
    or (select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]'::jsonb) from public.shopping_items i) is distinct from items_before then
    raise exception 'FAIL: inventory read RPCs mutated pantry/list/item rows or versions'; end if;
  raise notice 'PASS: inventory reads ownership, filters, status boundaries, literal search, list snapshots, paging, validation, and caller permissions';
end;
$inventory_reads$;
select 'PASS: inventory reads verified; full script includes ROLLBACK' as result;
