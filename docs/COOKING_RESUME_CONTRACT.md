# Cooking resume read contract

`get_my_open_cooking_session(p_recipe_id uuid, p_legacy_recipe_id text)` finds the caller's newest unfinished session for one recipe. Supply exactly one argument. UUID and legacy text identifiers are distinct namespaces, including when a legacy key happens to look like a UUID. Legacy keys must be nonblank and at most 500 characters.

“Newest” uses `started_at DESC, id DESC`: cooking sessions have no `updated_at` column. The UUID gives a stable tie break. Finished sessions are excluded; no session or unknown recipe returns `NULL`. The function resolves archived recipes too, so archiving a source recipe does not hide or change an existing snapshot. It does not update, finish, or otherwise mutate any session.

The function requires an authenticated active account and only returns sessions owned by that account, including for callers with `ADMIN`. Its payload is the existing `get_my_cooking_session` payload, retaining the immutable recipe snapshot, version, step completion, and derived timer state/remaining time.
