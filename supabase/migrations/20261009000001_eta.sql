-- "When will the driver arrive?"
--  * The driver says how many minutes they need when they accept / counter
--    (p_eta_min). Without GPS the server cannot work it out, so the driver's own
--    word is the ETA; with GPS it is the default the app suggests.
--  * The selected offer's ETA and pickup distance are returned with the ride so both
--    screens can show "Driver arrives in about N min".

drop function if exists public.submit_offer(uuid, public.offer_type, numeric, float8, float8);

create or replace function public.submit_offer(
  p_request_id uuid,
  p_offer_type public.offer_type,
  p_fare numeric default null,
  p_driver_lat float8 default null,
  p_driver_lng float8 default null,
  p_eta_min int default null
)
returns public.ride_offers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_driver drivers;
  v_vehicle_id uuid;
  v_req ride_requests;
  v_fare numeric;
  v_type offer_type := p_offer_type;
  v_offer ride_offers;
  v_dist float8;
  v_eta int;
  v_is_update boolean := false;
begin
  select * into v_driver from drivers where id = v_uid;
  if not found or v_driver.status <> 'APPROVED' then
    raise exception 'Only approved drivers can make offers' using errcode = '42501';
  end if;
  if not v_driver.is_online then
    raise exception 'Go online to make offers' using errcode = '42501';
  end if;
  if has_active_ride(v_uid) then
    raise exception 'Finish your current ride first' using errcode = '22023';
  end if;
  if p_eta_min is not null and p_eta_min not between 1 and 240 then
    raise exception 'Arrival time must be between 1 and 240 minutes' using errcode = '22023';
  end if;

  if p_driver_lat is not null and p_driver_lng is not null then
    update drivers set last_lat = p_driver_lat, last_lng = p_driver_lng, last_location_at = now()
     where id = v_uid;
  end if;

  select * into v_req from ride_requests where id = p_request_id for update;
  if not found
     or not driver_sees_request(v_req.category, v_req.pickup_lat, v_req.pickup_lng, v_req.status, v_req.expires_at)
     or v_req.passenger_id = v_uid then
    raise exception 'This request is no longer available' using errcode = 'P0002';
  end if;

  select id into v_vehicle_id from vehicles
   where driver_id = v_uid and is_active and category = v_req.category order by created_at limit 1;
  if v_vehicle_id is null then
    raise exception 'Your vehicle does not match this ride type' using errcode = '22023';
  end if;

  if v_type = 'ACCEPT' then
    v_fare := v_req.offered_fare;
  else
    v_fare := round(p_fare);
    perform assert_fare_for_category(v_req.distance_km, v_fare, v_req.category);
    if v_fare = v_req.offered_fare then
      v_type := 'ACCEPT';
    end if;
  end if;

  -- Distance to the pickup (straight line × 1.3 road factor) when we know where the
  -- driver is; the ETA is the driver's own answer, else ~30 km/h from that distance.
  if p_driver_lat is not null and p_driver_lng is not null
     and v_req.pickup_lat is not null and v_req.pickup_lng is not null then
    v_dist := haversine_km(p_driver_lat, p_driver_lng, v_req.pickup_lat, v_req.pickup_lng) * 1.3;
  end if;
  v_eta := coalesce(p_eta_min, case when v_dist is not null then greatest(2, ceil(v_dist / 30.0 * 60)::int) end);

  -- One live offer per driver per request: a new offer replaces the old one.
  update ride_offers
     set offer_type = v_type, fare = v_fare, vehicle_id = v_vehicle_id,
         eta_min = coalesce(v_eta, eta_min),
         distance_to_pickup_km = coalesce(round(v_dist::numeric, 1), distance_to_pickup_km),
         expires_at = now() + make_interval(mins => setting_num('offer_expiry_minutes', 3)::int)
   where request_id = p_request_id and driver_id = v_uid and status = 'PENDING'
  returning * into v_offer;
  v_is_update := found;

  if not v_is_update then
    insert into ride_offers (request_id, driver_id, vehicle_id, offer_type, fare, eta_min,
                             distance_to_pickup_km, expires_at)
    values (p_request_id, v_uid, v_vehicle_id, v_type, v_fare, v_eta, round(v_dist::numeric, 1),
            now() + make_interval(mins => setting_num('offer_expiry_minutes', 3)::int))
    returning * into v_offer;
  end if;

  if v_req.status <> 'OFFER_RECEIVED' then
    update ride_requests set status = 'OFFER_RECEIVED' where id = p_request_id;
    perform log_status(p_request_id, null, v_req.status, 'OFFER_RECEIVED', 'SYSTEM');
  end if;

  perform notify(v_req.passenger_id,
    case when v_type = 'ACCEPT' then 'OFFER_ACCEPTED' else 'OFFER_COUNTER' end,
    case when v_type = 'ACCEPT' then 'A driver accepted your offer' else 'New counter offer' end,
    (select full_name from profiles where id = v_uid) || ' · ' || fmt_rs(v_fare)
      || coalesce(' · arrives in ' || v_eta || ' min', ''),
    jsonb_build_object('request_id', p_request_id, 'offer_id', v_offer.id));

  return v_offer;
