"""Build a rollback-only permission rehearsal and local Auth bootstrap."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
schema = (root / 'migrations/202610300002_add_relational_domain_tables.sql').read_text(encoding='utf-8').rsplit('commit;', 1)[0]
stage = (root / 'tests/relational_permissions.stage.sql').read_text(encoding='utf-8')
(root / 'tests/relational_permissions_rehearsal.sql').write_text(
    '-- Run whole file as postgres. Synthetic tests; no permanent changes.\n'
    + schema.replace('begin;', "begin;\nset local lock_timeout='5s';\nset local statement_timeout='120s';", 1)
    + stage + '\nrollback;\n', encoding='utf-8')

# Keep local permission helpers identical to the application's real definitions.
roles = (root / 'migrations/202610160004_create_user_roles.sql').read_text(encoding='utf-8')
active = (root / 'migrations/202610170002_atomic_account_status.sql').read_text(encoding='utf-8').split('create or replace function public.admin_set_user_active', 1)[0] + 'commit;\n'
security = (root / 'migrations/202610170001_security_account_access.sql').read_text(encoding='utf-8')
role_helper = security[security.index('create or replace function public.current_app_role()'):security.index('-- Restrictive policies')]
fixture = """-- LOCAL ONLY: simulated Auth, actual application helper definitions below.
alter table auth.users add column banned_until timestamptz, add column created_at timestamptz default now();
insert into auth.users(id) values('22222222-2222-2222-2222-222222222222');
create or replace function auth.uid() returns uuid language sql stable as $$
 select coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid
$$;
grant usage on schema auth to authenticated, anon;
""" + roles + active + role_helper
(root / 'tests/fixtures/relational_permissions_local.sql').write_text(fixture, encoding='utf-8')
