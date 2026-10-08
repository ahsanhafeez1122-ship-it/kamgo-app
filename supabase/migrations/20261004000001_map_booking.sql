-- Map-based booking.
--
-- The passenger drops a pin for pickup and destination anywhere in the service
-- area (Chichawatni, Kamalia, Pir Mahal, Rajana, Toba Tek Singh and the roads
-- between them). Fare guardrails use the real pin-to-pin distance, and every
-- approved + online driver sees the request — no adda / route matching.
--
-- The rest of the system (offers, rides, commission, history) still hangs off
-- ride_requests.route_id, so a route row between the two nearest towns is
-- created on demand (`ensure_route`). A trip inside one town uses a route from
-- the town to itself.

alter table public.routes drop constraint if exists routes_check;

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.nearest_city(p_lat float8, p_lng float8)
returns table (id uuid, name text, km float8)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.name, haversine_km(p_lat, p_lng, c.lat, c.lng) as km
  from cities c
  where c.is_active and c.lat is not null and c.lng is not null
  order by km
  limit 1;
$$;

create or replace function public.ensure_route(p_origin uuid, p_destination uuid, p_distance numeric)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  select id into v_id from routes
   where origin_city_id = p_origin and destination_city_id = p_destination;
  if found then
    -- Re-activate if an admin switched it off; map trips must keep working.
    update routes set is_active = true where id = v_id and not is_active;
    return v_id;
  end if;
  insert into routes (origin_city_id, destination_city_id, distance_km)
  values (p_origin, p_destination, greatest(1, p_distance))
  on conflict (origin_city_id, destination_city_id) do update set is_active = true
  returning id into v_id;
  return v_id;
end;
$$;

