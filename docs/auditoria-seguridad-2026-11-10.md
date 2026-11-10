# Auditoría de seguridad de CocinAPP

Fecha: 10 de noviembre de 2026. Auditoría local; sin cambios funcionales ni despliegue remoto.

## Dictamen

No se confirmó una vulnerabilidad que permita a un usuario autenticado consultar o modificar los datos privados de otro mediante las API revisadas. Tampoco se encontraron credenciales privilegiadas reconocibles en los archivos actuales y el historial Git alcanzable inspeccionado. Esto no certifica que el sistema completo esté libre de vulnerabilidades ni que Supabase remoto tenga los mismos controles.

El código tiene controles importantes: RLS de propietario, comprobación de cuenta activa, autorización administrativa en servidor, escrituras por RPC y protección de muchas respuestas asíncronas frente a cambios de sesión. Las pruebas locales apoyan esos controles.

Quedan debilidades y verificaciones pendientes antes de considerar aprobado un despliegue: exigir segundo factor a administradores, revisar el estado de las pantallas ante sustitución de identidad, evitar contraseñas reales en el modo demo y comprobar la configuración efectiva del entorno remoto.

## Alcance y método

- Base principal: `CocinAPP`, rama `main`, commit base `e517752`, incluyendo los cambios locales existentes al comenzar. No se descartaron ni modificaron esos cambios.
- Revisiones independientes de frontend, SQL/RLS y secretos/Edge Function. Integración y ejecución de verificaciones por el agente principal.
- Inspección de las fronteras de autenticación, recuperación y cierre de sesión; almacenamiento personal; repositorios; pantallas; autorización administrativa; políticas y permisos SQL; funciones privilegiadas y scripts de conversión.
- Inventario principal: 124 archivos TS/TSX bajo `frontend/src`, 42 migraciones SQL y 24 etapas SQL. El inventario expresa el tamaño del alcance, no una afirmación de revisión manual línea por línea de cada archivo.
- Inspección de secretos en las tres copias: `CocinAPP`, `CocinAPP-backend-block3` y `CocinAPP-frontend-publish`, incluidos archivos ignorados, el build presente e historia alcanzable. Se buscaron formatos reconocibles de claves privilegiadas, JWT privilegiados y llaves privadas; un secreto arbitrario sin formato reconocible puede escapar a este método.
- Se comparó `admin-users/index.ts`: idéntico en las tres copias. La revisión funcional detallada corresponde al árbol principal; no equivale a revisar exhaustivamente todas las diferencias históricas de las otras ramas.

## Resultados y recomendaciones

### S01 — Administradores sin MFA exigido por la aplicación

**Prioridad media de refuerzo. Configuración confirmada; no constituye un bypass de roles.**

Referencias: `backend/supabase/migrations/202610170004_remove_mfa_admin_requirement.sql:3`, `backend/supabase/functions/admin-users/index.ts:94`, `backend/supabase/functions/README.md:36`.

La migración elimina los controles MFA anteriores. La función Edge valida el token con Auth y exige rol ADMIN, pero no exige nivel de autenticación `aal2`. Las RPC administrativas tampoco conservan aquel requisito adicional.

Si se compromete la contraseña o una sesión administrativa, las acciones administrativas no requieren un segundo factor adicional. Esto no concede por sí solo acceso a todos los datos privados: las restricciones de cada operación siguen siendo relevantes.

Recomendación: incorporar enrolamiento y verificación MFA, y exigir `aal2` en servidor para las operaciones sensibles, tanto RPC como Edge. Un bloqueo visual en el frontend es insuficiente. Implementarlo mediante una migración nueva y pruebas; no volver a ejecutar una migración histórica sobre la base convertida.

### S02 — El árbol de pantallas no está vinculado a la identidad

**Prioridad media de refuerzo. Riesgo condicional identificado por lectura de código; sin reproducción en navegador.**

Referencias: `frontend/src/app/AuthGuards.tsx:15`, `frontend/src/features/auth/data/AuthRepository.ts:204`, `frontend/src/pages/HomePage.tsx:34`, `frontend/src/pages/ProfilePage.tsx:29`.

