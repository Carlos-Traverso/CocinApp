# Prueba con dos conexiones reales

`atomic_account_status.sql` comprueba permisos y tokens anteriores al bloqueo en una sola transacción. No demuestra concurrencia entre conexiones. Esta prueba adicional comprueba que el segundo administrador espere y vuelva a autorizarse después de obtener el bloqueo compartido.

Ejecutar después de la migración `202610170002_atomic_account_status.sql`, en un **proyecto de prueba**, con dos cuentas de prueba A y B que ya sean administradoras activas, sin bloqueo de Auth. Se necesitan dos conexiones SQL persistentes como `postgres` (por ejemplo dos terminales de `psql`). Dos consultas completas del SQL Editor no permiten controlar de forma fiable la pausa entre `BEGIN` y `COMMIT`.

No se ejecutó esta prueba durante el desarrollo: el entorno local no dispone de `psql` ni Docker. No pegar contraseñas de conexión en el chat ni guardar la cadena de conexión en el repositorio.

1. Buscar los UUID de A y B en Authentication → Users. En los ejemplos reemplazar `UUID_A` y `UUID_B` por esos UUID. Anotar el estado original de ambas cuentas. A y B deben empezar con rol `ADMIN`, `account_status.active = true` y `auth.users.banned_until` vacío o vencido.
2. Abrir dos conexiones persistentes al mismo proyecto. Conservar ambas hasta terminar la limpieza.
3. En la conexión 1, ejecutar lo siguiente **sin COMMIT todavía**:

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"UUID_A","role":"authenticated"}', true);
select public.admin_set_user_active('UUID_B'::uuid, false);
```

4. En la conexión 2, ejecutar lo siguiente. Debe quedar esperando en la última sentencia:

```sql
begin;
set local statement_timeout = '60s';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"UUID_B","role":"authenticated"}', true);
select public.admin_set_user_active('UUID_A'::uuid, false);
```

5. Volver a la conexión 1 antes de los 60 segundos y ejecutar `commit;`. Este paso confirma temporalmente la desactivación de B en el proyecto de prueba.
6. La conexión 2 debe terminar con error de autorización (`42501`). Ejecutar `rollback;` en esa conexión. B no debe poder desactivar a A aunque presentó un token de antes del bloqueo.
7. En la conexión 1, limpiar inmediatamente usando la cuenta A:

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"UUID_A","role":"authenticated"}', true);
select public.admin_set_user_active('UUID_B'::uuid, true);
commit;
```

8. Repetir la prueba para el cruce entre cambio de rol y estado. En el paso 3 sustituir la llamada por `select public.admin_set_user_role('UUID_B'::uuid, 'USER');`. Mantener los pasos 4–6. B debe perder autoridad después de esperar, aunque su estado siga activo.
9. Para limpiar esta segunda variante, repetir el paso 7 sustituyendo la llamada por `select public.admin_set_user_role('UUID_B'::uuid, 'ADMIN');`.
10. Verificar que ambas cuentas vuelvan a estar activas y con rol ADMIN en el panel. Si se interrumpe la prueba después del COMMIT del paso 5, ejecutar la limpieza correspondiente antes de usar las cuentas.

Si la conexión 2 termina con timeout en vez de error de autorización, ejecutar `rollback;` en ambas conexiones si siguen abiertas y repetir. Un timeout no prueba que la autorización se haya reevaluado. Si la primera conexión hace `rollback` en vez de `commit`, la segunda puede completarse correctamente: ese resultado tampoco comprueba el rechazo de un administrador recién desactivado.

La protección del último administrador incluye la prohibición de que se quite su propio rol o se desactive. El script de una conexión prueba esas prohibiciones; la prueba de dos conexiones cubre el caso donde dos administradores intentan desactivarse mutuamente y el caso donde uno pierde su rol mientras espera.
