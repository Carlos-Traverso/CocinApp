> Estado actualizado: consultar `backend/supabase/CURRENT_STATUS.md`. Este documento conserva la planificación o auditoría histórica.

> Seguimiento posterior: A03–A07 atendidos en código y validados localmente; ver [correcciones](AUDIT_CORRECTIONS_2026-11-07.md). Siguen pendientes ensayo remoto/E2E y A01/A02. Los hallazgos debajo conservan la fotografía original de la auditoría.

# Auditoría integral de CocinAPP — 2026-11-07

## Dictamen

**No activar todavía el corte relacional en producción.** Los adaptadores principales están preparados y las verificaciones locales pasan, pero existen pendientes funcionales confirmados y faltan la conversión definitiva, respaldo restaurable y validación del producto contra el esquema final.

Alcance: código actual del repositorio, consumidores frontend con los flags relacionales previstos, migraciones hasta 013, función `admin-users`, datos iniciales/conversores y documentación operativa. Tres revisiones independientes de solo lectura: consumidores, seguridad SQL/Auth y datos/nutrición. El coordinador contrastó los hallazgos y ejecutó verificaciones locales. No se consultó ni modificó Supabase remoto; el último estado remoto conocido no se presenta como inventario actual.

P1 significa bloqueo de corte o conversión que debe resolverse antes de producción. P2 significa defecto funcional confirmado que debe corregirse o quedar excluido explícitamente del alcance publicado. No se asigna un porcentaje global.

## Hallazgos confirmados

| ID | Prioridad | Evidencia y reproducción | Consecuencia y cierre |
| --- | --- | --- | --- |
| A01 | P1 de corte | `backfill/personal_data_rehearsal.sql:34-36` aborta ante arrays no vacíos de `shopping` o `cooking_progress`. Los ensayos existentes terminan en rollback; `backfill/README.md` indica que no se ofrece conversión con COMMIT. | El uso actual puede haber creado compras o sesiones desde el inventario remoto previo. Elaborar conversores para esos datos, o demostrar con inventario actualizado que no existen y controlar nuevas escrituras durante el corte. Preparar script permanente revisable, reconciliación y recuperación. No eliminar documentos para superar el chequeo. |
| A02 | P1 de verificación operativa | No se verificó un respaldo restaurable ni el inventario remoto actual, migraciones/grants efectivos, versión de Edge o configuración del hosting. Los flags de `shared/data/supabaseClient.ts:14-22` están desactivados por defecto y no aparecen en `.env` local. | Los tests locales no prueban el despliegue final ni una activación parcial de flags. Verificar respaldo/restauración, entorno de ensayo con esquema final y flujos completos; fijar una única matriz coordinada de flags frontend y `COCINAPP_RELATIONAL_PROFILES` para Edge. No desplegar el build de esta auditoría como corte relacional. |
| A03 | P2 | `frontend/src/pages/AdminPage.tsx:69` obtiene recetas mediante repositorios de lectura personal. `features/admin/domain/adminDashboard.ts:9-20` cuenta esas listas; `migrations/202611010010_recipe_read_contract.sql:15-31` limita las oficiales conocidas a publicadas. | El resumen administrativo omite borradores y parte de las inactivas/archivadas, aunque el editor ya carga el catálogo oficial completo. Reproducir creando un borrador y comparar editor con resumen. Calcular métricas desde el catálogo administrativo, separando oficiales de privadas propias. |
| A04 | P2 | `migrations/202610240002_search_admin_audit_events.sql:39-68` obtiene/busca nombres desde JSON personal; 009 renombra las tablas pero no cambia esa fuente. `functions/admin-users/index.ts:141-149` y 013 renombrarán mediante `perfiles`. | Tras renombrar un perfil relacional, el historial administrativo puede mostrar/buscar el nombre anterior. Ajustar RPC de auditoría para priorizar el nombre canónico relacional y conservar alternativas cuando falte. Verificar actor y objetivo sin exponer datos privados. |
| A05 | P2 | `frontend/src/features/admin/ui/RecipesTab.tsx:268` acepta texto libre con ejemplos «Vegana, Sin TACC, Vegetariana»; el adaptador transmite `dietary_tags` sin resolver etiquetas. `migrations/202611010001_recipe_admin_rpcs.sql:151` exige claves activas `tag_key`. | Guardar una etiqueta visible en vez de una clave rechaza la receta. Reemplazar texto libre por selección del catálogo real de etiquetas activas, preservar las ya asignadas según el contrato y conectar la gestión de etiquetas/clasificación de ingredientes si forma parte del producto. |
| A06 | P2 de integración | `frontend/src/features/profile/domain/profile.ts:24-68` conserva factores y ajustes nutricionales locales. No hay consumidor frontend de `get_current_nutrition_config` ni `admin_publish_nutrition_config`. `migrations/202611010003_nutrition_config_rpcs.sql:3-4,36,150,172` ofrece versiones administrativas y no siembra una configuración. | Publicar una configuración en el backend no cambia las estimaciones de la web. Conectar lectura/publicación y estados de configuración ausente/futura, o definir explícitamente que esta versión utiliza reglas locales y no anuncia configuración remota operativa. No se evalúa aquí la adecuación clínica de las fórmulas. |
| A07 | P2 | `frontend/src/features/admin/ui/RecipesTab.tsx:280` admite cantidades desde 0.000001 con step libre; `adminValidation.ts:102` solo comprueba positivo/finito. El guardado SQL de receta `202611010001_recipe_admin_rpcs.sql:141-142` rechaza más de cuatro decimales. | El formulario acepta un valor que el servidor rechaza. Alinear precisión y mensajes de cantidades/overrides con numeric(14,4); revisar también calorías numeric(9,2) y límites antes del envío. No redondear silenciosamente. |