end;
$$;

revoke all on function public.submit_offer(uuid, public.offer_type, numeric, float8, float8, int) from public;
grant execute on function public.submit_offer(uuid, public.offer_type, numeric, float8, float8, int) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ride details also carry the selected offer's ETA and pickup distance.
-- (Same as before, plus 'eta_min' and 'pickup_distance_km'.)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_ride_details(p_ride_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
  v_ride rides;
begin
  select * into v_ride from rides where id = p_ride_id;
  if not found or not (auth.uid() in (v_ride.passenger_id, v_ride.driver_id) or is_admin()) then
    raise exception 'Ride not found' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'id', r.id,
    'request_id', r.request_id,
    'status', r.status,
    'final_fare', r.final_fare,
    'passenger_count', r.passenger_count,
    'confirmed_at', r.confirmed_at,
    'started_at', r.started_at,
    'completed_at', r.completed_at,
    'route_id', r.route_id,
    'distance_km', rt.distance_km,
    'est_duration_min', rt.est_duration_min,
    'eta_min', (select o2.eta_min from ride_offers o2 where o2.id = r.offer_id),
    'pickup_distance_km', (select o2.distance_to_pickup_km from ride_offers o2 where o2.id = r.offer_id),
    'origin', jsonb_build_object('id', o.id, 'name', o.name, 'lat', coalesce(q.pickup_lat, o.lat), 'lng', coalesce(q.pickup_lng, o.lng), 'label', q.pickup_label),
    'destination', jsonb_build_object('id', d.id, 'name', d.name, 'lat', coalesce(q.dropoff_lat, d.lat), 'lng', coalesce(q.dropoff_lng, d.lng), 'label', q.dropoff_label),
    'stops', coalesce((select jsonb_agg(jsonb_build_object('name', s.name, 'lat', s.lat, 'lng', s.lng) order by s.stop_order)
                       from route_stops s where s.route_id = r.route_id), '[]'::jsonb),
    'driver', jsonb_build_object(
      'id', dp.id, 'name', dp.full_name, 'rating', dr.rating_avg, 'rating_count', dr.rating_count,
      'avatar_url', dp.avatar_url,
      'phone', case when r.status in ('CONFIRMED','DRIVER_ARRIVING','RIDE_STARTED') then '+' || dp.phone end,
      'vehicle', jsonb_build_object('type', v.vehicle_type, 'make', v.make, 'model', v.model,
                                    'color', v.color, 'plate', v.plate_number)),
    'passenger', jsonb_build_object(
      'id', pp.id, 'name', pp.full_name, 'rating', pa.rating_avg,
      'phone', case when r.status in ('CONFIRMED','DRIVER_ARRIVING','RIDE_STARTED') then '+' || pp.phone end),
    'my_rating', (select stars from ratings where ride_id = r.id and rater_id = auth.uid()),
    'commission', case when auth.uid() = r.driver_id or is_admin() then
      (select jsonb_build_object('percent', c.commission_percent, 'amount', c.commission_amount,
                                 'driver_earning', c.driver_earning)
       from commissions c where c.ride_id = r.id) end,
    'last_location', (select jsonb_build_object('lat', l.lat, 'lng', l.lng, 'at', l.recorded_at)
                      from ride_locations l where l.ride_id = r.id order by l.recorded_at desc limit 1)
  ) into v
  from rides r
  join routes rt on rt.id = r.route_id
  join ride_requests q on q.id = r.request_id
  join cities o on o.id = r.origin_city_id
  join cities d on d.id = r.destination_city_id
  join profiles dp on dp.id = r.driver_id
  join drivers dr on dr.id = r.driver_id
  join profiles pp on pp.id = r.passenger_id
  left join passengers pa on pa.id = r.passenger_id
  left join vehicles v on v.id = r.vehicle_id
  where r.id = p_ride_id;
  return v;
end;
$$;
