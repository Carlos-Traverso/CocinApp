-- REHEARSAL ONLY. Run in an isolated copy after the catalog rehearsal stage.
begin;
set local lock_timeout = '5s';
lock table public.pantry_items in share row exclusive mode;
do $$ begin
  if exists(select 1 from public.pantry_items where ingredient_ref is not null or unit_ref is not null) then
    raise exception 'La despensa ya tiene referencias relacionales; se rechaza sobrescribirlas.';
  end if;
end $$;
-- An explicit legacy ID is authoritative; only rows without one use exact
-- normalized names. Never use approximate matching or alter inventory values.
update public.pantry_items p set ingredient_ref=i.id
from public.ingredients i
where (p.ingredient_id is not null and i.legacy_id=p.ingredient_id)
  or (p.ingredient_id is null and i.normalized_name=
    lower(translate(regexp_replace(trim(p.name),'\s+',' ','g'),'áéíóúüñÁÉÍÓÚÜÑ','aeiouunAEIOUUN')));
update public.pantry_items p set unit_ref=u.id
from public.units u where u.abbreviation=p.unit;
select 'pantry_rows' as dataset,count(*) as total from public.pantry_items
union all select 'ingredient_unmatched',count(*) from public.pantry_items where ingredient_ref is null
union all select 'unit_unmatched',count(*) from public.pantry_items where unit_ref is null
union all select 'dimension_mismatch',count(*) from public.pantry_items p
join public.ingredients i on i.id=p.ingredient_ref join public.units b on b.id=i.base_unit_id
join public.units u on u.id=p.unit_ref where b.dimension<>u.dimension;
rollback;
