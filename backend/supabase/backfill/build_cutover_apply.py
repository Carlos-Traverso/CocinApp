"""Build the permanent schema and data cutover from the validated rehearsal."""
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent
subprocess.run([sys.executable, str(root / 'build_cutover_data_rehearsal.py')], check=True)
source = (root / 'cutover_data_rehearsal.sql').read_text(encoding='utf-8')

def mask_sql(text: str) -> str:
    """Blank SQL comments, quoted literals, and dollar bodies, retaining offsets."""
    out = list(text)
    i = 0
    n = len(text)
    while i < n:
        if text.startswith('--', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j): out[k] = ' '
            i = j
        elif text.startswith('/*', i):
            depth, j = 1, i + 2
            while j < n and depth:
                if text.startswith('/*', j): depth += 1; j += 2
                elif text.startswith('*/', j): depth -= 1; j += 2
                else: j += 1
            for k in range(i, j):
                if out[k] != '\n': out[k] = ' '
            i = j
        elif text[i] == '$':
            m = re.match(r'\$[A-Za-z_0-9]*\$', text[i:])
            if m:
                tag = m.group(0); end = text.find(tag, i + len(tag))
                j = n if end < 0 else end + len(tag)
                for k in range(i, j):
                    if out[k] != '\n': out[k] = ' '
                i = j
            else: i += 1
        elif text[i] == "'" or text[i] == '"':
            quote = text[i]; j = i + 1
            while j < n:
                if text[j] == quote:
                    if j + 1 < n and text[j + 1] == quote: j += 2; continue
                    j += 1; break
                if text[j] == '\\' and quote == "'": j += 2
                else: j += 1
            for k in range(i, min(j, n)):
                if out[k] != '\n': out[k] = ' '
            i = j
        else: i += 1
    return ''.join(out)

masked = mask_sql(source)
controls = [(m.group(1).lower(), m.start(1)) for m in re.finditer(r'(?im)^\s*(begin|commit|rollback)\s*;', masked)]
if [kind for kind, _ in controls] != ['begin', 'rollback'] or controls[-1][1] != masked.lower().rfind('rollback;'):
    raise SystemExit('Rehearsal transaction boundary changed; review manually before generating permanent cutover')

rename = (root.parent / 'migrations/202611010009_rename_tables_spanish.sql').read_text(encoding='utf-8')
renames = re.findall(r'(?im)^alter\s+table\s+public\.([a-z_]+)\s+rename\s+to\s+([a-z_]+)\s*;', rename)
if len(renames) != 36 or len({a for a, _ in renames}) != 36 or len({b for _, b in renames}) != 36:
    raise SystemExit('Expected table rename inventory changed; inspect cutover migration')
legacy = {'pantry_items': 'articulos_despensa', 'personal_data': 'datos_personales',
          'user_roles': 'roles_usuario', 'catalog_core': 'catalogo_base',
          'shared_recipes': 'recetas_compartidas', 'account_status': 'estado_cuenta',
          'admin_audit_log': 'registro_auditoria'}
if dict(renames[:7]) != legacy:
    raise SystemExit('Legacy table inventory/order changed; review permanent-cutover guards')

preflight = """\n-- Permanent cutover guard: only the rehearsed legacy state is accepted.\n"""
preflight += """do $cutover_preflight$\ndeclare n integer;\nbegin\n  select count(*) into n from pg_class c join pg_namespace s on s.oid=c.relnamespace\n    where s.nspname='public' and c.relkind in ('r','p') and c.relname = any(array[\n"""
preflight += ',\n'.join("      '%s'" % old for old, _ in renames) + """\n    ]);\n  if n <> 7 then raise exception 'Estado previo inválido: se esperaban exactamente las 7 tablas legacy.'; end if;\n  select count(*) into n from pg_class c join pg_namespace s on s.oid=c.relnamespace\n    where s.nspname='public' and c.relkind in ('r','p') and c.relname = any(array[\n"""
preflight += ',\n'.join("      '%s'" % new for _, new in renames) + """\n    ]);\n  if n <> 0 then raise exception 'Estado previo inválido: ya existen tablas finales; no se permite reejecutar.'; end if;\nend;\n$cutover_preflight$;\n"""
preflight += """\n-- Prevent concurrent writes while preserving the exact legacy row baseline.\n"""
preflight += "create temporary table cocinapp_cutover_source_counts(table_name text primary key, row_count bigint not null) on commit drop;\n"
preflight += 'lock table ' + ', '.join(f'public.{old}' for old, _ in renames[:7]) + ' in access exclusive mode;\n'
for old, _ in renames[:7]:
    preflight += f"insert into cocinapp_cutover_source_counts values ('{old}', (select count(*) from public.{old}));\n"

