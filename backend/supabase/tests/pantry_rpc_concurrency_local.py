"""LOCAL ONLY: competing pantry mutations against one synthetic row."""
import argparse
import os
from pathlib import Path
import subprocess
import threading
import time
import uuid

A = '11111111-1111-1111-1111-111111111111'


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

    def run(sql, check=True):
        result = subprocess.run(command, input=sql, text=True, encoding='utf-8', capture_output=True,
                                timeout=12, env=env)
        if check and result.returncode:
            raise AssertionError('Local pantry SQL failed: ' + result.stderr[-1000:])
        return result

    item_id = str(uuid.uuid4())
    category_id = str(uuid.uuid4())
    unit_id = str(uuid.uuid4())
    run(f"""insert into public.categories(id,name,normalized_name) values('{category_id}','Otros','pantry-concurrency-{category_id}');
insert into public.units(id,name,abbreviation,dimension) values('{unit_id}','Gramo','g','mass');
insert into public.pantry_items(id,user_id,name,category,quantity,unit,minimum,unit_ref)
values('{item_id}','{A}','Stock','Otros',1,'g',0,'{unit_id}');""")
    barrier = threading.Barrier(2)
    results = []

    def writer(quantity, delay):
        barrier.wait()
        sql = f"""begin;
set request.jwt.claim.sub='{A}';
set request.jwt.claims='{{\"sub\":\"{A}\",\"role\":\"authenticated\"}}';
set role authenticated;
select (public.put_my_pantry_item('{{\"id\":\"{item_id}\",\"name\":\"Stock\",\"category\":\"Otros\",\"quantity\":{quantity},\"unit\":\"g\",\"minimum\":0,\"expiry\":null}}'::jsonb,1)).version;
select pg_sleep({delay});
commit;"""
        results.append(run(sql, check=False))

    first = threading.Thread(target=writer, args=(2, 0.5))
    second = threading.Thread(target=writer, args=(3, 0))
    first.start(); second.start(); first.join(); second.join()
    successes = [result for result in results if result.returncode == 0]
    conflicts = [result for result in results if result.returncode != 0 and '40001' in result.stderr]
    if len(successes) != 1 or len(conflicts) != 1:
        raise AssertionError('Expected one successful update and one SQLSTATE 40001 conflict')
    state = run(f"select version||':'||quantity from public.pantry_items where id='{item_id}';").stdout.strip()
    if state not in ('2:2.0000', '2:3.0000'):
        raise AssertionError('Pantry row version or committed quantity is inconsistent: ' + state)
    print('PASS: concurrent writes to one pantry row serialize; stale writer receives 40001')


if __name__ == '__main__':
    main()
