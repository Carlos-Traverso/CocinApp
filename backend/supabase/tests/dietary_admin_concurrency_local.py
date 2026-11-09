"""LOCAL ONLY: verify dietary link writes serialize with parent ingredient edits."""
import argparse
import os
from pathlib import Path
import subprocess
import threading
import time
import uuid

ADMIN = '22222222-2222-2222-2222-222222222222'
INGREDIENT = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
TAG = 'race-tag'


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
    prefix = 'cocinapp_dietary_test_' + uuid.uuid4().hex[:10]
    sessions = []

    def sql(query):
        result = subprocess.run(command, input=query, text=True, encoding='utf-8', capture_output=True, timeout=8, env=env)
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

    def identity(actor=ADMIN):
        return ("begin; set local role authenticated; "
                f"select set_config('request.jwt.claim.sub','{actor}',true); "
                f"select set_config('request.jwt.claims','{{\"sub\":\"{actor}\",\"role\":\"authenticated\"}}',true); ")

    try:
        sql(f"update public.ingredients set version=1,name='Dietary race ingredient' where id='{INGREDIENT}'; delete from public.ingredient_dietary_tags where ingredient_id='{INGREDIENT}';")
        replacement = f"select public.admin_save_ingredient_dietary_tags('{INGREDIENT}','[{{\"tag_key\":\"{TAG}\",\"compatibility\":\"unknown\",\"note\":\"first\"}}]'::jsonb,1);"
        first = Session('links_first', identity() + replacement)
        await_state(first, False)
        second = Session('links_second', identity() +
                         f"select public.admin_save_ingredient_dietary_tags('{INGREDIENT}','[]'::jsonb,1); commit;")
        await_state(second, True)
        first.send('commit;')
        first.finish()
        second.finish('40001')
        if sql(f"select i.version||':'||it.note from public.ingredients i join public.ingredient_dietary_tags it on it.ingredient_id=i.id join public.dietary_tags t on t.id=it.dietary_tag_id where i.id='{INGREDIENT}' and t.tag_key='{TAG}';") != '2:first':
            raise AssertionError('Stale concurrent link replacement overwrote the first write')

        # A concurrent core edit advances the same parent version token; the
        # waiting classification replacement must then fail its stale CAS.
        core = Session('core_edit', identity() +
                       f"select public.admin_put_ingredient('{{\"id\":\"{INGREDIENT}\",\"name\":\"Core edit wins\",\"category_id\":\"cccccccc-cccc-cccc-cccc-cccccccccccc\",\"base_unit_id\":\"dddddddd-dddd-dddd-dddd-dddddddddddd\",\"active\":true,\"is_deleted\":false}}'::jsonb,2);")
        await_state(core, False)
        links = Session('links_vs_core', identity() +
                        f"select public.admin_save_ingredient_dietary_tags('{INGREDIENT}','[]'::jsonb,2); commit;")
        await_state(links, True)
        core.send('commit;')
        core.finish()
        links.finish('40001')
        if sql(f"select version||':'||name||':'||(select count(*) from public.ingredient_dietary_tags where ingredient_id='{INGREDIENT}') from public.ingredients where id='{INGREDIENT}';") != '3:Core edit wins:1':
            raise AssertionError('Stale classification edit changed links after a concurrent core edit')

        # An in-flight dietary RPC holds the global advisory lock. Model the
        # trusted operator's role update with that same production lock, then
        # verify a fresh request under the revoked JWT is denied.
        held_write = Session('write_while_admin', identity() +
                             f"select public.admin_save_ingredient_dietary_tags('{INGREDIENT}','[{{\"tag_key\":\"{TAG}\",\"compatibility\":\"unknown\",\"note\":\"first\"}}]'::jsonb,3);")
        await_state(held_write, False)
        demotion = Session('role_demotion',
                           f"begin; select pg_advisory_xact_lock(74539,1); update public.user_roles set role='USER' where user_id='{ADMIN}'; commit;")
        await_state(demotion, True)
        held_write.send('commit;')
        held_write.finish()
        demotion.finish()
        revoked = Session('revoked_admin_write', identity() +
                          f"select public.admin_save_ingredient_dietary_tags('{INGREDIENT}','[]'::jsonb,3); commit;")
        revoked.finish('42501')
        if sql(f"select role from public.user_roles where user_id='{ADMIN}'; select version from public.ingredients where id='{INGREDIENT}';") != 'USER\n3':
            raise AssertionError('Concurrent role demotion did not take effect before subsequent dietary write')
        print('PASS: dietary CAS/core edits serialize and trusted role revocation blocks subsequent same-JWT writes')
    finally:
        for session in sessions:
            if session.process.poll() is None:
                session.process.kill()
                session.process.wait(timeout=3)
            session.reader.join(timeout=1)


if __name__ == '__main__':
    main()
