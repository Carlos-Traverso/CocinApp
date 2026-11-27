-- STAGE ONLY: run in a rollback-only transaction on the final schema.
do $initial_profile_onboarding$
declare
  existing_account uuid;
  relational_account uuid := gen_random_uuid();
  legacy_account uuid := gen_random_uuid();
  profile jsonb;
begin
  select id into strict existing_account from auth.users where email = 'rename-test@example.invalid';
  insert into auth.users(id, email) values
    (relational_account, 'relational-onboarding@example.invalid'),
    (legacy_account, 'legacy-onboarding@example.invalid');
  insert into public.etiquetas_dieteticas(tag_key, label) values ('vegan', 'Vegana')
    on conflict (tag_key) do update set active = true;

  perform set_config('request.jwt.claim.sub', existing_account::text, true);
  set local role authenticated;
  if public.get_my_onboarding_required() then
    raise exception 'FAIL: existing account entered onboarding';
  end if;

  perform set_config('request.jwt.claim.sub', relational_account::text, true);
  if not public.get_my_onboarding_required() then
    raise exception 'FAIL: a new account did not enter onboarding';
  end if;
  begin
    perform public.complete_my_onboarding('{"display_name":"Ana","goal":"maintain","weight_kg":305}', '{}', 0, true);
    raise exception 'FAIL: invalid measurements were accepted';
  exception when invalid_parameter_value then null;
  end;
  if not public.get_my_onboarding_required() or public.get_my_profile()->'profile' <> 'null'::jsonb then
    raise exception 'FAIL: failed save partially completed onboarding';
  end if;

  perform public.complete_my_onboarding('{"display_name":"Ana","goal":"maintain","height_cm":165}', '{vegan}', 0, true);
  perform public.complete_my_onboarding('{"display_name":"Retry","goal":"lose"}', '{}', 0, true);
  profile := public.get_my_profile();
  if public.get_my_onboarding_required()
    or profile->'profile'->>'display_name' is distinct from 'Ana'
    or (profile->'profile'->>'height_cm')::numeric is distinct from 165
    or profile->'profile'->>'goal' is distinct from 'maintain'
    or profile->'preference_keys' is distinct from '["vegan"]'::jsonb then
    raise exception 'FAIL: relational onboarding did not persist once';
  end if;

  perform set_config('request.jwt.claim.sub', legacy_account::text, true);
  if not public.get_my_onboarding_required() then
    raise exception 'FAIL: completing one account affected another';
  end if;
  perform public.complete_my_onboarding('{"display_name":"Luis","goal":"lose"}', '{vegetarian}', 0, false);
  if public.get_my_onboarding_required() then
    raise exception 'FAIL: the legacy profile remained pending';
  end if;
  reset role;

  select value into strict profile from public.datos_personales where user_id = legacy_account and data_key = 'profile';
  if profile is distinct from '{"email":"legacy-onboarding@example.invalid","name":"Luis","goal":"lose","preferences":["vegetarian"]}'::jsonb then
    raise exception 'FAIL: legacy onboarding produced the wrong profile';
  end if;
end;
$initial_profile_onboarding$;
