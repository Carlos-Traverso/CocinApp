"""Build the remote-ready table rename rehearsal with a final ROLLBACK."""
from __future__ import annotations

import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
migration = root / 'migrations/202611010009_rename_tables_spanish.sql'
source = migration.read_text(encoding='utf-8')
source = re.sub(r'^begin;\s*', '', source, count=1, flags=re.I)
source = re.sub(r'commit;\s*$', '', source, count=1, flags=re.I)
pending_migrations = sorted(
    (
        path for path in (root / 'migrations').glob('*.sql')
        if '202610300001_' <= path.name < '202611010009_'
    ),
    key=lambda path: path.name,
)
if len(pending_migrations) != 20:
    raise SystemExit(f'Expected pending application migrations before 009, found {len(pending_migrations)}')
staged_schema = []
for pending in pending_migrations:
    sql = pending.read_text(encoding='utf-8')
    sql = re.sub(r'^begin;\s*', '', sql, count=1, flags=re.I)
    sql = re.sub(r'commit;\s*$', '', sql, count=1, flags=re.I)
    staged_schema.append(f'-- Staged from {pending.name} inside the rehearsal transaction.\n{sql}')
staged_schema_sql = '\n'.join(staged_schema)
mapping = re.findall(r'alter table public\.([a-z_]+) rename to ([a-z_]+);', source, re.I)
if len(mapping) != 36:
    raise SystemExit(f'Expected 36 table renames, found {len(mapping)}')

before_counts = '\n'.join(
    f"insert into rename_rehearsal.row_counts values ('{old}', (select count(*) from public.{old}));"
    for old, _ in mapping
)
presence_checks = '\n'.join(
    f"if to_regclass('public.{old}') is not null or to_regclass('public.{new}') is null then raise exception 'Rename mismatch: {old}'; end if;"
    for old, new in mapping
)
count_checks = '\n'.join(
    f"if (select row_count from rename_rehearsal.row_counts where table_name='{old}') <> (select count(*) from public.{new}) then raise exception 'Row count mismatch: {new}'; end if;"
    for old, new in mapping
)
stale_relation_pattern = 'public\\.(' + '|'.join(re.escape(old) for old, _ in mapping) + ')([^a-z0-9_]|$)'
output = f"""-- TABLE RENAME REHEARSAL: run this complete file as postgres in Supabase SQL Editor.
-- Requires the seven legacy tables only; partial/premature relational installs fail before DDL.
-- All staged migrations, table renames, and checks are rolled back at the end.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
do $preflight_legacy$
declare legacy_names text[] := array['pantry_items','personal_data','user_roles','catalog_core','shared_recipes','account_status','admin_audit_log'];
        relational_names text[] := array[{','.join(repr(old) for old, _ in mapping if old not in {'pantry_items','personal_data','user_roles','catalog_core','shared_recipes','account_status','admin_audit_log'})}];
begin
  if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname=any(legacy_names)) <> 7 then
    raise exception 'Preflight failed: expected all seven legacy application tables';
  end if;
  if exists(select 1 from unnest(relational_names) names(name) where to_regclass('public.'||name) is not null) then
    raise exception 'Preflight failed: relational tables already exist; use the normal migration path instead';
  end if;
end;
$preflight_legacy$;
-- The remote project has only the seven legacy tables. Install pending migrations
-- inside this same transaction so they and the final rename all roll back together.
{staged_schema_sql}
create schema rename_rehearsal;
create table rename_rehearsal.row_counts(table_name text primary key,row_count bigint not null);
{before_counts}
create table rename_rehearsal.relations as
  select oid,relkind,relrowsecurity,relforcerowsecurity from pg_class
  where relnamespace='public'::regnamespace and relkind in ('r','p')
    and relname=any(array[{','.join(repr(old) for old, _ in mapping)}]);
create table rename_rehearsal.columns as
  select c.oid,a.attnum,a.attname,a.atttypid,a.atttypmod,a.attnotnull,a.attidentity,a.attgenerated
  from pg_class c join pg_attribute a on a.attrelid=c.oid
  where c.oid in(select oid from rename_rehearsal.relations) and a.attnum>0 and not a.attisdropped;

{source}

do $verify_rename$
declare i integer;
begin
  if (select count(*) from rename_rehearsal.relations) <> 36 then raise exception 'Expected 36 existing application tables'; end if;
  {presence_checks}
  {count_checks}
  if to_regclass('auth.users') is null then raise exception 'auth.users changed'; end if;
  if exists(select 1 from rename_rehearsal.relations before_row full join
    (select oid,relkind,relrowsecurity,relforcerowsecurity from pg_class where oid in(select oid from rename_rehearsal.relations)) after_row using(oid)
    where before_row.oid is null or after_row.oid is null or
      (before_row.relkind,before_row.relrowsecurity,before_row.relforcerowsecurity) is distinct from
      (after_row.relkind,after_row.relrowsecurity,after_row.relforcerowsecurity)) then raise exception 'Table OID or RLS metadata changed'; end if;
  if exists((select * from rename_rehearsal.columns except select c.oid,a.attnum,a.attname,a.atttypid,a.atttypmod,a.attnotnull,a.attidentity,a.attgenerated from pg_class c join pg_attribute a on a.attrelid=c.oid where c.oid in(select oid from rename_rehearsal.relations) and a.attnum>0 and not a.attisdropped)
    union all (select c.oid,a.attnum,a.attname,a.atttypid,a.atttypmod,a.attnotnull,a.attidentity,a.attgenerated from pg_class c join pg_attribute a on a.attrelid=c.oid where c.oid in(select oid from rename_rehearsal.relations) and a.attnum>0 and not a.attisdropped except select * from rename_rehearsal.columns)) then raise exception 'Table columns changed'; end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and
    p.prosrc ~ '{stale_relation_pattern}') then raise exception 'Stale qualified relation reference remains'; end if;
end;
$verify_rename$;
select 'PASS: table rename rehearsal completed; final ROLLBACK is required' as result;
rollback;
"""
(root / 'tests/table_rename_rehearsal.sql').write_text(output, encoding='utf-8')
