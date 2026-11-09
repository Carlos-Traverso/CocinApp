"""Generate one rollback-only schema + personal RPC regression script."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
schema = (root / 'migrations/202610300002_add_relational_domain_tables.sql').read_text(encoding='utf-8').rsplit('commit;', 1)[0]
rpcs = (root / 'migrations/202610300003_personal_write_rpcs.sql').read_text(encoding='utf-8').replace('begin;', '', 1).rsplit('commit;', 1)[0]
stage = (root / 'tests/personal_write_rpcs.stage.sql').read_text(encoding='utf-8')
(root / 'tests/personal_write_rpcs_rehearsal.sql').write_text(
    '-- PERSONAL RPC REHEARSAL: run whole file as postgres. Keep final ROLLBACK.\n'
    + schema.replace('begin;', "begin;\nset local lock_timeout='5s';\nset local statement_timeout='120s';", 1)
    + rpcs + stage + '\nrollback;\n', encoding='utf-8')

# Only the ephemeral local cluster uses this committed synthetic installation.
admin_source = (root / 'migrations/202610170004_remove_mfa_admin_requirement.sql').read_text(encoding='utf-8')
admin_active = admin_source[admin_source.index('create or replace function public.admin_set_user_active'):admin_source.index('create or replace function public.admin_set_user_role')]
(root / 'tests/fixtures/personal_rpc_concurrency_install.sql').write_text(
    '-- LOCAL ISOLATED DATABASE ONLY. Not a Supabase deployment script.\n'
    + (root / 'migrations/202610300002_add_relational_domain_tables.sql').read_text(encoding='utf-8')
    + (root / 'migrations/202610300003_personal_write_rpcs.sql').read_text(encoding='utf-8')
    + admin_active, encoding='utf-8')
