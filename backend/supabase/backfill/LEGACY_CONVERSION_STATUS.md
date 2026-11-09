> Confirmación remota posterior: el usuario ejecutó el archivo completo y comunicó `PASS: legacy data conversion verified; full script includes ROLLBACK`. Ensayo de conversión de datos reales aprobado; el ROLLBACK deshizo los cambios. No equivale a migración permanente, respaldo restaurado ni prueba de navegador.

> Actualización: inventario y clasificación de referencias recibidos. Las cuatro claves examinadas tienen cero referencias sin resolver; las 11 referencias adicionales provienen del catálogo inicial. Pendiente ensayo completo de datos reales con ROLLBACK.

# Conversión de compras y sesiones legacy — estado

Preparado y ensayado localmente, sin aplicación permanente ni lectura remota confirmada. El primer resultado remoto comunicado fue «Success. No rows returned»; el inventario fue corregido para devolver filas visibles. Se necesitan esas filas antes de decidir el corte real.

## Artefactos

- `../diagnostics/cutover_inventory.sql`: lectura de agregados, compatibilidad con siete tablas legacy y nombres finales, sin datos personales en la salida; termina en ROLLBACK.
- `build_cutover_data_rehearsal.py` genera `cutover_data_rehearsal.sql`: ensayo completo desde el esquema legacy, catálogo/perfil/favoritos/planes/historial, migraciones finales y conversión de compras/sesiones. No contiene fixtures ni COMMIT; termina en ROLLBACK. No ejecutar partes sueltas sobre el remoto.
- `build_legacy_shopping_cooking_rehearsal.py`: conversor especializado y stage generado con fixtures aislados. Los fixtures son solo para pruebas locales; nunca se deben ejecutar como conversión de datos reales.

## Validación local

`tests/run_table_rename_local.ps1 -ConversionData -Inventory -Port 55441`: PASS. Inventario ejecutado en esquema legacy y final; conversión integral con compras e inicio de cocina no vacíos más historial cerrado; rollback comprobado; **24 etapas SQL PASS**. La instancia temporal se detuvo. La prueba específica ejecuta el bloque real del conversor, comprueba stock/procedencia intactos y estado comprado, consulta sesión y stock por RPC, pausa temporizador y finaliza sin descuento. También rechaza destino ocupado y datos malformados sin dejar inserts parciales. Los avisos de transacción anidada del stage provienen del wrapper de pruebas; no representan un COMMIT ni un fallo del rollback.

La integración detectó y corrigió un snapshot histórico incompatible con el lector actual, variables SQL no declaradas, un alias de registro conflictivo y discrepancias del fixture Auth y del formato de respuesta de stock. No se alteró código frontend durante esta etapa.

## Semántica y límites

Los UUID son deterministas y separados por cuenta/tipo de registro. El JSON origen permanece intacto. Las compras ya reflejadas en despensa no se reactivan ni suman stock; se conservan en el JSON y en la procedencia original de despensa. No se fabrican comprobantes históricos con cantidades supuestas.

Las sesiones activas conservan porciones, paso, pasos completados y temporizadores; las fechas límite se interpretan en milisegundos epoch y se transforman a timestamp. Las recetas guardadas representan el catálogo de la migración, no una reconstrucción histórica exacta. Los timestamps de pasos completados usan started_at como marcador sintético porque el origen solo guarda booleanos; no se presentan como la hora real de completar cada paso. El historial cerrado se normaliza al contrato de snapshot actual conservando legacyEvent. No se generan nuevos eventos ni descuentos de stock al convertir progreso activo.

Se rechazan cantidades que no caben en la precisión SQL, referencias ambiguas, IDs duplicados, categorías sin coincidencia activa exacta y procedencias recipe/plan que no tengan vínculos suficientes. Una categoría ausente puede ser válida para el lector legacy que la enriquecía, pero este conversor no la infiere: requiere reconciliación explícita. Los orígenes múltiples se resuelven únicamente cuando cada vínculo es identificable; no se inventa una relación a partir de una etiqueta. El test principal no cubre todas las combinaciones de procedencia, por lo que la validación con el inventario/datos reales sigue siendo una condición de corte.

Este resultado no cierra A01/A02 por completo: faltan el inventario remoto actual, resolución de anomalías específicas, respaldo restaurable y ensayo sobre copia de datos reales, además de E2E y artefactos permanentes de despliegue/recuperación.

## Paso inmediato para el usuario

1. Abrir y ejecutar **completo** `../diagnostics/cutover_inventory.sql` en Supabase → SQL Editor con el rol operador. Es solo lectura y termina en ROLLBACK.
2. Copiar las filas de `inventory_report`, sobre todo `nonempty_documents`, `malformed`, `recipe_refs` y tablas presentes. El diagnóstico no publica nombres, emails ni UUIDs.
3. Revisar esos resultados antes de ejecutar el ensayo completo de conversión. No ejecutar una migración permanente ni sustituir ROLLBACK por COMMIT.
