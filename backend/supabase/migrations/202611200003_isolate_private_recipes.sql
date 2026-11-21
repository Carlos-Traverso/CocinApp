begin;

-- The direct Data API must enforce the same privacy boundary as the recipe RPCs.
create or replace function public.recipe_is_visible(target_recipe_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.recetas r
    where r.id = target_recipe_id and r.active and not r.is_deleted
      and (r.owner_user_id = (select auth.uid())
        or (r.recipe_source = 'official' and r.owner_user_id is null
          and (r.publication_status = 'published' or (select public.current_app_role()) = 'ADMIN')))
      and (select public.current_account_is_active())
  );
$$;

create or replace function public.recipe_is_manageable(target_recipe_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.recetas r
    where r.id = target_recipe_id
      and (r.owner_user_id = (select auth.uid())
        or (r.recipe_source = 'official' and r.owner_user_id is null
          and (select public.current_app_role()) = 'ADMIN'))
      and (select public.current_account_is_active())
  );
$$;

alter policy recipes_read_visible on public.recetas
  using (active and not is_deleted and (owner_user_id = (select auth.uid())
    or (recipe_source = 'official' and owner_user_id is null and publication_status = 'published'))
    and (select public.current_account_is_active()));

alter policy recipes_admin_all on public.recetas
  using (recipe_source = 'official' and owner_user_id is null
    and (select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()))
  with check (recipe_source = 'official' and owner_user_id is null
    and (select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()));

commit;
