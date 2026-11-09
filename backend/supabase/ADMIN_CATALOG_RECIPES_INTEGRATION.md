# Administración relacional de catálogo y recetas

Fecha: 2026-11-07. Flag frontend `VITE_RELATIONAL_ADMIN=true`, desactivado por defecto. Requiere las migraciones relacionales, renombres de 009 y lectura administrativa de 010. Coordinar con los demás adaptadores antes de activar el producto.

## Alcance y contratos

Categorías, unidades e ingredientes se leen de `categorias`, `unidades` e `ingredientes` bajo autorización administrativa y RLS. Las escrituras utilizan `admin_put_category`, `admin_put_unit` y `admin_put_ingredient`; conservan la versión leída al cargar y requieren recarga ante conflicto. El borrado es archivo lógico, con restauración explícita.

Recetas oficiales: lectura de identificadores administrativos y `admin_get_recipe` para contenido y versión, incluyendo borradores e inactivas. Guardado con `admin_save_recipe`, duplicado con `admin_duplicate_recipe`, estados mediante `admin_set_recipe_flags`. No concede acceso a recetas privadas ajenas. La conversión de datos iniciales no se ejecuta desde el editor: una receta sin referencias relacionales requiere la conversión de datos correspondiente.

La interfaz conserva los contratos anteriores mientras el flag está apagado. La activación no importa automáticamente colecciones locales ni usa escrituras JSON alternativas ante un rechazo de permisos.

## Pendientes del despliegue

Esta etapa prepara código local; no aplica migraciones ni despliega. Faltan Inicio completo, auditoría de consumidores y datos iniciales/nutrición, conversión y respaldo verificados, pruebas de navegador contra copia del esquema final y corte coordinado. Los ensayos remotos anteriores con ROLLBACK no instalaron permanentemente el esquema.

## Validación local y límites

TypeScript PASS; suite completa **193/193 PASS**; `git diff --check` PASS. Once pruebas nuevas verifican lecturas y nombres relacionales, payload/versión, permisos/sesión, reintentos con UUID estable, archivo/restauración y preservación de cantidades específicas al reordenar pasos. La revisión independiente detectó y permitió corregir versión refrescada indebidamente, nombres previos a 009, claves por sesión y cantidades asociadas por índice de paso.

El formulario y el listado administrativo usan las recetas oficiales completas, incluidos borradores y registros archivados. Activar una receta archivada solicita restauración explícita al servidor. Los conflictos requieren recargar y revisar la edición; una escritura ya enviada puede haberse confirmado aunque su respuesta se pierda. Los UUID de altas/duplicados se conservan para reintentos del mismo contenido en la misma sesión. Las versiones fuera del formato admitido se rechazan.

Las pruebas usan dobles de cliente y no demuestran todavía el navegador contra Supabase desplegado. No hubo cambios SQL ni ensayo remoto nuevo. No hace falta ejecutar un script nuevo en SQL Editor para preparar este código. Las funciones de nutrición/preferencias y las demás lecturas administrativas deben revisarse en la auditoría final; no se consideran cubiertas solo por adaptar categorías, unidades, ingredientes y recetas.

Próximo paso recomendado: integrar Inicio mediante el contrato de resumen existente. Después revisar todos los consumidores, datos iniciales y nutrición antes de preparar respaldo, conversión y activación permanente.
