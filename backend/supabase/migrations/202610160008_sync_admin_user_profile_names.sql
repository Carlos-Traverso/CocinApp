begin;

-- Show the editable profile name in Admin > Users, falling back to Auth metadata
-- for accounts that have not saved a profile yet.
create or replace function public.admin_list_users()
returns table (
  email text,
  display_name text,
  role text,
  active boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo una cuenta administradora puede consultar los usuarios.'
      using errcode = '42501';
  end if;

  return query
    select
      users.email::text,
      coalesce(
        nullif(trim(profile.value ->> 'name'), ''),
        nullif(trim(coalesce(users.raw_user_meta_data ->> 'name', users.raw_user_meta_data ->> 'full_name')), ''),
        split_part(users.email, '@', 1)
      )::text,
      coalesce(roles.role, 'USER')::text,
      (users.banned_until is null or users.banned_until <= now())
    from auth.users as users
    left join public.user_roles as roles on roles.user_id = users.id
    left join public.personal_data as profile
      on profile.user_id = users.id and profile.data_key = 'profile'
    where users.email is not null
    order by users.created_at desc;
end;
$$;

revoke all on function public.admin_list_users() from public, anon;
grant execute on function public.admin_list_users() to authenticated;

commit;
