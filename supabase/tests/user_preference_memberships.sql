begin;

do $$
declare
  alice uuid := gen_random_uuid();
  bob uuid := gen_random_uuid();
  auth_alice uuid := gen_random_uuid();
  auth_bob uuid := gen_random_uuid();
  changed integer;
  rejected boolean := false;
begin
  insert into auth.users(id, email)
    values (auth_alice, auth_alice::text || '@example.invalid'),
           (auth_bob, auth_bob::text || '@example.invalid');
  insert into public.users(id, auth_id)
    values (alice, auth_alice), (bob, auth_bob);
  insert into public.user_preferences(user_id) values (alice), (bob);

  if (select memberships from public.user_preferences where user_id = alice) <> '[]'::jsonb then
    raise exception 'New users must start without assumed memberships';
  end if;

  perform set_config('request.jwt.claim.sub', auth_alice::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', auth_alice)::text, true);
  set local role authenticated;
  if (select count(*) from public.user_preferences) <> 1 then
    raise exception 'Preferences are not isolated by owner';
  end if;
  update public.user_preferences set memberships = '["Costco"]' where user_id = alice;
  get diagnostics changed = row_count;
  if changed <> 1 then raise exception 'Owner cannot save memberships'; end if;
  update public.user_preferences set memberships = '["Other"]' where user_id = bob;
  get diagnostics changed = row_count;
  if changed <> 0 then raise exception 'Another account memberships can be changed'; end if;
  begin
    insert into public.user_preferences(user_id, memberships) values (bob, '["Other"]');
  exception when insufficient_privilege then
    rejected := true;
  end;
  if not rejected then raise exception 'Cross-account insertion was not rejected'; end if;
  reset role;

  if (select memberships from public.user_preferences where user_id = alice) <> '["Costco"]'::jsonb
     or (select memberships from public.user_preferences where user_id = bob) <> '[]'::jsonb then
    raise exception 'Membership values were not isolated';
  end if;
end $$;

select 'user_preference_memberships_isolation_passed' as result;
rollback;