## Seguridad y permisos

La revisión estática no confirmó una vulnerabilidad P1/P2 en el alcance SQL/Auth revisado. Se revisaron RLS y revocaciones de DML, RPC SECURITY DEFINER con search_path vacío, grants, cuenta activa, ownership, comprobación administrativa, renombres 009 y llamadas Edge. La ejecución local de permisos confirma sus escenarios conocidos. Esto no acredita los permisos efectivos del remoto, pruebas exhaustivas de seguridad ni revocación de operaciones Auth ya admitidas: esta última sigue siendo una limitación documentada.

## Datos iniciales y conversión

Los ensayos existentes conservan claves históricas y prioridad de overrides del catálogo; la despensa manual puede conservar referencias nulas sin inventar asociaciones. El inventario previo documentado (20 filas de despensa, una manual no asociada) es histórico y debe repetirse. No se afirma que el contenido remoto siga igual.

Los eventos históricos convertidos usan sesiones sintéticas cerradas y snapshots de receta del momento de la conversión (`backfill/personal_data_rehearsal.sql:115-148`); no representan una reconstrucción exacta de la receta ni del consumo histórico original. Debe aceptarse y reconciliarse expresamente esa semántica. Los datos personales parciales y timestamps deben comprobarse en la conversión definitiva. No se presenta como pérdida confirmada de los datos actuales.

Los documentos antiguos contienen tareas que luego fueron atendidas. Las frases de README que todavía dicen «frontend legacy» son estado histórico, no prueba de que falten todos los adaptadores. Esta auditoría prevalece como fotografía actual; el código y SQL continúan siendo la fuente de verdad.

## Verificación ejecutada

- `npm run typecheck`: PASS.
- `npm test`: **197/197 PASS**. La suite principal usa configuración local sin flags; los contratos nuevos tienen pruebas con clientes inyectados. No equivale a navegador con todos los flags activos.
- `npm run build`: PASS. Vite advierte un chunk JS de aproximadamente 874 kB (239.6 kB gzip); mejora de rendimiento, no fallo de compilación.
- `npm run lint`: exit 0 con advertencias de dependencias de hooks, refs durante render y recarga de componentes; no se declara libre de advertencias.
- `git diff --check`: PASS con avisos de conversión LF/CRLF.
- `./backend/supabase/tests/run_table_rename_local.ps1 -ProfileAdmin -Port 55441`: PASS. Cadena de migraciones y **22 etapas SQL** posteriores a los renombres, más ensayo autocontenido con rollback verificado. Incluye perfiles/admin, catálogo, recetas, nutrición, preferencias, planificación, compras, despensa, cocina, lecturas, resumen y permisos.
- El primer intento SQL quedó impedido por acceso local TCP (10013); el segundo se ejecutó con permiso para la instancia temporal local y finalizó correctamente. La instancia se detuvo. No hubo conexión remota ni aplicación permanente.

## Cobertura de consumidores

Perfil/usuarios, despensa, compras, cocina/historial, recetas/favoritos, planificación, catálogo/editor e Inicio disponen de adaptadores relacionales. Persisten los consumidores/gaps A03-A07. La lectura auxiliar de catálogo durante login está capturada como carga no crítica; no se encontró que un fallo de esa precarga invalide credenciales correctas. Los caminos legacy conservados detrás de flags no son por sí mismos un defecto; publicar combinaciones incompatibles sí debe prevenirse en el corte.

Límites ya documentados: paginación y lecturas paralelas no son un snapshot único de toda la aplicación; algunas operaciones compuestas usan varias RPC y requieren recarga ante fallo parcial; volúmenes reales y latencia no se midieron. Los fixtures y 22 escenarios SQL no cubren todo el producto de extremo a extremo.

## Orden recomendado para cerrar

1. Corregir A03, A04, A05 y A07 con pruebas de regresión focalizadas. Revisar etiquetas y cantidades antes de intentar cargar datos administrativos reales.
2. Resolver A06: conectar configuración nutricional y su inicialización explícita, con comportamiento verificable si falta configuración.
3. Inventariar datos remotos actuales y completar conversores y preflight A01; reconciliar propietarios, UUID/legacy, unidades, preferencias, fechas y cantidades sin descartar anomalías.
4. Ensayar respaldo/restauración y conversión sobre una copia, después flujos de navegador con la matriz final de flags y roles/cuentas distintas (A02).
5. Preparar artefactos concretos de corte y recuperación; solicitar autorización final para aplicación permanente y despliegue. Esta auditoría no los autoriza ni los ejecuta.

No se modificó código funcional para corregir los hallazgos en esta etapa de auditoría. IA/OCR externo sigue pendiente por decisión previa del usuario.
