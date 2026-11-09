"""Build a single rollback-only rehearsal from the seven-table legacy baseline."""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
tests = root / 'tests'
subprocess.run([sys.executable, str(tests / 'build_table_rename_rehearsal.py')], check=True)
sys.path.insert(0, str(tests))
from translate_table_names import translate

base = (tests / 'table_rename_rehearsal.sql').read_text(encoding='utf-8')
migration = (root / 'migrations/202611010010_recipe_read_contract.sql').read_text(encoding='utf-8')
stage = translate((tests / 'recipe_read_contract.stage.sql').read_text(encoding='utf-8'))
migration = re.sub(r'^begin;\s*', '', migration, count=1, flags=re.I)
migration = re.sub(r'commit;\s*$', '', migration, count=1, flags=re.I)
base = re.sub(
    r"select 'PASS: table rename rehearsal completed; final ROLLBACK is required' as result;\s*rollback;\s*$",
    '-- Install the post-rename recipe read API and exercise it against the staged legacy baseline.\n'
    + migration + '\n' + stage
    + "\nselect 'PASS: recipe read contract rehearsal completed; final ROLLBACK is required' as result;\nrollback;\n",
    base,
    flags=re.I,
)
if 'PASS: recipe read contract rehearsal completed' not in base:
    raise SystemExit('Could not locate the generated rehearsal rollback boundary')
(tests / 'recipe_read_contract_rehearsal.sql').write_text(base, encoding='utf-8')
