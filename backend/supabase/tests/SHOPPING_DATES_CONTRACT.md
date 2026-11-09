# Shopping suggestions by selected dates

`public.suggest_my_shopping_for_dates(p_dates date[], p_as_of date)` is an authenticated, read-only preview. The input must be a one-dimensional array containing 1 to 42 finite, non-NULL, distinct dates. It selects only the caller’s plan slots whose `meal_date` is in that set, including dates from multiple weeks. Requests spanning more than 20 owned plans are rejected so each proposal stays within the existing provenance limit.

All selected recipe requirements are aggregated by ingredient and converted to the ingredient base unit before the caller’s usable pantry stock is subtracted once. Existing expiry, manual pantry name normalization, unit compatibility, and suggestion array fields are preserved. `sources` contains one `{ "source": "plan", "plan_id": ... }` entry for each contributing plan, compatible with `put_my_shopping_item`. The RPC returns the established JSON array; an empty selection returns `[]`. Dates are not added to each proposal because the shopping write RPC strictly validates proposal keys and provenance objects. This function makes no writes.

Run `shopping_dates_suggestions.stage.sql` inside the rollback rehearsal after applying migrations through `202611010012`. It uses two existing Auth accounts and random fixture IDs; it does not create Auth users.
