# CocinAPP architecture

React, TypeScript and Vite form the web client. Supabase Auth establishes identity, and PostgreSQL row-level security and RPCs protect and persist application data. The development server can also run with browser-backed demo repositories.

## Boundaries

| Layer | Location | Responsibility |
| --- | --- | --- |
| Presentation | `frontend/src/pages`, `components`, `features/*/ui` | Routes, interaction, visual state, and accessibility. |
| Domain | `frontend/src/features/*/domain`, `frontend/src/shared/domain` | Models, validation, matching, and shared quantity conversion. |
| Data contracts and adapters | `frontend/src/features/*/data` | Async repository interfaces, Supabase adapters and browser storage. |
| Backend | `backend/supabase` | Schema, permissions, transactions, administrative Edge Function and database tests. |

Screens use repositories for business data and repositories translate between storage and domain models. The standalone HTML prototypes in `docs/reference/pantallas/` are design references outside the React application.

## Domain rules

- Recipe filters use saved dietary preferences and available stock. The recipe detail scales ingredients by portion count and can add missing ingredients to shopping.
- The weekly plan and favorites provide sources for shopping suggestions. Purchased items can be transferred into the pantry. Cooking can consume stock and record the preparation in the history shown on the dashboard.
- `shared/domain/units.ts` centralizes unit conversion and quantity rounding across local flows, with separate dimensions for mass, volume and count.
- The profile stores the active dietary preferences. Recipe discovery and recommendation flows filter by those preferences. Dietary tags remain informational and do not guarantee product or preparation safety.
- The receipt demo is available with browser storage and returns editable sample products. It validates the file type and size locally. Actual receipt recognition requires a separate integration.
- Recipe content comes from the curated catalog and the administrator's changes.

In relational mode, stock deductions and purchase transfers use database transactions. Frontend role guards control navigation. Supabase enforces permissions on reads and writes. See the [integration status](../backend/supabase/CURRENT_STATUS.md) for deployment evidence.

## CSS and build

The frontend uses standard CSS files (`src/index.css`, `src/styles/tokens.css`, and feature styles). Vite and TypeScript scripts live in `frontend/package.json`.
