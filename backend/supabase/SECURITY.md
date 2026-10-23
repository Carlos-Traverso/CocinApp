# Seguridad: primera revisión (17 de octubre de 2026)

## Cambios incluidos

- La aplicación compilada para producción rechaza acceso si falta Supabase: no acepta cuentas locales de demostración como alternativa.
- El cierre de sesión de Supabase limpia la identidad auxiliar de CocinAPP y actualiza las pantallas. Una consulta de sesión pendiente no puede restablecer la identidad después del cierre.
- El mensaje por límite de correos ya no recomienda desactivar la confirmación del correo.
- La migración `202610170001_security_account_access.sql` impide a cuentas bloqueadas leer o modificar las tablas de la aplicación con tokens anteriores al bloqueo, y revalida al administrador tras obtener el bloqueo transaccional de cambios de rol.

## Aplicación en Supabase

1. Abrir el proyecto correcto y entrar en **SQL Editor**.
2. Crear una consulta con **New query**.
3. Copiar todo el archivo `migrations/202610170001_security_account_access.sql` y pulsar **Run**. Requiere las migraciones anteriores, de 001 a 009.
4. No volver a ejecutar ni modificar migraciones antiguas para este cambio.
5. Verificar el resultado con la consulta de diagnóstico siguiente. En SQL Editor el rol es privilegiado: ejecutar un SELECT común allí no demuestra aislamiento entre usuarios.

```sql
select tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('pantry_items', 'personal_data', 'user_roles', 'catalog_core', 'shared_recipes')
order by tablename, policyname;
```

Cada una de las cinco tablas debe mostrar una política RESTRICTIVE que comprueba la cuenta activa. Esta política se combina con las políticas anteriores de propietario y administrador; no las sustituye.

## Prueba manual

1. Cerrar sesión. Abrir directamente `/pantry` y `/admin`: deben volver al inicio.
2. Entrar como usuario común e intentar `/admin`: debe volver a su panel.
3. Abrir la aplicación en dos ventanas con la misma sesión; cerrar sesión en una y comprobar que la otra deja de mostrar pantallas privadas.
4. Con dos cuentas de prueba distintas, crear productos y confirmar que cada una solo ve los propios.
5. Mantener abierta una cuenta de prueba en otro navegador y desactivarla desde el administrador. Al recargar o pedir datos al servidor, la solicitud no debe devolver ni modificar sus datos. Los datos ya descargados o copiados no se pueden retirar del dispositivo.
6. Reactivar esa cuenta, volver a iniciar sesión y comprobar el acceso normal.

Los scripts de prueba SQL deben ejecutarse completos: simulan identidades, verifican permisos y terminan con ROLLBACK. No ejecutar fragmentos que cambien el estado de cuentas sin su reversión.

## Alcance y pendientes

Esta revisión se realizó sobre archivos locales. No confirma la configuración ni las políticas desplegadas del proyecto remoto. Las pruebas SQL requieren PostgreSQL/Supabase y no se ejecutaron durante esta revisión.

- La migración `202610170002_atomic_account_status.sql` y la nueva Edge Function corrigen la carrera de desactivación/cambio de rol mediante estado de aplicación y bloqueo compartido. Aplicar ambos cambios siguiendo `functions/README.md`. Las pruebas de dos conexiones están documentadas en `tests/concurrency_account_status.md`; no se ejecutaron localmente. Cambios directos de SQL Editor/Dashboard quedan fuera de esta protección.
- La migración `202610230001_prevent_catalog_overwrite.sql` agrega versiones crecientes y escrituras condicionales para evitar que una pestaña sobrescriba ediciones recientes del catálogo o de recetas. Aplicar la migración y ejecutar `tests/shared_catalog_versions.sql` siguiendo `functions/README.md`.
- El módulo 3 agrega `tests/real_permissions.sql`: con dos cuentas existentes, simula un usuario común y un administrador para probar aislamiento de datos, permisos administrativos y que solo las funciones versionadas escriban en catálogos. La guía está en `tests/README.md`; termina con `ROLLBACK`. Debe ejecutarse en el SQL Editor del proyecto desplegado para comprobar sus permisos reales.
- El módulo 5 agrega la tabla privada `admin_audit_log`, triggers transaccionales para cambios de roles, estados, catálogo y recetas, y un listado de eventos disponible solo a administradores activos. Las altas y cambios de nombre hechos por la Edge Function también se registran. Aplicar `migrations/202610240001_admin_audit_log.sql` y desplegar la versión actualizada de `functions/admin-users/index.ts` siguiendo `functions/README.md`.
- La migración `202610240002_search_admin_audit_events.sql` agrega el nombre visible del actor y una búsqueda de eventos por nombre, correo y descripción. Aplicarla luego de la primera migración del historial.
- El cierre de sesión revoca sesiones de Auth, pero los JWT emitidos pueden seguir válidos hasta vencer. La nueva protección bloquea cuentas desactivadas; no consulta `auth.sessions` para revocar inmediatamente cada JWT al cerrar sesión.
- Las cuentas locales de desarrollo guardan contraseñas de demostración en el navegador: usar solo datos ficticios. La autenticación real utiliza Supabase.
- No se verificaron dependencias contra un registro de vulnerabilidades ni infraestructura de alojamiento, copias de seguridad o encabezados HTTP del despliegue.
- Pendientes: revisar CAPTCHA/límites de intentos, validar en la base el contenido de los datos JSON y confirmar operaciones atómicas de compras y cocina. El historial administrativo y sus pruebas de permisos ya están implementados en los archivos locales.

Nunca colocar claves `service_role`, `sb_secret_...` o contraseñas SMTP en variables `VITE_*`. La clave publishable es pública por diseño; la protección depende de RLS y de las comprobaciones del servidor.

Fuentes oficiales: [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [cierre de sesión](https://supabase.com/docs/guides/auth/signout), [preparación para producción](https://supabase.com/docs/guides/deployment/going-into-prod).
