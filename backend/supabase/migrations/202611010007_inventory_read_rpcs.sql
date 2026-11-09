begin;

-- Inventory read APIs keep ownership checks explicit even though they run as
-- SECURITY DEFINER. Each page and its total are built by one statement.
create function public.get_my_pantry(
  p_search text default null,
  p_category text default null,
  p_status text default 'all',
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb; as_of date := current_date; needle text; category_key text;
begin
  actor := public.lock_my_relational_account();
  if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset not between 0 and 5000
    or p_status is null or p_status not in ('all','ok','low','empty','soon','expired')
    or (p_search is not null and length(p_search)>120)
    or (p_category is not null and length(p_category)>80) then
    raise exception 'Los filtros de despensa no son válidos.' using errcode='22023';
  end if;
  needle := nullif(lower(regexp_replace(normalize(trim(regexp_replace(coalesce(p_search,''),'[[:space:]]+',' ','g')),NFD),U&'[\0300-\036f]','','g')),'');
  category_key := nullif(lower(regexp_replace(normalize(trim(regexp_replace(coalesce(p_category,''),'[[:space:]]+',' ','g')),NFD),U&'[\0300-\036f]','','g')),'');
  with mine as materialized (
    select p.*,
      lower(regexp_replace(regexp_replace(normalize(trim(regexp_replace(p.name,'[[:space:]]+',' ','g')),NFD),U&'[\0300-\036f]','','g'),'[[:space:]]+',' ','g')) as normalized_name,
      lower(regexp_replace(regexp_replace(normalize(trim(regexp_replace(p.category,'[[:space:]]+',' ','g')),NFD),U&'[\0300-\036f]','','g'),'[[:space:]]+',' ','g')) as normalized_category,
      case when p.expiry is null then null else p.expiry-as_of end as days,
      p.quantity=0 as empty,
      (p.minimum>0 and p.quantity>0 and p.quantity<p.minimum) as low,
      (p.expiry is not null and p.expiry between as_of and as_of+3) as soon,
      (p.expiry is not null and p.expiry<as_of) as expired
    from public.pantry_items p where p.user_id=actor
  ), filtered as materialized (
    select m.*, case when m.expired then 'expired' when m.empty then 'empty'
      when m.soon then 'soon' when m.low then 'low' else 'ok' end as display_status
    from mine m
    where (needle is null or strpos(m.normalized_name,needle)>0)
      and (category_key is null or m.normalized_category=category_key)
      and (p_status='all' or (p_status='ok' and not (m.low or m.empty or m.soon or m.expired))
        or (p_status='low' and (m.low or m.empty)) or (p_status='empty' and m.empty)
        or (p_status='soon' and m.soon) or (p_status='expired' and m.expired))
  ), page as (
    select * from filtered order by normalized_name,id offset p_offset limit p_limit
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(p) - 'normalized_name' - 'normalized_category' - 'days' - 'empty' - 'low' - 'soon' - 'expired' - 'display_status'
      || jsonb_build_object('flags',jsonb_build_object('days',p.days,'empty',p.empty,'low',p.low,'soon',p.soon,'expired',p.expired),'status',p.display_status)
      order by p.normalized_name,p.id) from page p),'[]'::jsonb),
    'total',(select count(*)::integer from filtered),'limit',p_limit,'offset',p_offset,'as_of',as_of
  ) into result;
  return result;
end;
$$;

create function public.get_my_shopping_list(
  p_list_id uuid default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; selected_id uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset not between 0 and 5000 then
    raise exception 'La página de compras no es válida.' using errcode='22023';
  end if;
  if p_list_id is null then
    select l.id into selected_id from public.shopping_lists l
      where l.owner_user_id=actor and l.status='active' order by l.updated_at desc,l.id desc limit 1;
  else
    select l.id into selected_id from public.shopping_lists l where l.id=p_list_id and l.owner_user_id=actor;
    if selected_id is null then raise exception 'La lista no existe.' using errcode='P0002'; end if;
  end if;
  with chosen as materialized (
    select l.* from public.shopping_lists l where l.id=selected_id and l.owner_user_id=actor
  ), mine as materialized (
    select i.*,to_jsonb(u) as unit_row from chosen l join public.shopping_items i on i.list_id=l.id
      left join public.units u on u.id=i.unit_id
  ), page as (
    select * from mine order by created_at,id offset p_offset limit p_limit
  )
  select jsonb_build_object(
    'list',(select to_jsonb(l) from chosen l),
    'items',coalesce((select jsonb_agg((to_jsonb(p)-'unit_row') || jsonb_build_object(
      'unit_detail',case when p.unit_row is null then null else p.unit_row end,
      'sources',coalesce((select jsonb_agg(to_jsonb(s) order by s.id) from public.shopping_item_sources s where s.shopping_item_id=p.id),'[]'::jsonb)
    ) order by p.created_at,p.id) from page p),'[]'::jsonb),
    'total',(select count(*)::integer from mine),'limit',p_limit,'offset',p_offset
  ) into result;
  return result;
end;
$$;

create function public.get_my_shopping_lists(
  p_status text default null,
  p_limit integer default 30,
  p_offset integer default 0
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset not between 0 and 5000
    or (p_status is not null and p_status not in ('all','active','archived')) then
    raise exception 'Los filtros de listas no son válidos.' using errcode='22023';
  end if;
  with mine as materialized (
    select l.* from public.shopping_lists l where l.owner_user_id=actor
      and (p_status is null or p_status='all' or l.status=p_status)
  ), page as (
    select * from mine order by updated_at desc,id desc offset p_offset limit p_limit
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(p) order by p.updated_at desc,p.id desc) from page p),'[]'::jsonb),
    'total',(select count(*)::integer from mine),'limit',p_limit,'offset',p_offset
  ) into result;
  return result;
end;
$$;

revoke all on function public.get_my_pantry(text,text,text,integer,integer) from public,anon,service_role;
revoke all on function public.get_my_shopping_list(uuid,integer,integer) from public,anon,service_role;
revoke all on function public.get_my_shopping_lists(text,integer,integer) from public,anon,service_role;
grant execute on function public.get_my_pantry(text,text,text,integer,integer) to authenticated;
grant execute on function public.get_my_shopping_list(uuid,integer,integer) to authenticated;
grant execute on function public.get_my_shopping_lists(text,integer,integer) to authenticated;

commit;
