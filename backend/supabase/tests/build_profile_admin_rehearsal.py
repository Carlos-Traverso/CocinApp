"""Append the admin profile-name migration/stage to the full post-rename rehearsal."""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
tests = root / 'tests'
subprocess.run([sys.executable, str(tests / 'build_resume_dates_rehearsal.py')], check=True)
base = (tests / 'resume_dates_rehearsal.sql').read_text(encoding='utf-8')
boundary = "select 'PASS: cooking resume and selected-date shopping verified; full script includes ROLLBACK' as result;\nrollback;"
prefix, separator, _ = base.rpartition(boundary)
if not separator:
    raise SystemExit('Missing resume/dates rollback boundary')

migration = (root / 'migrations/202611010013_admin_profile_names.sql').read_text(encoding='utf-8')
migration = re.sub(r'^\s*begin;\s*', '', migration, count=1, flags=re.I)
migration = re.sub(r'commit;\s*$', '', migration, flags=re.I)
stage = (tests / 'admin_profile_names.stage.sql').read_text(encoding='utf-8')
result = (prefix + '\n-- Stage the final administrative profile-name RPC after the renamed schema.\n'
          + migration + '\n' + stage
          + "\nselect 'PASS: profile admin contract verified; full script includes ROLLBACK' as result;\nrollback;\n")
(tests / 'profile_admin_rehearsal.sql').write_text(result, encoding='utf-8')
