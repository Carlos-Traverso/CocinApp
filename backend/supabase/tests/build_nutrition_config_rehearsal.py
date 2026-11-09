"""Build nutrition config rehearsal from the frontend's canonical product parameters."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
profile = (root.parent.parent / 'frontend/src/features/profile/domain/profile.ts').read_text(encoding='utf-8')


def object_body(name: str) -> str:
    match = re.search(rf'const {name} = \{{(.*?)\n\}} satisfies', profile, re.S)
    if not match:
        raise SystemExit(f'Could not find {name} in profile.ts')
    return match.group(1)


def values(name: str) -> dict:
    body = object_body(name)
    if name == 'activityFactors':
        pairs = re.findall(r"(?:'([^']+)'|([a-z-]+)):\s*([0-9.]+)", body)
        data = {(a or b): float(v) for a, b, v in pairs}
    else:
        pairs = re.findall(r"(?:'([^']+)'|([a-z-]+)):\s*\{\s*minimum:\s*(-?\d+),\s*maximum:\s*(-?\d+)\s*\}", body)
        data = {(a or b): {'minimum': int(lo), 'maximum': int(hi)} for a, b, lo, hi in pairs}
    expected = {'activityFactors': {'sedentary','light','moderate','active','very-active'},
                'goalAdjustments': {'lose','maintain','gain','gain-muscle'}}[name]
    if set(data) != expected:
        raise SystemExit(f'Unexpected {name} keys parsed from profile.ts: {set(data)}')
    return data


parameters = {'activity_factors': values('activityFactors'), 'goal_adjustments': values('goalAdjustments')}
(root / 'tests/nutrition_config_parameters.json').write_text(json.dumps(parameters, separators=(',', ':')) + '\n', encoding='utf-8')
template = (root / 'tests/nutrition_config.stage.sql').read_text(encoding='utf-8')
template = template.replace('__ACTIVITY_FACTORS__', json.dumps(parameters['activity_factors'], separators=(',', ':')))
template = template.replace('__GOAL_ADJUSTMENTS__', json.dumps(parameters['goal_adjustments'], separators=(',', ':')))
schema = (root / 'migrations/202610300002_add_relational_domain_tables.sql').read_text(encoding='utf-8').rsplit('commit;', 1)[0]
migrations = (
    '202610300003_personal_write_rpcs.sql', '202610300004_planning_write_rpcs.sql',
    '202610300005_shopping_write_rpcs.sql', '202610300006_shopping_transfer_rpcs.sql',
    '202610300007_shopping_suggestions_rpc.sql', '202610310001_pantry_write_rpcs.sql',
    '202610310002_cooking_session_rpcs.sql', '202610310003_cooking_finish_rpcs.sql',
    '202610310004_cooking_queries_history_rpcs.sql', '202610310005_catalog_admin_rpcs.sql',
    '202611010001_recipe_admin_rpcs.sql', '202611010002_dietary_admin_rpcs.sql',
    '202611010003_nutrition_config_rpcs.sql',
)
rpcs = ''.join((root / 'migrations' / name).read_text(encoding='utf-8').replace('begin;', '', 1).rsplit('commit;', 1)[0] for name in migrations)
full_schema = schema.replace('begin;', "begin;\nset local lock_timeout='5s';\nset local statement_timeout='120s';", 1)
(root / 'tests/nutrition_config_rehearsal.sql').write_text(
    '-- NUTRITION CONFIG REHEARSAL: send as one SQL Editor request; preserve final ROLLBACK.\n'
    + full_schema + rpcs + template + '\nrollback;\n', encoding='utf-8')
(root / 'tests/fixtures/nutrition_config_schema_local.sql').write_text(
    '-- LOCAL ISOLATED DATABASE ONLY. Full relational schema and RPC installer.\n'
    + schema + rpcs + '\ncommit;\n', encoding='utf-8')
