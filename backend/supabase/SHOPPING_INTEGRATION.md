# Compras: adaptación relacional

Fecha: 2026-11-06. Activación explícita mediante `VITE_RELATIONAL_SHOPPING=true`, desactivada por defecto. Requiere el esquema relacional, sus RPC y los renombres de tablas de 009. Coordinar con `VITE_RELATIONAL_PANTRY=true`; los consumidores restantes deben estar adaptados antes del corte general.

## Contratos

Lectura: `get_my_shopping_list`. Escrituras: `create_my_shopping_list`, `put_my_shopping_item`, `set_my_shopping_checked`, `remove_my_shopping_item`. Las mutaciones usan la versión de la lista; los artículos y la lista se crean con UUID proporcionados por el cliente.

Transferencia: `transfer_my_shopping_to_pantry` confirma existencias y comprobante en una transacción. Un resultado incierto debe reintentarse con la misma lista, artículos y clave de idempotencia. No debe sumarse stock localmente como parte de esa operación.

Sugerencias: `suggest_my_shopping` para favoritos/reposición y `suggest_my_shopping_for_dates` para las fechas seleccionadas. Los vínculos de procedencia (`recipe_id`, `plan_id`) deben conservarse al editar y consolidar propuestas; los identificadores históricos del catálogo no son UUID relacionales.

## Corte pendiente

Esta etapa prepara código, sin aplicar migraciones permanentes ni desplegar. Los ensayos SQL aprobados con ROLLBACK no instalaron el esquema remoto. Cocina, planificación y recetas todavía necesitan su adaptación completa; la conexión de compras no convierte esos módulos en integraciones verificadas.

## Validación y límites

TypeScript y suite completa frontend: **164/164 PASS**. Seis pruebas nuevas cubren UUID/versiones, clave estable tras timeout de transferencia, respuestas fuera de orden, conflicto con recarga explícita, fechas/procedencia y cambio de sesión durante catálogo. Revisión independiente de contratos y adaptador completada.

Un guardado admite un artículo cambiado o un borrado. La incorporación de múltiples sugerencias usa operaciones secuenciales: puede completarse parcialmente; se debe recargar y reconciliar si falla. La transferencia sí es atómica en SQL. Los artículos transferidos conservan su comprobante y se muestran sin edición ni desmarcado; las existencias se corrigen desde Despensa. El catálogo se obtiene con el lector relacional de despensa; siguen pendientes su validación E2E y los volúmenes mayores al límite de SELECT del servidor.

No se modificó SQL en esta etapa ni se ejecutó un ensayo remoto nuevo. No hay acciones que ejecutar ahora en SQL Editor para instalar este código. La prueba de navegador contra una copia del esquema final y el despliegue coordinado siguen pendientes. Próximo módulo recomendado: cocina (sesiones, recuperación y finalización con descuento transaccional).