`RequireUser` conserva el mismo `Outlet` entre dos identidades con acceso a la misma ruta. El refresco de autenticación no siempre pone la pantalla en estado de carga; varios efectos de carga dependen de montaje/reintento y no del usuario. Si la sesión de A se sustituye directamente por la de B en otra pestaña del mismo perfil de navegador, sin un evento intermedio SIGNED_OUT, el estado React ya cargado puede permanecer visible bajo la identidad nueva.

El escenario requiere sustitución de sesión sin el cierre normal: por ejemplo, autenticación directa con credenciales válidas de B mediante el cliente de Auth. No se verificó que el recorrido habitual de la interfaz lo produzca. El logout normal sí limpia la sesión y desmonta las rutas. No se demostró lectura cruzada de la base de datos ni acceso entre navegadores separados.

El perfil puede contener fecha de nacimiento, medidas y preferencias. Por eso conviene no depender únicamente del desmontaje causado por logout.

Recomendación: invalidar inmediatamente las vistas al cambiar de identidad y remontar el subárbol privado con una clave basada en el UUID del usuario. Vincular borradores y acciones a la identidad que los originó. Probar cambio A→B, peticiones pendientes y dos pestañas, además del logout normal.

### S03 — Contraseñas en texto claro en modo demo

**Riesgo confirmado de desarrollo/demo; no se confirmó exposición de contraseñas de Supabase.**

Referencias: `frontend/src/features/auth/data/localAuthStore.ts:49`, `frontend/src/features/auth/data/localAuthStore.ts:59`, `frontend/src/features/auth/data/AuthRepository.ts:40`, `frontend/src/features/auth/domain/security.ts:2`.

Las cuentas locales incluyen el password y se serializan en `localStorage`. Cualquier persona con acceso al perfil de navegador o script del mismo origen puede leerlo. El build de producción exige autenticación configurada y no usa automáticamente cuentas demo si Supabase falla.

Recomendación: usar exclusivamente credenciales ficticias en demo y retirar el almacenamiento de contraseñas de ese adaptador si deja de ser necesario. Si alguna persona reutilizó allí una contraseña real, cambiar esa contraseña. No hay evidencia en esta auditoría de que eso haya ocurrido.

### S04 — Respuestas administrativas y dependencia Edge mejorables

**Prioridad baja de refuerzo. Sin explotación confirmada.**

Referencias: `backend/supabase/functions/admin-users/index.ts:1`, `:125`, `:231`.

Se devuelven algunos mensajes de error originales de Supabase y excepciones. Además, la dependencia de Edge se importa desde esm.sh con versión mayor `@2`, sin fijar una versión exacta en ese archivo. No se encontró una filtración concreta de secretos por esos errores ni una dependencia comprometida.

Recomendación: devolver errores públicos controlados, conservar detalles en registros privados sin passwords/tokens y fijar una versión exacta del SDK de Edge con su verificación correspondiente. El resultado de npm audit del frontend no cubre esa importación remota.

La función no implementa un límite propio de altas por administrador. Revisar cuotas y límites efectivos de plataforma antes de añadir controles. `Access-Control-Allow-Origin: *` no evita ni reemplaza la autenticación Bearer; no se reporta como bypass de autorización.

## Secretos y datos del navegador

- No se encontraron valores reconocibles de `sb_secret_*`, JWT con rol `service_role`/`supabase_admin` ni llaves privadas en el alcance inspeccionado.
- La clave del `.env` local y del bundle es `sb_publishable_*`, pública por diseño. No se imprime en este informe. `.env` no está seguido por Git y se encontró ignorado; las otras dos copias contienen ejemplos con placeholders.
- Los nombres `service_role` y variables de secretos en SQL, documentación y código no son por sí mismos credenciales expuestas. La función Edge obtiene su clave privilegiada desde el runtime del servidor.
- El cliente Supabase usa persistencia de sesión predeterminada en el navegador. Proteger contra XSS y no compartir perfiles de navegador sigue siendo importante; no se halló un XSS explotable en las superficies inspeccionadas.
- Los adaptadores locales separan datos por cuenta, pero las claves de `localStorage` no ofrecen confidencialidad frente a alguien con acceso al mismo perfil de navegador. No deben presentarse como una base de datos segura multiusuario.

## Validación ejecutada

