-- LOCAL ISOLATED DATABASE ONLY. Synthetic ingredients and tags for lock tests.
insert into auth.users(id,banned_until) values('33333333-3333-3333-3333-333333333333',null)
on conflict(id) do nothing;
insert into public.user_roles(user_id,role) values('22222222-2222-2222-2222-222222222222','ADMIN'),('33333333-3333-3333-3333-333333333333','USER')
on conflict(user_id) do update set role=excluded.role;
insert into public.account_status(user_id,active) values('22222222-2222-2222-2222-222222222222',true),('33333333-3333-3333-3333-333333333333',true)
on conflict(user_id) do update set active=true;
insert into public.categories(id,name,normalized_name) values('cccccccc-cccc-cccc-cccc-cccccccccccc','Dietary race','dietary race') on conflict(id) do nothing;
insert into public.units(id,name,abbreviation,dimension) values('dddddddd-dddd-dddd-dddd-dddddddddddd','Race gram','drg','mass') on conflict(id) do nothing;
insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values
 ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','Dietary race ingredient','dietary race ingredient','cccccccc-cccc-cccc-cccc-cccccccccccc','dddddddd-dddd-dddd-dddd-dddddddddddd')
 on conflict(id) do nothing;
insert into public.dietary_tags(id,tag_key,label,description,active) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','race-tag','Race tag','',true) on conflict(id) do nothing;