-- "Kamalia → Pir Mahal", or "Kamalia · local trip" inside one town.
create or replace function public.route_label(p_route_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select o.name || case when o.id = d.id then ' · local trip' else ' → ' || d.name end
  from routes r join cities o on o.id = r.origin_city_id join cities d on d.id = r.destination_city_id
  where r.id = p_route_id;
$$;

-- Same rule as assert_fare_allowed(), but for an arbitrary distance.
create or replace function public.assert_fare_for_distance(p_distance numeric, p_fare numeric)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_min numeric := ceil(p_distance * setting_num('min_fare_per_km', 20));
  v_max numeric := floor(p_distance * setting_num('max_fare_per_km', 100));
begin
  if p_fare is null or p_fare < v_min or p_fare > v_max then
    raise exception 'Fare must be between Rs. % and Rs. % for this trip', v_min::bigint, v_max::bigint
      using errcode = '22023';
  end if;
end;
$$;

-- Any approved, online, active driver can see an open request (no adda match).
-- The signature is unchanged because RLS and the feeds call it.
create or replace function public.driver_can_see_request(
  p_origin_city_id uuid,
  p_route_id uuid,
  p_status public.ride_status,
  p_expires_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_status in ('REQUESTED', 'SEARCHING', 'OFFER_RECEIVED')
    and p_expires_at > now()
    and exists (
      select 1
      from drivers d
      join profiles p on p.id = d.id
      where d.id = auth.uid()
        and d.status = 'APPROVED'
        and d.is_online
        and p.account_status = 'ACTIVE'
    );
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Passenger creates a request from two map pins
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.create_ride_request_geo(
  p_pickup_lat float8,
  p_pickup_lng float8,
  p_dropoff_lat float8,
  p_dropoff_lng float8,
  p_passenger_count int,
  p_offered_fare numeric,
  p_pickup_label text default null,
  p_dropoff_label text default null,
  p_notes text default null
)
returns public.ride_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_o record;
  v_d record;
  v_max_km numeric := setting_num('max_service_km', 40);
  v_dist numeric;
  v_route_id uuid;
  v_req ride_requests;
  v_driver record;
  v_label text;
begin
  if p_pickup_lat is null or p_pickup_lng is null or p_dropoff_lat is null or p_dropoff_lng is null
     or p_pickup_lat not between -90 and 90 or p_dropoff_lat not between -90 and 90
     or p_pickup_lng not between -180 and 180 or p_dropoff_lng not between -180 and 180 then
    raise exception 'Choose a pickup and a destination on the map' using errcode = '22023';
  end if;

  select * into v_o from nearest_city(p_pickup_lat, p_pickup_lng);
  select * into v_d from nearest_city(p_dropoff_lat, p_dropoff_lng);
  if v_o.id is null or v_d.id is null then
    raise exception 'No service area is set up yet' using errcode = '22023';
  end if;
  if v_o.km > v_max_km then
    raise exception 'Pickup is outside our service area' using errcode = '22023';
  end if;
  if v_d.km > v_max_km then
    raise exception 'Destination is outside our service area' using errcode = '22023';
  end if;

  if haversine_km(p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng) < 0.3 then
    raise exception 'Pickup and destination are the same place' using errcode = '22023';
  end if;
  -- Straight line × 1.3 road factor, one decimal. The app uses the same formula.
  v_dist := greatest(1, round((haversine_km(p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng) * 1.3)::numeric, 1));

  if p_passenger_count is null
     or p_passenger_count < 1
     or p_passenger_count > setting_num('max_passengers', 6) then
    raise exception 'Passengers must be between 1 and %', setting_num('max_passengers', 6)::int
      using errcode = '22023';
  end if;

  perform assert_fare_for_distance(v_dist, p_offered_fare);

  -- Serialise this passenger's requests so two taps can't create two.
  perform 1 from profiles where id = v_uid for update;

  if exists (
    select 1 from ride_requests
    where passenger_id = v_uid
      and status in ('REQUESTED', 'SEARCHING', 'OFFER_RECEIVED')
      and expires_at > now()
  ) then
    raise exception 'You already have an open ride request' using errcode = '23505';
  end if;
  if has_active_ride(v_uid) then
    raise exception 'You already have an active ride' using errcode = '23505';
  end if;

  insert into passengers (id) values (v_uid) on conflict (id) do nothing;

  v_route_id := ensure_route(v_o.id, v_d.id, v_dist);

  insert into ride_requests (
    passenger_id, route_id, origin_city_id, destination_city_id,
    pickup_label, pickup_lat, pickup_lng, dropoff_label, dropoff_lat, dropoff_lng,
    passenger_count, offered_fare, distance_km, status, expires_at, notes
  ) values (
    v_uid, v_route_id, v_o.id, v_d.id,
    coalesce(nullif(btrim(p_pickup_label), ''), 'Map pin'), p_pickup_lat, p_pickup_lng,
    coalesce(nullif(btrim(p_dropoff_label), ''), 'Map pin'), p_dropoff_lat, p_dropoff_lng,
    p_passenger_count, round(p_offered_fare), v_dist, 'SEARCHING',
    now() + make_interval(mins => setting_num('request_expiry_minutes', 15)::int),
    nullif(btrim(p_notes), '')
  )
  returning * into v_req;

  perform log_status(v_req.id, null, null, 'REQUESTED', 'PASSENGER');
  perform log_status(v_req.id, null, 'REQUESTED', 'SEARCHING', 'SYSTEM');

  v_label := route_label(v_route_id);
  perform notify(v_uid, 'REQUEST_SENT', 'Request sent',
    v_label || ' · ' || fmt_rs(v_req.offered_fare) || ' · finding drivers',
    jsonb_build_object('request_id', v_req.id));

  -- Tell every approved, online, active driver.
  for v_driver in
    select d.id,
           exists (
             select 1 from rides x
             where x.driver_id = d.id and x.status = 'COMPLETED'
               and x.destination_city_id = v_req.origin_city_id
               and x.completed_at > now() - interval '3 hours'
           ) as is_return
    from drivers d
    join profiles p on p.id = d.id
    where d.status = 'APPROVED' and d.is_online and p.account_status = 'ACTIVE'
      and d.id <> v_uid
  loop
    perform notify(
      v_driver.id,
      case when v_driver.is_return then 'RETURN_RIDE' else 'NEW_REQUEST' end,
      case when v_driver.is_return then 'Return ride opportunity' else 'New ride request' end,
      v_label || ' · ' || v_req.passenger_count || ' passenger(s) · offer ' || fmt_rs(v_req.offered_fare),
      jsonb_build_object('request_id', v_req.id)
    );
  end loop;

  return v_req;
end;
$$;

revoke all on function public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text) from public;
grant execute on function public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text) to authenticated;
revoke all on function public.nearest_city(float8, float8) from public;
grant execute on function public.nearest_city(float8, float8) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Driver offers: the fare guardrail now follows the request's own distance.
-- (Identical to the Phase 2 version except for the assert below.)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.submit_offer(
  p_request_id uuid,
  p_offer_type public.offer_type,
  p_fare numeric default null,
  p_driver_lat float8 default null,
  p_driver_lng float8 default null
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

  select id into v_vehicle_id from vehicles
   where driver_id = v_uid and is_active order by created_at limit 1;
  if v_vehicle_id is null then
    raise exception 'Add your vehicle before making offers' using errcode = '22023';
  end if;

  select * into v_req from ride_requests where id = p_request_id for update;
  if not found
     or not driver_can_see_request(v_req.origin_city_id, v_req.route_id, v_req.status, v_req.expires_at)
     or v_req.passenger_id = v_uid then
    raise exception 'This request is no longer available' using errcode = 'P0002';
  end if;

  if v_type = 'ACCEPT' then
    v_fare := v_req.offered_fare;
  else
    v_fare := round(p_fare);
    perform assert_fare_for_distance(v_req.distance_km, v_fare);
    if v_fare = v_req.offered_fare then
      v_type := 'ACCEPT';
    end if;
  end if;

  -- Distance / ETA to pickup (straight line × 1.3 road factor, ~30 km/h).
  if p_driver_lat is not null and p_driver_lng is not null
     and v_req.pickup_lat is not null and v_req.pickup_lng is not null then
    v_dist := haversine_km(p_driver_lat, p_driver_lng, v_req.pickup_lat, v_req.pickup_lng) * 1.3;
    v_eta := greatest(2, ceil(v_dist / 30.0 * 60)::int);
  end if;

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
    (select full_name from profiles where id = v_uid) || ' · ' || fmt_rs(v_fare),
    jsonb_build_object('request_id', p_request_id, 'offer_id', v_offer.id));

  return v_offer;
end;
$$;

-- Internal helpers: only the SECURITY DEFINER functions above may call them.
revoke all on function public.ensure_route(uuid, uuid, numeric) from public;
revoke all on function public.assert_fare_for_distance(numeric, numeric) from public;
