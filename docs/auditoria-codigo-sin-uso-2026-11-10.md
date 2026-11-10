# Auditoría de código y archivos sin uso — 10 de noviembre de 2026

Se completó una primera auditoría estática y una limpieza conservadora de CocinAPP. Se preservaron los cambios de recetas que ya estaban presentes al comenzar. No se hicieron commits ni despliegues.

## Alcance y método

- Inventario de las carpetas de Entregas, excluyendo dependencias, compilaciones, metadatos Git, cachés y archivos de entorno. CocinAPP tenía 678 archivos en ese inventario inicial; las otras dos copias de trabajo tenían 461 y 478.
- Verificación con `git worktree list`: `CocinAPP`, `CocinAPP-backend-block3` y `CocinAPP-frontend-publish` son worktrees de ramas distintas. No son basura por tener archivos parecidos. Los otros dos worktrees no tenían cambios locales al comenzar y se conservaron íntegros.
- Análisis de imports relativos usando el compilador TypeScript instalado, resolución de módulos y recorrido desde `frontend/src/main.tsx`, incluyendo imports de CSS y `@import`. De 133 archivos TS/TSX/CSS en `src`, 132 eran alcanzables; solamente `src/App.css` quedó fuera del grafo.
- Análisis de símbolos exportados y búsqueda textual adicional en código, pruebas, scripts y documentación. La ausencia de import directo es una pista: los reexports y los usos internos se verificaron antes de borrar.
- Búsqueda de referencias a recursos en el repositorio, revisión de `index.html`, manifest y configuración Vite, y búsqueda de carga dinámica. No se encontraron consumidores de los recursos eliminados.
- Investigación independiente del backend y revisión independiente de la limpieza del frontend por un subagente, conforme a `AGENTS.md`.

El inventario abarca toda la carpeta; el análisis de dependencias y la limpieza de código se concentraron en el proyecto principal. No se inspeccionó el contenido de cada documento Word/Excel/ZIP ni se auditó línea por línea el código de los otros worktrees. No se consultó ni modificó la base de datos remota y no se leyeron archivos `.env`.

## Limpieza aplicada

### Archivos eliminados

| Archivo relativo a frontend | Evidencia |
| --- | --- |
| `src/App.css` | CSS de la plantilla inicial, sin imports. Incluía `.counter`, `.hero` y secciones de enlaces de Vite. |
| `src/assets/react.svg` | Recurso de la plantilla sin referencias. |
| `src/assets/vite.svg` | Recurso de la plantilla sin referencias. |
| `src/assets/hero.png` | Imagen de la plantilla sin referencias. |
| `public/icons.svg` | Símbolos de redes de la plantilla sin referencias. |
| `public/favicon.svg` | Favicon sin referencias; `index.html` usa `cocinapp-favicon-64.png`. |

Los seis archivos estaban versionados en Git antes de eliminarlos. Los recursos originales pueden recuperarse del historial sin restaurar otros cambios del usuario.

### Funciones eliminadas

| Archivo relativo a frontend/src | Símbolo eliminado | Motivo |
| --- | --- | --- |
| `app/AuthGuards.tsx` | `RequireAuth` | Sin consumidores. Las rutas usan `RequireUser`, `RequireAdmin` y `RedirectIfAuthenticated`. |
| `features/auth/domain/routeAccess.ts` | `unknownPathDestination` | Wrapper sin consumidores de `roleHome`, que se conserva. |
| `features/admin/domain/adminModels.ts` | `isAdminEntityActive` | Sin referencias. |
| `features/admin/data/localAdminStore.ts` | `getUnitsForIngredient` | Sin referencias. Se quitó también su import exclusivo de `compatibleUnitAbbreviations`; la utilidad compartida sigue existiendo. |
| `features/admin/data/relationalAdminCatalog.ts` | Export `getCatalogCore` al final del archivo | Wrapper sin consumidores. Se conservaron el método del repositorio y sus llamadas internas. |
| `features/recipes/data/localFavoritesStore.ts` | `saveFavoriteIds` | Wrapper sin consumidores. Se conservaron `getFavoriteIds`, los repositorios y sus operaciones `saveIds`. |

