"""Verify concurrent finish retries are once-only and competing sessions cannot overdraw."""
import argparse
import subprocess
import threading
import uuid

USER = '11111111-1111-1111-1111-111111111111'


def run(psql: str, port: int, sql: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run([psql, '-h', '127.0.0.1', '-p', str(port), '-U', 'postgres', '-v',
                             'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-At', '-c', sql],
                            text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--psql', required=True)
    parser.add_argument('--port', type=int, required=True)
    args = parser.parse_args()
    category, unit, ingredient, recipe, ri, step, lot, session_a, session_b = [str(uuid.uuid4()) for _ in range(9)]
    run(args.psql, args.port, f"""
      insert into public.account_status(user_id,active) values ('{USER}',true) on conflict(user_id) do update set active=true;
      insert into public.categories(id,name,normalized_name) values ('{category}','Local finish','finish-{category}');
      insert into public.units(id,name,abbreviation,dimension) values ('{unit}','Gram','f{unit[:3]}','mass');
      insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id) values ('{ingredient}','Race ingredient','finish-{ingredient}','{category}','{unit}');
      insert into public.recipes(id,recipe_source,title,total_minutes,portions,difficulty,publication_status) values ('{recipe}','official','Finish race',2,1,'easy','published');
      insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,position) values ('{ri}','{recipe}','{ingredient}',1,'{unit}',1);
      insert into public.recipe_steps(id,recipe_id,position,instruction) values ('{step}','{recipe}',1,'Cook');
      insert into public.pantry_items(id,user_id,name,category,quantity,unit,minimum,ingredient_ref,unit_ref) values ('{lot}','{USER}','Race ingredient','Local finish',1,'f{unit[:3]}',0,'{ingredient}','{unit}');
      select set_config('request.jwt.claim.sub','{USER}',false);
      select public.start_my_cooking_session('{session_a}','{recipe}',1);
      select public.start_my_cooking_session('{session_b}','{recipe}',1);
    """)

    gate = threading.Barrier(2)
    results: list[subprocess.CompletedProcess[str]] = []

    def finish(session: str) -> None:
        sql = f"begin; select set_config('request.jwt.claim.sub','{USER}',true); select set_config('request.jwt.claims','{{\"sub\":\"{USER}\",\"role\":\"authenticated\"}}',true); set local role authenticated; select public.finish_my_cooking_session('{session}',1,true); commit;"
        gate.wait()
        results.append(run(args.psql, args.port, sql, check=False))

    threads = [threading.Thread(target=finish, args=(session_a,)), threading.Thread(target=finish, args=(session_b,))]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    successes = [r for r in results if r.returncode == 0]
    failures = [r for r in results if r.returncode != 0]
    if len(successes) != 1 or len(failures) != 1 or '22023' not in failures[0].stderr:
        raise RuntimeError(f'Expected one successful finish and one atomic shortage: {[r.stderr for r in results]}')
    count, qty = run(args.psql, args.port, f"select count(*), (select quantity from public.pantry_items where id='{lot}') from public.cooking_events where deduct_stock").stdout.strip().split('|')
    if count != '1' or qty != '0.0000':
        raise RuntimeError(f'Competing sessions overdrew stock or duplicated events: count={count}, quantity={qty}')
    winner = run(args.psql, args.port, f"select session_id from public.cooking_events where deduct_stock").stdout.strip()
    retry = run(args.psql, args.port, f"begin; select set_config('request.jwt.claim.sub','{USER}',true); set local role authenticated; select id from public.finish_my_cooking_session('{winner}',999,true); commit;")
    if retry.returncode:
        raise RuntimeError(f'Completed finish retry failed with stale version: {retry.stderr}')
    if run(args.psql, args.port, "select count(*) from public.cooking_events").stdout.strip() != '1':
        raise RuntimeError('Retry duplicated the cooking event')
    print('PASS: concurrent finish serialized stock, stale same-payload retry returned the one event')


if __name__ == '__main__':
    main()
