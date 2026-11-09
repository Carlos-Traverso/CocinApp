# Cocina: integración relacional

Fecha: 2026-11-06. Activación explícita: `VITE_RELATIONAL_COOKING=true`, desactivada por defecto. Requiere la cadena de migraciones relacionales y los renombres de 009. Coordinar con las integraciones de despensa y compras antes del corte general.

## Contratos existentes

`start_my_cooking_session` inicia con UUID proporcionado por el cliente y crea la copia de receta, ingredientes y pasos. `get_my_open_cooking_session` recupera una sesión abierta y `get_my_cooking_session` obtiene el estado guardado. Las actualizaciones de pasos, porciones y temporizadores usan `update_my_cooking_session` con versión esperada.

La receta guardada en la sesión prevalece al retomar la cocina. Los temporizadores utilizan las fechas límite del servidor; sonido y notificaciones siguen siendo tareas del navegador. Cambiar de paso pausa el temporizador anterior según el contrato SQL.

`check_my_cooking_stock` es una consulta previa; la autoridad para finalizar es `finish_my_cooking_session`, que descuenta existencias y registra el evento dentro de la misma transacción. Un reintento de finalización conserva sesión y decisión de descuento; no debe aplicar stock ni historial local por separado.

El historial usa `get_my_cooking_history` con paginación por fecha/UUID; ocultar y limpiar mediante `hide_my_cooking_history_entry` y `clear_my_cooking_history`. Las copias históricas permiten mostrar eventos aunque la receta actual cambie.

## Pendientes del corte

Esta preparación no aplica migraciones permanentes ni despliega la aplicación. Los ensayos anteriores con ROLLBACK no instalaron el esquema remoto. Recetas, planificación, catálogo administrativo y resumen de inicio todavía requieren integración completa antes del despliegue coordinado.

## Verificación y límites

Validación local final: TypeScript PASS, **168/168 pruebas frontend PASS** y `git diff --check` PASS. Cuatro pruebas nuevas verifican inicio/UUID y versiones, conflicto/reintento de finalización, historial por snapshot y descarte de respuesta tras cambio de sesión. Revisión independiente de contratos y adaptador completada; se corrigieron el mapeo `completed_at`, la comparación con el progreso anterior, las porciones de inicio y las acciones de temporizador.

Una actualización que combina varias acciones usa RPC secuenciales, no una transacción única; ante un fallo parcial se requiere recarga explícita. La finalización sí es transaccional e idempotente en SQL. La UI conserva la decisión de descuento ante una respuesta incierta; un rechazo explícito permite recuperación. El descuento ya no se aplica al almacenamiento local en el camino relacional.

El historial consulta hasta 10.000 eventos por paginación. El resumen Inicio usa ahora el repositorio de cocina para su historial, aunque el resto del resumen sigue pendiente de integración. Las rutas de receta actuales continúan siendo una dependencia del adaptador de recetas pendiente; mostrar un snapshot histórico no garantiza que el enlace al detalle actual funcione.

No hubo cambios SQL ni un ensayo remoto nuevo en esta etapa. No hay un script nuevo que ejecutar en SQL Editor. Faltan la prueba de navegador contra una copia del esquema final y la aplicación permanente coordinada. Próximo paso recomendado: adaptar recetas y sus lecturas de catálogo, y luego planificación para cerrar los consumidores que todavía usan el modelo anterior.
