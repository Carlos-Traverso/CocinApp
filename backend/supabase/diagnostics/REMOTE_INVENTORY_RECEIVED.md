# Inventario remoto comunicado por el usuario

Resultado recibido de `cutover_inventory.sql`; solo lectura, sin aplicación permanente.

- Siete tablas legacy presentes y todas las tablas españolas ausentes. RPC relacionales representativas ausentes; RPC de auditoría legacy presente.
- Despensa: 22 filas. Documentos personales: 12; perfiles 6, favoritos 1 no vacío, planificación 1 no vacía, historial 1 no vacío, progreso de cocina 2 documentos (uno no vacío), compras 1 documento vacío.
- Sin duplicados fecha/turno detectados, sin errores de formato de perfil/plan/favoritos/historial o versiones detectados por esta consulta acotada.
- `cooking_progress_shape=2` fue un falso positivo del diagnóstico: el código esperaba object/null, pero el contrato real es array. La salida suministrada identifica ambos documentos como arrays. Se corrigió el detector; no se concluye corrupción de esos registros.
- 11 referencias no encontradas en `shared_recipes` únicamente. No equivale a 11 recetas huérfanas: falta clasificar contra los IDs del catálogo inicial incluido (`recipe_seed_v3.json`). Ejecutar `relational_seed_reference_check.sql` para determinar `unresolved_references` después de incluir ambos catálogos.
- Los permisos de tabla amplios para anon sobre despensa/documentos no demuestran por sí solos acceso a filas: RLS figura activado. Falta verificar políticas efectivas y permisos de función en entorno final. El inventario no muestra datos personales.

Conclusión: no activar flags ni migrar permanentemente. El caso real requiere conversión de progreso activo; compras actualmente están vacías. Próximo paso: clasificar referencias con el catálogo inicial, luego ensayo integral con ROLLBACK y reconciliación de datos reales. Respaldo restaurable y pruebas de navegador siguen pendientes.

## Clasificación adicional confirmada por el usuario

| Clave | Referencias remotas | Solo catálogo inicial | Sin resolver |
| --- | ---: | ---: | ---: |
| cooking_history | 2 | 3 | 0 |
| cooking_progress | 1 | 0 | 0 |
| favorites | 1 | 3 | 0 |
| meal_plan | 7 | 5 | 0 |

Las 11 referencias del primer diagnóstico son 11 referencias al catálogo inicial (3 historial + 3 favoritos + 5 planificación). No hay referencias a recetas sin resolver en las claves examinadas. Esto no valida aún cada ingrediente/unidad/perfil ni el estado del temporizador: corresponde probar el ensayo completo de conversión con ROLLBACK. Sin aplicación permanente.

## Ensayo remoto confirmado

El usuario confirmó `PASS: legacy data conversion verified; full script includes ROLLBACK` de `backfill/cutover_data_rehearsal.sql`. Conversión integral ensayada sobre datos reales; cambios deshechos por rollback. Siguen pendientes respaldo/restauración, artefactos permanentes de corte/recuperación, pruebas de navegador y autorización de aplicación definitiva.
