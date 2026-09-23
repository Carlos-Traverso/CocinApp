# Frontend CocinAPP

SPA con React, TypeScript, Vite y Tailwind. Ejecutar `npm install` y `npm run dev`. La ruta raíz abre la pantalla de bienvenida original; las pantallas se versionan dentro de `public/pantallas` para que el proyecto funcione después de clonarlo.

`src/features` organiza los dominios; `src/pages` compone rutas; `src/mocks` ofrece los adaptadores locales iniciales. Los componentes no consultan Supabase: cada dominio define contratos y adaptadores. Configurar Supabase copiando `.env.example` a `.env` cuando corresponda.
