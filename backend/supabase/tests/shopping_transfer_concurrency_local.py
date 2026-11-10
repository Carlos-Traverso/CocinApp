"""LOCAL ONLY: concurrent retries of one shopping-to-pantry transfer."""
import argparse
import os
from pathlib import Path
import subprocess
import threading
import time
import uuid

A = '11111111-1111-1111-1111-111111111111'
LIST = '55555555-5555-5555-5555-555555555555'
ITEM = '77777777-7777-7777-7777-777777777777'
UNIT = '33333333-3333-3333-3333-333333333333'
KEY = '88888888-8888-8888-8888-888888888888'


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
    prefix = 'cocinapp_transfer_test_' + uuid.uuid4().hex[:10]
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
            self.reader = threading.Thread(target=self.read, daemon=True)
            self.reader.start()
            self.send(f"set application_name='{self.name}'; set statement_timeout='8s'; " + query)

        def read(self):
            for line in self.process.stdout:
                self.lines.append(line)

        def send(self, query):
            self.process.stdin.write(query + '\n')
            self.process.stdin.flush()

        def finish(self):
            if self.process.poll() is None:
                self.send('\\q')
            code = self.process.wait(timeout=10)
            self.reader.join(timeout=1)
            output = ''.join(self.lines)
            if code:
                raise AssertionError('Local transfer session failed: ' + output[-1000:])
            return output

    def await_blocked(session):
        deadline = time.monotonic() + 7
        while time.monotonic() < deadline:
            if session.process.poll() is not None:
                session.reader.join(timeout=1)
                raise AssertionError('Retry exited before blocking: ' + ''.join(session.lines)[-1000:])
            if sql(f"select count(*) from pg_stat_activity where application_name='{session.name}' and wait_event_type='Lock';") == '1':
                return
            time.sleep(0.04)
        raise AssertionError('Concurrent retry did not wait on the in-flight transfer')

    identity = ("begin; set local role authenticated; "
                f"select set_config('request.jwt.claim.sub','{A}',true); "
                f"select set_config('request.jwt.claims','{{\"sub\":\"{A}\",\"role\":\"authenticated\"}}',true); ")
    try:
        if sql(f"select count(*) from auth.users where id='{A}';") != '1':
            raise AssertionError('Synthetic local Auth account required')
        if sql('select (select count(*) from public.shopping_lists)+(select count(*) from public.pantry_receipts);') != '0':
            raise AssertionError('An empty isolated transfer schema is required')
        sql(f"insert into public.account_status(user_id,active) values('{A}',true) on conflict(user_id) do update set active=true; "
            f"insert into public.user_roles(user_id,role) values('{A}','USER') on conflict(user_id) do update set role='USER'; "
            f"insert into public.categories(id,name,normalized_name) values('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Concurrent synthetic','concurrent synthetic'); "
            f"insert into public.units(id,name,abbreviation,dimension) values('{UNIT}','Concurrent unit','conc-u','count');")
        setup = (identity + f"select (public.create_my_shopping_list('{LIST}','Concurrent transfer',null)).version; "
                 f"select (public.put_my_shopping_item('{LIST}', '{{\"id\":\"{ITEM}\",\"name_snapshot\":\"Concurrent item\",\"category_snapshot\":\"Concurrent synthetic\",\"quantity\":2,\"unit_id\":\"{UNIT}\",\"checked\":true,\"source\":\"manual\",\"sources\":[{{\"source\":\"manual\"}}]}}'::jsonb,1)).version; commit;")
        sql(setup)
        transfer = f"select 'receipt='||(public.transfer_my_shopping_to_pantry('{LIST}',array['{ITEM}']::uuid[],'{KEY}',2)).id;"
        first = Session('first', identity + transfer)
        deadline = time.monotonic() + 7
        while time.monotonic() < deadline and not any('(' in line for line in first.lines):
            if first.process.poll() is not None:
                raise AssertionError('First transfer exited early: ' + ''.join(first.lines)[-1000:])
            time.sleep(0.04)
        second = Session('retry', identity + transfer + 'commit;')
        await_blocked(second)
        first.send('commit;')
        first_output = first.finish()
        second_output = second.finish()
        receipt_ids = [line.strip().removeprefix('receipt=')
                       for line in (first_output + '\n' + second_output).splitlines()
                       if line.strip().startswith('receipt=')]
        if len(receipt_ids) != 2 or receipt_ids[0] != receipt_ids[1]:
            raise AssertionError('Concurrent retry did not return the same receipt: ' + repr(receipt_ids))
        if sql(f"select count(*)=1 and exists(select 1 from public.pantry_items where user_id='{A}' and name='Concurrent item' and quantity=2) from public.pantry_receipts where owner_user_id='{A}' and idempotency_key='{KEY}';") != 't':
            raise AssertionError('Concurrent retry duplicated the receipt or pantry addition')
        print('PASS: concurrent idempotent transfer retry serializes and applies once')
    finally:
        for session in sessions:
            if session.process.poll() is None:
                session.process.kill()
                session.process.wait(timeout=3)
            session.reader.join(timeout=1)


if __name__ == '__main__':
    main()
