-- Run against the migrated schema with synthetic rows. All changes roll back.
begin;

insert into auth.users(id) values ('cc000000-0000-4000-8000-000000000001');
insert into public.estado_cuenta(user_id, active) values ('cc000000-0000-4000-8000-000000000001', true);
insert into public.categorias(name, normalized_name) values ('Legacy transfer test', 'legacy transfer test');
insert into public.unidades(name, abbreviation, dimension) values ('Legacy transfer test', 'ltt', 'count');
insert into public.datos_personales(user_id, data_key, value)
values ('cc000000-0000-4000-8000-000000000001', 'shopping',
  '[{"id":"purchased","checked":true},{"id":"pending","checked":false}]');

select set_config('request.jwt.claim.sub', 'cc000000-0000-4000-8000-000000000001', true);
do $$
declare
  original jsonb := '[{"id":"purchased","checked":true},{"id":"pending","checked":false}]';
  changes jsonb := '[{"item":{"id":"cc000000-0000-4000-8000-000000000002","name":"Sample","category":"Legacy transfer test","unit":"ltt","quantity":2,"minimum":0},"expected_version":0,"purchase_ids":["purchased"]}]';
  bad_batch jsonb;
begin
  bad_batch := changes || jsonb_build_array(jsonb_build_object(
    'item', (changes->0->'item') || '{"id":"cc000000-0000-4000-8000-000000000003","unit":"invalid"}'::jsonb,
    'expected_version', 0, 'purchase_ids', '["purchased"]'::jsonb));
  begin
    perform public.transfer_my_legacy_shopping_to_pantry(original, bad_batch);
    raise exception 'Duplicate purchase accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.transfer_my_legacy_shopping_to_pantry(original, jsonb_set(changes, '{0,item,unit}', '"invalid"'));
    raise exception 'Invalid pantry write accepted';
  exception when invalid_parameter_value then null;
  end;
  if (select value from public.datos_personales where user_id = auth.uid() and data_key = 'shopping') is distinct from original then
    raise exception 'Failed pantry write removed purchases';
  end if;
  perform public.transfer_my_legacy_shopping_to_pantry(original, changes);
  begin
    perform public.transfer_my_legacy_shopping_to_pantry(original, changes);
    raise exception 'Stale transfer was repeated';
  exception when serialization_failure then null;
  end;
  if (select value from public.datos_personales where user_id = auth.uid() and data_key = 'shopping')
    is distinct from '[{"id":"pending","checked":false}]'::jsonb then
    raise exception 'Transfer removed the wrong purchases';
  end if;
  if not exists (select 1 from public.articulos_despensa where user_id = auth.uid()
    and id = 'cc000000-0000-4000-8000-000000000002' and quantity = 2
    and source_shopping_ids = array['purchased']) then
    raise exception 'Pantry write or receipt missing';
  end if;
end;
$$;

rollback;
