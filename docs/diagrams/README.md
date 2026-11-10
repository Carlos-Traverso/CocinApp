# Modelo completo para revisión académica

Esquema implementado por las 40 migraciones hasta `202611010012_shopping_dates_suggestions.sql`, con nombres españoles finales. Extraído de los catálogos de PostgreSQL local tras instalar las migraciones, sin datos de usuarios ni conexión a Supabase.

Inventario: **36 tablas públicas de aplicación, 271 atributos y 56 claves foráneas**. La referencia externa `auth.users.id` agrega una tarjeta y un atributo: 37 tarjetas / 272 atributos dibujados. El resto del esquema interno de Supabase Auth no es parte del modelo de aplicación y no se representa.

- `cocinapp_backend_uml.png`: imagen completa para entregar o insertar en un documento.
- `cocinapp_backend_uml.svg`: imagen vectorial para ampliar y leer sin pérdida de resolución.
- `backend_schema.json`: catálogo de respaldo, con columnas, tipos, nulabilidad, defaults, claves primarias/únicas, checks, FK y acciones de borrado, índices únicos y predicados parciales.

Las tablas antiguas se incluyen porque siguen formando parte de la transición. No se dibujan relaciones que solo existen como IDs dentro de documentos JSON: las líneas representan restricciones FK realmente declaradas. Las reglas de RPC, roles y RLS requieren consultar el código y la auditoría; una lámina de clases no demuestra por sí sola el comportamiento de esas funciones.

**Estado:** modelo nuevo preparado y probado en ensayos. El último resultado remoto comunicado fue PASS del ensayo de cocina/compras con ROLLBACK; no corresponde afirmar que estas 36 tablas estén instaladas permanentemente en Supabase. La lámina permite revisar el diseño completo antes del corte.

Regeneración de catálogo (PowerShell, PostgreSQL 18 local):

```powershell
./backend/supabase/tests/run_table_rename_local.ps1 -SchemaExportPath "$PWD/docs/diagrams/backend_schema.json" -SchemaOnly -Port 55441
```

Luego ejecutar `python docs/diagrams/render_schema.py` para regenerar el SVG y `powershell -NoProfile -ExecutionPolicy Bypass -File docs/diagrams/render_png.ps1` para PNG y vista previa. La imagen completa mide 3000 × 5361 píxeles. La exportación de catálogo no consulta filas de aplicación. La revisión del diagrama no cambia la base remota.
