# Activación local tras la migración

Estado comunicado por el usuario: PASS permanente en Supabase, 36 tablas finales y conteos de las siete tablas de origen conservados. No volver a ejecutar cutover_apply.sql.

Se activaron los ocho VITE_RELATIONAL_* en frontend/.env para el proyecto rgvbpceaoimakqosiqvm. Credenciales existentes conservadas. Esto requiere reiniciar Vite; no demuestra funcionamiento de los módulos desde navegador.

## Abrir la web

1. Detener el servidor anterior con Ctrl+C en su terminal, si sigue abierto.
2. Abrir PowerShell y ejecutar:

```powershell
cd 'C:\Users\carlo\OneDrive\Desktop\Universidad\TERCER AÑO\Desarrollo de Software\Tp Anual\Entregas\CocinAPP\frontend'
npm run dev
```

3. Abrir la dirección Local que muestre Vite. Iniciar sesión y revisar primero Recetas y Despensa. Informar errores antes de modificar más datos.

## Administración de usuarios pendiente

No se confirmó el despliegue remoto del código actual de backend/supabase/functions/admin-users/index.ts. Antes de crear/editar/desactivar usuarios desde la web, hay que actualizar esa función y establecer COCINAPP_RELATIONAL_PROFILES=true en sus secretos/configuración. El frontend local no despliega la función ni configura ese valor remoto.

Siguiente etapa: comprobar módulos con sesiones reales y completar la función administrativa. El usuario aceptó omitir el ensayo de restauración aislada; el respaldo public fue leído y su SHA256 verificado, pero no acredita una recuperación completa de Auth.
