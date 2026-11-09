> Estado actualizado: consultar `backend/supabase/CURRENT_STATUS.md`. Este documento conserva la planificación o auditoría histórica.

# Runbook de preparación para corte relacional

**Estado: preparación solamente. Corte permanente no autorizado ni ejecutado.** El ensayo `backfill/cutover_data_rehearsal.sql` fue comunicado como PASS remoto con `ROLLBACK` completo. Eso acredita el ensayo transaccional en ese momento; no acredita backup restaurable, estado remoto actual, E2E, ni una conversión permanente. El backup aún debe ejecutarse y verificarse. La herramienta de exportación del esquema `public` es `backup_legacy.ps1`; su alcance y los respaldos complementarios se detallan en `BACKUP.md`.

## Entorno confirmado

El usuario confirmó Supabase Free y frontend todavía sin publicar. El ensayo de navegador puede hacerse con Vite local conectado a un proyecto aislado de Supabase; no requiere elegir hosting ahora. El corte de la base sigue requiriendo control de escrituras de todos los clientes de desarrollo. Las instrucciones de hosting de este documento aplican a una publicación futura.

## Puertas de entrada

No iniciar corte hasta cerrar todas estas puertas y registrar operador, hora UTC, proyecto/entorno, commit/build y evidencia:

1. **Congelar escrituras.** Anunciar ventana; poner la aplicación en mantenimiento o deshabilitar escrituras por todos los canales (web, Edge, tareas administrativas/importadores). Confirmar que no quedan sesiones de escritura activas. Mantener la congelación desde el inventario final y el backup hasta la reapertura. No confiar solo en ocultar botones.
2. **Inventario actual.** Con la app congelada, relevar las siete tablas legacy, Auth/usuarios, conteos y contenido necesario para reconciliar perfiles, recetas y referencias, planificación, favoritos, despensa, compras, cocina/historial y solicitudes. Inspeccionar especialmente compras/sesiones activas, conflictos y filas de despensa sin ingrediente asociado. El inventario documentado previamente es histórico. Investigar cada discrepancia; no borrar ni adivinar asociaciones.
3. **Backup verificable.** Ejecutar el procedimiento aprobado `backup_legacy.ps1` contra el proyecto correcto; guardar fuera del proyecto productivo el artefacto, fecha, alcance, checksum y log sin secretos. El archivo de esta herramienta solo cubre `public`: reunir también el respaldo complementario de Auth/roles y la configuración necesaria; Storage requiere respaldo de objetos por separado si se utiliza. Comprobar el conjunto completo y hacer una restauración en un proyecto aislado, sin tráfico ni credenciales productivas. Consultar conteos y muestras de reconciliación en la copia. Un archivo creado sin restauración comprobada no satisface esta puerta.
4. **Rehearsal fresco.** En una copia aislada restaurada desde ese backup, regenerar/ejecutar `backfill/cutover_data_rehearsal.sql` completo con `ROLLBACK`; no editar sus límites transaccionales. Reconciliar conteos y excepciones contra el inventario congelado, incluyendo el registro manual de despensa y la semántica de sesiones/snapshots históricos sintéticos. Resolver errores y repetir. Confirmar que tras rollback no queda esquema ni dato convertido. El PASS remoto anterior no sustituye este ensayo con snapshot fresco.
5. **Paquete de corte.** Revisar y aprobar por separado las migraciones ordenadas, la conversión permanente reproducible, consultas de reconciliación antes/después, y procedimiento de recuperación. El ensayo actual termina en `ROLLBACK`; no sustituirlo por `COMMIT` ni construir una conversión permanente por edición improvisada durante la ventana. Esta preparación no crea ni autoriza ese artefacto.
6. **E2E preproducción.** En una instancia aislada con esquema final y datos representativos restaurados/sintéticos, probar la matriz de módulos de abajo con todos los flags coordinados, primero en build candidato. Cubrir dos cuentas distintas y administrador; validar permisos y ausencia de cruces. Registrar resultado por caso, navegador/build, rol y evidencia. Ningún E2E se considera pasado por pruebas unitarias o SQL.

## Matriz E2E obligatoria

