# Edge Functions

Crear una función por integración u operación que requiera credenciales privadas, procesamiento confiable o acceso a servicios externos. Validar autenticación y entrada, limitar los datos enviados a proveedores externos y validar su respuesta antes de persistirla. Nunca exponer secretos al frontend.

## `admin-users`

La función `admin-users/index.ts` crea cuentas, cambia nombres y activa/desactiva cuentas de Supabase Auth. Cada solicitud valida el JWT, consulta `current_app_role()` y requiere el rol `ADMIN`. La clave privilegiada solo se lee dentro de la Edge Function.

Para publicarla desde el Dashboard:

1. Abrir el proyecto de Supabase y entrar en **Edge Functions**.
2. Elegir **Deploy a new function** y crear una función llamada `admin-users`.
3. En el editor, reemplazar el contenido de `index.ts` por el archivo de este directorio.
4. Pulsar **Deploy function**. Mantener activa la verificación JWT de la función.
5. Aplicar las migraciones pendientes `migrations/202610160008_sync_admin_user_profile_names.sql` y `migrations/202610160009_secure_admin_role_changes.sql` en el SQL Editor.
6. Volver a CocinAPP y probar crear, editar y desactivar una cuenta desde **Admin → Usuarios**.

La plataforma proporciona `SUPABASE_URL` y las claves del proyecto al runtime. No copiar la clave `service_role`/secret al frontend ni al archivo `.env` de Vite.

## Actualización: estado de cuentas atómico

1. Mientras se actualiza, no usar las acciones de activar/desactivar ni cambiar roles.
2. Ejecutar en SQL Editor la migración completa `migrations/202610170002_atomic_account_status.sql`, después de `202610170001_security_account_access.sql`.
3. Abrir **Edge Functions → admin-users → Code**, reemplazar `index.ts` por el archivo local completo y pulsar **Deploy updates** (o **Deploy function**, según la pantalla). Conservar la configuración JWT existente que ya funciona.
4. Actualizar el frontend y probar las acciones desde **Admin → Usuarios**.
5. Ejecutar el script completo `tests/atomic_account_status.sql` con tres cuentas existentes; sus cambios de prueba terminan en ROLLBACK.

La tabla `account_status` controla el acceso a CocinAPP. Las RPC de estado y rol comparten un bloqueo transaccional y vuelven a autorizar al administrador después de esperar. Las políticas RLS anteriores consultan este estado mediante `current_account_is_active()`.

Las desactivaciones nuevas no escriben `ban_duration` en Auth. Supabase puede emitir una sesión de autenticación a una cuenta desactivada, pero el frontend la rechaza y RLS bloquea sus datos. **Admin → Usuarios** es la fuente del estado de aplicación; la pantalla Authentication de Supabase no mostrará un ban nuevo. El bloqueo previo de Auth sigue siendo respetado, y al reactivar una cuenta antigua la función quita ese bloqueo después de la RPC. Si falla ese paso, informa que hay que reintentar la activación; no concede acceso mientras el ban siga vigente.

Aplicar solo la migración dejando la Edge Function vieja publicada no completa la corrección. Las acciones privilegiadas realizadas directamente desde SQL Editor o el Dashboard de Auth no participan en la protección del último administrador de la aplicación.

Pruebas de integración del handler con transportes simulados: desde `frontend`, ejecutar `npm run test:admin-users-edge`. La concurrencia real de PostgreSQL se comprueba por separado con `tests/concurrency_account_status.md`.

## Reversión del segundo factor para administración

Si se aplicó la migración `202610170003_require_mfa_for_admin_actions.sql`, ejecutar completa `migrations/202610170004_remove_mfa_admin_requirement.sql` en SQL Editor. Luego desplegar la versión local de `admin-users/index.ts` y actualizar el frontend para quitar el bloqueo de la aplicación. La reversión conserva las comprobaciones de rol y los cambios atómicos de estado y rol.

## Evitar sobrescrituras del catálogo

1. Ejecutar `migrations/202610230001_prevent_catalog_overwrite.sql` completa en SQL Editor, después de las migraciones anteriores.
2. Actualizar el frontend.
3. Ejecutar el script completo `tests/shared_catalog_versions.sql`. Requiere que el catálogo y las recetas ya estén inicializados; termina con `ROLLBACK`.
4. Probar desde dos pestañas: guardar un cambio en la primera y luego intentar guardar un cambio basado en la versión vieja desde la segunda. La segunda operación debe pedir recargar, sin borrar el cambio anterior.

La base lleva una versión creciente para el catálogo y otra para recetas. Cada guardado compara la versión leída con la vigente; si otra pestaña o administrador ya guardó, la base rechaza el cambio viejo y conserva los datos recientes. Las escrituras directas a esas tablas quedan reservadas a las funciones SQL con control de versión.

## Historial administrativo

1. Ejecutar completa la migración `migrations/202610240001_admin_audit_log.sql` en **SQL Editor** después de las migraciones anteriores, incluida `202610230001_prevent_catalog_overwrite.sql`.
2. En **Edge Functions → admin-users → Code**, reemplazar el contenido por el archivo local actualizado `functions/admin-users/index.ts` y desplegarlo. Mantener activa la verificación JWT.
3. Iniciar CocinAPP como administrador, abrir **Historial** y probar un cambio de nombre y una edición de ingrediente o receta. Cada acción debe mostrar quién la hizo, qué cuenta afectó (cuando corresponda) y la fecha.

El historial registra altas y cambios de nombre de cuentas desde `admin-users`; cambios de rol y estado, y guardados de catálogo y recetas, desde triggers de PostgreSQL dentro de la misma transacción que el cambio. La tabla no tiene permisos de lectura ni escritura para el cliente: el administrador consulta mediante `admin_list_audit_events`, y la función valida que su cuenta siga activa y tenga rol ADMIN. La clave de servicio se usa únicamente en la Edge Function para registrar las dos acciones de gestión de cuenta que usan Supabase Auth.

La aplicación muestra hasta los últimos 100 eventos. No se guardan contraseñas, tokens ni el contenido completo del catálogo en el historial. Los cambios ejecutados desde SQL Editor pueden aparecer sin correo de actor, porque allí no existe la sesión autenticada de la aplicación. La migración no importa acciones anteriores a su instalación.

Para mostrar el nombre de quien realizó cada acción y habilitar la búsqueda por nombre, correo o tipo de cambio, aplicar también `migrations/202610240002_search_admin_audit_events.sql`. La búsqueda se realiza en Supabase y devuelve como máximo 100 coincidencias.
