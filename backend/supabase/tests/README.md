# Account access security checks

## Comprobar los permisos reales

`real_permissions.sql` prueba permisos efectivos de RLS y funciones administrativas simulando las solicitudes de dos sesiones autenticadas: la primera cuenta existente de Supabase se usa como USER y la segunda como ADMIN. La transacción también prepara filas temporales y termina con `ROLLBACK`, por lo que las asignaciones de roles y los datos de prueba no quedan guardados.

Requisitos: haber aplicado las migraciones `202610160001` a `202610160009`, `202610170001`, `202610170002`, `202610170004` y `202610230001`; tener al menos dos cuentas en **Authentication → Users**; y que CocinAPP ya haya inicializado el catálogo y las recetas compartidas.

Para ejecutarla, abrir el proyecto correcto en Supabase, ir a **SQL Editor → New query**, copiar el contenido completo de `real_permissions.sql`, pegarlo y pulsar **Run**. No ejecutar solo una selección del código. Si pasa, la última fila muestra `PASS`. Si aparece un error `FAIL` o de migración, copiar el mensaje completo para diagnosticarlo. Si la interfaz informa que una transacción quedó abierta o abortada, ejecutar `ROLLBACK;` antes de volver a correr la prueba.

La prueba comprueba que el usuario ve y modifica sus propios datos privados, no puede ver o cambiar los del admin, no puede invocar operaciones administrativas y solo puede leer el catálogo compartido; también verifica que el admin puede listar cuentas y guardar el catálogo y las recetas mediante las funciones versionadas, pero no puede leer la despensa o los datos personales del usuario. Esto comprueba las políticas en la base desplegada, pero no reemplaza las pruebas desde dos sesiones reales de la aplicación.

El orden de cuentas se basa en la fecha de creación. Si las dos primeras cuentas no son la pareja USER/ADMIN que querés usar para la prueba, no ejecutes el script todavía: avísame y ajustamos la selección para tus cuentas.

## Historial administrativo

Después de aplicar `202610240001_admin_audit_log.sql`, ejecutar el archivo completo `admin_audit_permissions.sql` en SQL Editor. Requiere una cuenta activa USER y otra ADMIN. Simula ambas sesiones: espera que el usuario no pueda leer la tabla ni la función de historial, que tampoco pueda insertar eventos falsos, y que el administrador sí pueda consultar el historial sin permiso para borrarlo. Termina con `ROLLBACK` y debe mostrar `PASS`.

Apply migration `202610170001_security_account_access.sql` after migrations 001–009.
Run `account_access.sql` in the Supabase SQL Editor with at least two existing accounts. Execute the complete script. It changes fixtures only inside a transaction and finishes with ROLLBACK. On a failed assertion the transaction is aborted; issue ROLLBACK before another query if the editor retains that connection. These tests simulate JWT claims as a privileged database operator; ordinary clients cannot impersonate another user this way.

The migration checks account existence and banned_until for each request. Existing JWTs cannot bypass a ban. It does not inspect auth.sessions or immediately revoke an otherwise active user's access JWT after logout; that token follows Supabase's expiry rules.

After migration `202610170002_atomic_account_status.sql` and deployment of the updated `admin-users` function, application status and role mutations share the same transaction lock. The handler no longer issues Auth bans on deactivation. Legacy reactivation only clears an existing Auth ban after the application state RPC succeeds.

Run `atomic_account_status.sql` in full with at least three existing accounts for permission and stale-token assertions (all fixture changes roll back). A single SQL transaction does not prove concurrent behavior: follow `concurrency_account_status.md` in a test project using two persistent connections for that validation. New accounts with no status row remain active by default.

Not executed against a live project from this workspace. Passing application lint/build does not validate SQL policies. Also run two real user sessions against the deployed Data API to verify the deployed configuration and grants.
