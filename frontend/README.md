# CocinAPP frontend

CocinAPP is a React, TypeScript, and Vite single page app. It uses plain CSS in `src/index.css`, `src/styles/tokens.css`, and feature styles; Tailwind is not installed. Supabase provides authentication and remote persistence. Local demo adapters remain available during development without Supabase configuration; production requires Supabase.

## Run it

```powershell
cd frontend
npm install
npm run dev
```

Check the app with `npm run typecheck`, `npm run lint`, `npm test`, or `npm run build`.

Copy `.env.example` to `.env` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` to the public project configuration. Restart Vite after editing the environment. Keep service-role keys, secret keys, and SMTP credentials on the server.

The backend migrations and `admin-users` Edge Function are in [backend/supabase](../backend/supabase). Check the [integration status](../backend/supabase/CURRENT_STATUS.md) before applying migrations or deploying the function.

`npm test` runs the frontend tests and exercises the checked-in administrative handler with simulated transports. Use `npm run test:admin-users-edge` to run just the handler tests.

## Direct links in production

Publish the Vite output in `dist`. Configure the hosting provider to serve existing assets and files first, then rewrite navigation requests such as `/panel`, `/admin/users`, and `/restablecer-contrasena` to `/index.html` while keeping the requested URL and query string. This lets CocinAPP check the session, handle password recovery, and display its own 404 page for unknown addresses. The development server and `npm run preview` already support this behavior.

## Structure and data boundary

- `src/app` contains routes and session and role guards.
- `src/pages` composes route screens.
- `src/features/*/domain` contains models, calculations, and validation.
- `src/features/*/data` contains repository contracts, Supabase adapters, and local caches or demo adapters.
- `src/shared/domain/units.ts` centralizes unit conversion and quantity rounding.
- `src/components` contains shared navigation and shell components.

Pages call asynchronous repository contracts for authentication, profile, recipes, pantry, cooking, planning, shopping, dashboard, and administration. With Supabase configured, the app uses Auth, private pantry and personal-data tables, shared catalogs, administrative RPCs, and the user-management Edge Function. Catalog writes compare versions to reject stale saves. Relational mode uses database transactions for purchases transferred to the pantry and cooking finalization.

## Recipe meal shifts

Recipes can be assigned to more than one meal shift. The recipe catalog filters by every assigned shift, the detail page lists them all, and the weekly planner offers the recipe in each matching meal slot. Older recipes continue to use their single `mealShift` value, then `category` as a fallback.

## Transient notices and confirmations

Use the app-wide `NotificationProvider` and the `useNotifications()` hook from `src/shared/notifications/NotificationProvider.tsx` for modal notices. Avoid interrupting routine successful actions: a `success` request without `cancelLabel` resolves immediately to `true` and does not open a modal. Use `info` only for information the user needs to act on or understand an unavailable option; use `error` for failures that need attention. Each displayed request includes a short `title` and `message`.

For a confirmation, provide explicit `confirmLabel` and `cancelLabel`, then await `notify(...)`. These requests remain decisions even when their type is `success`; continue the action only when it resolves to `true`. Cancellation, Escape, or dismissal resolves to `false`. Preserve confirmations for destructive actions.

Show routine form validation errors inline beside the relevant field or form, associate field errors with their controls using `aria-describedby`, and focus the first invalid field when submission fails. Do not use a modal notice for these validation errors. This also avoids stacking a notice dialog over an already-open native dialog.

## Demo limitations

Local development simulates accounts and the administrator role in the browser. Use fictitious credentials. The local receipt demo validates the file type and size and returns editable sample rows. Actual receipt recognition requires a separate integration. Recipe suggestions use the curated catalog.

Dietary tags are informational and cannot guarantee allergen or cross contamination safety. Users should check product labels and preparation conditions.

## Integración relacional

Los ocho indicadores `VITE_RELATIONAL_*` de `.env.example` se activan juntos con `true` cuando la base relacional está migrada. Reiniciá Vite después de cambiar la configuración. La función `admin-users` requiere `COCINAPP_RELATIONAL_PROFILES=true` en el servidor. Consultá el [estado de integración](../backend/supabase/CURRENT_STATUS.md).
