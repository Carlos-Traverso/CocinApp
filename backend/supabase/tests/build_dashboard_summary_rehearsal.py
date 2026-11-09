"""Build a rollback-only dashboard summary rehearsal from the local RPC stack."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
migrations = (
    '202610300003_personal_write_rpcs.sql', '202610300004_planning_write_rpcs.sql',
    '202610300005_shopping_write_rpcs.sql',
    '202610300006_shopping_transfer_rpcs.sql', '202610300007_shopping_suggestions_rpc.sql',
    '202610310001_pantry_write_rpcs.sql', '202610310002_cooking_session_rpcs.sql',
    '202610310003_cooking_finish_rpcs.sql', '202610310004_cooking_queries_history_rpcs.sql',
    '202610310005_catalog_admin_rpcs.sql', '202611010001_recipe_admin_rpcs.sql',
    '202611010002_dietary_admin_rpcs.sql', '202611010003_nutrition_config_rpcs.sql',
    '202611010004_recipe_discovery_rpcs.sql', '202611010006_personal_read_rpcs.sql',
    '202611010007_inventory_read_rpcs.sql', '202611010008_dashboard_summary_rpc.sql',
)
schema = (root / 'migrations/202610300002_add_relational_domain_tables.sql').read_text(encoding='utf-8').rsplit('commit;', 1)[0]
rpcs = ''.join((root / 'migrations' / name).read_text(encoding='utf-8').replace('begin;', '', 1).rsplit('commit;', 1)[0] for name in migrations)
stage = (root / 'tests/dashboard_summary.stage.sql').read_text(encoding='utf-8')
(root / 'tests/dashboard_summary_rehearsal.sql').write_text(
    '-- DASHBOARD SUMMARY REHEARSAL: run the whole file as postgres; final ROLLBACK is included.\n'
    + schema.replace('begin;', "begin;\nset local lock_timeout='5s';\nset local statement_timeout='120s';", 1)
    + rpcs + stage + '\nrollback;\n', encoding='utf-8')
