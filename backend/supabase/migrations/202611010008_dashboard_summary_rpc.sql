begin;

-- Dashboard summary composes the existing personal read APIs while holding
-- the same account lock used by relational writers. Nested volatile RPCs may
-- use their own statement snapshots; this follows the app writer lock protocol.
create function public.get_my_dashboard_summary(
  p_day date default current_date,
  p_recent_limit integer default 4
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid;
  result jsonb;
  week_start date;
  plan_payload jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_day is null or not isfinite(p_day) or p_day < date '1900-01-01' or p_day > date '9999-12-31'
    or p_recent_limit is null or p_recent_limit not between 1 and 20 then
    raise exception 'Los parámetros del resumen no son válidos.' using errcode='22023';
  end if;

  week_start := p_day - (extract(isodow from p_day)::integer - 1);
  plan_payload := public.get_my_meal_plan(week_start);

  select jsonb_build_object(
    'as_of', p_day,
    'profile', public.get_my_profile(),
    'pantry', jsonb_build_object(
      'total', count(*),
      'low', count(*) filter (where p.quantity = 0 or (p.minimum > 0 and p.quantity > 0 and p.quantity < p.minimum)),
      'empty', count(*) filter (where p.quantity = 0),
      'soon', count(*) filter (where p.expiry between p_day and p_day + 3),
      'expired', count(*) filter (where p.expiry < p_day)
    ),
    'favorites', jsonb_build_object(
      'total', (select count(*)::integer from public.favorite_recipes f where f.user_id=actor),
      'available', (select count(*)::integer
        from public.favorite_recipes f join public.recipes r on r.id=f.recipe_id
        where f.user_id=actor and r.active and not r.is_deleted
          and ((r.recipe_source='official' and r.publication_status='published')
            or coalesce(r.owner_user_id=actor,false)))
    ),
    'shopping', (select jsonb_build_object(
      'active_list_id', l.id,
      'version', l.version,
      'pending_items', count(i.id) filter (where not i.checked and i.transferred_at is null),
      'checked_items', count(i.id) filter (where i.checked and i.transferred_at is null),
      'transferred_items', count(i.id) filter (where i.transferred_at is not null)
    ) from public.shopping_lists l left join public.shopping_items i on i.list_id=l.id
      where l.owner_user_id=actor and l.status='active' group by l.id,l.version),
    'today_plan', jsonb_build_object(
      'plan', plan_payload->'plan',
      'slots', coalesce((select jsonb_agg(s.value order by s.ordinality)
        from jsonb_array_elements(coalesce(plan_payload->'slots','[]'::jsonb)) with ordinality s(value,ordinality)
        where (s.value->>'meal_date')::date=p_day), '[]'::jsonb)
    ),
    'recent_preparations', public.get_my_cooking_history(p_recent_limit)
  ) into result
  from public.pantry_items p
  where p.user_id=actor;

  result := jsonb_set(result,'{shopping}',coalesce(nullif(result->'shopping','null'::jsonb),
    jsonb_build_object('active_list_id',null,'version',null,'pending_items',0,'checked_items',0,'transferred_items',0)));
  return result;
end;
$$;

revoke all on function public.get_my_dashboard_summary(date,integer) from public,anon,service_role;
grant execute on function public.get_my_dashboard_summary(date,integer) to authenticated;

commit;
