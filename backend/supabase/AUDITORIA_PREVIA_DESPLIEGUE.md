> Estado actualizado: ver [auditoría integral del 2026-11-07](AUDITORIA_INTEGRAL_2026-11-07.md). Los bloqueos B01-B10 y seguimientos de este documento conservan historia y no deben interpretarse aisladamente como estado vigente.

# Auditoría previa al despliegue

Fecha: 2026-11-01. Revisión del código local y pruebas locales; tres revisores Luna en lectura (seguridad, integridad/migración, frontend), contrastados por el coordinador. No se modificó código funcional ni se desplegó nada. Este documento complementa FRONTEND_INTEGRATION_AUDIT.md y prevalece para el dictamen actual.

## Dictamen

**No aprobar todavía el corte a producción del modelo relacional.** La estructura y sus operaciones tienen una base sólida y pasan las pruebas disponibles, pero la aplicación aún utiliza persistencia legacy y existen contratos sin resolver. Un PASS de ensayo no equivale a migración permanente ni a prueba integral de las pantallas contra el modelo nuevo.

El último estado remoto comunicado por el usuario es PASS del ensayo de renombrado completo con ROLLBACK. Por ello se espera que Supabase conserve las siete tablas originales en inglés. No se inspeccionó el catálogo remoto durante esta auditoría; debe confirmarse antes del corte.

## Evidencia ejecutada en esta revisión

- Frontend: `npm run typecheck` PASS y `npm test` **140/140 PASS**.
- SQL: `backend/supabase/tests/run_table_rename_local.ps1 -Port 55441` PASS, PostgreSQL 18 temporal y Auth simulado; servidor detenido al terminar.
- El ejecutor instala la base legacy, ejecuta el ensayo autocontenido y comprueba su rollback; instala las migraciones pendientes, aplica realmente 009 y comprueba datos y metadatos antes/después. Pasan los **18 escenarios SQL** de catálogo, recetas, nutrición, preferencias, perfil, planes, compras, transferencias, despensa, cocina, historial, descubrimiento, solicitudes externas, lecturas, dashboard y permisos.
- Comparaciones del renombrado: identidad de tablas, columnas/tipos, restricciones, índices, RLS, políticas, triggers, grants e identidad/propiedad/permisos de funciones. Atributos y contratos JSON permanecen en inglés.
- Las pruebas SQL incluyen aislamiento entre cuentas, rechazo anónimo/inactivo, permisos administrativos, versiones y reintentos. No se volvió a ejecutar en esta revisión cada arnés separado de concurrencia. Tampoco son pruebas E2E del navegador con Supabase real.
- El primer intento con salida redirigida no progresó; se interrumpió y se repitió directamente con éxito. No se contabiliza ese intento como PASS.

## Inventario y revisión estructural

Hay **36 tablas de aplicación previstas tras las migraciones**: siete legacy, 28 nuevas de dominio y una auxiliar técnica (`estado_escritura_receta_admin`). `auth.users` es externa a ese recuento. Los nombres finales constan en TABLE_NAMES_ES.md.

Se revisaron PK/FK, restricciones, precisión numérica, nulabilidad, RLS, funciones de validación y escrituras. El modelo contempla identidad/perfil/preferencias, catálogo/unidades/etiquetas, recetas y detalles, favoritos, planes, despensa, compras y comprobantes, sesiones/timers/eventos de cocina, auditoría/configuración y metadatos IA/OCR. Los snapshots históricos y claves legacy evitan depender exclusivamente del catálogo actual.

Puntos positivos comprobados: cantidades controladas, conversiones por dimensión, operaciones transaccionales de stock, bloqueos de despensa en orden estable, claves de idempotencia por propietario, control de versiones y archivo lógico de referencias utilizadas. No se confirmó una fuga entre cuentas ni una RPC SECURITY DEFINER sensible accesible anónimamente en lo revisado. Esto no constituye garantía de ausencia de defectos fuera de los escenarios inspeccionados.

