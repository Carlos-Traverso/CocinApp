-- Run manually in Supabase SQL Editor after migration 004.
-- Replace the email below with an existing CocinAPP account's email.
do $$
declare
  account_email text := 'REEMPLAZAR_CON_TU_CORREO';
  account_id uuid;
begin
  select id into account_id from auth.users
    where lower(email) = lower(trim(account_email));
  if account_id is null then
    raise exception 'No existe una cuenta registrada con ese correo. Revisá el correo o registrala primero en CocinAPP.';
  end if;

  insert into public.user_roles (user_id, role, updated_at)
    values (account_id, 'ADMIN', now())
    on conflict (user_id) do update set role = excluded.role, updated_at = excluded.updated_at;
end;
$$;

select users.email, roles.role
  from public.user_roles roles
  join auth.users users on users.id = roles.user_id
  where roles.role = 'ADMIN';
