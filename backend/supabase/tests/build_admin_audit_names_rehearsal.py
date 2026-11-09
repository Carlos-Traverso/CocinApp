"""Append the admin audit-name migration and stage to the full rollback rehearsal."""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
tests = root / 'tests'
subprocess.run([sys.executable, str(tests / 'build_profile_admin_rehearsal.py')], check=True)
base = (tests / 'profile_admin_rehearsal.sql').read_text(encoding='utf-8')
boundary = "select 'PASS: profile admin contract verified; full script includes ROLLBACK' as result;\nrollback;"
prefix, separator, _ = base.rpartition(boundary)
if not separator:
    raise SystemExit('Missing profile-admin rollback boundary')

migration = (root / 'migrations/202611070001_admin_audit_profile_names.sql').read_text(encoding='utf-8')
migration = re.sub(r'^\s*begin;\s*', '', migration, count=1, flags=re.I)
migration = re.sub(r'commit;\s*$', '', migration, count=1, flags=re.I)
stage = (tests / 'admin_audit_names.stage.sql').read_text(encoding='utf-8')
result = (prefix + '\n-- Stage profile-backed audit actor and target names.\n'
          + migration + '\n' + stage
          + "\nselect 'PASS: audit profile names verified; full script includes ROLLBACK' as result;\nrollback;\n")
(tests / 'admin_audit_names_rehearsal.sql').write_text(result, encoding='utf-8')
