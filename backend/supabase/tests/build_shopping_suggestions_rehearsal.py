"""Build standalone rollback-only shopping suggestion preview rehearsal."""
from pathlib import Path
root = Path(__file__).resolve().parent.parent
names = ['202610300002_add_relational_domain_tables.sql', '202610300003_personal_write_rpcs.sql',
         '202610300004_planning_write_rpcs.sql', '202610300005_shopping_write_rpcs.sql',
         '202610300007_shopping_suggestions_rpc.sql']
parts = [(root / 'migrations' / name).read_text(encoding='utf-8-sig').replace('begin;', '', 1).rsplit('commit;', 1)[0] for name in names]
(root / 'tests/shopping_suggestions_rehearsal.sql').write_text(
    '-- SHOPPING SUGGESTIONS: execute the COMPLETE file as postgres; retain ROLLBACK.\n'
    "begin;\nset local lock_timeout='5s';\nset local statement_timeout='120s';\n"
    + '\n'.join(parts) + (root / 'tests/shopping_suggestions.stage.sql').read_text(encoding='utf-8-sig')
    + '\nrollback;\n', encoding='utf-8')
