"""Generate structural PostgreSQL DDL for diagram import from the catalog export."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
data = json.loads((root / 'backend_schema.json').read_text(encoding='utf-8'))


def ident(name):
    return '"' + name.replace('"', '""') + '"'


def qualified(schema, name):
    return ident(schema) + '.' + ident(name)


def columns(names):
    return ', '.join(map(ident, names))


parts = [
    '-- CocinAPP: modelo estructural completo para importar en un generador de diagramas.',
    '-- Estado implementado hasta 202611010012; pendiente de despliegue permanente.',
    '-- 36 tablas de aplicacion, 271 atributos y 56 FK. No contiene datos de usuarios.',
    '-- auth.users se representa SOLO mediante su id como referencia externa de Supabase.',
    '-- Este archivo es documental: NO ejecutar en el proyecto Supabase existente.',
    '-- No incluye RPC, triggers ni politicas RLS; para desplegar usar las migraciones.',
    'CREATE SCHEMA IF NOT EXISTS "public";',
    'CREATE SCHEMA IF NOT EXISTS "auth";',
]

for table in data['tables']:
    name = qualified(table['schema'], table['name'])
    rows = []
    for col in table['columns']:
        row = ident(col['name']) + ' ' + col['type']
        if col.get('identity'):
            row += ' GENERATED ' + ('ALWAYS' if col['identity'] == 'a' else 'BY DEFAULT') + ' AS IDENTITY'
        elif col.get('default') is not None:
            row += ' DEFAULT ' + col['default']
        if not col['nullable']:
            row += ' NOT NULL'
        rows.append(row)
    for constraint in table.get('constraints', []):
        rows.append('CONSTRAINT ' + ident(constraint['name']) + ' ' + constraint['definition'])
    parts.append(('\n-- Referencia externa, no es una tabla propia de CocinAPP.' if table.get('external') else '')
                 + '\nCREATE TABLE ' + name + ' (\n    ' + ',\n    '.join(rows) + '\n);')

parts.append('\n-- Relaciones declaradas como claves foraneas (incluye relaciones a la propia tabla).')
for fk in data['foreign_keys']:
    parts.append('ALTER TABLE ' + qualified(fk['source_schema'], fk['source_table'])
                 + '\n    ADD CONSTRAINT ' + ident(fk['name'])
                 + ' FOREIGN KEY (' + columns(fk['source_columns']) + ')'
                 + '\n    REFERENCES ' + qualified(fk['target_schema'], fk['target_table'])
                 + ' (' + columns(fk['target_columns']) + ')'
                 + ' ON DELETE ' + fk['on_delete'] + ';')

parts.append('\n-- Indices unicos adicionales; los respaldados por PK/UNIQUE ya se crean arriba.')
for table in data['tables']:
    constraint_names = {c['name'] for c in table.get('constraints', [])}
    for index in table.get('unique_indexes', []):
        if not index.get('primary') and index['name'] not in constraint_names:
            parts.append(index['definition'].rstrip(';') + ';')

destination = root / 'cocinapp_esquema_completo.sql'
destination.write_text('\n'.join(parts) + '\n', encoding='utf-8')
print(destination)
print(f"Tables: {len(data['tables'])} (36 application + auth stub); FK: {len(data['foreign_keys'])}")
