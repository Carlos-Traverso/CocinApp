"""LOCAL ONLY: deterministic overlapping transactions against synthetic accounts.

Requires the relational schema, personal RPC migration, and admin_set_user_active.
The caller starts/stops an isolated cluster. Never accepts a remote host or URL.
"""
import argparse
import os
from pathlib import Path
import subprocess
import threading
import time
import uuid

A = '11111111-1111-1111-1111-111111111111'
B = '22222222-2222-2222-2222-222222222222'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--psql', required=True, type=Path)
    parser.add_argument('--port', type=int, default=55439)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error('A local test port between 1024 and 65535 is required')
    # Prevent ambient PG* variables from selecting a service/remote destination.
    env = {key: value for key, value in os.environ.items() if not key.upper().startswith('PG')}
    env['PGCLIENTENCODING'] = 'UTF8'
    command = [str(args.psql), '-X', '-qAt', '-h', '127.0.0.1', '-p', str(args.port),
               '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
    sessions = []
    prefix = 'cocinapp_rpc_test_' + uuid.uuid4().hex[:10]

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
            self.reader = threading.Thread(target=self.read, daemon=True)
            self.reader.start()
            self.send(f"set application_name='{self.name}'; set statement_timeout='8s'; " + query)

        def read(self):
            for line in self.process.stdout:
                self.lines.append(line)

        def send(self, query):
            self.process.stdin.write(query + '\n')
            self.process.stdin.flush()

        def finish(self, expected_error=None):
            if self.process.poll() is None:
                try:
                    self.send('\\q')
                except (BrokenPipeError, OSError):
                    pass
            try:
                code = self.process.wait(timeout=10)
            except subprocess.TimeoutExpired as exc:
                raise AssertionError('Local test session did not finish') from exc
            self.reader.join(timeout=1)
            output = ''.join(self.lines)
            if expected_error:
                if code == 0 or f' {expected_error}:' not in output:
                    raise AssertionError('Expected SQLSTATE ' + expected_error + ', received: ' + output[-1000:])
            elif code != 0:
                raise AssertionError('Local test session failed: ' + output[-1000:])

    def await_state(session, blocked):
        deadline = time.monotonic() + 7
        while time.monotonic() < deadline:
            if session.process.poll() is not None:
                session.reader.join(timeout=1)
                raise AssertionError('Session exited before expected lock state: ' + ''.join(session.lines)[-1000:])
            predicate = "wait_event_type='Lock'" if blocked else "state='idle in transaction'"
            if sql(f"select count(*) from pg_stat_activity where application_name='{session.name}' and {predicate};") == '1':
                return
            time.sleep(0.04)
        raise AssertionError('Expected overlapping transaction lock state was not observed')

    def identity(user):
        return ("begin; set local role authenticated; "
                f"select set_config('request.jwt.claim.sub','{user}',true); "
                f"select set_config('request.jwt.claims','{{\"sub\":\"{user}\",\"role\":\"authenticated\"}}',true); ")

    def save(label, version):
        return (f"select (public.save_my_profile('{{\"display_name\":\"{label}\"}}'::jsonb,"
                f"array[]::text[],{version})).version;")

    def reset():
        sql(f"update auth.users set banned_until=null where id in ('{A}','{B}'); "
            f"insert into public.account_status(user_id,active) values('{A}',true),('{B}',true) "
            "on conflict(user_id) do update set active=true; "
            f"delete from public.profiles where user_id in ('{A}','{B}');")

    try:
        if sql(f"select count(*) from auth.users where id in ('{A}','{B}');") != '2':
            raise AssertionError('The two synthetic local Auth accounts are required')
        sql(f"insert into public.user_roles(user_id,role) values('{A}','USER'),('{B}','ADMIN') "
            'on conflict(user_id) do update set role=excluded.role;')

        # First save is uncommitted while a second save uses the same version.
        reset()
        first = Session('cas_first', identity(A) + save('CAS first', 0))
        await_state(first, False)
        second = Session('cas_second', identity(A) + save('CAS second', 0) + 'commit;')
        await_state(second, True)
        first.send('commit;')
        first.finish()
        second.finish('40001')
        if sql(f"select version||':'||display_name from public.profiles where user_id='{A}';") != '1:CAS first':
            raise AssertionError('Concurrent stale save overwrote the first profile')

        # A write authorized first retains its locks until commit; revocation waits.
        reset()
        writer = Session('write_first', identity(A) + save('Before revocation', 0))
        await_state(writer, False)
        admin = Session('revoke_second', identity(B) + f"select public.admin_set_user_active('{A}',false); commit;")
        await_state(admin, True)
        writer.send('commit;')
        writer.finish()
        admin.finish()
        if sql(f"select (select count(*) from public.profiles where user_id='{A}')||':'||active from public.account_status where user_id='{A}';") != '1:false':
            raise AssertionError('Write-before-revocation ordering failed')

        # Revocation acquires authorization lock first; queued write must recheck.
        reset()
        admin = Session('revoke_first', identity(B) + f"select public.admin_set_user_active('{A}',false);")
        await_state(admin, False)
        writer = Session('write_second', identity(A) + save('Forbidden after revocation', 0) + 'commit;')
        await_state(writer, True)
        admin.send('commit;')
        admin.finish()
        writer.finish('42501')
        if sql(f"select count(*) from public.profiles where user_id='{A}';") != '0':
            raise AssertionError('Revoked account wrote a profile after waiting')

        # Auth ban updates do not use the app advisory lock, so test the Auth row lock.
        reset()
        ban = Session('ban_first', f"begin; update auth.users set banned_until=now()+interval '1 day' where id='{A}';")
        await_state(ban, False)
        writer = Session('write_after_ban', identity(A) + save('Forbidden after ban', 0) + 'commit;')
        await_state(writer, True)
        ban.send('commit;')
        ban.finish()
        writer.finish('42501')
        if sql(f"select count(*) from public.profiles where user_id='{A}';") != '0':
            raise AssertionError('Banned account wrote a profile after waiting')
        print('PASS: concurrent profile CAS, both account-revocation orderings, and Auth-ban recheck verified locally')
    finally:
        for session in sessions:
            if session.process.poll() is None:
                session.process.kill()
                session.process.wait(timeout=3)
            session.reader.join(timeout=1)


if __name__ == '__main__':
    main()
