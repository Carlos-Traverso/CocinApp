"""Generate rollback-only cooking session rehearsal and isolated local install."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
schema = (root / 'migrations/202610300002_add_relational_domain_tables.sql').read_text(encoding='utf-8').rsplit('commit;', 1)[0]
migrations = ('202610300003_personal_write_rpcs.sql','202610300004_planning_write_rpcs.sql',
 '202610300005_shopping_write_rpcs.sql','202610300006_shopping_transfer_rpcs.sql',
 '202610300007_shopping_suggestions_rpc.sql','202610310001_pantry_write_rpcs.sql',
 '202610310002_cooking_session_rpcs.sql')
rpcs = ''.join((root / 'migrations' / name).read_text(encoding='utf-8').replace('begin;', '', 1).rsplit('commit;', 1)[0] for name in migrations)
stage = (root / 'tests/cooking_session.stage.sql').read_text(encoding='utf-8')
(root / 'tests/cooking_session_rehearsal.sql').write_text(
 '-- COOKING SESSION REHEARSAL: run whole file as postgres; keep final ROLLBACK.\n'
 + schema.replace('begin;', "begin;\nset local lock_timeout='5s';\nset local statement_timeout='120s';", 1)
 + rpcs + stage + '\nrollback;\n', encoding='utf-8')
(root / 'tests/fixtures/cooking_session_local.sql').write_text(
 '-- LOCAL ISOLATED DATABASE ONLY. Not a Supabase deployment script.\n' + schema + rpcs + '\ncommit;\n', encoding='utf-8')
