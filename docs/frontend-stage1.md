# Frontend · criterios de aceptación de etapa 1

Este documento traduce el pedido de etapa 1 a una lista revisable por flujo y describe las interfaces mock que preparan el frontend para una integración posterior. El alcance es una demo local: los flujos no necesitan Supabase, una API de recetas ni servicios de reconocimiento.

**Estado:** verificaciones automatizadas aprobadas y recorridos manuales principales completados. Los límites de cobertura manual se detallan al final.

## Matriz de aceptación

| Flujo | Criterio verificable de aceptación | Evidencia principal | Estado |
| --- | --- | --- | --- |
| Perfil y preferencias | Guardar y volver a cargar datos del perfil y las cinco preferencias; filtrar descubrimiento y recomendaciones con preferencias activas; explicar exclusiones y ausencia de resultados; mostrar el carácter informativo de etiquetas y calorías. | `pages/ProfilePage.tsx`, `features/profile/domain/profile.ts`, `features/recipes/data/RecipeRepository.ts` | Recorrido manual realizado. |
| Búsqueda y filtros de recetas | Buscar por título o ingrediente; combinar turno, etiqueta, dificultad y tiempo; limpiar filtros; identificar filtros activos y cantidad/estado de resultados. | `pages/RecipesPage.tsx`, `features/recipes/domain/recipeRules.ts` | Recorrido manual realizado. |
| Matching y faltantes | Mostrar coincidencia y los tres rangos acordados; detallar cantidades faltantes escaladas a porciones; comparar solo unidades compatibles de la misma dimensión. | `features/recipes/domain/recipeRules.ts`, `features/recipes/data/MockRecipeRepository.ts`, `shared/domain/units.ts` | Cubierto por regresiones automatizadas. |
| Detalle y porciones | Cambiar porciones entre 1 y 20; actualizar cantidades; mostrar kcal por porción y total cuando hay datos, con aviso orientativo. | `pages/RecipeDetailPage.tsx`, `features/recipes/domain/recipeRules.ts` | Recorrido manual realizado. |
| Cocinar Ahora | Comprobar cada ingrediente antes de descontar; bloquear el descuento si falta stock e informar disponible, requerido y faltante; permitir finalizar sin descuento y comunicar los ingredientes agotados. | `pages/CookingPage.tsx`, `features/cooking/data/CookingRepository.ts`, `features/cooking/domain/cooking.ts` | Recorrido y regresiones realizados; no constituye atomicidad de servidor. |
| Modo cocina | Avanzar y retroceder por pasos, mostrar progreso y guías, y usar temporizadores con inicio, pausa, reanudación, reinicio y alertas visuales/sonoras sujetas a permisos del navegador. | `pages/CookingPage.tsx`, `features/cooking/domain/cooking.ts` | Recorrido manual y lógica automatizada revisados. |
| Planificador semanal | Mostrar lunes a domingo y cuatro turnos; cambiar semana; asignar, mover, quitar y guardar porciones por asignación; conservar semanas independientes y anunciar cambios/errores. | `pages/PlannerPage.tsx`, `features/planner/data/PlannerRepository.ts`, `features/planner/domain/planner.ts` | Recorrido manual realizado. |
| Compras | Crear y editar artículos, buscar, filtrar, marcar y eliminar; diferenciar texto libre de asociación válida; generar necesidades del plan por porciones, consolidar conversiones compatibles y descontar stock; transferir solo filas asociadas válidas sin duplicar transferencias. | `pages/ShoppingPage.tsx`, `features/shopping/data/ShoppingRepository.ts`, `features/shopping/domain/shopping.ts` | Recorrido y regresiones realizados. |
| Compartir compras | Ofrecer texto plano consolidado, copia al portapapeles, compartir nativo si existe y enlace codificado de WhatsApp; mantener alternativa de copia visible si compartir no está disponible. | `pages/ShoppingPage.tsx`, `features/shopping/domain/shopping.ts` | Copia y enlace codificado comprobados; compartir nativo depende del dispositivo. |
| Administración | Validar campos obligatorios, cantidades, dimensiones y duplicados; administrar categorías, unidades, ingredientes y recetas; conservar con baja lógica los registros referenciados; mantener restricciones de rol como protección visual. | `pages/AdminPage.tsx`, `features/admin/data/AdminRepository.ts`, `features/admin/domain/adminValidation.ts` | Recorrido manual realizado; el rol no es autorización real. |
| Unidades compartidas | Usar conversiones centralizadas para g/kg, ml/l, conteo y unidades compatibles definidas; no inferir equivalencias entre dimensiones; rechazar cantidades/unidades inválidas en operaciones de dominio. | `shared/domain/units.ts`, `features/pantry/domain/pantry.ts`, dominios de recetas, cocina y compras | Cubierto por regresiones automatizadas. |
| Colección Personal | Mantener sección con favoritos activos y filtrar por turno y etiquetas; excluir recetas generadas por IA. | `pages/RecipesPage.tsx`, `components/navigation.ts`, `features/recipes/data/localFavoritesStore.ts` | Recorrido manual realizado. |
| Escaneo de tickets | Elegir o tomar imagen compatible; validar tipo y límite de 5 MB; procesar respuesta mock cancelable; revisar/editar filas, asociarlas al catálogo y confirmar antes de modificar la despensa; no guardar ni subir bytes. | `pages/PantryPage.tsx`, `features/pantry/data/mockReceiptScanner.ts` | Flujo mock revisado; cámara nativa depende del dispositivo. |

