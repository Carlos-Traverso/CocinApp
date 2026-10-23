begin;

-- Keep the original list RPC stable for clients that may still be using it.
-- This search RPC adds actor display names and filters the full event history.
create or replace function public.admin_search_audit_events(p_query text default null, p_limit integer default 100)
returns table (
  id uuid,
  occurred_at timestamptz,
  actor_name text,
  actor_email text,
  action text,
  target_name text,
  target_email text,
  details jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  search_text text := nullif(pg_catalog.btrim(p_query), '');
begin
  if (select auth.uid()) is null or (select public.current_app_role()) <> 'ADMIN'
    or not (select public.current_account_is_active()) then
    raise exception 'Solo un administrador activo puede consultar el historial.' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception 'El límite debe estar entre 1 y 200.' using errcode = '22023';
  end if;
  if search_text is not null and pg_catalog.char_length(search_text) > 120 then
    raise exception 'La búsqueda no puede superar los 120 caracteres.' using errcode = '22023';
  end if;

  return query
  select events.id,
    events.occurred_at,
    coalesce(
      nullif(pg_catalog.btrim(actor_profile.value ->> 'name'), ''),
      nullif(pg_catalog.btrim(actor.raw_user_meta_data ->> 'name'), ''),
      nullif(pg_catalog.btrim(actor.raw_user_meta_data ->> 'full_name'), ''),
      pg_catalog.split_part(actor.email, '@', 1)
    )::text,
    actor.email::text,
    events.action,
    coalesce(
      nullif(pg_catalog.btrim(target_profile.value ->> 'name'), ''),
      nullif(pg_catalog.btrim(target.raw_user_meta_data ->> 'name'), ''),
      nullif(pg_catalog.btrim(target.raw_user_meta_data ->> 'full_name'), ''),
      pg_catalog.split_part(target.email, '@', 1)
    )::text,
    target.email::text,
    events.details
  from public.admin_audit_log as events
  left join auth.users as actor on actor.id = events.actor_user_id
  left join public.personal_data as actor_profile on actor_profile.user_id = actor.id and actor_profile.data_key = 'profile'
  left join auth.users as target on target.id = events.target_user_id
  left join public.personal_data as target_profile on target_profile.user_id = target.id and target_profile.data_key = 'profile'
  where search_text is null
    or coalesce(
      nullif(pg_catalog.btrim(actor_profile.value ->> 'name'), ''),
      nullif(pg_catalog.btrim(actor.raw_user_meta_data ->> 'name'), ''),
      nullif(pg_catalog.btrim(actor.raw_user_meta_data ->> 'full_name'), ''),
      pg_catalog.split_part(actor.email, '@', 1), ''
    ) ilike '%' || search_text || '%'
    or coalesce(actor.email, '') ilike '%' || search_text || '%'
    or coalesce(
      nullif(pg_catalog.btrim(target_profile.value ->> 'name'), ''),
      nullif(pg_catalog.btrim(target.raw_user_meta_data ->> 'name'), ''),
      nullif(pg_catalog.btrim(target.raw_user_meta_data ->> 'full_name'), ''),
      pg_catalog.split_part(target.email, '@', 1), ''
    ) ilike '%' || search_text || '%'
    or coalesce(target.email, '') ilike '%' || search_text || '%'
    or (
      events.action || ' ' || case events.action
        when 'user.created' then 'Creó una cuenta'
        when 'user.name_updated' then 'Cambió el nombre de una cuenta'
        when 'user.role_changed' then 'Cambió el rol de una cuenta'
        when 'user.activated' then 'Activó una cuenta'
        when 'user.deactivated' then 'Desactivó una cuenta'
        when 'catalog.core_saved' then 'Guardó cambios en ingredientes, categorías o unidades'
        when 'catalog.recipes_saved' then 'Guardó cambios en recetas'
        else ''
      end
    ) ilike '%' || search_text || '%'
  order by events.occurred_at desc, events.id desc
  limit p_limit;
end;
$$;

revoke all on function public.admin_search_audit_events(text, integer) from public, anon;
grant execute on function public.admin_search_audit_events(text, integer) to authenticated;

commit;
