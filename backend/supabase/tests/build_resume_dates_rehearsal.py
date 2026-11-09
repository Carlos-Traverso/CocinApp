"""Build a complete rollback rehearsal of recipe reads, resume and date previews."""
import re
import subprocess
import sys
from pathlib import Path

tests = Path(__file__).resolve().parent
root = tests.parent
subprocess.run([sys.executable, str(tests / 'build_recipe_read_contract_rehearsal.py')], check=True)
sys.path.insert(0, str(tests))
from translate_table_names import translate

base = (tests / 'recipe_read_contract_rehearsal.sql').read_text(encoding='utf-8')
boundary = "select 'PASS: recipe read contract rehearsal completed; final ROLLBACK is required' as result;"
prefix, separator, _ = base.rpartition(boundary)
if not separator:
    raise SystemExit('Missing rollback boundary in base rehearsal')
parts = [prefix]
for migration, stage in (
    ('202611010011_cooking_resume_read.sql', 'cooking_resume_read.stage.sql'),
    ('202611010012_shopping_dates_suggestions.sql', 'shopping_dates_suggestions.stage.sql'),
):
    sql = (root / 'migrations' / migration).read_text(encoding='utf-8')
    sql = re.sub(r'^\s*begin;\s*', '', sql, count=1, flags=re.I)
    sql = re.sub(r'commit;\s*$', '', sql, count=1, flags=re.I)
    parts.extend([sql, translate((tests / stage).read_text(encoding='utf-8'))])
parts.append("select 'PASS: cooking resume and selected-date shopping verified; full script includes ROLLBACK' as result;\nrollback;\n")
(tests / 'resume_dates_rehearsal.sql').write_text('\n'.join(parts), encoding='utf-8')