## Bloqueos antes del corte final

| ID | Hallazgo y evidencia | Efecto y condición de cierre |
| --- | --- | --- |
| B01 | El código consulta nombres españoles: `frontend/src/shared/data/personalDataRepository.ts:15`, `features/pantry/data/supabasePantryRepository.ts:55`, `features/admin/data/supabaseCatalogCore.ts:94`, `supabaseRecipes.ts:37`; los crea la migración 009. | Con el remoto legacy en inglés, publicar estos archivos rompe las consultas correspondientes. Coordinar versión de aplicación, Edge Function y esquema; probar compatibilidad de la versión activada. No se afirma que esos archivos ya estén publicados. |
| B02 | Despensa hace upsert de colección y borra IDs ausentes (`supabasePantryRepository.ts:51-87`); las migraciones revocan DML y ofrecen RPC versionadas. | Tras la migración las escrituras fallan; el patrón previo también puede borrar cambios concurrentes. Cambiar a operaciones RPC por fila/lote y relectura por conflicto; no reabrir DML para eludir la adaptación. |
| B03 | Perfil, favoritos, planes, compras y cocina siguen usando `loadPersonalData/savePersonalData`; el guardado reemplaza documentos completos (`personalDataRepository.ts:25-38`). | Las tablas normalizadas no se alimentan desde esos repositorios. Preparar adaptadores, IDs legacy/UUID, snake_case/camelCase, versiones, claves de reintento, paginación e invalidación de caché; eliminar importaciones locales silenciosas en el corte. |
| B04 | `RecipeRepository.ts:7-14` requiere recetas conocidas y detalle con inactivas; discovery devuelve principalmente activas permitidas (`202611010004_recipe_discovery_rpcs.sql:44-47,77-80`). | Falta contrato de detalle por UUID/legacy_id y lectura histórica autorizada, con referencias archivadas necesarias; jamás ampliar lectura a privadas ajenas. Definir también lectura/versiones del editor ADMIN; el export interno no es API cliente. |
| B05 | `CookingRepository.ts:6` recupera por receta, `get_my_cooking_session(uuid)` por sesión. | Definir consulta de sesión abierta por receta y desempate si hay varias, para recuperación entre dispositivos. |
| B06 | `MockShoppingRepository.ts:46-54` selecciona fechas; `suggest_my_shopping('plan',...)` procesa el plan completo. | Agregar exactamente las fechas elegidas, incluso varias semanas, descontando despensa una sola vez. |
| B07 | Nombre de usuario sigue en JSON en Edge `admin-users/index.ts:139-164` y `admin_list_users`; perfil relacional posee su propio nombre/versión. | Evitar dos fuentes divergentes; adaptar lectura y escritura administrativas antes de activar perfiles relacionales. |
| B08 | Los convertidores existentes son ensayos con ROLLBACK; las migraciones estructurales no convierten los documentos personales ni importan el catálogo completo. | Preparar conversión permanente revisable con reconciliación reciente, orden de ejecución, backups/restauración y recuperación. No sustituir ROLLBACK por COMMIT sin revisar el guion completo y sus objetos auxiliares. |
| B09 | La configuración nutricional no incluye una semilla productiva aprobada; el dashboard agregado no sustituye recomendaciones/rankings de HomePage. | Publicar configuración inicial y completar composición del repositorio de inicio antes de activar esas pantallas. |
| B10 | No hay prueba integral de la aplicación conectada al modelo normalizado. | Probar USER/ADMIN, dos cuentas y dos dispositivos, recarga, pérdida de red, reintentos, democión/desactivación, versiones concurrentes y todos los flujos de stock antes de aprobar producción. |

Los B04-B07 son contratos o comportamientos aún por cerrar; no se resuelven únicamente traduciendo nombres de tablas. B01-B03 explican por qué los PASS actuales no permiten desplegar el frontend y el esquema sin trabajo adicional.

## Riesgos y mejoras adicionales

