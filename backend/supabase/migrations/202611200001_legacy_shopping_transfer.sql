begin;

create or replace function public.transfer_my_legacy_shopping_to_pantry(
  p_expected_shopping jsonb,
  p_changes jsonb
) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid;
  shopping jsonb;
  purchase_ids text[];
begin
  actor := public.lock_my_relational_account();
  select value into shopping from public.datos_personales
  where user_id = actor and data_key = 'shopping' for update;
  if jsonb_typeof(shopping) is distinct from 'array' or shopping is distinct from p_expected_shopping then
    raise exception 'La lista de compras cambió. Recargala antes de transferir.' using errcode = '40001';
  end if;

  if jsonb_typeof(p_changes) is distinct from 'array' then
    raise exception 'La transferencia no es válida.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_changes) not between 1 and 200 or exists (
    select 1 from jsonb_array_elements(p_changes) as changes(entry)
    where jsonb_typeof(entry->'purchase_ids') is distinct from 'array'
       or entry->'purchase_ids' = '[]'::jsonb
  ) then
    raise exception 'La transferencia no es válida.' using errcode = '22023';
  end if;

  select array_agg(id) into purchase_ids
  from jsonb_array_elements(p_changes) as changes(entry)
  cross join lateral jsonb_array_elements_text(entry->'purchase_ids') as purchases(id);
  if exists (
    select 1 from unnest(purchase_ids) as purchases(id)
    group by id having id is null or id = '' or count(*) > 1
  ) or exists (
    select 1 from unnest(purchase_ids) as purchases(id)
    where not exists (
      select 1 from jsonb_array_elements(shopping) as rows(item)
      where item->>'id' = id and item->'checked' = 'true'::jsonb
        and item->'transferredToPantry' is distinct from 'true'::jsonb
    )
  ) then
    raise exception 'La lista contiene compras que no se pueden transferir.' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.articulos_despensa
    where user_id = actor and source_shopping_ids && purchase_ids
  ) then
    raise exception 'Una compra ya está en la despensa. Recargá la lista.' using errcode = '40001';
  end if;

  perform public.put_my_pantry_items((
    select jsonb_agg(entry - 'purchase_ids') from jsonb_array_elements(p_changes) as changes(entry)
  ));

  update public.articulos_despensa as pantry
  set source_shopping_ids = pantry.source_shopping_ids ||
    array(select jsonb_array_elements_text(entry->'purchase_ids'))
  from jsonb_array_elements(p_changes) as changes(entry)
  where pantry.user_id = actor and pantry.id = (entry->'item'->>'id')::uuid;

  update public.datos_personales
  set value = (
    select coalesce(jsonb_agg(item order by position), '[]'::jsonb)
    from jsonb_array_elements(shopping) with ordinality as rows(item, position)
    where (item->>'id' = any(purchase_ids)) is not true
  ), updated_at = clock_timestamp()
  where user_id = actor and data_key = 'shopping';
end;
$$;

revoke all on function public.transfer_my_legacy_shopping_to_pantry(jsonb,jsonb) from public,anon,service_role;
grant execute on function public.transfer_my_legacy_shopping_to_pantry(jsonb,jsonb) to authenticated;

commit;
