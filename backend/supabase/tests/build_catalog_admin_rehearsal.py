"""Build a rollback-only rehearsal from the production migrations."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
migrations = (
    '202610300003_personal_write_rpcs.sql', '202610300004_planning_write_rpcs.sql',
    '202610300005_shopping_write_rpcs.sql', '202610300006_shopping_transfer_rpcs.sql',
    '202610300007_shopping_suggestions_rpc.sql', '202610310001_pantry_write_rpcs.sql',
    '202610310002_cooking_session_rpcs.sql', '202610310003_cooking_finish_rpcs.sql',
    '202610310004_cooking_queries_history_rpcs.sql', '202610310005_catalog_admin_rpcs.sql',
)
schema = (root / 'migrations/202610300002_add_relational_domain_tables.sql').read_text(encoding='utf-8').rsplit('commit;', 1)[0]
rpcs = ''.join((root / 'migrations' / name).read_text(encoding='utf-8').replace('begin;', '', 1).rsplit('commit;', 1)[0] for name in migrations)
stage = (root / 'tests/catalog_admin.stage.sql').read_text(encoding='utf-8')
# One request, as in the SQL Editor. Auth, roles, and admin_audit_log are real
# project dependencies and are intentionally never synthesized in this file.
parts = [schema.replace('begin;', "begin;\nset local lock_timeout='5s';\nset local statement_timeout='120s';", 1), rpcs, stage, '\nrollback;\n']
(root / 'tests/catalog_admin_rehearsal.sql').write_text('\n'.join(parts), encoding='utf-8')
(root / 'tests/fixtures/catalog_admin_local.sql').write_text(
    '-- LOCAL ISOLATED DATABASE ONLY. Add-on after the shared relational bootstrap.\n'
    '-- Models the real admin audit table shape/action constraint; no Auth or helper mocks.\n'
    + """create table public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default clock_timestamp(),
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null check (action in (
    'user.created','user.name_updated','user.role_changed','user.activated','user.deactivated',
    'catalog.core_saved','catalog.recipes_saved'
  )),
  target_user_id uuid references auth.users(id) on delete set null,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object')
);
alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from public, anon, authenticated;
""", encoding='utf-8')

(root / "tests/fixtures/catalog_admin_schema_local.sql").write_text("-- LOCAL ISOLATED DATABASE ONLY. Not a Supabase deployment script.\n" + schema + rpcs + "\ncommit;\n", encoding="utf-8")
