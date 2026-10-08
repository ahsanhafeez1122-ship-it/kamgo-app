-- One account, two modes (like inDrive): a passenger can open "Driver mode",
-- which starts a PENDING driver application on the same account. The driver
-- registration screen then collects the vehicle and documents, and an admin
-- approves it. A driver can always switch back to Passenger mode (the booking
-- RPCs never check the role).

create or replace function public.become_driver(p_city_id uuid default null)
returns public.drivers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_profile profiles;
  v_driver drivers;
  v_city uuid;
begin
  select * into v_profile from profiles where id = v_uid for update;
  if not found or not v_profile.onboarded then
    raise exception 'Finish setting up your profile first' using errcode = '42501';
  end if;
  if v_profile.role = 'ADMIN' then
    raise exception 'Admin accounts are managed by KAM GO' using errcode = '42501';
  end if;

  v_city := coalesce(
    (select id from cities where id = p_city_id and is_active),
    (select id from cities where is_active order by sort_order, name limit 1)
  );
  if v_city is null then
    raise exception 'No active city is set up yet' using errcode = '22023';
  end if;

  insert into drivers (id, current_city_id) values (v_uid, v_city)
  on conflict (id) do nothing;

  update profiles set role = 'DRIVER' where id = v_uid;

  select * into v_driver from drivers where id = v_uid;
  return v_driver;
end;
$$;

revoke all on function public.become_driver(uuid) from public;
grant execute on function public.become_driver(uuid) to authenticated;
