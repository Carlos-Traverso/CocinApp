begin;

revoke all on function public.lock_my_relational_account() from service_role;

-- Personal reads use the same account lock protocol as relational writes. Each
-- response is assembled by one SQL statement so its children share a snapshot.
create function public.get_my_profile()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  select jsonb_build_object(
    'profile', (select to_jsonb(p) from public.profiles p where p.user_id=actor),
    'preference_keys', coalesce((
      select jsonb_agg(t.tag_key order by t.tag_key)
      from public.user_dietary_preferences pref
      join public.dietary_tags t on t.id=pref.dietary_tag_id
      where pref.user_id=actor
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

create function public.get_my_favorites(p_limit integer default 30,p_offset integer default 0)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset not between 0 and 5000 then
    raise exception 'La página de favoritos no es válida.' using errcode='22023';
  end if;
  with mine as materialized (
    select f.recipe_id,f.created_at as favorite_created_at,r as recipe,
      (r.id is not null and r.active and not r.is_deleted and
        ((r.recipe_source='official' and r.publication_status='published') or coalesce(r.owner_user_id=actor,false))) as visible
    from public.favorite_recipes f
    left join public.recipes r on r.id=f.recipe_id
    where f.user_id=actor
  ), page as (
    select * from mine order by favorite_created_at desc,recipe_id desc offset p_offset limit p_limit
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'recipe_id',p.recipe_id,'created_at',p.favorite_created_at,'available',p.visible,
      'recipe',case when p.visible then public.recipe_discovery_payload(p.recipe,null)->'recipe' else null end
    ) order by p.favorite_created_at desc,p.recipe_id desc) from page p),'[]'::jsonb),
    'total',(select count(*)::integer from mine),'limit',p_limit,'offset',p_offset
  ) into result;
  return result;
end;
$$;

create function public.get_my_meal_plan(p_week_start date)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_week_start is null or not isfinite(p_week_start) or extract(isodow from p_week_start)<>1 then
    raise exception 'La semana debe comenzar un lunes válido.' using errcode='22023';
  end if;
  select jsonb_build_object(
    'plan',(select to_jsonb(mp) from public.meal_plans mp where mp.owner_user_id=actor and mp.week_start=p_week_start),
    'slots',coalesce((
      select jsonb_agg(
        to_jsonb(s) || jsonb_build_object(
          'available', (r.id is not null and r.active and not r.is_deleted and
            ((r.recipe_source='official' and r.publication_status='published') or coalesce(r.owner_user_id=actor,false))),
          'recipe', case when r.id is not null and r.active and not r.is_deleted and
            ((r.recipe_source='official' and r.publication_status='published') or coalesce(r.owner_user_id=actor,false))
            then public.recipe_discovery_payload(r,null)->'recipe' else null end
        ) order by s.meal_date,
          case s.meal_shift when 'breakfast' then 1 when 'lunch' then 2 when 'snack' then 3 when 'dinner' then 4 end,
          s.position,s.id
      )
      from public.meal_plans mp
      join public.meal_plan_slots s on s.plan_id=mp.id
      left join public.recipes r on r.id=s.recipe_id
      where mp.owner_user_id=actor and mp.week_start=p_week_start
    ),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.get_my_profile() from public,anon,service_role;
revoke all on function public.get_my_favorites(integer,integer) from public,anon,service_role;
revoke all on function public.get_my_meal_plan(date) from public,anon,service_role;
grant execute on function public.get_my_profile() to authenticated;
grant execute on function public.get_my_favorites(integer,integer) to authenticated;
grant execute on function public.get_my_meal_plan(date) to authenticated;

commit;