## Contratos y sustitución de mocks

Las interfaces viven bajo `frontend/src/features/*/data`. Las páginas consumen funciones asíncronas para que carga, éxito y error tengan la misma forma que una futura operación remota. Las implementaciones actuales resuelven localmente y pueden usar almacenamiento del navegador dentro de la capa de datos.

| Dominio | Contrato o fachada | Implementación actual y límite |
| --- | --- | --- |
| Autenticación | `AuthRepository` | `authRepository`; cuentas/sesiones locales de demostración. No es Supabase Auth ni gestión segura de credenciales. |
| Perfil | `ProfileRepository` | `profileRepository`; perfil y preferencias locales. |
| Recetas | `RecipeRepository` | `mockRecipeRepository`; catálogo curado, matching, detalle y recomendaciones mock. No genera recetas con IA. |
| Despensa | `PantryRepository` | `pantryRepository`; lectura y guardado local. |
| Escaneo | `ReceiptScanner` | `mockReceiptScanner`; acepta señal de cancelación y devuelve filas de ejemplo. No reconoce texto real ni transmite la imagen. |
| Cocina e historial | `CookingRepository` | `mockCookingRepository`; sesión, historial, verificación y operación local de descuento. No garantiza transacciones distribuidas o concurrencia de servidor. |
| Planificador | `PlannerRepository` | `mockPlannerRepository`; asignaciones y recetas cargadas de forma asíncrona; la generación de compras delega al contrato de compras. |
| Compras | `ShoppingRepository` | `mockShoppingRepository`; lista, sugerencias, estados y transferencia local a despensa. |
| Inicio | `DashboardRepository` | `mockDashboardRepository`; composición de datos de demostración de otros dominios. |
| Administración | `AdminRepository` | `adminRepository`; catálogo y acciones locales. La restricción por rol es visual, sin seguridad de backend. |

No hay acceso de páginas a `localStorage` directamente. El almacenamiento, la normalización de modelos locales y los mecanismos de fallback pertenecen a los adaptadores mock. La persistencia del navegador permite demostrar flujos, pero no aporta aislamiento multiusuario, autorización, sincronización ni garantías transaccionales reales.

## Discrepancias y decisiones pendientes frente al SRS

La especificación fuente es [`Especificación de Requisitos Traverso Pugnaloni.docx`](../../Especificación%20de%20Requisitos%20Traverso%20Pugnaloni.docx). Las instrucciones de etapa 1 tienen prioridad para esta entrega; las siguientes diferencias deben permanecer explícitas para una revisión de alcance, sin implementar servicios o funciones adicionales:

