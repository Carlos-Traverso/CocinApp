"""Exercise cooking-session optimistic concurrency in an isolated local PostgreSQL database."""
import argparse
import subprocess
import threading
import uuid

USERS = ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')


def run(psql: str, port: int, sql: str, *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run([psql, '-h', '127.0.0.1', '-p', str(port), '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-At', '-c', sql],
                            text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--psql', required=True)
    parser.add_argument('--port', type=int, required=True)
    args = parser.parse_args()
    category, unit, ingredient, recipe, recipe_ingredient, step_a, step_b, session = [str(uuid.uuid4()) for _ in range(8)]
    run(args.psql, args.port, f"""
      insert into public.account_status(user_id,active) values ('{USERS[0]}',true),('{USERS[1]}',true)
        on conflict(user_id) do update set active=true;
      insert into public.categories(id,name,normalized_name) values ('{category}','Local test','local-{category}');
      insert into public.units(id,name,abbreviation,dimension) values ('{unit}','Gram','l{unit[:3]}','mass');
      insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values ('{ingredient}','Test ingredient','local-{ingredient}','{category}','{unit}');
      insert into public.recipes(id,recipe_source,title,total_minutes,portions,difficulty,publication_status) values ('{recipe}','official','Concurrency test',5,2,'easy','published');
      insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,position) values ('{recipe_ingredient}','{recipe}','{ingredient}',1,'{unit}',1);
      insert into public.recipe_steps(id,recipe_id,position,instruction,duration_minutes) values
        ('{step_a}','{recipe}',1,'Stir',1),('{step_b}','{recipe}',2,'Serve',1);
      select set_config('request.jwt.claim.sub','{USERS[0]}',false);
      select public.start_my_cooking_session('{session}','{recipe}',2);
    """)

    gate = threading.Barrier(2)
    results: list[subprocess.CompletedProcess[str]] = []

    def write(action: str, step: int) -> None:
        sql = f"begin; select set_config('request.jwt.claim.sub','{USERS[0]}',true); select set_config('request.jwt.claims','{{\"sub\":\"{USERS[0]}\",\"role\":\"authenticated\"}}',true); set local role authenticated; select public.update_my_cooking_session('{session}',1,'{action}',{step}); commit;"
        gate.wait()
        results.append(run(args.psql, args.port, sql, check=False))

    workers = [threading.Thread(target=write, args=('move', 1)), threading.Thread(target=write, args=('complete', 0))]
    for worker in workers:
        worker.start()
    for worker in workers:
        worker.join()
    successes = [result for result in results if result.returncode == 0]
    failures = [result for result in results if result.returncode != 0]
    if len(successes) != 1 or len(failures) != 1 or '40001' not in failures[0].stderr:
        raise RuntimeError(f'Expected exactly one stale-version conflict; results: {[r.stderr for r in results]}')
    version = run(args.psql, args.port, f"select version from public.cooking_sessions where id='{session}'").stdout.strip()
    if version != '2':
        raise RuntimeError(f'Concurrent update advanced version unexpectedly: {version}')
    print('PASS: overlapping updates serialized and rejected the stale session version')


if __name__ == '__main__':
    main()
