# CocinAPP · etapa frontend

CocinAPP is a React, TypeScript, and Vite single page frontend for recipes, pantry, weekly planning, shopping, cooking, and personal preferences. This stage runs with local mock adapters so the main flows can be demonstrated without a backend.

## Start

```powershell
cd frontend
npm install
npm run dev
```

Run `npm run typecheck`, `npm run lint`, `npm test`, and `npm run build` from `frontend` for checks.

## Architecture

- `frontend/src/app` composes routing and demo role guards.
- `frontend/src/pages` composes screens.
- `frontend/src/features` keeps domain rules and async repository contracts together.
- `frontend/src/components` contains shared shells and navigation.
- `frontend/src/shared/domain/units.ts` is the shared quantity and unit conversion contract.
- `docs/architecture.md` describes the current frontend boundary and later integration stages.

Feature pages use asynchronous repositories backed by local mock adapters. Those adapters store demonstration data in the browser. Backend work, remote persistence, Supabase Auth, RLS, RPC, and external receipt recognition are future work. Admin roles only control the demo interface and are not a security boundary. Do not use real passwords in this demo.

Receipt scanning currently validates an image and presents editable mock products without uploading or retaining the image. Recipe discovery uses curated recipes and does not generate recipes with AI. Dietary labels are informational and do not guarantee absence of allergens or cross contamination.
