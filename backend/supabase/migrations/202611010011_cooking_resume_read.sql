begin;

-- Resolve one open cooking session by recipe identity. Cooking sessions do not
-- have updated_at, so “most recent” means latest started_at, then UUID order.
-- The recipe lookup intentionally includes archived/inactive rows: an existing
-- snapshot remains resumable after its source recipe is archived.
create function public.get_my_open_cooking_session(
  p_recipe_id uuid default null,
  p_legacy_recipe_id text default null
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid;
  resolved_recipe_id uuid;
  session_id uuid;
begin
  actor := public.lock_my_relational_account();
  if (p_recipe_id is null) = (p_legacy_recipe_id is null)
     or p_legacy_recipe_id is not null
       and (length(trim(p_legacy_recipe_id)) = 0 or length(p_legacy_recipe_id) > 500) then
    raise exception 'Indicá un único identificador de receta válido.' using errcode = '22023';
  end if;

  if p_recipe_id is not null then
    resolved_recipe_id := p_recipe_id;
  else
    select r.id into resolved_recipe_id
      from public.recetas r where r.legacy_id = p_legacy_recipe_id;
    if not found then return null; end if;
  end if;

  select s.id into session_id
    from public.sesiones_cocina s
   where s.owner_user_id = actor
     and s.recipe_id = resolved_recipe_id
     and s.finished_at is null
   order by s.started_at desc, s.id desc
   limit 1;
  if not found then return null; end if;

  -- Keep payload fields and timer deadline calculations in one canonical RPC.
  return public.get_my_cooking_session(session_id);
end;
$$;

revoke all on function public.get_my_open_cooking_session(uuid,text) from public, anon;
grant execute on function public.get_my_open_cooking_session(uuid,text) to authenticated;

commit;
