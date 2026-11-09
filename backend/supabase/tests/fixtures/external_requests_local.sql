-- LOCAL ISOLATED DATABASE ONLY. Never install/mimic Supabase Auth in a remote project.
do $$ begin
  if not exists(select 1 from pg_roles where rolname='service_role') then
    create role service_role nologin;
  end if;
end $$;
