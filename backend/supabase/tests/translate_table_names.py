"""Translate SQL relation references for rollback rehearsals after table cutover.

The lexer skips strings and comments so JSON documents, RPC names, columns, and
other string-valued contracts stay byte-for-byte unchanged.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


TABLES = {
    'pantry_items': 'articulos_despensa',
    'personal_data': 'datos_personales',
    'user_roles': 'roles_usuario',
    'catalog_core': 'catalogo_base',
    'shared_recipes': 'recetas_compartidas',
    'account_status': 'estado_cuenta',
    'admin_audit_log': 'registro_auditoria',
    'dietary_tags': 'etiquetas_dieteticas',
    'nutrition_config': 'configuracion_nutricional',
    'profiles': 'perfiles',
    'user_dietary_preferences': 'preferencias_dieteticas_usuario',
    'categories': 'categorias',
    'units': 'unidades',
    'ingredients': 'ingredientes',
    'ingredient_dietary_tags': 'etiquetas_dieteticas_ingrediente',
    'recipes': 'recetas',
    'recipe_meal_shifts': 'turnos_comida_receta',
    'recipe_dietary_tags': 'etiquetas_dieteticas_receta',
    'recipe_ingredients': 'ingredientes_receta',
    'recipe_steps': 'pasos_receta',
    'recipe_step_ingredients': 'ingredientes_paso_receta',
    'favorite_recipes': 'recetas_favoritas',
    'meal_plans': 'planes_comida',
    'meal_plan_slots': 'turnos_plan_comida',
    'pantry_receipts': 'comprobantes_despensa',
    'shopping_lists': 'listas_compras',
    'shopping_items': 'articulos_compra',
    'shopping_item_sources': 'origenes_articulo_compra',
    'pantry_receipt_items': 'articulos_comprobante_despensa',
    'cooking_sessions': 'sesiones_cocina',
    'cooking_session_steps': 'pasos_sesion_cocina',
    'cooking_events': 'eventos_cocina',
    'cooking_event_ingredients': 'ingredientes_evento_cocina',
    'recipe_generation_requests': 'solicitudes_generacion_receta',
    'receipt_recognition_requests': 'solicitudes_reconocimiento_ticket',
    'admin_recipe_write_state': 'estado_escritura_receta_admin',
}

TOKEN = re.compile(r"'(?:''|[^'])*'|--[^\r\n]*|/\*.*?\*/", re.S)
TABLE_CONTEXT = re.compile(r"\b(FROM|JOIN|UPDATE|INTO|REFERENCES|TABLE|TRUNCATE|LOCK\s+TABLE)\s+([a-z_][a-z0-9_]*)\b", re.I)


def translate(code: str) -> str:
    def translate_code(chunk: str) -> str:
        for old, new in TABLES.items():
            chunk = re.sub(rf"public\.{old}([^a-z0-9_]|$)", lambda m: f'public.{new}{m.group(1)}', chunk)
            chunk = re.sub(rf"\b{old}\.(?=[a-z_])", f'{new}.', chunk)

        def context(match: re.Match[str]) -> str:
            keyword, name = match.group(1), match.group(2)
            return f'{keyword} {TABLES.get(name, name)}'

        return TABLE_CONTEXT.sub(context, chunk)

    parts: list[str] = []
    cursor = 0
    for match in TOKEN.finditer(code):
        parts.append(translate_code(code[cursor:match.start()]))
        token = match.group(0)
        if token.startswith("'"):
            body = token[1:-1]
            prefix = code[:match.start()]
            in_table_name_array = re.search(r'foreach\s+table_name\s+in\s+array\s+array\[[^\]]*$', prefix, re.I) is not None
            in_declared_table_array = re.search(r'(?:tables|private_tables|recipe_children)\s+text\[\]\s*:=\s*array\[[^\]]*$', prefix, re.I) is not None
            in_table_case = re.search(r'\bcase\s+tbl\b[^;]*\bwhen\s*$', prefix, re.I) is not None
            is_table_name_value = in_table_name_array or in_declared_table_array or in_table_case
            if re.fullmatch(r'public\.[a-z_][a-z0-9_]*', body) or re.search(r"\b(FROM|JOIN|UPDATE|INTO|ON|REFERENCES|TABLE)\s+public\.", body, re.I) or is_table_name_value:
                for old, new in TABLES.items():
                    if body == old and is_table_name_value:
                        body = new
                    else:
                        body = re.sub(rf"public\.{old}([^a-z0-9_]|$)", lambda m: f'public.{new}{m.group(1)}', body)
                token = "'" + body + "'"
        parts.append(token)
        cursor = match.end()
    parts.append(translate_code(code[cursor:]))
    translated = ''.join(parts)
    # Trigger functions dispatch on PostgreSQL's physical table name.
    for old, new in TABLES.items():
        translated = translated.replace(f"tg_table_name = '{old}'", f"tg_table_name = '{new}'")
    return translated


def main() -> None:
    path = Path(sys.argv[1])
    source = path.read_text(encoding='utf-8')
    path.write_text(translate(source), encoding='utf-8')


if __name__ == '__main__':
    if len(sys.argv) == 1:
        raise SystemExit('usage: translate_table_names.py <sql-file>')
    main()
