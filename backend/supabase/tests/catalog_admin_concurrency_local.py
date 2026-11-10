"""LOCAL ONLY: verify catalog version serialization and role-revocation ordering."""
import argparse
import os
from pathlib import Path
import subprocess
import threading
import time
import uuid

ADMIN = '11111111-1111-1111-1111-111111111111'
ENTITY = 'cccccccc-cccc-cccc-cccc-cccccccccccc'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--psql', required=True, type=Path)
    parser.add_argument('--port', type=int, default=55439)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error('A local test port between 1024 and 65535 is required')
    env = {key: value for key, value in os.environ.items() if not key.upper().startswith('PG')}
    env['PGCLIENTENCODING'] = 'UTF8'
    command = [str(args.psql), '-X', '-qAt', '-h', '127.0.0.1', '-p', str(args.port),
               '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
    prefix = 'cocinapp_catalog_test_' + uuid.uuid4().hex[:10]
    sessions = []

    def sql(query):
        result = subprocess.run(command, input=query, text=True, encoding='utf-8',
                                capture_output=True, timeout=8, env=env)
        if result.returncode:
            raise AssertionError('Local control query failed: ' + result.stderr[-1000:])
        return result.stdout.strip()

    class Session:
        def __init__(self, suffix, query):
            self.name = prefix + '_' + suffix
            self.lines = []
            self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=subprocess.STDOUT, text=True, encoding='utf-8', env=env)
            sessions.append(self)
            self.reader = threading.Thread(target=lambda: self.lines.extend(self.process.stdout), daemon=True)
            self.reader.start()
            self.send(f"set application_name='{self.name}'; set statement_timeout='8s'; " + query)

        def send(self, query):
            self.process.stdin.write(query + '\n')
            self.process.stdin.flush()

        def finish(self, expected_error=None):
            if self.process.poll() is None:
                self.send('\\q')
            code = self.process.wait(timeout=10)
            self.reader.join(timeout=1)
            output = ''.join(self.lines)
            if expected_error:
                if code == 0 or f' {expected_error}:' not in output:
                    raise AssertionError('Expected SQLSTATE ' + expected_error + ': ' + output[-1000:])
            elif code != 0:
                raise AssertionError('Local SQL session failed: ' + output[-1000:])

    def await_state(session, blocked):
        deadline = time.monotonic() + 7
        while time.monotonic() < deadline:
            if session.process.poll() is not None:
                session.reader.join(timeout=1)
                raise AssertionError('Session exited early: ' + ''.join(session.lines)[-1000:])
            predicate = "wait_event_type='Lock'" if blocked else "state='idle in transaction'"
            if sql(f"select count(*) from pg_stat_activity where application_name='{session.name}' and {predicate};") == '1':
                return
            time.sleep(.04)
        raise AssertionError('Expected lock state was not observed')

    def identity():
        return ("begin; set local role authenticated; "
                f"select set_config('request.jwt.claim.sub','{ADMIN}',true); ")

    def save(name, version):
        return ("select public.admin_put_category(" +
                f"'{{\"id\":\"{ENTITY}\",\"name\":\"{name}\",\"active\":true,\"is_deleted\":false}}'::jsonb,{version});")

    try:
        sql(f"update public.user_roles set role='ADMIN' where user_id='{ADMIN}'; "
            f"update public.account_status set active=true where user_id='{ADMIN}'; "
            f"update public.categories set name='Race category',normalized_name='race category',version=1 where id='{ENTITY}';")
        first = Session('cas_first', identity() + save('CAS first', 1))
        await_state(first, False)
        second = Session('cas_second', identity() + save('CAS second', 1) + 'commit;')
        await_state(second, True)
        first.send('commit;')
        first.finish()
        second.finish('40001')
        if sql(f"select version||':'||name from public.categories where id='{ENTITY}';") != '2:CAS first':
            raise AssertionError('Concurrent stale catalog save overwrote the first mutation')

        # The RPC holds the exclusive global role lock; trusted role revocation
        # uses the matching exclusive lock and must wait for that transaction.
        sql(f"update public.user_roles set role='ADMIN' where user_id='{ADMIN}'; "
            f"update public.categories set name='Race category',normalized_name='race category',version=1 where id='{ENTITY}';")
        writer = Session('write_first', identity() + save('Before role revoke', 1))
        await_state(writer, False)
        revoker = Session('role_revoke',
                          f"begin; select pg_advisory_xact_lock(74539,1); "
                          f"update public.user_roles set role='USER' where user_id='{ADMIN}'; commit;")
        await_state(revoker, True)
        writer.send('commit;')
        writer.finish()
        revoker.finish()
        if sql(f"select version||':'||name from public.categories where id='{ENTITY}';") != '2:Before role revoke':
            raise AssertionError('Authorized write did not serialize before role revocation')

        # Revocation wins the global lock; a waiting RPC must recheck its role.
        sql(f"update public.user_roles set role='ADMIN' where user_id='{ADMIN}'; "
            f"update public.categories set name='Race category',normalized_name='race category',version=1 where id='{ENTITY}';")
        revoker = Session('revoke_first',
                          f"begin; select pg_advisory_xact_lock(74539,1); "
                          f"update public.user_roles set role='USER' where user_id='{ADMIN}';")
        await_state(revoker, False)
        writer = Session('write_after_revoke', identity() + save('Must fail', 1) + 'commit;')
        await_state(writer, True)
        revoker.send('commit;')
        revoker.finish()
        writer.finish('42501')
        if sql(f"select version||':'||name from public.categories where id='{ENTITY}';") != '1:Race category':
            raise AssertionError('Catalog RPC wrote after role revocation')
        print('PASS: catalog CAS and both trusted role-revocation orderings verified locally')
    finally:
        for session in sessions:
            if session.process.poll() is None:
                session.process.kill()
                session.process.wait(timeout=3)
            session.reader.join(timeout=1)


if __name__ == '__main__':
    main()