final_check = """\ndo $cutover_final_check$\ndeclare n integer; old_name text; new_name text; old_count bigint; new_count bigint;\nbegin\n  select count(*) into n from pg_class c join pg_namespace s on s.oid=c.relnamespace\n    where s.nspname='public' and c.relkind in ('r','p') and c.relname = any(array[\n"""
final_check += ',\n'.join("      '%s'" % new for _, new in renames) + """\n    ]);\n  if n <> 36 then raise exception 'Validación final fallida: no aparecen las 36 tablas del esquema final.'; end if;\n  if exists (select 1 from pg_class c join pg_namespace s on s.oid=c.relnamespace\n      where s.nspname='public' and c.relkind in ('r','p') and c.relname = any(array[\n"""
final_check += ',\n'.join("        '%s'" % old for old, _ in renames[:7]) + """\n      ])) then raise exception 'Validación final fallida: quedan nombres de tablas legacy.'; end if;\n"""
for old, new in renames[:7]:
    final_check += f"  select row_count into old_count from cocinapp_cutover_source_counts where table_name='{old}';\n  select count(*) into new_count from public.{new};\n  if old_count is distinct from new_count then raise exception 'Validación final fallida: cambió la cantidad de filas de {old}.'; end if;\n"
final_check += """end;\n$cutover_final_check$;\n\ncommit;\nselect 'PASS: permanent cutover committed; 36 final tables verified and 7 legacy tables renamed with source row counts preserved.' as result;\n"""

body = source[:controls[-1][1]]
body = re.sub(r'(?m)^-- DATA REHEARSAL ONLY:.*\n', '', body, count=1)
body = re.sub(r'(?m)^-- FULL REHEARSAL:.*\n', '', body, count=1)
body = re.sub(r'(?m)^-- REHEARSAL ONLY\..*\n', '', body)
body = re.sub(r'(?m)^-- The final ROLLBACK preserves.*\n', '', body)
body = re.sub(r'(?m)^-- Private staging objects belong.*\n', '', body)
body = re.sub(r'(?m)^--.*\bROLLBACK\b.*\n', '', body, flags=re.I)
body = re.sub(r'(?m)^-- This script enables domain RLS itself\..*\n', '', body)
body = re.sub(r'(?m)^-- Version 20261030-03: private transaction-scoped staging; no TEMP tables\s*\n',
              '-- Version 20261030-03: private transaction-scoped staging.\n', body)
body = re.sub(r"(?m)^select 'PASS: legacy data conversion verified; full script includes ROLLBACK' as result;\s*\n", '', body)
body = body.replace("set local statement_timeout = '120s';", "set local statement_timeout = '120s';", 1)
body = body.replace("set local statement_timeout = '120s';", "set local statement_timeout = '120s';\n" + preflight, 1)
# Keep the validated rehearsal body intact; the stronger ACCESS EXCLUSIVE locks are
# already held before schema changes and are compatible with its later SHARE locks.
body = body.rstrip() + '\n' + final_check

header = """-- PERMANENT CUTOVER: runs the validated schema and data conversion and commits once.\n-- Run only against the original 7-table legacy schema after the validated rehearsal PASS.\n-- Close the app and pause writes before starting. Do not rerun after a successful PASS.\n-- Any SQL error before COMMIT aborts the transaction; do not retry blindly.\nbegin;\nset local lock_timeout = '5s';\nset local statement_timeout = '120s';\n"""
# Keep precisely one top-level BEGIN and the single transaction-scoped setup.
body = re.sub(r'(?im)^begin;\s*\n', '', body, count=1)
body = re.sub(r'(?im)^set local lock_timeout = \'5s\';\s*\n', '', body, count=1)
body = re.sub(r'(?im)^set local statement_timeout = \'120s\';\s*\n', '', body, count=1)
output = root / 'cutover_apply.sql'
output.write_text(header + body, encoding='utf-8')
print('Generated permanent cutover_apply.sql')
