-- LOCAL ISOLATED DATABASE ONLY. Seed a catalog row for concurrency probes.
insert into public.user_roles(user_id,role)
values ('11111111-1111-1111-1111-111111111111','ADMIN')
on conflict (user_id) do update set role=excluded.role;
insert into public.account_status(user_id,active)
values ('11111111-1111-1111-1111-111111111111',true)
on conflict (user_id) do update set active=true;
insert into public.categories(id,name,normalized_name,active,is_deleted)
values ('cccccccc-cccc-cccc-cccc-cccccccccccc','Race category','race category',true,false)
on conflict (id) do nothing;
