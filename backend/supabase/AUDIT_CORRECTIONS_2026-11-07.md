# Correcciones posteriores a la auditoría integral

Fecha: 2026-11-07. Estado: código preparado y validación local; pendiente ensayo remoto, navegador y activación coordinada. Los flags permanecen desactivados. No se efectuó despliegue ni aplicación permanente.

## Hallazgos atendidos

- **A03, métricas:** el resumen administrativo relacional cuenta el catálogo oficial completo (borradores, inactivas y archivadas) y no las lecturas personales de recetas. El camino legacy mantiene sus métricas anteriores.
- **A04, nombres:** nueva migración `migrations/202611070001_admin_audit_profile_names.sql`. `admin_search_audit_events` prioriza `perfiles.display_name` tanto al mostrar como al buscar actor/objetivo; conserva alternativas Auth/email y los controles administrativos. No se alteró una migración histórica.
- **A05, etiquetas:** el editor relacional selecciona `tag_key` real mostrando su etiqueta legible. No inventa claves a partir de texto. Las referencias inactivas/desconocidas se muestran hasta que el administrador las quite expresamente; el contrato SQL exige todas activas para guardar. Esto no incorpora todavía un editor completo de etiquetas o clasificación dietética de ingredientes.
- **A06, nutrición:** lectura de `get_current_nutrition_config` al consultar el perfil relacional. Los cálculos consumen los factores/ajustes de la versión vigente; un resultado ausente desactiva la estimación sin sustituirlo por constantes locales. El perfil se mantiene editable y su guardado no serializa la configuración. Nueva sección administrativa `/admin/nutrition` para consultar versiones y publicar mediante RPC, con vigencia explícita y versión esperada. Los datos y fechas de un reintento de publicación se conservan. La configuración futura no reemplaza la vigente hasta su fecha. No se publicaron valores ni se sembró configuración automática. Los caminos legacy mantienen las reglas anteriores.
- **A07, precisión:** cantidades positivas hasta 1.000.000 con cuatro decimales y calorías con dos decimales dentro de numeric(9,2), sin redondeo silencioso. Formulario y validación informan los límites. Los overrides que conserva el adaptador siguen sujetos al contrato SQL.

## Validación

TypeScript, **206/206 pruebas frontend**, compilación de producción y `git diff --check`: PASS. El build mantiene el aviso de tamaño del bundle. Se añadieron nueve pruebas focalizadas de métricas, etiquetas/cantidades y nutrición; se actualizaron expectativas de navegación y metadata del perfil.

Ensayo SQL local: `tests/run_table_rename_local.ps1 -AuditNames -Port 55441` PASS, **23 etapas SQL** más el ensayo integral con rollback. La instancia temporal fue detenida. Se comprobó tanto la migración nueva junto al esquema final como el archivo autocontenido destinado al SQL Editor. El generador `tests/build_admin_audit_names_rehearsal.py` reutiliza la cadena existente y añade la migración/escenario dentro de una única transacción exterior.

## Ensayo remoto opcional antes del corte

1. Abrir `tests/admin_audit_names_rehearsal.sql` completo. No ejecutar el stage aislado ni solo la migración para probarla sobre el remoto legacy.
2. En Supabase → SQL Editor ejecutar el archivo completo con rol postgres y «Run without RLS», igual que los ensayos anteriores. El archivo prepara el esquema dentro de una transacción y **termina en ROLLBACK**; no instala permanentemente la migración. Puede requerir desactivar la paginación automática del editor para ejecutar todo el archivo.
3. Confirmar el resultado `PASS: audit profile names verified; full script includes ROLLBACK`. Si se ejecutó completo no hace falta otro rollback. Ante error, registrar el mensaje y cerrar la transacción fallida antes de reintentar.

No se ejecutó este ensayo contra Supabase remoto durante esta etapa. Las pruebas locales no sustituyen navegador, entorno efectivo de permisos, respaldo o conversión de datos reales.

## Trabajo restante

A01/A02 siguen abiertos: conversores de compras/sesiones antiguas con contenido, inventario remoto actualizado, respaldo restaurable, ensayo del corte con datos reales y despliegue coordinado. La configuración nutricional requiere una decisión explícita de sus valores y una publicación autorizada durante la preparación del entorno; no basta activar flags para que exista una versión vigente. Un editor completo de etiquetas y clasificación de ingredientes sigue fuera de este bloque.

Siguiente trabajo recomendado: inventario actualizado y conversores de compras/cocina legacy, sin aplicar permanentemente migraciones hasta disponer de respaldo y artefactos de corte revisados.
