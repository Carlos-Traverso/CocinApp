"""Compose a rollback-only data rehearsal from legacy schema to final contracts."""
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent
subprocess.run([sys.executable, str(root / 'build_catalog_rehearsal.py')], check=True)
subprocess.run([sys.executable, str(root / 'build_legacy_shopping_cooking_rehearsal.py')], check=True)
base = (root / 'supabase_validation_rehearsal.sql').read_text(encoding='utf-8')
guard = """  if exists(select 1 from public.personal_data
    where data_key in ('cooking_progress','shopping') and jsonb_array_length(value) > 0) then
    raise exception 'Hay compras o sesiones activas nuevas: requieren su conversor antes de continuar.';
  end if;"""
empty_lists = """  insert into public.shopping_lists(id,owner_user_id,created_at,updated_at)
  select md5('cocinapp:shopping:' || user_id::text)::uuid,user_id,updated_at,updated_at
  from public.personal_data where data_key='shopping';"""
for marker in (guard, empty_lists):
    if base.count(marker) != 1:
        raise SystemExit('Source backfill boundary changed; review composer before proceeding')
    base = base.replace(marker, '-- Delegated to final-schema legacy shopping/cooking converter.', 1)
base = base.rsplit('rollback;', 1)[0]

def body(text):
    text = re.sub(r'^\s*begin;\s*', '', text, count=1, flags=re.I | re.M)
    return re.sub(r'commit;\s*$', '', text, flags=re.I)

migrations = []
for path in sorted((root.parent / 'migrations').glob('*.sql')):
    if path.name < '202610300001_' or path.name == '202610300002_add_relational_domain_tables.sql':
        continue
    migrations.append('-- Migration: ' + path.name + '\n' + body(path.read_text(encoding='utf-8')))
converter = (root / 'legacy_shopping_cooking_rehearsal.sql').read_text(encoding='utf-8')
converter = body(converter).rsplit('rollback;', 1)[0]
# Older history conversion used a display-incompatible snapshot; normalize it from
# the same migration-time recipe catalog, preserving legacyEvent and source data.
match = re.search(r"(select coalesce\(jsonb_agg\(jsonb_build_object\('ingredientId'.*?snapshot:=jsonb_build_object.*?);\s*session_uuid:=", converter, re.S)
if not match:
    raise SystemExit('Active snapshot boundary changed; review historical normalization')
snapshot_sql = match.group(1) + ";"
snapshot_sql = snapshot_sql.replace("item->>'recipeId'", "recipe_row.legacy_id")
normalize_history = """
do $history_snapshot$
declare recipe_row record; snapshot jsonb; ingredient_rows jsonb; step_rows jsonb;
begin
  for recipe_row in select r.* from public.recetas r where exists(
    select 1 from public.sesiones_cocina s where s.recipe_id=r.id and s.finished_at is not null
      and s.recipe_snapshot->>'snapshotOrigin'='migration_catalog') loop
""" + snapshot_sql + """
    update public.sesiones_cocina set recipe_snapshot=recipe_snapshot||snapshot
      where recipe_id=recipe_row.id and finished_at is not null
        and recipe_snapshot->>'snapshotOrigin'='migration_catalog';
  end loop;
  update public.eventos_cocina e set recipe_snapshot=s.recipe_snapshot
    from public.sesiones_cocina s where e.session_id=s.id
      and s.finished_at is not null and e.recipe_snapshot->>'snapshotOrigin'='migration_catalog';
end;
$history_snapshot$;
"""

output = root / 'cutover_data_rehearsal.sql'
output.write_text('-- DATA REHEARSAL ONLY: no fixtures; full execution ends with ROLLBACK.\n' + base + '\n'.join(migrations) + '\n' + normalize_history + '\n' + converter + "\nselect 'PASS: legacy data conversion verified; full script includes ROLLBACK' as result;\nrollback;\n", encoding='utf-8')
print('Generated rollback-only cutover_data_rehearsal.sql')
