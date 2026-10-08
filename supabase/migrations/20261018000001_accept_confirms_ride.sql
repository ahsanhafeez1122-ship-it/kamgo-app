-- inDrive style: when a driver ACCEPTS the passenger's own fare, the ride is confirmed straight
-- away (first driver wins) and the driver can start. Only a COUNTER offer (a different price)
-- still waits for the passenger to choose.

-- The part of select_offer that turns an offer into a ride, shared by both ways in.
create or replace function public.confirm_offer(p_offer_id uuid, p_by public.ride_actor)
returns public.rides
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_id uuid;
  v_req ride_requests;
  v_offer ride_offers;
  v_ride rides;
  v_other record;
begin
  select request_id into v_request_id from ride_offers where id = p_offer_id;
  if v_request_id is null then
    raise exception 'Offer not found' using errcode = 'P0002';
  end if;

  -- Lock order: request, then offer (same order everywhere → no deadlocks).
  select * into v_req from ride_requests where id = v_request_id for update;
  if v_req.status <> 'OFFER_RECEIVED' then
    raise exception 'A driver has already been selected for this request' using errcode = '40001';
  end if;
  if v_req.expires_at <= now() then
    raise exception 'This request has expired' using errcode = '22023';
  end if;

  select * into v_offer from ride_offers where id = p_offer_id for update;
  if v_offer.status <> 'PENDING' or v_offer.expires_at <= now() then
    raise exception 'This offer is no longer available' using errcode = '22023';
  end if;

  -- Driver must still be able to take it.
  perform 1 from drivers where id = v_offer.driver_id for update;
  if not exists (
    select 1 from drivers d join profiles p on p.id = d.id
    where d.id = v_offer.driver_id and d.status = 'APPROVED' and d.is_online
      and p.account_status = 'ACTIVE'
  ) or has_active_ride(v_offer.driver_id) then
    update ride_offers set status = 'UNAVAILABLE' where id = p_offer_id;
    raise exception 'This driver is no longer available' using errcode = '22023';
  end if;

  update ride_offers set status = 'SELECTED' where id = p_offer_id;
  for v_other in
    update ride_offers set status = 'UNAVAILABLE'
    where request_id = v_request_id and status = 'PENDING' and id <> p_offer_id
    returning driver_id
  loop
    perform notify(v_other.driver_id, 'OFFER_UNAVAILABLE', 'Another driver got this ride',
      route_label(v_req.route_id), jsonb_build_object('request_id', v_request_id));
  end loop;

  update ride_requests set status = 'DRIVER_SELECTED', selected_offer_id = p_offer_id where id = v_request_id;
  perform log_status(v_request_id, null, 'OFFER_RECEIVED', 'DRIVER_SELECTED', p_by);

  insert into rides (request_id, offer_id, passenger_id, driver_id, vehicle_id, route_id,
                     origin_city_id, destination_city_id, passenger_count, final_fare, status)
  values (v_request_id, p_offer_id, v_req.passenger_id, v_offer.driver_id, v_offer.vehicle_id, v_req.route_id,
          v_req.origin_city_id, v_req.destination_city_id, v_req.passenger_count, v_offer.fare, 'CONFIRMED')
  returning * into v_ride;

  update ride_requests set status = 'CONFIRMED' where id = v_request_id;
  perform log_status(v_request_id, v_ride.id, 'DRIVER_SELECTED', 'CONFIRMED', 'SYSTEM');

  perform notify(v_offer.driver_id, 'SELECTED', 'You got the ride!',
    route_label(v_req.route_id) || ' · ' || fmt_rs(v_offer.fare) || ' · ' || v_req.passenger_count || ' passenger(s)',
    jsonb_build_object('ride_id', v_ride.id));
  perform notify(v_req.passenger_id, 'RIDE_CONFIRMED', 'Ride confirmed',
    (select full_name from profiles where id = v_offer.driver_id) || ' is your driver · ' || fmt_rs(v_offer.fare)
      || coalesce(' · arrives in ' || v_offer.eta_min || ' min', ''),
    jsonb_build_object('ride_id', v_ride.id));

  return v_ride;
end;
$$;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'confirm_offer' loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
  end loop;
end;
$$;

-- The passenger picks an offer (a driver's counter, or one left waiting).
create or replace function public.select_offer(p_offer_id uuid)
returns public.rides
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
begin
  if not exists (
    select 1 from ride_offers o join ride_requests q on q.id = o.request_id
    where o.id = p_offer_id and q.passenger_id = v_uid
  ) then
    raise exception 'Offer not found' using errcode = 'P0002';
  end if;
  return confirm_offer(p_offer_id, 'PASSENGER');
end;
$$;

-- submit_offer: an ACCEPT confirms the ride on the spot.
do $$
declare
  v_src text;
  v_new text;
begin
  select pg_get_functiondef('public.submit_offer(uuid, public.offer_type, numeric, float8, float8, int)'::regprocedure) into v_src;
  v_new := replace(v_src,
    '  perform notify(v_req.passenger_id,',
    '  -- The driver takes the passenger''s own fare: no second step, the ride is on.
  if v_type = ''ACCEPT'' then
    perform confirm_offer(v_offer.id, ''DRIVER'');
    select * into v_offer from ride_offers where id = v_offer.id;
    return v_offer;
  end if;

  perform notify(v_req.passenger_id,');
  if v_new = v_src then raise exception 'submit_offer patch failed'; end if;
  execute v_new;
end;
$$;