1. **Administración/Auth (P2, limitación conocida):** `admin-users/index.ts:113-115,148-164` comprueba el rol antes de usar Auth con service role. Una democión posterior no cancela una acción ya admitida. `set_role` y `set_active` sí usan RPC atómicas. Además, si falla la actualización Auth después de escribir el nombre JSON, quedan fuentes desincronizadas. Definir reconciliación/reintento explícito y documentar la semántica de acciones en curso.
2. **Precisión de cantidades (P2 de integración):** `RecipesTab.tsx:248` permite 0.000001, mientras las cantidades relacionales de receta son numeric(14,4). Alinear validación y mensaje de UI con la precisión admitida; no confundirla con multiplicadores de conversión de seis decimales.
3. **Vínculos de propietario (endurecimiento, P2):** las FK independientes de `cooking_events.session_id` y de `pantry_receipt_items` no imponen por sí solas que ambos extremos pertenezcan al mismo usuario. Las RPC actuales construyen esos vínculos con propiedad consistente y el cliente carece de DML. Un futuro escritor privilegiado podría violar esa invariancia; valorar FK compuestas o triggers si se exige garantía en toda escritura de servidor.
4. **Planes legacy duplicados (condicional):** `backfill/supabase_validation_rehearsal.sql:855-857` deriva un único ID/position por usuario-fecha-turno. Duplicados en el JSON abortan la conversión con rollback. La UI actual (`planner/domain/planner.ts:26-31`) sustituye la asignación anterior, por lo que no se identificó un flujo normal que cree ese estado; comprobarlo en el preflight y reportar anomalías, sin presumir que existan ni normalizarlas silenciosamente.
5. **Operación:** no se auditaron configuración real de Auth, SMTP, recuperación de cuentas, secretos desplegados, CORS/URLs productivas, backups restaurables, volumen/latencia real, índices bajo carga ni observabilidad. Son comprobaciones pendientes de entorno, no defectos confirmados del esquema. Antes del corte ejecutar inventario remoto de tablas/columnas/RPC/grants/RLS/versiones desplegadas y reconciliación actualizada por propietario.

## Matriz de cobertura funcional

| Flujo | Backend preparado | Integración o cierre pendiente |
| --- | --- | --- |
| Autenticación y administración de cuentas | Auth, roles/estado, RPC y Edge | Confirmar despliegue/configuración real; B01/B07 y riesgos Auth |
| Perfil/preferencias/favoritos | Lecturas/escrituras, aislamiento y versiones | Adaptadores, IDs y conflictos |
| Catálogo/etiquetas/unidades | CRUD administrativo, archivo, conversión, auditoría | Lecturas del editor y cambio desde JSON |
| Recetas/búsqueda/detalle | Guardado ADMIN, búsqueda, stock, tendencias | B04, precisión y referencias archivadas |
| Despensa y confirmación de lotes | Lecturas, CRUD/lote, validación/versiones | B02, manuales y confirmación sin DML directo |
| Planificación | Semanas, turnos, posiciones y versiones | Adaptador y fechas de sugerencias B06 |
| Compras/transferencias | Listas, artículos/orígenes, sugerencias, transferencia atómica | Adaptador y claves/versiones; B06 |
| Cocina/timers/historial | Sesiones persistentes, stock/finalización e historial | Reanudación B05, snapshots y versiones del cliente |
| Inicio/nutrición | Resumen, consultas y configuración versionada | Composición de HomePage y B09 |
| IA/OCR | Metadatos, permisos, estados y vencimiento | Proveedor, Edge de procesamiento y flujo real pospuestos por el usuario; no considerar la función completa |

## Secuencia recomendada

