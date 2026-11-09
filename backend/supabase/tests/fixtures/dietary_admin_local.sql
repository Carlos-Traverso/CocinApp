-- LOCAL ISOLATED DATABASE ONLY. Extend the synthetic audit action constraint.
alter table public.admin_audit_log drop constraint if exists admin_audit_log_action_check;
alter table public.admin_audit_log add constraint admin_audit_log_action_check check (action in (
  'user.created','user.name_updated','user.role_changed','user.activated','user.deactivated',
  'catalog.core_saved','catalog.recipes_saved','catalog.category_saved','catalog.unit_saved','catalog.ingredient_saved',
  'catalog.recipe_saved','catalog.recipe_duplicated','catalog.recipe_flags_changed',
  'catalog.dietary_tag_saved','catalog.ingredient_dietary_tags_saved'
));
