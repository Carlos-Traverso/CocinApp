# Aplicar el cutover permanente

Este paso cambia el esquema de Supabase y confirma la migración con `COMMIT`. La restauración desde el respaldo podría no ser posible; el respaldo público y la rehearsal con checksum verificado ya fueron revisados.

## Antes de ejecutar

1. Confirma que `cutover_data_rehearsal.sql` terminó con `PASS` y `ROLLBACK` el 7 de noviembre, y que el respaldo validado sigue disponible.
2. Cierra CocinAPP en navegadores y dispositivos, y pausa cualquier proceso que pueda escribir datos.
3. En el SQL Editor del proyecto Supabase correcto, abre el archivo completo [cutover_apply.sql](../cutover_apply.sql). Comprueba el nombre del proyecto antes de ejecutarlo.

## Ejecución

4. Ejecuta el archivo completo una sola vez, con `Run` en el SQL Editor de Supabase. No selecciones fragmentos. No habilites opciones que ejecuten sentencias por separado: el archivo requiere una sola transacción.
5. Espera la última fila de resultados. El éxito es el mensaje `PASS: permanent cutover committed; 36 final tables verified and 7 legacy tables renamed with source row counts preserved.` Ese mensaje aparece después del `COMMIT`.
6. Guarda el resultado y la hora de ejecución, y vuelve a habilitar escrituras.

Si aparece un error y no aparece el mensaje final, no vuelvas a ejecutar el archivo ni intentes renombrar tablas a mano. Conserva el error y solicita revisión del estado actual de la base antes de cualquier recuperación. Si el mensaje final aparece, no vuelvas a correr el script.

La validación local del cutover confirmó que `COMMIT` conserva las 36 tablas finales y que una repetición se rechaza. La rehearsal remota con `ROLLBACK` fue PASS el 7 de noviembre; el script permanente aún debe ejecutarse en el proyecto objetivo.
