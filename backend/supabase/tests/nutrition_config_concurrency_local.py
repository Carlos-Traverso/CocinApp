"""LOCAL ONLY: verify publication CAS and serialization with role revocation."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import threading
import time
import uuid

ADMIN_A = '22222222-2222-2222-2222-222222222222'
ADMIN_B = '33333333-3333-3333-3333-333333333333'
PARAMETERS = json.loads(Path(__file__).with_name('nutrition_config_parameters.json').read_text(encoding='utf-8'))
FACTORS = json.dumps(PARAMETERS['activity_factors'], separators=(',', ':'))
GOALS = json.dumps(PARAMETERS['goal_adjustments'], separators=(',', ':'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--psql', required=True, type=Path)
    parser.add_argument('--port', type=int, default=55439)
    args = parser.parse_args()
    env = {key: value for key, value in os.environ.items() if not key.upper().startswith('PG')}
    command = [str(args.psql), '-X', '-qAt', '-h', '127.0.0.1', '-p', str(args.port), '-U', 'postgres',
               '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
    sessions = []
    prefix = 'cocinapp_nutrition_' + uuid.uuid4().hex[:10]

    def sql(query):
        result = subprocess.run(command, input=query, text=True, encoding='utf-8', capture_output=True, timeout=8, env=env)
        if result.returncode:
            raise AssertionError('Local SQL control query failed: ' + result.stderr[-1000:])
        return result.stdout.strip()

    class Session:
        def __init__(self, suffix, query):
            self.name = prefix + '_' + suffix
            self.lines = []
            self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                            text=True, encoding='utf-8', env=env)
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

    def identity(actor):
        return ("begin; set local role authenticated; "
                f"select set_config('request.jwt.claim.sub','{actor}',true); "
                f"select set_config('request.jwt.claims','{{\"sub\":\"{actor}\",\"role\":\"authenticated\"}}',true); ")

    try:
        sql('delete from public.nutrition_config;')
        effective = "to_char((clock_timestamp()-interval '1 day') at time zone 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US')||'Z'"
        payload_a = f"jsonb_build_object('activity_factors','{FACTORS}'::jsonb,'goal_adjustments','{GOALS}'::jsonb,'source_note','race A','effective_at',{effective})"
        payload_b = f"jsonb_build_object('activity_factors','{FACTORS}'::jsonb,'goal_adjustments','{GOALS}'::jsonb,'source_note','race B','effective_at',{effective})"
        first = Session('publish_a', identity(ADMIN_A) + f'select public.admin_publish_nutrition_config({payload_a},0);')
        await_state(first, False)
        second = Session('publish_b', identity(ADMIN_B) + f'select public.admin_publish_nutrition_config({payload_b},0); commit;')
        await_state(second, True)
        first.send('commit;')
        first.finish()
        second.finish('40001')
        if sql('select count(*) from public.nutrition_config;') != '1':
            raise AssertionError('Expected exactly one version from competing publishers')

        # The role change follows the shared advisory-lock protocol, then the same JWT is rejected.
        held = Session('role_lock', 'begin; select pg_advisory_xact_lock(74539,1); update public.user_roles set role=\'USER\' where user_id=\'' + ADMIN_A + '\';')
        await_state(held, False)
        publisher = Session('role_publish', identity(ADMIN_A) + f'select public.admin_publish_nutrition_config({payload_b},1); commit;')
        await_state(publisher, True)
        reader = Session('role_history', identity(ADMIN_A) + 'select public.admin_list_nutrition_configs(); commit;')
        await_state(reader, True)
        held.send('commit;')
        held.finish()
        publisher.finish('42501')
        reader.finish('42501')
        denied_query = ("begin; set local role authenticated; select set_config('request.jwt.claim.sub','" + ADMIN_A + "',true); "
                        "select set_config('request.jwt.claims','{\"sub\":\"" + ADMIN_A + "\",\"role\":\"authenticated\"}',true); "
                        "select public.admin_list_nutrition_configs(); commit;")
        denied = subprocess.run(command, input=denied_query, text=True, encoding='utf-8', capture_output=True, timeout=8, env=env)
        if denied.returncode == 0 or '42501' not in denied.stderr:
            raise AssertionError('Demoted administrator was not denied: ' + denied.stderr[-1000:])
        print('PASS: concurrent publishers serialize; role demotion blocks subsequent publish and history access')
    finally:
        for session in sessions:
            if session.process.poll() is None:
                session.process.kill()
                session.process.wait(timeout=5)
                session.reader.join(timeout=1)


if __name__ == '__main__':
    main()
