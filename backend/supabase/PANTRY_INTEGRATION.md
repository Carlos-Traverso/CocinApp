# Despensa: integración relacional preparada

Fecha: 2026-11-06. Activación frontend: `VITE_RELATIONAL_PANTRY=true`; desactivada por defecto. Requiere la cadena relacional y los renombres de 009. Este trabajo no aplica migraciones ni despliega la aplicación.

## Contratos existentes

Lectura mediante `get_my_pantry`; altas y cambios mediante `put_my_pantry_items`; borrado mediante `delete_my_pantry_item`. Las versiones leídas controlan la concurrencia. Los UUID de altas se mantienen durante un reintento; una respuesta perdida de actualización puede requerir recarga y reconciliación. El catálogo activo se obtiene de `categorias`, `unidades` e `ingredientes` usando SELECT autorizado por RLS, sin importar el JSON legacy como catálogo relacional.

Las unidades se envían como abreviaturas existentes, las cantidades admiten hasta cuatro decimales y las referencias de ingrediente se seleccionan del catálogo relacional. Los datos históricos y la procedencia de compras se conservan; no se infieren UUID relacionales a partir de identificadores legacy.

## Pendientes del corte

Compras y cocina siguen teniendo flujos locales que modifican existencias. Deben adaptarse a sus RPC antes de activar la aplicación completa: transferencias y finalización de cocina no deben convertirse en guardados de una colección local sobre el stock remoto. También siguen pendientes los demás consumidores y el catálogo administrativo relacional.

El flag de despensa no constituye autorización de despliegue ni compatibilidad completa del producto. La aplicación permanente requiere respaldo, conversión de datos, integración de módulos restantes y despliegue coordinado. El ensayo remoto aprobado de perfil/administración fue con ROLLBACK y no instaló el esquema.

## Validación local y límites

`npm run typecheck`: PASS. `npm test`: **158/158 PASS**, incluyendo siete casos del adaptador relacional: snapshots manuales/asociados, versiones enviadas a RPC, rechazo de operaciones mixtas antes de escribir, conflicto y recarga, cambio de sesión pendiente y respuestas fuera de orden. Los dobles de cliente verifican integración del adaptador; no equivalen a una prueba de navegador contra Supabase.

Las altas/cambios se confirman en un lote atómico de hasta 200 cambios; el borrado es de un solo artículo por operación. Se rechazan antes de escribir los guardados que mezclan cambios y borrados o varios borrados. Ante resultado remoto incierto o conflicto se requiere recarga explícita. La lectura paginada verifica duplicados y coherencia de conteos, pero no garantiza un snapshot transaccional entre páginas durante modificaciones concurrentes. Las versiones fuera del rango entero seguro de JavaScript se rechazan.

No se modificaron contratos SQL ni migraciones en esta etapa. No hace falta repetir los ensayos SQL ya aprobados ni ejecutar un script nuevo en Supabase para preparar este código. Queda pendiente el ensayo de la aplicación contra una copia del esquema final y la aplicación permanente coordinada.