| Comprobación | Resultado | Qué demuestra |
| --- | --- | --- |
| `npm test`, frontend principal | PASS: 211 pruebas, 0 fallos | Contratos y regresiones cubiertos por la suite, incluidas pruebas del handler administrativo |
| `npm audit --json`, tres copias | PASS: 0 vulnerabilidades reportadas en cada lockfile | Sin avisos conocidos del registro consultado para esas dependencias en esta fecha |
| `run_table_rename_local.ps1 -AuditNames -Port 55449` | PASS: ensayo completo y 24 etapas SQL | Migraciones y controles ensayados en PostgreSQL temporal local |
| Búsqueda de secretos actuales/históricos | Sin credenciales privilegiadas reconocibles encontradas | Ausencia de coincidencias confirmadas dentro del alcance y formatos buscados |
| Supabase remoto, navegador con dos usuarios y hosting | No ejecutado | No corresponde marcar aprobación remota |

El ensayo SQL incluye aislamiento A/B, aislamiento de datos privados frente a un administrador, bloqueo de cuentas inactivas, lecturas anónimas, revocación de escritura directa, permisos de RPC, versiones e idempotencia. Usa una simulación local de Auth; no prueba el servicio Auth remoto ni condiciones reales de concurrencia por sí solo.

Para reproducir en Windows, establecer `PGCLIENTENCODING=UTF8` y desactivar `PSQL_PAGER`/`PAGER` antes de lanzar el script. El primer intento falló en una comparación acentuada por la codificación del cliente; con UTF-8 explícito pasó. No se corrigió ni alteró código SQL para obtener el resultado. La instancia temporal fue detenida.

## Verificaciones pendientes del entorno real

1. Confirmar versión desplegada de `admin-users` y `COCINAPP_RELATIONAL_PROFILES=true`. `backend/supabase/CURRENT_STATUS.md:7` lo deja pendiente; esta auditoría no permite saber si se resolvió fuera del repositorio.
2. Comprobar RLS, grants y funciones del esquema final desplegado. Probar solicitudes Data API con dos usuarios y un administrador: UUID ajeno, consulta sin filtro, RPC ajena, escritura directa, cuenta bloqueada y degradación administrativa con token previo. El administrador tampoco debe leer despensa/perfil privado ajeno fuera de las capacidades expresamente previstas.
3. Revisar en Supabase confirmación de correo, URLs permitidas para recuperación/redirección, política de contraseñas, límites de Auth, CAPTCHA y duración de JWT. No inferir estos valores desde validaciones del frontend.
4. Verificar HTTPS, CSP, `frame-ancestors`, `X-Content-Type-Options`, política de referrer y reglas de entrega de archivos en el hosting. No se encontró configuración local suficiente para confirmar esos encabezados ni se proporcionó una URL publicada.
5. Confirmar que todos los flags relacionales esperados están habilitados en el build publicado. La configuración local no prueba la del hosting.
6. Verificar acceso a backups/exportaciones y ensayar restauración, incluyendo alcance de Auth. No se inspeccionaron secretos de proveedores, paneles externos, historial inaccesible, backups externos ni configuración de buckets que pudiera existir fuera de estos archivos.

No ejecutar nuevamente el corte permanente ni repetir migraciones históricas sobre el proyecto ya convertido. Los ensayos locales aprobados no son autorización ni evidencia de un despliegue remoto.

El logout revoca la sesión de Auth, pero un access token ya emitido puede seguir siendo válido hasta expirar; el código revisado comprueba cuenta activa, no cada sesión revocada en `auth.sessions`. Es un límite conocido de la arquitectura JWT, no un fallo de aislamiento confirmado. Ajustar expiración o incorporar verificación de sesión si se requiere revocación inmediata del access token.

## Orden propuesto para continuar

1. Corregir y probar el ciclo de pantallas/drafts ante cambio de identidad.
2. Incorporar MFA administrativo con controles de servidor y pruebas de permisos.
3. Endurecer demo, errores y dependencia de Edge.
4. Verificar el despliegue real y las pruebas A/B antes de aprobar seguridad en producción.

## Fuentes oficiales contrastadas

- [Supabase: seguridad de Data API](https://supabase.com/docs/guides/api/securing-your-api).
- [Supabase: tipos de claves y exposición permitida](https://supabase.com/docs/guides/getting-started/api-keys).
- [Supabase: autorización con MFA](https://supabase.com/docs/guides/auth/auth-mfa).
- [Supabase: cierre de sesión y vigencia del access token](https://supabase.com/docs/guides/auth/signout).
