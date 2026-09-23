# CocinAPP

Aplicación de gestión alimentaria organizada como una SPA cliente y un backend Supabase, con separación por capas. Durante esta etapa, la experiencia navegable utiliza directamente las pantallas HTML originales de `../Pantallas`, preservando su diseño responsive y sus interacciones.

## Frontend

```powershell
cd frontend
npm install
npm run dev
```

La aplicación queda en `http://localhost:5173/` y abre la pantalla de bienvenida original. Para generar la versión distribuible: `npm run build`.

Copiá `.env.example` como `.env` y completá `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` cuando comience la integración. El cliente Supabase se inicializa bajo demanda. Las claves privadas y de servicios externos nunca se guardan en variables `VITE_*`.

## Organización

- `frontend/src/app`: composición global, rutas y proveedores.
- `frontend/src/features`: módulos por dominio y sus servicios/repositorios.
- `frontend/src/pages`: pantallas asociadas a rutas.
- `frontend/src/components`: interfaz compartida, sin reglas de dominio.
- `frontend/src/mocks`: datos y adaptadores de demostración.
- `frontend/src/lib/supabase`: cliente e integración de infraestructura.
- `backend/supabase/migrations`: evolución versionada del esquema PostgreSQL.
- `backend/supabase/functions`: operaciones que requieren ejecución segura del lado servidor.
- `docs`: decisiones y acuerdos arquitectónicos.

Las pantallas iniciales guardan su estado de demostración en el navegador. Todavía no hay autenticación real ni persistencia remota.
