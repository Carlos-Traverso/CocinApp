# Arquitectura de CocinAPP

## Decisión

CocinAPP adopta una arquitectura cliente-servidor organizada en capas. React, TypeScript, Vite y Tailwind forman la presentación SPA. Supabase aporta autenticación, PostgreSQL y acceso a servicios backend; las Edge Functions se reservan para operaciones que necesitan secretos o ejecución confiable del lado servidor. No se introduce un servidor propio ni microservicios para las necesidades actuales.

## Capas y límites

| Capa | Ubicación | Responsabilidad |
| --- | --- | --- |
| Presentación | `frontend/src/pages`, `components`, `features/*/ui` | Rutas, interacción, estado visual y accesibilidad. |
| Aplicación y dominio | `frontend/src/features/*` | Casos de uso, tipos del dominio, validaciones y contratos de repositorio. |
| Infraestructura cliente | `frontend/src/lib`, `features/*/data` | Adaptadores mock o Supabase; componentes y páginas no consultan Supabase directamente. |
| Datos y seguridad | `backend/supabase/migrations` | PostgreSQL, constraints, índices, RLS y funciones RPC transaccionales. |
| Servicios protegidos | `backend/supabase/functions` | Integraciones con credenciales privadas, validación y llamadas externas. |

## Organización por funcionalidad

Cada módulo concentra su UI específica, modelo, casos de uso y adaptadores de datos. Las dependencias compartidas viven en `components`, `shared` o `lib` solo cuando son realmente transversales. Las páginas ensamblan funcionalidades; no contienen consultas SQL, reglas críticas ni secretos.

Dominios iniciales: `auth`, `onboarding`, `profile`, `recipes`, `cooking`, `pantry`, `planner`, `shopping`, `favorites` y `admin`. `cooking` se explicita porque “Cocinar Ahora” necesita una operación atómica; `profile` conserva preferencias y datos personales fuera del flujo de autenticación.

## Etapas de integración

1. **Frontend:** mantener el contrato de cada repositorio e implementar adaptadores mock. La interfaz no depende de la ubicación de los datos.
2. **Backend:** crear el esquema relacional normalizado, migraciones, restricciones, índices, RLS, Auth y las RPC requeridas.
3. **Integración:** reemplazar mocks por adaptadores Supabase bajo los mismos contratos; validar permisos, errores y estados de carga en el cliente.

## Operaciones con requisitos especiales

- **Matching de recetas:** la RPC consulta despensa y recetas, normaliza unidades y devuelve coincidencias; el frontend presenta resultados.
- **Cocinar Ahora:** una RPC valida stock, descuenta cantidades y registra la preparación dentro de una transacción única.
- **Escaneo de tickets y recetas con IA:** una Edge Function conserva las credenciales de Gemini del lado servidor; el cliente revisa los datos antes de persistirlos.
- **Administración:** ocultar controles en la interfaz no concede ni revoca permisos. La autorización se aplica en las políticas RLS y en las operaciones de backend.

## Contrato de ejemplo

`features/recipes/data/RecipeRepository.ts` define una interfaz independiente del proveedor. `MockRecipeRepository.ts` es el adaptador inicial y `mocks/recipes.ts` aporta datos locales. La futura implementación Supabase respetará este contrato para que la página no cambie al integrar el backend.

## Migraciones y configuración

Cada cambio de esquema se agrega como una migración SQL nueva y ordenada; no se reescriben migraciones ya compartidas. El cliente utiliza únicamente URL y clave pública anon. Claves de servicio, Gemini y otros secretos se configuran en el entorno de Supabase y nunca en el bundle del navegador.
