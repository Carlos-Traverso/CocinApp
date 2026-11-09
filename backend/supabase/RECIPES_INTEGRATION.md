# Recetas: integración relacional

Fecha: 2026-11-06. Opción frontend `VITE_RELATIONAL_RECIPES=true`, desactivada por defecto. Requiere el esquema relacional y las migraciones de lectura 010; activar junto con perfil, despensa, compras y cocina durante el corte coordinado.

## Contratos

`search_my_recipes` para descubrimiento y filtros; `list_known_recipes` para referencias históricas visibles; `get_my_recipe_detail` para detalle. La autorización permanece en SQL: recetas oficiales publicadas y recetas propias, con lectura histórica explícita cuando corresponde. Ser administrador no concede lectura de recetas privadas ajenas.

Los identificadores históricos se resuelven mediante el argumento `p_legacy_id`; el UUID real se conserva por separado para operaciones relacionales. La resolución de rutas consulta primero el identificador histórico y luego, cuando corresponde, el UUID explícito. Esto conserva los identificadores históricos que tienen formato UUID.

La disponibilidad usa `check_my_cooking_stock` o el stock del descubrimiento. Los favoritos se consultan con `get_my_favorites` y se cambian mediante `set_my_favorite`, sin importar automáticamente los favoritos locales.

## Alcance del corte

Este adaptador prepara la lectura de recetas y sus acciones personales. La administración de recetas/catálogo es un consumidor diferente y necesita su propio adaptador; no se considera integrada por conectar el listado público. No se configura IA ni se crean servicios externos.

No se aplican migraciones permanentes ni despliegues en esta etapa. Quedan pendientes pruebas de navegador sobre una copia del esquema final y la conversión/despliegue coordinados del producto.

## Validación y límites

Validación local final: TypeScript PASS, **174/174 pruebas frontend PASS**, revisión independiente de contratos/adaptador y `git diff --check`. Seis casos nuevos cubren mapeo y filtros, precedencia de claves históricas UUID, rutas UUID nativas, lectura histórica explícita, respuestas de sesión inválidas y cambios puntuales de favoritos/propietario.

Los lectores paginan hasta el límite de desplazamiento del contrato SQL y fallan si se supera. Las páginas no constituyen un snapshot transaccional durante escrituras concurrentes. El reemplazo completo de favoritos (`saveIds`) se rechaza en modo relacional; las pantallas usan `setFavorite` por receta para conservar cambios de otros dispositivos. Los favoritos no disponibles se conservan en servidor y no se incluyen en la lista visible.

La entrada compartida `mockRecipeRepository` selecciona el adaptador relacional con el flag, incluyendo lectores de Inicio, planificación y cocina. Esto conecta esas lecturas de recetas, pero no sustituye la adaptación pendiente de planificación o del resumen completo. Cocina reconoce el UUID explícito de las recetas nuevas; las rutas históricas conservan su precedencia.

No se agregaron migraciones ni se repitieron ensayos remotos aprobados. Falta verificar estos flujos en navegador contra una copia del esquema final y desplegar de forma coordinada. Próxima etapa recomendada: planificación, seguida por administración de catálogo/recetas y resumen de Inicio, antes de preparar la conversión permanente.
