"""LOCAL ONLY: overlapping planner/shopping transactions with synthetic accounts.

The caller installs schema 300002 and RPCs 300003/300004/300005 in an isolated
cluster and starts/stops it. No remote host or connection URL is accepted.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import threading
import time
import uuid

A = '11111111-1111-1111-1111-111111111111'
B = '22222222-2222-2222-2222-222222222222'
UNIT = '33333333-3333-3333-3333-333333333333'
RECIPE = '44444444-4444-4444-4444-444444444444'
LIST_A = '55555555-5555-5555-5555-555555555555'
LIST_B = '66666666-6666-6666-6666-666666666666'
ITEM = '77777777-7777-7777-7777-777777777777'


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
    sessions = []
    prefix = 'cocinapp_plan_shop_test_' + uuid.uuid4().hex[:10]

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

    def save_week(portions):
        slots = json.dumps([{'meal_date': '2026-10-26', 'meal_shift': 'lunch',
                             'recipe_id': RECIPE, 'portions': portions}])
        return f"select (public.save_my_meal_plan(date '2026-10-26','{slots}'::jsonb,0)).version;"

    def create_list(list_id):
        return f"select (public.create_my_shopping_list('{list_id}','Synthetic concurrent list',null)).version;"

    def put_item(list_id, label, quantity):
        item = json.dumps({'id': ITEM, 'name_snapshot': label, 'quantity': quantity,
                           'unit_id': UNIT, 'source': 'manual', 'sources': [{'source': 'manual'}]})
        return f"select (public.put_my_shopping_item('{list_id}','{item}'::jsonb,1)).version;"

    def reset_domains():
        sql(f"delete from public.pantry_receipt_items; delete from public.pantry_receipts; "
            f"delete from public.shopping_lists where owner_user_id in ('{A}','{B}'); "
            f"delete from public.meal_plans where owner_user_id in ('{A}','{B}');")

    try:
        # Refuse non-fixture databases even if they happen to listen on loopback.
        if sql(f"select (select count(*) from auth.users)||':'||count(*) from auth.users where id in ('{A}','{B}');") != '2:2':
            raise AssertionError('Only the two synthetic local Auth accounts are permitted')
        if sql('select (select count(*) from public.recipes)+(select count(*) from public.units)+(select count(*) from public.meal_plans)+(select count(*) from public.shopping_lists);') != '0':
            raise AssertionError('An empty newly installed local domain schema is required')
        sql(f"update auth.users set banned_until=null where id in ('{A}','{B}'); "
            f"insert into public.account_status(user_id,active) values('{A}',true),('{B}',true) "
            "on conflict(user_id) do update set active=true; "
            f"insert into public.user_roles(user_id,role) values('{A}','USER'),('{B}','USER') "
            "on conflict(user_id) do update set role=excluded.role; "
            f"insert into public.units(id,name,abbreviation,dimension) values('{UNIT}','Synthetic count','test-u','count'); "
            f"insert into public.recipes(id,recipe_source,title,total_minutes,portions,difficulty,publication_status) "
            f"values('{RECIPE}','official','Synthetic concurrent recipe',1,1,'easy','published');")

        # Same owner/week/version: second transaction waits, then must reject stale CAS.
        first = Session('week_first', identity(A) + save_week(1))
        await_state(first, False)
        second = Session('week_second', identity(A) + save_week(2) + 'commit;')
        await_state(second, True)
        first.send('commit;')
        first.finish()
        second.finish('40001')
        if sql(f"select p.version||':'||s.portions from public.meal_plans p join public.meal_plan_slots s on s.plan_id=p.id where p.owner_user_id='{A}';") != '1:1':
            raise AssertionError('Stale simultaneous plan save overwrote committed content')

        # Two simultaneous explicit creates serialize and leave one active list.
        reset_domains()
        first = Session('list_first', identity(A) + create_list(LIST_A))
        await_state(first, False)
        second = Session('list_second', identity(A) + create_list(LIST_B) + 'commit;')
        await_state(second, True)
        first.send('commit;')
        first.finish()
        second.finish()
        if sql(f"select count(*) from public.shopping_lists where owner_user_id='{A}' and status='active';") != '1':
            raise AssertionError('Concurrent creates left more than one active list')
        if sql(f"select status||':'||version from public.shopping_lists where id='{LIST_A}';") != 'archived:2':
            raise AssertionError('First list was not archived/versioned after the second create')
        if sql(f"select status||':'||version from public.shopping_lists where id='{LIST_B}';") != 'active:1':
            raise AssertionError('Second list is not the sole new active list')

        # A colliding UUID from B must not overwrite A's uncommitted item or sources.
        reset_domains()
        sql(identity(A) + create_list(LIST_A) + 'commit;')
        sql(identity(B) + create_list(LIST_B) + 'commit;')
        first = Session('item_owner_a', identity(A) + put_item(LIST_A, 'Synthetic A purchase', 2))
        await_state(first, False)
        second = Session('item_owner_b', identity(B) + put_item(LIST_B, 'Synthetic B purchase', 9) + 'commit;')
        await_state(second, True)
        first.send('commit;')
        first.finish()
        second.finish('42501')
        if sql(f"select list_id||':'||name_snapshot||':'||quantity::numeric from public.shopping_items where id='{ITEM}';") != LIST_A + ':Synthetic A purchase:2.0000':
            raise AssertionError('Cross-account UUID collision overwrote item data')
        if sql(f"select count(*) from public.shopping_item_sources where shopping_item_id='{ITEM}' and source='manual';") != '1':
            raise AssertionError('Cross-account UUID collision changed source links')
        if sql(f"select version from public.shopping_lists where id='{LIST_A}';") != '2':
            raise AssertionError('Successful item save did not advance its own list version')
        if sql(f"select version||':'||(select count(*) from public.shopping_items where list_id='{LIST_B}') from public.shopping_lists where id='{LIST_B}';") != '1:0':
            raise AssertionError('Rejected collision changed the other list or its version')
        print('PASS: concurrent weekly CAS, single active shopping list, and cross-account item-UUID collision verified locally')
    finally:
        for session in sessions:
            if session.process.poll() is None:
                session.process.kill()
                session.process.wait(timeout=3)
            session.reader.join(timeout=1)


if __name__ == '__main__':
    main()
