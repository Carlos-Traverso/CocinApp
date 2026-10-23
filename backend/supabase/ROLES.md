# Roles de acceso

1. Ejecutar una vez `migrations/202610160004_create_user_roles.sql` en SQL Editor.
2. Registrar una cuenta desde CocinAPP si todavía no existe.
3. Abrir `assign_admin.sql`, reemplazar `REEMPLAZAR_CON_TU_CORREO` por su correo real y ejecutar el contenido en SQL Editor.
4. Cerrar sesión en CocinAPP e ingresar con ese correo y contraseña. Se abrirá el panel de administración.

Las cuentas sin una fila en `user_roles` tienen rol `USER`. Solo el SQL Editor o un servidor de confianza puede modificar los roles: los clientes autenticados únicamente pueden leer el propio. El frontend consulta `current_app_role()` y no confía en roles del almacenamiento local ni en metadatos editables de Auth.

Para devolver una cuenta a `USER`, editar su fila en Table Editor o ejecutar desde SQL Editor:

```sql
update public.user_roles
set role = 'USER', updated_at = now()
where user_id = (select id from auth.users where lower(email) = lower('CORREO_DE_LA_CUENTA'));
```

Este módulo protege la asignación de roles y el acceso a las pantallas. Las migraciones posteriores incorporan el catálogo compartido, la gestión atómica de cuentas y el historial administrativo. El rol se vuelve a consultar al verificar la sesión; para comprobar cambios con una pantalla ya abierta, cerrar sesión y volver a entrar. Consultar `functions/README.md` para aplicar las actualizaciones de administración.
