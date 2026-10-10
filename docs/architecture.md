# CocinAPP architecture

## Current stage

The shipped app in this repository is the React, TypeScript, and Vite frontend. It uses plain CSS; Tailwind is not installed. Frontend flows run with asynchronous local mock adapters and browser storage. No backend, Supabase Auth, remote database access, RLS policy, RPC, or Edge Function is implemented in this stage.

## Boundaries

| Layer | Location | Responsibility |
| --- | --- | --- |
| Presentation | `frontend/src/pages`, `components`, `features/*/ui` | Routes, interaction, visual state, and accessibility. |
| Domain | `frontend/src/features/*/domain`, `frontend/src/shared/domain` | Models, validation, matching, and shared quantity conversion. |
| Data contracts and adapters | `frontend/src/features/*/data` | Async repository interfaces and replaceable local mock implementations. |
| Future backend | `backend/` | Reserved for a later stage; it is not required by this frontend. |

Pages and shared UI should call a domain repository rather than access browser storage directly. Current examples include `AuthRepository`, `ProfileRepository`, `RecipeRepository`, `PantryRepository`, `PlannerRepository`, `ShoppingRepository`, and `DashboardRepository`. The mock implementations may use local storage internally. Model to storage translation belongs in these adapters.

Legacy standalone HTML screen prototypes are kept under `docs/reference/pantallas/` as design references. They are not part of the Vite public assets or the React application; their demo controls and flows are not maintained as product behavior.

## Domain rules

- `shared/domain/units.ts` is the source for compatible unit conversion and quantity rounding. It supports mass, volume, and count separately; a conversion across dimensions requires an explicit ingredient equivalence, which this stage does not infer.
- The profile stores the active dietary preferences. Recipe discovery and recommendation flows filter by those preferences. Dietary tags remain informational and do not guarantee product or preparation safety.
- The ticket reader is a replaceable `ReceiptScanner` contract. Its mock validates an image locally and returns editable sample data. It does not upload, retain, or log image bytes. A future external recognition service is not implemented.
- Recipe content is curated mock data and admin managed content. AI generated recipes are outside the current scope.
- Admin role guards are a visual demo restriction. They do not provide authentication, authorization, or data security.

## Later integration

When a backend is introduced, replace each mock adapter behind its existing contract. A backend may add database transactions for stock deductions and server side permission checks. Those guarantees cannot be supplied by browser storage or client side role guards. Keep credentials for external services on the server and never ship private keys in the Vite client bundle.

## CSS and build

The frontend uses standard CSS files (`src/index.css`, `src/App.css`, and feature styles). Vite and TypeScript scripts live in `frontend/package.json`; no Tailwind build plugin or CSS framework is configured.