| Área | Casos mínimos y roles |
| --- | --- |
| Autenticación, perfil y administración de cuentas | inicio/cierre, perfil parcial, editar perfil; admin lista/busca y cambia estado/rol; usuario común no administra. Verificar Edge con bandera de perfiles alineada. |
| Despensa | alta, edición, consumo/cantidad, vencimiento, fila manual sin ingrediente, filtros y persistencia; A no ve ni modifica B. |
| Compras | crear/editar/completar/eliminar lista e ítems, sugerencias y transferencia de compras a despensa (reintento sin duplicar stock); cantidades y fecha; aislamiento A/B. |
| Cocina e historial | iniciar/reanudar sesión, progreso, finalizar, eventos e historial/snapshot; persistencia y aislamiento A/B. |
| Recetas y favoritos | descubrir/abrir recetas, guardar/quitar favorito; receta privada propia y no accesible desde B. |
| Planificación | asignar/quitar receta por fecha/turno, cambios entre semanas, sugerencias; aislamiento A/B. |
| Administración de catálogo | roles admin: crear/editar/duplicar/activar/archivar recetas, catálogo/ingredientes/unidades/etiquetas y solicitudes según alcance; usuario común no puede ejecutar operaciones admin. |
| Inicio y resumen | totales/listas coherentes con despensa, plan, cocina y compras; cambios se reflejan tras navegación/recarga. |
| Seguridad transversal | con A y B activos, cada uno intenta leer/escribir IDs ajenos; confirmar denegación en tablas/RPC y UI. Admin demovido no conserva autorización con la misma sesión/JWT según contrato. Probar invitado/anon donde aplique. |

## Coordinación de banderas y activación

El frontend lee estas variables de build, todas en `frontend/src/shared/data/supabaseClient.ts`:

```text
VITE_RELATIONAL_PROFILES
VITE_RELATIONAL_PANTRY
VITE_RELATIONAL_SHOPPING
VITE_RELATIONAL_COOKING
VITE_RELATIONAL_RECIPES
VITE_RELATIONAL_PLANNING
VITE_RELATIONAL_ADMIN
VITE_RELATIONAL_DASHBOARD
```

Todas deben tener el valor literal `true` en el build candidato de corte; las omitidas/desactivadas mantienen caminos legacy y pueden mezclar esquemas incompatibles. La función `backend/supabase/functions/admin-users/index.ts` también debe desplegarse/configurarse con `COCINAPP_RELATIONAL_PROFILES=true` en la misma ventana que el esquema relacional de perfiles. Verificar configuración efectiva, versión desplegada, URL/proyecto y build publicado; no basta con editar `.env` local. Probar el despliegue coordinado en preproducción. No habilitar consumidores relacionales antes de confirmar esquema y conversión final.

## Ventana de corte y puertas de salida

Con todas las puertas previas cerradas, responsables presentes y escrituras aún congeladas:

1. Confirmar por última vez proyecto, backup restaurable, cero escrituras en curso, migraciones/paquete aprobados y flags objetivo.
2. Aplicar migraciones en orden y la conversión permanente aprobada como unidad de cambio controlada. Capturar logs. Ejecutar reconciliaciones de conteos, referencias, ownership/RLS, roles, permisos y excepciones contra el inventario; cualquier discrepancia inexplicada detiene la reapertura.
3. Desplegar juntos el build frontend con los ocho flags `true` y Edge con `COCINAPP_RELATIONAL_PROFILES=true`; validar versión y entorno efectivos.
4. Bajo mantenimiento, hacer smoke/E2E de autenticación, lectura/escritura por módulo, separación A/B y administración. Solo reabrir escrituras si todos pasan, las reconciliaciones están aceptadas y responsables registran GO.

## Recuperación

**Antes de reabrir escrituras:** mantener mantenimiento y congelación. Si migración, conversión, reconciliación o smoke falla, no activar el build relacional. Desplegar la versión frontend/Edge compatible con legacy (flags relacionales apagados/coherentes), y restaurar el backup verificado en el proyecto objetivo solo si la recuperación exige volver al estado previo. Verificar restauración y conteos antes de reabrir. Documentar datos/operaciones descartados por la restauración.

**Después de reabrir escrituras relacionales:** detener nuevas escrituras inmediatamente y conservar logs/inventario de lo ocurrido desde la reapertura. No hacer rollback ciego ni restaurar el backup previo sobre datos nuevos: perdería escrituras legítimas. Mantener mantenimiento; comparar cambios relacionales posteriores al corte con el snapshot anterior, reconciliar/exportar esos cambios y elegir explícitamente entre corregir hacia delante o una restauración con replay verificado de todas las escrituras nuevas. Revertir frontend/Edge a los repositorios legacy solo cuando se demuestre que los cambios relacionales quedaron preservados o reproducidos en legacy. Si no se puede demostrar integridad y reconciliación, no reabrir. Registrar decisión, responsable y evidencia.

## Registro de decisión

Completar durante la futura ejecución; no rellenar anticipadamente con PASS:

```text
Proyecto/entorno:
Ventana y responsable:
Commit frontend / versión Edge:
Backup, checksum y restauración aislada:
Inventario y hora de congelación:
Rehearsal fresco y reconciliación:
E2E (matriz adjunta):
Migraciones y conversión permanente aprobadas:
Reconciliación posconversión:
GO/NO-GO, responsable y hora:
Incidentes/recuperación:
```
