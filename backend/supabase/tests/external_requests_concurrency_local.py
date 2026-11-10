"""LOCAL ONLY: exercise external request lifecycle races against PostgreSQL."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import threading
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--psql', required=True, type=Path)
    parser.add_argument('--port', type=int, default=55439)
    args = parser.parse_args()
    env = {key: value for key, value in os.environ.items() if not key.upper().startswith('PG')}
    command = [str(args.psql), '-X', '-qAt', '-h', '127.0.0.1', '-p', str(args.port), '-U', 'postgres',
               '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
    sessions = []
    prefix = 'cocinapp_external_' + uuid.uuid4().hex[:10]

    def sql(query):
        result = subprocess.run(command, input=query, text=True, encoding='utf-8', capture_output=True,
                                timeout=8, env=env)
        if result.returncode:
            raise AssertionError('Local SQL control query failed: ' + result.stderr[-1000:])
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

        def collect(self):
            if self.process.poll() is None:
                self.send('\\q')
            code = self.process.wait(timeout=10)
            self.reader.join(timeout=1)
            return code, ''.join(self.lines)

        def finish(self, expected_error=None):
            code, output = self.collect()
            if expected_error:
                if code == 0 or f' {expected_error}:' not in output:
                    raise AssertionError('Expected SQLSTATE ' + expected_error + ': ' + output[-1000:])
            elif code != 0:
                raise AssertionError('Local SQL session failed: ' + output[-1000:])

        def json_result(self):
            rows = [line.strip() for line in self.lines if line.strip().startswith('{')]
            if len(rows) != 1:
                raise AssertionError('Expected one JSON RPC result: ' + ''.join(self.lines)[-1000:])
            return json.loads(rows[0])

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

    def service(query):
        return "begin; set local role service_role; " + query + ' commit;'

    def owner(actor, query):
        return ("begin; set local role authenticated; "
                f"select set_config('request.jwt.claim.sub','{actor}',true); "
                f"select set_config('request.jwt.claims','{{\"sub\":\"{actor}\",\"role\":\"authenticated\"}}',true); "
                + query + ' commit;')

    try:
        users = sql("select id from auth.users order by id limit 2;").splitlines()
        if len(users) < 2:
            raise AssertionError('Local concurrency fixture requires two Auth users')
        a, b = users
        sql(f"insert into public.account_status(user_id,active) values('{a}',true),('{b}',true) "
            "on conflict(user_id) do update set active=true;")
        sql(f"insert into public.user_roles(user_id,role) values('{a}','USER'),('{b}','USER') "
            "on conflict(user_id) do update set role='USER';")
        collision = str(uuid.uuid4())
        # Queue both owners on one request lock. Exactly one insert can win.
        hold = Session('collision_hold', f"begin; select pg_advisory_xact_lock(hashtextextended('cocinapp.external-request:{collision}',0));")
        await_state(hold, False)
        one = Session('collision_a', service(f"select public.begin_external_request('{a}','{collision}','recipe',null);"))
        await_state(one, True)
        two = Session('collision_b', service(f"select public.begin_external_request('{b}','{collision}','recipe',null);"))
        await_state(two, True)
        hold.send('commit;')
        hold.finish()
        one.finish()
        two.finish('40001')
        if sql(f"select count(*) from public.recipe_generation_requests where id='{collision}';") != '1':
            raise AssertionError('Competing request ID did not produce exactly one row')

        # The same UUID cannot be claimed in both lifecycle tables either.
        cross_kind = str(uuid.uuid4())
        hold = Session('kind_hold', f"begin; select pg_advisory_xact_lock(hashtextextended('cocinapp.external-request:{cross_kind}',0));")
        await_state(hold, False)
        recipe = Session('kind_recipe', service(f"select public.begin_external_request('{a}','{cross_kind}','recipe',null);"))
        await_state(recipe, True)
        receipt_kind = Session('kind_receipt', service(f"select public.begin_external_request('{b}','{cross_kind}','receipt',null);"))
        await_state(receipt_kind, True)
        hold.send('commit;'); hold.finish()
        # The lock queue can choose either kind as the winner.
        recipe_code, recipe_result = recipe.collect()
        receipt_code, receipt_result = receipt_kind.collect()
        recipe_won = ' 40001:' not in recipe_result
        receipt_won = ' 40001:' not in receipt_result
        if recipe_won == receipt_won or (recipe_won and recipe_code != 0) or (receipt_won and receipt_code != 0):
            raise AssertionError('Cross-kind race did not have exactly one winner')
        loser_code, loser_output = (receipt_code, receipt_result) if recipe_won else (recipe_code, recipe_result)
        if loser_code == 0 or ' 40001:' not in loser_output:
            raise AssertionError('Cross-kind loser did not receive SQLSTATE 40001: ' + loser_output[-1000:])
        if sql(f"select (select count(*) from public.recipe_generation_requests where id='{cross_kind}') + "
               f"(select count(*) from public.receipt_recognition_requests where id='{cross_kind}');") != '1':
            raise AssertionError('Cross-kind request ID produced zero or multiple rows')

        same = str(uuid.uuid4())
        hold = Session('same_hold', f"begin; select pg_advisory_xact_lock(hashtextextended('cocinapp.external-request:{same}',0));")
        await_state(hold, False)
        one = Session('same_a', service(f"select public.begin_external_request('{a}','{same}','recipe','model-v1');"))
        await_state(one, True)
        two = Session('same_b', service(f"select public.begin_external_request('{a}','{same}','recipe','model-v1');"))
        await_state(two, True)
        hold.send('commit;')
        hold.finish(); one.finish(); two.finish()
        first_result, second_result = one.json_result(), two.json_result()
        if first_result != second_result:
            raise AssertionError('Identical concurrent begin retries returned different lifecycle metadata')
        if sql(f"select count(*) from public.recipe_generation_requests where id='{same}';") != '1':
            raise AssertionError('Identical begin retries did not retain one row')

        # Queue a begin behind global account coordination, then revoke before commit.
        inactive = str(uuid.uuid4())
        sql(f"insert into auth.users(id,banned_until) values('{inactive}',null); "
            f"insert into public.account_status(user_id,active) values('{inactive}',true);")
        status = Session('revoke_hold', "begin; select pg_advisory_xact_lock(74539,1); "
                         f"update public.account_status set active=false where user_id='{inactive}';")
        await_state(status, False)
        check = Session('revoke_begin', service(f"select public.begin_external_request('{inactive}','{uuid.uuid4()}','recipe',null);"))
        await_state(check, True)
        status.send('commit;'); status.finish(); check.finish('42501')

        # Discard takes the owner actor lock; queue finish behind it before releasing the actor.
        receipt = str(uuid.uuid4())
        sql(service(f"select public.begin_external_request('{a}','{receipt}','receipt',null);"))
        actor_key = f"cocinapp.personal:{a}"
        hold = Session('discard_hold', f"begin; select pg_advisory_xact_lock(hashtextextended('{actor_key}',0));")
        await_state(hold, False)
        discard = Session('discard', owner(a, f"select public.discard_my_receipt_request('{receipt}');"))
        await_state(discard, True)
        finish = Session('finish', service(f"select public.finish_external_request('{a}','{receipt}','receipt','completed',null);"))
        await_state(finish, True)
        hold.send('commit;'); hold.finish(); discard.finish(); finish.finish('40001')
        if sql(f"select status from public.receipt_recognition_requests where id='{receipt}';") != 'discarded':
            raise AssertionError('Discard did not win the queued finish race')
        print('PASS: request ID serialization, idempotent begin timestamps, inactive revocation, and discard/finish race')
    finally:
        for session in sessions:
            if session.process.poll() is None:
                session.process.kill()
                session.process.wait(timeout=5)
                session.reader.join(timeout=1)


if __name__ == '__main__':
    main()
