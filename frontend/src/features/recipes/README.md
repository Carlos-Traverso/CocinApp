# Recipes

`RecipeRepository` exposes async listing, detail, matching, and readiness contracts. The shared repository in `data/recipeData.ts` selects the Supabase adapter or the catalog backed by browser storage. Stock checks and dietary filters use the pantry and profile data.
