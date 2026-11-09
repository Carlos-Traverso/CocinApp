"""LOCAL ONLY: verify recipe optimistic writes and cooking snapshot lock ordering."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import threading
import time
import uuid

ADMIN = '22222222-2222-2222-2222-222222222222'
USER = '33333333-3333-3333-3333-333333333333'
RECIPE = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
INGREDIENT = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
UNIT = 'dddddddd-dddd-dddd-dddd-dddddddddddd'


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
    prefix = 'cocinapp_recipe_test_' + uuid.uuid4().hex[:10]
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

    def identity(actor):
        return ("begin; set local role authenticated; "
                f"select set_config('request.jwt.claim.sub','{actor}',true); "
                f"select set_config('request.jwt.claims','{{\"sub\":\"{actor}\",\"role\":\"authenticated\"}}',true); ")

    def payload(title):
        return json.dumps({
            'title': title, 'author': 'CocinAPP', 'description': '', 'category_label': 'Race',
            'meal_shifts': ['lunch'], 'total_minutes': 5, 'preparation_minutes': None,
            'cooking_minutes': None, 'portions': 1, 'difficulty': 'easy', 'calories_per_portion': None,
            'dietary_tags': [], 'featured': False, 'symbol': 'R', 'color': 'green',
            'cross_contamination_note': None, 'image_path': None, 'image_alt': None,
            'publication_status': 'published', 'active': True,
            'ingredients': [{'ingredient_id': INGREDIENT, 'quantity': 1, 'unit_id': UNIT, 'note': ''}],
            'steps': [{'instruction': 'Cook race recipe', 'duration_minutes': None, 'temperature': None,
                       'tip': None, 'warning': None, 'utensils': [], 'special_instructions': None, 'ingredients': []}],
        }, separators=(',', ':'))

    def save(title, version):
        quoted = payload(title).replace("'", "''")
        return f"select public.admin_save_recipe('{RECIPE}','{quoted}'::jsonb,{version});"

    try:
        sql(f"update public.recipes set version=1,title='Recipe race',active=true,is_deleted=false,publication_status='published' where id='{RECIPE}';")
        first = Session('cas_first', identity(ADMIN) + save('CAS first', 1))
        await_state(first, False)
        second = Session('cas_second', identity(ADMIN) + save('CAS second', 1) + 'commit;')
        await_state(second, True)
        first.send('commit;')
        first.finish()
        second.finish('40001')
        if sql(f"select version||':'||title from public.recipes where id='{RECIPE}';") != '2:CAS first':
            raise AssertionError('Concurrent stale recipe save overwrote the first mutation')

        # A user session holds FOR SHARE on the recipe parent while the trusted
        # writer requests FOR UPDATE before replacing any child rows.
        session_id = str(uuid.uuid4())
        cooker = Session('cooking_snapshot', identity(USER) +
                         f"select * from public.start_my_cooking_session('{session_id}','{RECIPE}',1);")
        await_state(cooker, False)
        editor = Session('recipe_edit', identity(ADMIN) + save('After cooking start', 2) + 'commit;')
        await_state(editor, True)
        cooker.send('commit;')
        cooker.finish()
        editor.finish()
        result = sql(f"select r.title||':'||(s.recipe_snapshot->>'name') from public.recipes r join public.cooking_sessions s on s.recipe_id=r.id where r.id='{RECIPE}' and s.id='{session_id}';")
        if result != 'After cooking start:CAS first':
            raise AssertionError('Recipe edit raced the cooking snapshot or changed its immutable snapshot: ' + result)
        print('PASS: same-version recipe saves serialize; cooking snapshots precede concurrent child replacement')
    finally:
        for session in sessions:
            if session.process.poll() is None:
                session.process.kill()
                session.process.wait(timeout=3)
            session.reader.join(timeout=1)


if __name__ == '__main__':
    main()