1. Cerrar contratos faltantes de recetas, sesiones y sugerencias; fijar lectura ADMIN y fuente del nombre.
2. Implementar adaptadores por módulo y control de activación; probar contra una copia del esquema final. Mantener coordinados nombres de tablas y Edge Function.
3. Preparar conversión definitiva y reconciliación, configuración inicial y recuperación; ensayar con una copia actual de datos. Revalidar fuente seed y precedencia de overrides.
4. Ejecutar pruebas E2E de roles/cuentas/dispositivos y concurrencia de extremo a extremo, además de verificar el entorno desplegado.
5. Aprobar un corte coordinado con escrituras detenidas/controladas, respaldo verificado, conversión, activación de la aplicación y comprobaciones posteriores. Conservar datos legacy durante la ventana de recuperación.

No corresponde dar un porcentaje global de backend listo a partir de 28 tablas o del número de pruebas. La aprobación final depende de cerrar los bloqueos y demostrar los flujos completos.

## Seguimiento de correcciones

2026-11-01: migración 010 implementada para detalle por UUID/legacy, recetas conocidas archivadas y lectura ADMIN individual de recetas oficiales con versión. Contrato en RECIPE_READ_CONTRACT.md. PASS local del ensayo completo desde siete tablas con rollback y 19 escenarios SQL posteriores; PASS remoto comunicado por el usuario del ensayo completo, sin instalación permanente. B04 queda parcialmente atendido en backend; falta conectar el adaptador y completar las lecturas de catálogo del editor.

Migraciones 011/012: implementadas recuperación de sesión abierta por receta (última iniciada, desempate por UUID, snapshot conservado) y sugerencias de compras para fechas concretas entre semanas (agregación previa y descuento único de despensa). B05/B06 atendidos en contrato backend; los adaptadores frontend siguen pendientes. Ensayo autocontenido `tests/resume_dates_rehearsal.sql` desde siete tablas y rollback verificado, más **21 escenarios SQL locales PASS**, ejecutados con `tests/run_table_rename_local.ps1 -ResumeDates -Port 55441`. La prueba inicial de día seleccionado esperaba erróneamente vacío y fue corregida antes del PASS. Resultado remoto de 011/012 pendiente; ningún despliegue permanente. B01-B03 y B07-B10 siguen vigentes.

2026-11-06: el usuario confirmó PASS remoto de 011/012 con rollback. Primera integración de perfil/administración preparada: migración 013, Edge Function y adaptador frontend con activación explícita. B07 atendido en código, pendiente verificación remota/E2E y activación coordinada; B03 parcialmente atendido solo para perfil. Ver PROFILE_ADMIN_INTEGRATION.md: 151 pruebas frontend y 22 escenarios SQL locales PASS. Ningún despliegue permanente; resto de módulos legacy pendiente. Se conservan los bloqueos de corte general.

2026-11-06: el usuario confirmó `PASS: profile admin contract verified; full script includes ROLLBACK` del ensayo remoto de perfil/administración (013). El rollback del script completo deshizo los cambios. Sigue pendiente la aplicación permanente y el flujo E2E desplegado.

2026-11-06: adaptador de despensa relacional preparado con flag `VITE_RELATIONAL_PANTRY`, lecturas/escrituras RPC, catálogo activo relacional, versiones y recarga explícita ante conflicto. Compatibilidad legacy preservada con flag desactivado. TypeScript y 158 pruebas frontend PASS. Ver PANTRY_INTEGRATION.md para límites y pendientes. Compras/cocina y otros módulos todavía requieren adaptación; sin nueva migración ni aplicación permanente.

2026-11-06: compras/transferencia preparadas mediante RPC, flag VITE_RELATIONAL_SHOPPING desactivado, procedencias y fechas seleccionadas conservadas, reintentos de transferencia con clave estable. TypeScript y 164 pruebas frontend PASS; ver SHOPPING_INTEGRATION.md. Sin aplicación permanente ni prueba E2E remota nueva. Cocina y módulos restantes siguen pendientes.

