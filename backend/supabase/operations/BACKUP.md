# Legacy public-schema backup

`backup_legacy.ps1` writes a read-only `pg_dump` custom-format archive of `public`, asks `pg_restore --list` to read it, requires all seven legacy tables in its TOC, and writes a SHA-256 manifest. It never runs restore commands. Archive inspection and a hash do **not** prove that a restore will succeed.

## Current environment

The current Supabase project is on the Free plan, and the frontend has not been deployed; it is being tested locally. Keep a manual export outside the project and rehearse local frontend behavior against an isolated clone before selecting hosting or planning a production cutover. Supabase documents that Free projects rely on manual database exports; see the [platform backup guide](https://supabase.com/docs/guides/platform/backups).

## Prepare and run

Install PostgreSQL client tools (`pg_dump` and `pg_restore`) and put them on `PATH`. Create a secured backup directory outside this repository and ensure the account running the script can write there. Configure libpq with either:

- `PGSERVICE` referring to a protected service definition, or
- `PGHOST`, `PGDATABASE`, and `PGUSER`.

Provide credentials only through a protected `PGPASSFILE` or protected service file. Do not set `PGPASSWORD`, place passwords in command arguments, or paste connection strings into logs or tickets. The script uses `--no-password`, so it will not prompt interactively. Supabase connection details and password-file guidance are in the [Supabase backup and restore guide](https://supabase.com/docs/guides/platform/backups).

From PowerShell, first check local prerequisites without contacting the database:

```powershell
& .\backend\supabase\operations\backup_legacy.ps1 -OutputDirectory 'D:\secure-backups\CocinAPP' -ValidateOnly
```

After reviewing the resolved target and configuration, run the same command without `-ValidateOnly`. The output directory must already exist and must be outside the repository. Each run chooses a UTC timestamped name and refuses to overwrite existing output. Keep the archive, TOC list, and hash manifest together in access-controlled storage; copy or verify the hash through a separate trusted channel if tamper evidence is needed.

The script checks the TOC for `pantry_items`, `personal_data`, `user_roles`, `catalog_core`, `shared_recipes`, `account_status`, and `admin_audit_log`. A successful command means only that `pg_dump` exited successfully, `pg_restore --list` could read the archive, and those table entries were listed.

## Scope and restore rehearsal

This is a **public schema export**, not a complete Supabase recovery backup. It does not back up Storage object contents, and it does not establish recovery of Auth-managed state, roles/grants, extensions, Edge Functions, secrets, or hosting configuration. Supabase platform backups also treat database and Storage object backups separately; consult the [platform backup guide](https://supabase.com/docs/guides/platform/backups) and [Supabase backup/restore migration guide](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore) for platform-specific coverage and migration requirements.

Before a restore rehearsal, confirm the target is an isolated preproduction Supabase project with matching PostgreSQL/Supabase extensions and no production credentials or data writes. Review ownership/role handling, extension availability, and the restore plan before executing it. Verify application behavior and data reconciliation there. Do not use an automatic or in-place production restore procedure based on this artifact alone.

## Ejecución interactiva en Windows

`start_backup.ps1` configura la conexión solo durante la ejecución, pide la contraseña con entrada oculta y utiliza un archivo temporal de credenciales con permisos restringidos. No pegar contraseñas ni URI completas en el chat. El directorio de destino debe existir y estar fuera del repositorio; preferir una ubicación local protegida sin sincronización automática.

En Supabase → Connect, copiar Host, Port, Database y User de **Session pooler** (modo sesión, no transacción). Este modo permite redes IPv4; para respaldos Supabase recomienda conexión directa cuando está disponible. Referencia: [conexiones PostgreSQL](https://supabase.com/docs/guides/database/connecting-to-postgres).

Con los valores reales, primero ejecutar `start_backup.ps1 -HostName HOST -Port 5432 -Database postgres -UserName USUARIO -OutputDirectory DIRECTORIO -ValidateOnly`. Esta comprobación no conecta ni pide contraseña. Repetir sin `-ValidateOnly` para exportar: la contraseña se ingresa en la terminal local, nunca como argumento. Los valores HOST, USUARIO y DIRECTORIO son marcadores, no configuración lista para usar.
