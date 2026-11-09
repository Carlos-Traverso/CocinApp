# Perfil y administración: integración preparada

Fecha: 2026-11-06. La migración 013 requiere las migraciones previas y los nombres españoles de 009. No se aplicó permanentemente a Supabase ni se desplegó la Edge Function.

## Fuente del nombre

En modo relacional, `perfiles.display_name` es la fuente del nombre de la cuenta. `admin_list_users` prioriza ese dato y usa metadatos de Auth únicamente si falta el perfil. No entrega medidas ni preferencias privadas al administrador.

La Edge Function `admin-users`, para `update_name`, delega en `admin_set_profile_name(p_user_id,p_display_name)` usando el JWT del administrador. La función SQL revalida la autorización dentro de su transacción, coordina los bloqueos con cambios de rol/estado y guardados propios, conserva datos personales y preferencias, incrementa versión si cambia el nombre y registra auditoría atómicamente. Repetir el mismo nombre no incrementa versión ni duplica auditoría. Un perfil ausente se crea mínimo para una cuenta Auth existente.

No se realiza una segunda escritura de nombre en Auth: sus metadatos dejan de ser la fuente del nombre una vez creado el perfil relacional. Esto elimina el fallo parcial entre dos sistemas para renombrar. Crear una cuenta sigue usando la API Auth y conserva sus limitaciones de acciones ya admitidas en vuelo; no se afirma que Auth y SQL formen una transacción distribuida.

## Adaptador de perfil

El frontend mapea `get_my_profile` y `save_my_profile` al formulario actual; email permanece en Auth. Guarda versiones como strings para evitar pérdida de precisión. No importa perfiles locales automáticamente ni escribe la caché legacy en el camino relacional.

Para modificar un perfil existente debe haber una lectura explícita previa. Un conflicto 40001 exige recargar y reaplicar los cambios; no se reintenta automáticamente con la versión nueva. Las versiones y preferencias preservadas se invalidan al cambiar cuenta o sesión. Se validan las respuestas y se descartan lecturas antiguas que llegan fuera de orden.

Las preferencias desconocidas por la UI se conservan. SQL permite mantener una etiqueta inactiva que ya estaba asignada, pero rechaza incorporarla por primera vez. La actualización de nombre local refresca la cabecera sin convertir un cambio de texto en un cambio de identidad.

## Activación durante el corte

- Frontend: `VITE_RELATIONAL_PROFILES=true` al construir la versión que vaya a usar el esquema relacional.
- Edge Function: `COCINAPP_RELATIONAL_PROFILES=true` al desplegar la versión correspondiente de `admin-users`.
- Las opciones permanecen desactivadas por defecto. No activarlas contra las siete tablas originales: requiere migración, conversión y despliegue coordinados. Estas opciones no resuelven por sí solas el desajuste de nombres españoles de los demás repositorios legacy.
- Conservar el circuito de recuperación; los otros módulos siguen pendientes de integración. No mezclar clientes que escriban JSON con clientes que escriban perfiles relacionales tras convertir los datos.

## Ensayo

Verificación local final: `npm run typecheck` PASS, `npm test` **151/151 PASS**, ensayo completo desde siete tablas con rollback PASS y **22 escenarios SQL PASS**. Se revisaron permisos, preservación de datos y preferencias, versiones, reintentos, sesiones cambiadas y respuestas fuera de orden. Las primeras ejecuciones detectaron problemas de fixtures/expectativas que fueron corregidos antes del PASS final. El usuario confirmó el ensayo remoto de 013: `PASS: profile admin contract verified; full script includes ROLLBACK`. El script completo deshizo los cambios; la prueba de navegador contra una Edge Function desplegada sigue pendiente.

`tests/profile_admin_rehearsal.sql` está destinado a SQL Editor: ejecutar completo como postgres, con «Run without RLS». Prepara el esquema pendiente dentro de una transacción y termina en ROLLBACK; no cambia permanentemente datos, roles ni nombres de cuentas. No ejecutar el stage aislado.

Ejecutor local reproducible: `tests/run_table_rename_local.ps1 -ProfileAdmin -Port 55441`. Simula Auth; no demuestra aún el flujo de navegador contra una Edge Function desplegada. La verificación remota del ensayo fue confirmada por el usuario; la prueba E2E de perfil/administración queda pendiente del corte de pruebas correspondiente.
