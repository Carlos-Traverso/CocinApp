# Inicio: resumen relacional

Fecha: 2026-11-07. Activación frontend mediante `VITE_RELATIONAL_DASHBOARD=true`, desactivada por defecto. Requiere el esquema relacional y `get_my_dashboard_summary` (migración 008, compatible con renombres 009). Coordinar con los demás adaptadores antes del corte general.

## Contrato y lecturas

El resumen recibe la fecha local de la aplicación y devuelve `as_of`, perfil/preferencias, contadores de despensa, favoritos y compras, plan del día y preparaciones recientes. Esos datos no equivalen a colecciones completas de artículos o recetas. Las recomendaciones necesitan además las lecturas relacionales de catálogo, despensa, unidades y favoritos.

Las recetas embebidas en los turnos de hoy y las copias históricas del historial conservan su significado aunque el catálogo actual cambie. Las referencias no disponibles se deben mostrar sin ofrecer una acción de cocina incorrecta.

No se importan colecciones locales ni se escribe en Supabase por consultar Inicio. Los flags anteriores permanecen separados y deben activarse coordinadamente. Las pruebas locales no sustituyen una prueba de navegador contra el esquema final.

## Pendientes del corte

Después de integrar Inicio corresponde revisar todos los consumidores, datos iniciales, nutrición y permisos; preparar respaldo y conversión verificados; ensayar el producto contra una copia del esquema final y desplegar coordinadamente. No se aplican migraciones permanentes ni se configura IA en esta etapa.

## Validación local y límites

TypeScript PASS; suite completa **197/197 PASS**; pruebas focalizadas de Inicio **8/8 PASS**; `git diff --check` PASS. Cuatro casos nuevos verifican contadores exactos y fecha local, datos/snapshots/ausencias del plan, rechazo de resumen malformado, cambio de sesión y cargas fuera de orden. Revisión independiente final sin hallazgos P1 pendientes.

Los contadores se toman del resumen; las recomendaciones utilizan lecturas reales adicionales de recetas, despensa, unidades y favoritos. El historial de Inicio usa las cuatro preparaciones recientes devueltas por el resumen; el historial completo sigue disponible en su pantalla propia. El resumen y las lecturas adicionales no forman un único snapshot transaccional: cambios concurrentes pueden producir diferencias temporales entre contadores y recomendaciones.

Los turnos no disponibles conservan una tarjeta con su referencia, sin enlaces de detalle/cocina incorrectos. Las preparaciones recientes priorizan su snapshot y resuelven el ID histórico cuando la receta sigue disponible. Cualquier fallo necesario para la carga se informa, sin sustituirlo por colecciones vacías.

No se modificó SQL ni se ejecutó un ensayo remoto nuevo. No hay un script nuevo que aplicar en SQL Editor en esta etapa. Quedan pendientes auditoría integral de consumidores/permisos, datos iniciales y nutrición, ensayos contra copia final, respaldo/conversión y despliegue coordinados.
