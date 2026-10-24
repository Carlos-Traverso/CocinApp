begin;

-- Read Auth state on every database request, including requests with a JWT
-- issued before the account was banned. Never expose auth.users to clients.
create or replace function public.current_account_is_active()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from auth.users
    where id = (select auth.uid())
      and (banned_until is null or banned_until <= now())
  );
$$;
revoke all on function public.current_account_is_active() from public, anon;
grant execute on function public.current_account_is_active() to authenticated;

-- Explicit check also protects calls from SECURITY DEFINER admin functions,
-- whose privileged context can bypass user_roles RLS.
create or replace function public.current_app_role()
returns text
language sql stable security invoker
set search_path = ''
as $$
  select case when public.current_account_is_active() then coalesce(
    (select role from public.user_roles where user_id = (select auth.uid())),
    'USER'
  ) else 'USER' end;
$$;
revoke all on function public.current_app_role() from public, anon;
grant execute on function public.current_app_role() to authenticated;

-- Restrictive policies AND with the existing ownership/administrator policies.
-- They never grant access on their own and cover reads and all mutations.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'pantry_items', 'personal_data', 'user_roles', 'catalog_core', 'shared_recipes'
  ] loop
    execute format('drop policy if exists "Active accounts only" on public.%I', table_name);
    execute format(
      'create policy "Active accounts only" on public.%I as restrictive for all to authenticated using ((select public.current_account_is_active())) with check ((select public.current_account_is_active()))',
      table_name
    );
  end loop;
end;
$$;

create or replace function public.admin_set_user_role(target_user_id uuid, new_role text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  previous_role text;
  target_is_active boolean;
  active_admin_count integer;
begin
  -- Recheck authorization after serialization: the previous transaction may
  -- have removed this caller's administrator role while this call waited.
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if (select auth.uid()) is null or (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo una cuenta administradora puede cambiar roles.' using errcode = '42501';
  end if;
  if new_role is null or new_role not in ('USER', 'ADMIN') then
    raise exception 'El rol solicitado no es válido.' using errcode = '22023';
  end if;
  if target_user_id = (select auth.uid()) then
    raise exception 'No podés cambiar tu propio rol desde esta cuenta.' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users where id = target_user_id) then
    raise exception 'No existe la cuenta indicada.' using errcode = 'P0002';
  end if;
  select coalesce(roles.role, 'USER'),
    (users.banned_until is null or users.banned_until <= now())
    into previous_role, target_is_active
    from auth.users as users
    left join public.user_roles as roles on roles.user_id = users.id
    where users.id = target_user_id;
  if previous_role = 'ADMIN' and new_role = 'USER' and target_is_active then
    select count(*)::integer into active_admin_count
      from auth.users as users
      join public.user_roles as roles on roles.user_id = users.id
      where roles.role = 'ADMIN' and (users.banned_until is null or users.banned_until <= now());
    if active_admin_count <= 1 then
      raise exception 'No se puede quitar el rol al último administrador activo.' using errcode = '42501';
    end if;
  end if;
  insert into public.user_roles (user_id, role, updated_at)
    values (target_user_id, new_role, now())
    on conflict (user_id) do update set role = excluded.role, updated_at = excluded.updated_at;
end;
$$;
revoke all on function public.admin_set_user_role(uuid, text) from public, anon;
grant execute on function public.admin_set_user_role(uuid, text) to authenticated;

commit;
