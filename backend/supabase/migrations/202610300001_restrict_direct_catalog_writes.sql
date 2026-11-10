begin;

-- Shared catalog writes must go through the version-aware RPCs. Restore the
-- intended client grants explicitly in case an earlier setup granted them.
revoke insert, update, delete on table public.catalog_core from public, anon, authenticated;
revoke insert, update, delete on table public.shared_recipes from public, anon, authenticated;

grant select on table public.catalog_core to authenticated;
grant select on table public.shared_recipes to authenticated;

grant execute on function public.admin_save_catalog_core(integer, jsonb) to authenticated;
grant execute on function public.admin_save_shared_recipes(integer, jsonb) to authenticated;

commit;
