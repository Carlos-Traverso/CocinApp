# Estado de integración al 9 de noviembre de 2026

- El usuario confirmó en Supabase: `PASS: permanent cutover committed; 36 final tables verified and 7 legacy tables renamed with source row counts preserved.` No volver a ejecutar la conversión permanente en ese proyecto.
- Respaldo del esquema public creado el 7 de noviembre; lectura del archivo y SHA256 verificados. No se ensayó restauración y no cubre recuperación completa de Auth. El usuario aceptó continuar con ese riesgo.
- Frontend local configurado con los ocho VITE_RELATIONAL_* en true. El archivo .env queda fuera de Git. La web todavía no está publicada.
- Se corrigieron respuestas nutricionales vacías, avisos de cargas obsoletas en Perfil y lecturas administrativas simultáneas. Falta confirmar estabilidad completa desde sesiones reales.
- Pendiente desplegar/verificar admin-users actualizado y COCINAPP_RELATIONAL_PROFILES=true, recorrer guardados/transacciones de todos los módulos y comprobar aislamiento con dos usuarios y administrador.
- Las auditorías fechadas y los runbooks previos describen etapas anteriores. Este documento actualiza su estado, sin convertir los pendientes en pruebas aprobadas.

## Ramas

Frontend y backend se publican por separado, ambas basadas en main. Para validar el sistema completo deben integrarse las dos ramas. Los tests frontend incluyen pruebas del handler Edge de backend y requieren la versión backend correspondiente.

Los scripts SQL de ensayo terminan en ROLLBACK. cutover_apply.sql confirma con COMMIT y tiene guardas contra reejecución. Las migraciones históricas no deben repetirse manualmente sobre el proyecto ya convertido.
