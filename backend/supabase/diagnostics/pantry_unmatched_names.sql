-- Read-only: report unmatched food labels without account identifiers.
with catalog as (
  select x->>'id' as legacy_id,
    lower(translate(regexp_replace(trim(x->>'name'), '\s+', ' ', 'g'),
      'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')) as normalized_name
  from public.catalog_core c
  cross join lateral jsonb_array_elements(c.payload->'ingredients') x
  where c.catalog_key = 'main'
)
select p.name as pantry_label, p.unit, count(*) as affected_rows,
  case when p.ingredient_id is null then 'name_not_in_catalog'
    else 'explicit_id_not_in_catalog' end as reason
from public.pantry_items p
where not exists (
  select 1 from catalog i
  where (p.ingredient_id is not null and i.legacy_id = p.ingredient_id)
    or (p.ingredient_id is null and i.normalized_name =
      lower(translate(regexp_replace(trim(p.name), '\s+', ' ', 'g'),
        'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')))
)
group by p.name, p.unit, p.ingredient_id is null;
