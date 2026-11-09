-- LOCAL ISOLATED DATABASE ONLY. Synthetic rows for recipe RPC lock tests.
insert into auth.users(id,banned_until) values('33333333-3333-3333-3333-333333333333',null)
on conflict(id) do nothing;
insert into public.user_roles(user_id,role) values('22222222-2222-2222-2222-222222222222','ADMIN')
on conflict(user_id) do update set role='ADMIN';
insert into public.user_roles(user_id,role) values('33333333-3333-3333-3333-333333333333','USER')
on conflict(user_id) do update set role='USER';
insert into public.account_status(user_id,active) values('22222222-2222-2222-2222-222222222222',true)
on conflict(user_id) do update set active=true;
insert into public.account_status(user_id,active) values('33333333-3333-3333-3333-333333333333',true)
on conflict(user_id) do update set active=true;
insert into public.categories(id,name,normalized_name) values
 ('cccccccc-cccc-cccc-cccc-cccccccccccc','Recipe race','recipe race') on conflict(id) do nothing;
insert into public.units(id,name,abbreviation,dimension) values
 ('dddddddd-dddd-dddd-dddd-dddddddddddd','Race gram','rg','mass') on conflict(id) do nothing;
insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values
 ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','Race ingredient','recipe race ingredient',
  'cccccccc-cccc-cccc-cccc-cccccccccccc','dddddddd-dddd-dddd-dddd-dddddddddddd') on conflict(id) do nothing;
insert into public.recipes(id,recipe_source,title,total_minutes,portions,difficulty,publication_status)
values('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','official','Recipe race',5,1,'easy','published') on conflict(id) do nothing;
insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,position) values
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',1,'dddddddd-dddd-dddd-dddd-dddddddddddd',1) on conflict(id) do nothing;
insert into public.recipe_steps(id,recipe_id,position,instruction) values
 ('ffffffff-ffff-ffff-ffff-ffffffffffff','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',1,'Cook race recipe') on conflict(id) do nothing;
