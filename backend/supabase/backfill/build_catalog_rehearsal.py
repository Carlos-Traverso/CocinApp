"""Generate SQL rehearsal from public recipe seed; never reads credentials."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
seed = json.loads((root / 'recipe_seed_v3.json').read_text(encoding='utf-8'))
template = (root / 'catalog_rehearsal.template.sql').read_text(encoding='utf-8')
payload = json.dumps(seed['recipes'], ensure_ascii=False)
assert '$seed$' not in payload
(root / 'catalog_backfill_rehearsal.sql').write_text(
    template.replace('SEED_JSON_PAYLOAD', payload), encoding='utf-8')

# Both stages share one transaction so personal references see staged recipes.
catalog = (root / 'catalog_backfill_rehearsal.sql').read_text(encoding='utf-8')
personal = (root / 'personal_data_rehearsal.sql').read_text(encoding='utf-8')
pantry = (root / 'pantry_reference_rehearsal.sql').read_text(encoding='utf-8')
(root / 'complete_backfill_rehearsal.sql').write_text(
    catalog.rsplit('rollback;', 1)[0] + personal.replace('begin;', '', 1).rsplit('rollback;', 1)[0]
    + pantry.replace('begin;', '', 1).rsplit('rollback;', 1)[0]
    + (root / 'validation_report.sql').read_text(encoding='utf-8') + 'rollback;\n', encoding='utf-8')

# One transaction rehearses schema + conversion and removes all new objects.
schema = (root.parent / 'migrations/202610300002_add_relational_domain_tables.sql').read_text(encoding='utf-8')
combined = (root / 'complete_backfill_rehearsal.sql').read_text(encoding='utf-8')
(root / 'full_validation_rehearsal.sql').write_text(
    '-- FULL REHEARSAL: schema and data changes roll back together. No COMMIT.\n'
    '-- Supabase SQL Editor: choose "Run without RLS" if prompted.\n'
    '-- Version 20261030-03: private transaction-scoped staging; no TEMP tables.\n'
    '-- This script enables domain RLS itself. Keep the final ROLLBACK.\n'
    + schema.rsplit('commit;', 1)[0].replace('begin;', "begin;\nset local lock_timeout = '5s';\nset local statement_timeout = '120s';", 1) + combined.replace('begin;', '', 1), encoding='utf-8')

# Distinct name prevents accidentally reusing the previous editor contents.
(root / 'supabase_validation_rehearsal.sql').write_text(
    (root / 'full_validation_rehearsal.sql').read_text(encoding='utf-8'), encoding='utf-8')