2026-11-06: cocina/historial preparados con VITE_RELATIONAL_COOKING desactivado por defecto; inicio/recuperación, progreso versionado, snapshots y finalización RPC transaccional. Historial de Inicio conecta al repositorio. TypeScript, 168 pruebas frontend y diff check PASS. Ver COOKING_INTEGRATION.md para límites. No se aplicó SQL ni se desplegó; recetas, planificación y resto de consumidores pendientes.

2026-11-06: lecturas personales de recetas y favoritos preparadas con VITE_RELATIONAL_RECIPES desactivado. Incluye listado/detalle/stock remoto, metadata UUID/legacy, cambios puntuales de favoritos y entrada compartida para consumidores. TypeScript y 174 pruebas frontend PASS. Ver RECIPES_INTEGRATION.md. Administración/editor de recetas y catálogo siguen pendientes, al igual que planificación e Inicio completo. Sin cambio SQL, ensayo remoto nuevo ni despliegue permanente.

2026-11-06: planificación semanal preparada mediante get_my_meal_plan/save_my_meal_plan, versión y sesión, recarga explícita y conexión con compras por fechas. Flag VITE_RELATIONAL_PLANNING desactivado. 182 pruebas frontend y TypeScript PASS; ver PLANNING_INTEGRATION.md. Sin SQL nuevo, aplicación permanente ni despliegue. Administración de catálogo/recetas e Inicio completo siguen pendientes.

2026-11-07: administración de categorías/unidades/ingredientes y recetas oficiales preparada con VITE_RELATIONAL_ADMIN desactivado. RPC versionadas, archivo/restauración, duplicación y proyección de borradores/inactivas. TypeScript, 193 pruebas frontend y diff check PASS; ver ADMIN_CATALOG_RECIPES_INTEGRATION.md. Sin cambios SQL, ensayo remoto nuevo ni despliegue. Inicio, auditoría final, datos iniciales/nutrición y conversión permanente pendientes.

2026-11-07: Inicio preparado mediante get_my_dashboard_summary y lecturas relacionales adicionales, con VITE_RELATIONAL_DASHBOARD desactivado. Contadores autoritativos, plan no disponible visible, snapshots recientes y protección sesión/cargas fuera de orden. TypeScript, 197 pruebas frontend y diff check PASS; ver DASHBOARD_INTEGRATION.md. Sin SQL nuevo, ensayo remoto ni despliegue. Sigue pendiente auditoría integral, datos iniciales/nutrición y conversión/activación permanente.

2026-11-07: auditoría integral consolidada. 197 pruebas frontend, TypeScript, build y 22 etapas SQL locales PASS; lint con advertencias. Confirmados pendientes A01-A07 en AUDITORIA_INTEGRAL_2026-11-07.md; corte permanente no aprobado. Sin cambios funcionales ni acceso remoto en esta auditoría.

2026-11-07: correcciones A03-A07 preparadas (métricas, nombres de auditoría, etiquetas, nutrición y precisión). Nueva migración 202611070001_admin_audit_profile_names.sql sin aplicar remotamente; ensayo completo con rollback local y 23 etapas SQL PASS. Frontend206/206, TypeScript/build/diff-check PASS. Ver AUDIT_CORRECTIONS_2026-11-07.md. A01/A02 siguen pendientes.

Continuación: inventario de solo lectura con resultados visibles y conversores de compras/progreso preparados. Ensayo integral de datos no vacíos, rollback e inventarios legacy/final y 24 etapas SQL locales PASS. Ver backfill/LEGACY_CONVERSION_STATUS.md. Inventario remoto aún sin conteos recibidos; «Success. No rows returned» no confirma su contenido. A01/A02 siguen condicionados a datos reales, anomalías y respaldo/corte.

Confirmación remota del usuario: PASS: legacy data conversion verified; full script includes ROLLBACK. Inventario actualizado y referencias (cero sin resolver) revisados; ensayo integral de conversión aprobado con datos reales. No hubo instalación permanente. A01 atendido en el ensayo para los datos examinados, sujeto a revalidación si cambian antes del corte; A02 respaldo restaurable, E2E y corte/recuperación siguen pendientes.
