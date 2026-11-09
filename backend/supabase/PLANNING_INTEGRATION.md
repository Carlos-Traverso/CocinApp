# Planificación: integración relacional

Fecha: 2026-11-06. Activación frontend mediante `VITE_RELATIONAL_PLANNING=true`, desactivada por defecto. Requiere el esquema relacional, las RPC de planificación/lectura y los renombres de tablas de 009. Coordinar con recetas y compras durante la activación del producto.

## Contrato

`get_my_meal_plan(p_week_start)` consulta una semana que comienza en lunes. `save_my_meal_plan(p_week_start,p_slots,p_expected_version)` reemplaza esa semana dentro de una transacción, preserva su identidad y controla la versión. Para una semana nueva se envía versión 0. Los identificadores de slots los genera el servidor; fecha, turno y posición conservan su identidad funcional.

El backend admite hasta 140 entradas semanales con porciones 1..20 y posición 1..100. Las referencias inactivas se devuelven como `available=false` y no se eliminan automáticamente. El contrato de guardado actual requiere recetas disponibles en todos los slots enviados: se deben retirar o reemplazar las referencias no disponibles antes de guardar.

Las sugerencias de compras usan las fechas seleccionadas mediante el repositorio de compras; la RPC existente agrupa necesidades y descuenta la despensa una sola vez. No se importan automáticamente planes locales al esquema relacional.

## Corte pendiente

No se aplican migraciones permanentes ni despliegues en esta etapa. Faltan administración de catálogo/recetas, integración completa de Inicio, auditoría final de consumidores y conversión/respaldo coordinados. La validación local no sustituye las pruebas de navegador contra una copia del esquema final.

## Validación y límites

TypeScript PASS, suite completa frontend **182/182 PASS**, pruebas focalizadas de planificación **17/17 PASS**, revisión independiente sin hallazgos P1 pendientes y `git diff --check` PASS. Ocho casos nuevos verifican mapeo UUID/versiones, semana vacía, referencias inactivas, posiciones adicionales, rechazo multi-semana, conflicto con recarga, cambio de sesión y lecturas fuera de orden.

La pantalla expone recarga explícita y bloquea navegación mientras guarda. Puede quitar todas las referencias no disponibles mediante confirmación. La edición de un turno con varias posiciones se bloquea para conservar las entradas que la UI actual no muestra; los demás slots se preservan. El reemplazo de una semana es atómico; una respuesta perdida requiere recargar para reconciliar, no reintentar a ciegas con una versión nueva.

La consulta sin semana explícita, utilizada por Inicio, carga la semana local actual. Los flags de recetas y compras deben activarse coordinadamente; el resumen de Inicio completo aún requiere su adaptador específico. No se modificaron migraciones ni se ejecutó un ensayo remoto nuevo: faltan prueba de navegador sobre una copia final y despliegue coordinado.

Próximo trabajo recomendado: administración de catálogo y recetas. Después cerrar Inicio y realizar la auditoría final de consumidores antes de preparar el respaldo y la migración permanente.
