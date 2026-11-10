-- LOCAL ISOLATED DATABASE ONLY. Synthetic administrators for race checks.
alter table public.admin_audit_log drop constraint if exists admin_audit_log_action_check;
alter table public.admin_audit_log add constraint admin_audit_log_action_check check (action in (
  'user.created','user.name_updated','user.role_changed','user.activated','user.deactivated',
  'catalog.core_saved','catalog.recipes_saved','catalog.category_saved','catalog.unit_saved','catalog.ingredient_saved',
  'catalog.recipe_saved','catalog.recipe_duplicated','catalog.recipe_flags_changed',
  'catalog.dietary_tag_saved','catalog.ingredient_dietary_tags_saved','nutrition.config_published'
));
insert into auth.users(id,banned_until) values('33333333-3333-3333-3333-333333333333',null) on conflict(id) do nothing;
insert into public.user_roles(user_id,role) values
 ('22222222-2222-2222-2222-222222222222','ADMIN'),('33333333-3333-3333-3333-333333333333','ADMIN')
on conflict(user_id) do update set role='ADMIN';
insert into public.account_status(user_id,active) values
 ('22222222-2222-2222-2222-222222222222',true),('33333333-3333-3333-3333-333333333333',true)
on conflict(user_id) do update set active=true;