| SRS | Diferencia respecto del alcance de frontend | Interpretación conservadora de etapa 1 |
| --- | --- | --- |
| Alcance, RF-01 y restricciones de persistencia | El SRS describe Supabase Auth, PostgreSQL, RLS, funciones y persistencia relacional; el pedido actual limita esta etapa a adaptadores mock locales. | Demostrar registro, inicio/cierre y roles locales. No presentar el guardado local ni los guards como autenticación, autorización o seguridad real. |
| Alcance, RF-05 y privacidad | El SRS requiere procesamiento externo con Gemini y menciona Edge Functions; la etapa 1 prohíbe subir imágenes o incorporar credenciales y exige un flujo mock. | Validar la imagen localmente, ofrecer propuesta editable mock y confirmar antes de tocar stock. Informar que el servicio externo pertenece a una etapa futura. |
| Alcance, RF-03 y generación de recetas | El SRS incluye recetas generadas por IA y aplicarles las reglas de validación; el pedido de etapa 1 excluye generación por IA. | Usar catálogo curado y recetas administradas. No prometer generación ni validación de contenido generado. |
| RF-07 y RF-10 | El SRS exige matching vía RPC y descuento transaccional en base de datos; la etapa 1 pide cálculo/caso de uso mock. | Mantener contratos intercambiables y cálculo local demostrable. Atomicidad, aislamiento y permisos corresponden al backend. |
| RF-03, RF-06 y RF-19 | El SRS menciona etiquetas en ingredientes y recetas, pero no define un catálogo obligatorio ni una regla completa para derivar compatibilidad de receta desde ingredientes. La aceptación pide filtros y etiquetas de receta, y recuerda que son informativas. | Usar etiquetas mock explícitas a nivel de receta; no inferir seguridad ni garantía de ausencia de trazas. La semántica de etiquetas por ingrediente queda por acordar. |
| RF-04 Starter Kit | El SRS pide seleccionar productos y editar cantidades antes de confirmar; la aceptación de etapa 1 no describe ese subflujo con el mismo detalle. La demo actual ofrece un kit de ejemplo confirmado como acción única. | No ampliar el flujo sin decisión de producto; registrar si la selección/edición individual entra en una revisión posterior de RF-04. |
| RF-12 Tendencias | El SRS propone popularidad por preparaciones o marca destacada; la aceptación de etapa 1 no define métrica ni exige un módulo independiente de tendencias. | Las recomendaciones y destacadas mock no deben presentarse como popularidad calculada por uso real. Definir criterio antes de agregar analítica. |
| RF-21 Colección Personal | El SRS menciona favoritos y recetas personalizadas del usuario; la aceptación actual exige favoritos, filtros y exclusión de recetas IA, sin especificar creación/edición de recetas personales. | Entregar favoritos de recetas del catálogo. La colección de recetas personales no se presupone en esta etapa. |
| RF-02 | Se exige documentar factores de actividad y ajustes del objetivo, pero el SRS no fija en el requisito los valores concretos de configuración. | Los valores mostrados son orientativos de la implementación; confirmar los parámetros funcionales antes de tratar resultados como definitivos. |

RF-01 no define explícitamente recuperación o restablecimiento de contraseña; no se incorpora ese flujo por inferencia. Las recetas y valores calóricos siguen siendo datos de muestra y estimaciones, no asesoramiento médico.

## Evidencia de QA

- Verificaciones finales: `npm test` 113/113; typecheck, lint (0 advertencias), build y diff checks aprobados. El build final tras la limpieza Vite produjo `index.html`, un bundle JavaScript de 530.21 KB (151.00 KB gzip) y CSS de 79.43 KB. El bundle supera el aviso de tamaño de Vite de 500 KB.
- Navegador: perfil y cinco preferencias guardadas; filtros combinados de título/ingrediente y exclusiones; cálculo informativo de energía (220 kcal × 4 porciones = 880; × 5 = 1100; objetivo informado 8–9%); plan semanal con porciones, movimiento y semanas independientes.
- Navegador: sugerencias netas de compra (300 g de quinoa, 50 g de tomate, 2 u de limón), copia y enlace de WhatsApp codificado; texto libre excluido de transferencia; tres artículos de catálogo transferidos sin duplicación.
- Navegador: temporizador de cocina con inicio, pausa, reanudación, recarga y reinicio; preflight de finalización, bloqueo ante stock insuficiente, finalización sin descuento e historial; filas de ticket mock editables con asociación manual y confirmación, rechazo de operación pendiente y cancelación.
- Administración: error de contraseña incorrecta y controles de rol; validación de unidad duplicada, unidad compatible (dag=10 g) y formulario revisados.
- Responsive: pantallas principales de recetas, detalle/cocina, planificador, despensa, compras, perfil y administración revisadas a 360 px; panel a 768 px; panel y planificador a 1920 px. No se observó desbordamiento horizontal en esos recorridos.
- Teclado: navegación con Tab revisada y foco visible en verde de alto contraste. También se revisaron unidades base g/ml/u, conversión de receta leche solo en ml/l, texto compartido sin desbordamiento a 360 px, bloqueo de sugerencias con porciones pendientes y altura compacta de fila vacía en escritorio.

## Límites de la revisión

Los temporizadores están cubiertos por pruebas de dominio y el manejo seguro del audio se revisó en código, sin comprobación audible en un dispositivo físico. La cámara nativa y `navigator.share` dependen del navegador/dispositivo y no se probaron con servicios externos. No se realizó certificación exhaustiva con lectores de pantalla ni auditoría completa de accesibilidad. La especificación DOCX fuente permanece intacta y no se agregaron dependencias.
