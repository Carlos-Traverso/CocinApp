# CocinAPP

CocinAPP conecta el catálogo de recetas con la despensa, el plan semanal y la lista de compras. El modo cocina permite seguir los pasos, registrar preparaciones y descontar ingredientes de la despensa. El perfil guarda las preferencias que usa el catálogo y la administración mantiene el contenido compartido.

## Desarrollo local

```powershell
cd frontend
npm install
npm run dev
```

Sin configuración de Supabase, el servidor de desarrollo ofrece una demostración con almacenamiento en el navegador. Para conectar el backend, seguí la [configuración del frontend](frontend/README.md) y consultá el [estado de Supabase](backend/supabase/CURRENT_STATUS.md).

Desde `frontend`, ejecutá `npm run typecheck`, `npm run lint`, `npm test` y `npm run build`.

La [arquitectura](docs/architecture.md) describe cómo se conectan las pantallas, la lógica de dominio y Supabase.
