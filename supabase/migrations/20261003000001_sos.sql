-- SOS: a passenger or driver on an active ride can raise an emergency alert.
-- It is stored as a high-priority complaint (type SOS) with the location link,
-- and every admin is notified.

alter type public.complaint_type add value if not exists 'SOS';

create or replace function public.trigger_sos(
  p_ride_id uuid, p_lat double precision default null, p_lng double precision default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_ride rides;
  v_id uuid;
  v_who text;
  v_where text;
  v_admin uuid;
begin
  select * into v_ride from rides where id = p_ride_id;
  if not found or v_uid not in (v_ride.passenger_id, v_ride.driver_id) then
    raise exception 'Ride not found' using errcode = 'P0002';
  end if;
  if v_ride.status not in ('CONFIRMED', 'DRIVER_ARRIVING', 'RIDE_STARTED') then
    raise exception 'SOS is only available during an active ride' using errcode = '22023';
  end if;

  -- Pressing twice must not spam the admins: reuse an alert raised in the last 2 minutes.
  select id into v_id from complaints
   where reporter_id = v_uid and ride_id = p_ride_id and complaint_type::text = 'SOS'
     and created_at > now() - interval '2 minutes'
   order by created_at desc limit 1;
  if found then
    return v_id;
  end if;

  v_who := case when v_uid = v_ride.driver_id then 'Driver' else 'Passenger' end;
  v_where := case when p_lat is null or p_lng is null then 'location unavailable'
                  else 'https://maps.google.com/?q=' || p_lat || ',' || p_lng end;

  insert into complaints (reporter_id, against_user_id, ride_id, complaint_type, description)
  values (v_uid,
          case when v_uid = v_ride.driver_id then v_ride.passenger_id else v_ride.driver_id end,
          p_ride_id, 'SOS'::public.complaint_type,
          'EMERGENCY (SOS) from the ' || lower(v_who) || ' during a ride. Location: ' || v_where)
  returning id into v_id;

  for v_admin in select user_id from admin_users loop
    perform notify(v_admin, 'SOS', 'SOS emergency alert',
                   v_who || ' pressed SOS · ' || v_where,
                   jsonb_build_object('ride_id', p_ride_id, 'complaint_id', v_id));
  end loop;

  return v_id;
end;
$$;

revoke all on function public.trigger_sos(uuid, double precision, double precision) from public;
grant execute on function public.trigger_sos(uuid, double precision, double precision) to authenticated;
