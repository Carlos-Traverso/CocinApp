begin;

-- Remove only the additional MFA gates introduced by migration 003.
drop policy if exists "Admin actions require MFA" on public.catalog_core;
drop policy if exists "Admin actions require MFA" on public.shared_recipes;
drop function if exists public.current_admin_mfa_verified();

-- Restore the role-only authorization from migration 002 while preserving
-- its transaction lock and last-active-admin protections.
create or replace function public.admin_list_users()
returns table(email text, display_name text, role text, active boolean)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo una cuenta administradora puede consultar los usuarios.' using errcode = '42501';
  end if;
  return query select users.email::text,
    coalesce(nullif(trim(profile.value ->> 'name'), ''),
      nullif(trim(coalesce(users.raw_user_meta_data ->> 'name', users.raw_user_meta_data ->> 'full_name')), ''),
      split_part(users.email, '@', 1))::text,
    coalesce(roles.role, 'USER')::text,
    coalesce(status.active, true) and (users.banned_until is null or users.banned_until <= now())
  from auth.users as users
  left join public.user_roles as roles on roles.user_id = users.id
  left join public.account_status as status on status.user_id = users.id
  left join public.personal_data as profile on profile.user_id = users.id and profile.data_key = 'profile'
  where users.email is not null order by users.created_at desc;
end;
$$;
revoke all on function public.admin_list_users() from public, anon;
grant execute on function public.admin_list_users() to authenticated;

create or replace function public.admin_set_user_active(target_user_id uuid, new_active boolean)
returns void language plpgsql volatile security definer set search_path = ''
as $$
declare target_role text; target_is_active boolean; active_admin_count bigint;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La operación requiere aislamiento READ COMMITTED.' using errcode = '25000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if (select auth.uid()) is null or (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo una cuenta administradora puede cambiar el estado de una cuenta.' using errcode = '42501';
  end if;
  if target_user_id is null or new_active is null then
    raise exception 'La cuenta y el estado son obligatorios.' using errcode = '22023';
  end if;
  if target_user_id = (select auth.uid()) and not new_active then
    raise exception 'No podés desactivar tu propia cuenta.' using errcode = '42501';
  end if;
  select coalesce(roles.role, 'USER'), coalesce(status.active, true)
      and (users.banned_until is null or users.banned_until <= now())
    into target_role, target_is_active
    from auth.users as users
    left join public.user_roles as roles on roles.user_id = users.id
    left join public.account_status as status on status.user_id = users.id
    where users.id = target_user_id;
  if not found then raise exception 'No existe la cuenta indicada.' using errcode = 'P0002'; end if;
  if target_role = 'ADMIN' and target_is_active and not new_active then
    select count(*) into active_admin_count from auth.users as users
      join public.user_roles as roles on roles.user_id = users.id
      left join public.account_status as status on status.user_id = users.id
      where roles.role = 'ADMIN' and coalesce(status.active, true)
        and (users.banned_until is null or users.banned_until <= now());
    if active_admin_count <= 1 then
      raise exception 'No se puede desactivar al último administrador activo.' using errcode = '42501';
    end if;
  end if;
  insert into public.account_status(user_id, active, updated_at) values (target_user_id, new_active, now())
    on conflict (user_id) do update set active = excluded.active, updated_at = excluded.updated_at;
end;
$$;
revoke all on function public.admin_set_user_active(uuid, boolean) from public, anon;
grant execute on function public.admin_set_user_active(uuid, boolean) to authenticated;

create or replace function public.admin_set_user_role(target_user_id uuid, new_role text)
returns void language plpgsql volatile security definer set search_path = ''
as $$
declare previous_role text; target_is_active boolean; active_admin_count bigint;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La operación requiere aislamiento READ COMMITTED.' using errcode = '25000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if (select auth.uid()) is null or (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo una cuenta administradora puede cambiar roles.' using errcode = '42501';
  end if;
  if target_user_id is null or new_role is null or new_role not in ('USER', 'ADMIN') then
    raise exception 'La cuenta o el rol solicitado no es válido.' using errcode = '22023';
  end if;
  if target_user_id = (select auth.uid()) then
    raise exception 'No podés cambiar tu propio rol desde esta cuenta.' using errcode = '42501';
  end if;
  select coalesce(roles.role, 'USER'), coalesce(status.active, true)
      and (users.banned_until is null or users.banned_until <= now())
    into previous_role, target_is_active
    from auth.users as users
    left join public.user_roles as roles on roles.user_id = users.id
    left join public.account_status as status on status.user_id = users.id
    where users.id = target_user_id;
  if not found then raise exception 'No existe la cuenta indicada.' using errcode = 'P0002'; end if;
  if previous_role = 'ADMIN' and new_role = 'USER' and target_is_active then
    select count(*) into active_admin_count from auth.users as users
      join public.user_roles as roles on roles.user_id = users.id
      left join public.account_status as status on status.user_id = users.id
      where roles.role = 'ADMIN' and coalesce(status.active, true)
        and (users.banned_until is null or users.banned_until <= now());
    if active_admin_count <= 1 then
      raise exception 'No se puede quitar el rol al último administrador activo.' using errcode = '42501';
    end if;
  end if;
  insert into public.user_roles(user_id, role, updated_at) values (target_user_id, new_role, now())
    on conflict (user_id) do update set role = excluded.role, updated_at = excluded.updated_at;
end;
$$;
revoke all on function public.admin_set_user_role(uuid, text) from public, anon;
grant execute on function public.admin_set_user_role(uuid, text) to authenticated;

commit;