Se corrigieron las referencias a `App.css` en el README del frontend, el README de estilos y `docs/architecture.md`.

## Elementos conservados y pendientes

| Elemento | Decisión y evidencia |
| --- | --- |
| Repositorios `Mock*`, cachés locales y `legacySupabasePantryRepository.ts` | Permanecen conectados al grafo de la aplicación. Los modos local, remoto y relacional requieren revisar las condiciones de configuración antes de reducir compatibilidad. |
| `public/assets/branding/cocinapp-logo-original.png` | No se encontró referencia por nombre. Se conserva como original de diseño; no se puede inferir que sea descartable por no mostrarse en pantalla. |
| Imágenes de recetas | No se encontraron imágenes sin referencia por nombre en el proyecto. Las rutas también pueden estar persistidas en datos remotos. |
| Interfaces y exports usados internamente | Una exportación innecesaria no implica que la implementación esté desconectada. No se eliminaron contratos ni tipos usados localmente. |
| Migraciones SQL | Preservan la reconstrucción y evolución de la base. No se borran por haber sido reemplazadas por migraciones posteriores. |
| Archivos `*.stage.sql`, fixtures, backfill y operaciones | Tienen consumidores en generadores y runners o un papel documentado en ensayos, conversión y recuperación. No se confirmó lógica huérfana del backend. |
| `backend/supabase/tests/__pycache__/*.pyc` | Caché regenerable e ignorada por Git; prescindible, pero no se borró en esta limpieza de código. |
| Prototipos HTML, diagramas, documentos y `Specs.zip` | Material de diseño, documentación o entregas; estar fuera de Vite es esperable. Requieren una decisión documental para descartar versiones. |
| `node_modules`, `dist` y `.temp` | Dependencias, salida de compilación y estado de herramientas. No se clasificaron como código abandonado. `dist` se regeneró al verificar. |
| `docs/architecture.md` y documentación de etapas | Hay descripciones históricas que no reflejan las integraciones actuales. Se corrigió la mención al CSS eliminado; la actualización integral del contenido queda pendiente. |
| Selectores de `src/index.css` y estilos de features | No se purgaron por ausencia textual: existen nombres construidos con interpolación, variantes, pseudoclases y estados responsivos. Requieren inventario de selectores y cobertura de pantallas/estados. |

## Validación local

- Antes: `npm run typecheck` pasó; `npm test` pasó con **211/211** pruebas; `npm run build` pasó.
- Después: `npm test` pasó con **211/211** pruebas; `npm run build` pasó, incluyendo `tsc -b`.
- `npm run lint` terminó con código 0 antes y después. Permanecen **21 advertencias** preexistentes de React, hooks y refs.
- `git diff --check` pasó tras corregir líneas vacías al final de dos archivos.
- El CSS compilado conserva exactamente el mismo SHA-256 antes y después: `55CA7E0B50E8AA20119503C16D33A1B09A4518ACCD7A69527D8D1726A71FC1C2`.
- El JavaScript compilado cambió de hash; no se afirma identidad binaria del bundle JS. La compilación conserva la advertencia preexistente de un chunk mayor a 500 kB.

Estas verificaciones respaldan la limpieza local; no sustituyen una comprobación visual de todos los flujos ni prueban el estado de una instalación remota. No se ejecutaron pruebas SQL contra Supabase.

## Próximo grupo sugerido

1. Auditar selectores CSS con sus consumidores dinámicos y verificar visualmente las pantallas afectadas antes de eliminar reglas.
2. Revisar cada modo de configuración para determinar qué compatibilidad legacy sigue siendo necesaria en las instalaciones que se usan.
3. Actualizar la documentación histórica y decidir cuáles prototipos y originales se conservan como material de entrega.

No hacer una restauración global de Git para deshacer esta limpieza: ya existían modificaciones y archivos nuevos del usuario al comenzar.
