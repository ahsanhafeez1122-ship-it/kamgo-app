-- Ride categories (Bike · Rickshaw · Mini · Premium · Courier) and nearby matching.
--
--  * Each category has its own fare range per km and seat limit (admin-editable).
--  * A driver's vehicle belongs to one category; a request goes only to drivers
--    of that category (a Mini driver never sees a Premium request).
--  * A request goes only to drivers within `search_radius_km` of the pickup
--    (the driver app reports its location while online). A driver with no
--    recent location is not filtered out, so GPS problems never hide requests.
--  * Courier is just the loader-rickshaw category, booked like any other ride.

-- ─────────────────────────────────────────────────────────────────────────────
-- Categories
-- ─────────────────────────────────────────────────────────────────────────────
create table public.ride_categories (
  code             text primary key,
  name             text not null,
  name_ur          text,
  vehicle_type     public.vehicle_type not null,
  min_fare_per_km  numeric(8,2) not null check (min_fare_per_km > 0),
  max_fare_per_km  numeric(8,2) not null,
  max_passengers   int not null default 4 check (max_passengers between 1 and 20),
  sort_order       int not null default 0,
  is_active        boolean not null default true,
  updated_at       timestamptz not null default now(),
  check (max_fare_per_km >= min_fare_per_km)
);

insert into public.ride_categories
  (code, name, name_ur, vehicle_type, min_fare_per_km, max_fare_per_km, max_passengers, sort_order) values
  ('BIKE',     'Bike',     'بائیک',    'MOTORCYCLE', 10, 40,  1, 1),
  ('RICKSHAW', 'Rickshaw', 'رکشہ',     'RICKSHAW',   15, 50,  3, 2),
  ('MINI',     'Mini',     'منی',      'CAR',        20, 70,  4, 3),
  ('PREMIUM',  'Premium',  'پریمیم',   'CAR',        35, 100, 4, 4),
  ('COURIER',  'Courier',  'کوریئر',   'RICKSHAW',   25, 90,  1, 5);

alter table public.ride_categories enable row level security;
grant select on public.ride_categories to authenticated;
grant update (name, name_ur, min_fare_per_km, max_fare_per_km, max_passengers, sort_order, is_active)
  on public.ride_categories to authenticated;
create policy ride_categories_read on public.ride_categories for select to authenticated using (true);
create policy ride_categories_admin_update on public.ride_categories for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- Vehicles and requests carry a category
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.vehicles
  add column category text not null default 'MINI' references public.ride_categories(code);
update public.vehicles set category = case vehicle_type
  when 'MOTORCYCLE' then 'BIKE' when 'RICKSHAW' then 'RICKSHAW' else 'MINI' end;

-- A driver may not pick or change their own category (that is the admin's review):
-- only the RPCs below write it.
revoke insert, update on public.vehicles from authenticated;
grant insert (driver_id, vehicle_type, make, model, color, plate_number, seats, year, is_active)
  on public.vehicles to authenticated;
grant update (vehicle_type, make, model, color, plate_number, seats, year, is_active)
  on public.vehicles to authenticated;

alter table public.ride_requests
  add column category text not null default 'MINI' references public.ride_categories(code);

-- ─────────────────────────────────────────────────────────────────────────────
-- Drivers report where they are while online
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.drivers
  add column last_lat double precision,
  add column last_lng double precision,
  add column last_location_at timestamptz;

create or replace function public.update_driver_location(p_lat float8, p_lng float8)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    return;
  end if;
  update drivers set last_lat = p_lat, last_lng = p_lng, last_location_at = now() where id = v_uid;
end;
$$;
revoke all on function public.update_driver_location(float8, float8) from public;
grant execute on function public.update_driver_location(float8, float8) to authenticated;

-- "Driver search radius around pickup": 4 km, edit in the admin Settings page. 0 = no limit.
update public.settings set value = '4', description = 'Only drivers within this many km of the pickup get the request (0 = everyone)'
 where key = 'search_radius_km';

-- ─────────────────────────────────────────────────────────────────────────────
-- Matching helpers
-- ─────────────────────────────────────────────────────────────────────────────
-- Is the driver close enough to the pickup? (straight line × 1.3 road factor.)
-- A driver whose location is unknown or older than 10 minutes is not filtered out.
create or replace function public.driver_in_range(p_driver uuid, p_lat float8, p_lng float8)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    setting_num('search_radius_km', 4) <= 0
    or p_lat is null or p_lng is null
    or d.last_lat is null or d.last_lng is null
    or d.last_location_at is null or d.last_location_at < now() - interval '10 minutes'
    or haversine_km(d.last_lat, d.last_lng, p_lat, p_lng) * 1.3 <= setting_num('search_radius_km', 4),
    false)
  from drivers d where d.id = p_driver;
$$;

-- Can the calling driver act on this request? Approved, online, active, has a
-- vehicle of the request's category, and is near the pickup.
create or replace function public.driver_sees_request(
  p_category text,
  p_pickup_lat float8,
  p_pickup_lng float8,
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
        and exists (select 1 from vehicles v
                    where v.driver_id = d.id and v.is_active and v.category = p_category)
        and driver_in_range(d.id, p_pickup_lat, p_pickup_lng)
    );
$$;

drop policy if exists ride_requests_read on public.ride_requests;
create policy ride_requests_read on public.ride_requests for select to authenticated
  using (
    passenger_id = auth.uid()
    or public.is_admin()
    or public.driver_sees_request(category, pickup_lat, pickup_lng, status, expires_at)
    or public.i_offered_on(id)
  );

-- Fare guardrail for a category (falls back to the global range if the code is unknown).
create or replace function public.assert_fare_for_category(p_distance numeric, p_fare numeric, p_category text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_lo numeric;
  v_hi numeric;
  v_min numeric;
  v_max numeric;
begin
  select min_fare_per_km, max_fare_per_km into v_lo, v_hi from ride_categories where code = p_category;
  v_lo := coalesce(v_lo, setting_num('min_fare_per_km', 20));
  v_hi := coalesce(v_hi, setting_num('max_fare_per_km', 100));
  v_min := ceil(p_distance * v_lo);
  v_max := floor(p_distance * v_hi);
  if p_fare is null or p_fare < v_min or p_fare > v_max then
    raise exception 'Fare must be between Rs. % and Rs. % for this trip', v_min::bigint, v_max::bigint
      using errcode = '22023';
  end if;
end;
$$;
revoke all on function public.assert_fare_for_category(numeric, numeric, text) from public;
revoke all on function public.driver_in_range(uuid, float8, float8) from public;

-- ─────────────────────────────────────────────────────────────────────────────
-- Passenger creates a request (category + two map pins)
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text);

create or replace function public.create_ride_request_geo(
  p_pickup_lat float8,
  p_pickup_lng float8,
  p_dropoff_lat float8,
  p_dropoff_lng float8,
  p_passenger_count int,
  p_offered_fare numeric,
  p_pickup_label text default null,
  p_dropoff_label text default null,
  p_notes text default null,
  p_category text default 'MINI'
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
  v_cat ride_categories;
  v_max_km numeric := setting_num('max_service_km', 40);
  v_dist numeric;
  v_route_id uuid;
  v_req ride_requests;
  v_driver record;
  v_label text;
begin
  select * into v_cat from ride_categories where code = coalesce(p_category, 'MINI') and is_active;
  if not found then
    raise exception 'This ride type is not available' using errcode = '22023';
  end if;

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
     or p_passenger_count > least(setting_num('max_passengers', 6), v_cat.max_passengers) then
    raise exception 'Passengers must be between 1 and %', least(setting_num('max_passengers', 6), v_cat.max_passengers)::int
      using errcode = '22023';
  end if;

  perform assert_fare_for_category(v_dist, p_offered_fare, v_cat.code);

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
    passenger_count, offered_fare, distance_km, status, expires_at, notes, category
  ) values (
    v_uid, v_route_id, v_o.id, v_d.id,
    coalesce(nullif(btrim(p_pickup_label), ''), 'Map pin'), p_pickup_lat, p_pickup_lng,
    coalesce(nullif(btrim(p_dropoff_label), ''), 'Map pin'), p_dropoff_lat, p_dropoff_lng,
    p_passenger_count, round(p_offered_fare), v_dist, 'SEARCHING',
    now() + make_interval(mins => setting_num('request_expiry_minutes', 15)::int),
    nullif(btrim(p_notes), ''), v_cat.code
  )
  returning * into v_req;

  perform log_status(v_req.id, null, null, 'REQUESTED', 'PASSENGER');
  perform log_status(v_req.id, null, 'REQUESTED', 'SEARCHING', 'SYSTEM');

  v_label := v_cat.name || ' · ' || route_label(v_route_id);
  perform notify(v_uid, 'REQUEST_SENT', 'Request sent',
    v_label || ' · ' || fmt_rs(v_req.offered_fare) || ' · finding drivers',
    jsonb_build_object('request_id', v_req.id));

  -- Tell the drivers who can take it: right category, near the pickup.
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
      and exists (select 1 from vehicles v where v.driver_id = d.id and v.is_active and v.category = v_cat.code)
      and driver_in_range(d.id, p_pickup_lat, p_pickup_lng)
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

revoke all on function public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text) from public;
grant execute on function public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Driver offers: category vehicle, category fare range, new visibility rule
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

  -- The driver's current position is the most useful thing we know: keep it fresh.
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Driver feed: only matching requests, nearest first, with the category
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists public.get_driver_feed();
create or replace function public.get_driver_feed()
returns table (
  request_id uuid, route_id uuid, origin_city_id uuid, destination_city_id uuid,
  origin_name text, destination_name text, pickup_label text, dropoff_label text,
  passenger_first_name text, passenger_rating numeric, passenger_count int,
  offered_fare numeric, distance_km numeric, created_at timestamptz, expires_at timestamptz,
  my_offer_id uuid, my_offer_type offer_type, my_offer_fare numeric, is_return boolean,
  category text, pickup_km numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.route_id, r.origin_city_id, r.destination_city_id, o.name, d.name,
         r.pickup_label, r.dropoff_label,
         split_part(coalesce(p.full_name, 'Passenger'), ' ', 1), pa.rating_avg, r.passenger_count,
         r.offered_fare, r.distance_km, r.created_at, r.expires_at,
         mo.id, mo.offer_type, mo.fare,
         exists (
           select 1 from rides x
           where x.driver_id = auth.uid() and x.status = 'COMPLETED'
             and x.destination_city_id = r.origin_city_id
             and x.completed_at > now() - interval '3 hours'
         ),
         r.category,
         case when me.last_lat is null or r.pickup_lat is null then null
              else round((haversine_km(me.last_lat, me.last_lng, r.pickup_lat, r.pickup_lng) * 1.3)::numeric, 1) end
  from ride_requests r
  join cities o on o.id = r.origin_city_id
  join cities d on d.id = r.destination_city_id
  join profiles p on p.id = r.passenger_id
  left join passengers pa on pa.id = r.passenger_id
  left join drivers me on me.id = auth.uid()
  left join ride_offers mo on mo.request_id = r.id and mo.driver_id = auth.uid() and mo.status = 'PENDING'
  where driver_sees_request(r.category, r.pickup_lat, r.pickup_lng, r.status, r.expires_at)
    and r.passenger_id <> auth.uid()
    and not exists (select 1 from request_dismissals x where x.driver_id = auth.uid() and x.request_id = r.id)
  order by 21 nulls last, r.created_at desc
  limit 50;
$$;
revoke all on function public.get_driver_feed() from public;
grant execute on function public.get_driver_feed() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Driver registration: the driver picks a category; routes are no longer needed
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists public.save_driver_application(text, uuid, public.vehicle_type, text, text, text, text, int, int, uuid[], uuid[]);

create or replace function public.save_driver_application(
  p_cnic text,
  p_city_id uuid,
  p_vehicle_type public.vehicle_type,
  p_vehicle_make text,
  p_vehicle_model text,
  p_vehicle_color text,
  p_plate_number text,
  p_seats int,
  p_vehicle_year int,
  p_route_ids uuid[] default '{}',
  p_service_area_ids uuid[] default '{}',
  p_category text default null
)
returns public.drivers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_driver drivers;
  v_cnic text := regexp_replace(coalesce(p_cnic, ''), '[^0-9]', '', 'g');
  v_plate text := upper(btrim(coalesce(p_plate_number, '')));
  v_cat ride_categories;
  v_type public.vehicle_type := p_vehicle_type;
begin
  select * into v_driver from drivers where id = v_uid for update;
  if not found then
    raise exception 'Choose "I drive" during sign-up first' using errcode = '42501';
  end if;
  if v_driver.status not in ('PENDING', 'REJECTED') then
    raise exception 'Your application is already %', lower(v_driver.status::text) using errcode = '22023';
  end if;
  if char_length(v_cnic) <> 13 then
    raise exception 'CNIC must have 13 digits' using errcode = '22023';
  end if;
  if not exists (select 1 from cities where id = p_city_id and is_active) then
    raise exception 'Please choose an active city' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_vehicle_model, ''))) < 2 or char_length(v_plate) < 3 then
    raise exception 'Vehicle model and number plate are required' using errcode = '22023';
  end if;
  if p_seats is null or p_seats not between 1 and 20 then
    raise exception 'Seats must be 1–20' using errcode = '22023';
  end if;
  if exists (select 1 from vehicles where plate_number = v_plate and driver_id <> v_uid) then
    raise exception 'This number plate is already registered' using errcode = '23505';
  end if;

  -- The category decides the vehicle type; without one, derive it from the type.
  select * into v_cat from ride_categories
   where code = coalesce(p_category, case v_type
       when 'MOTORCYCLE' then 'BIKE' when 'RICKSHAW' then 'RICKSHAW' else 'MINI' end)
     and is_active;
  if not found then
    raise exception 'Choose a ride type for your vehicle' using errcode = '22023';
  end if;
  v_type := v_cat.vehicle_type;

  update drivers set
    cnic_number = substr(v_cnic, 1, 5) || '-' || substr(v_cnic, 6, 7) || '-' || substr(v_cnic, 13, 1),
    current_city_id = p_city_id,
    status = 'PENDING',
    rejection_reason = null
  where id = v_uid
  returning * into v_driver;

  insert into vehicles (driver_id, vehicle_type, category, make, model, color, plate_number, seats, year)
  values (v_uid, v_type, v_cat.code, nullif(btrim(p_vehicle_make), ''), btrim(p_vehicle_model),
          nullif(btrim(p_vehicle_color), ''), v_plate, p_seats, p_vehicle_year)
  on conflict (plate_number) do update set
    vehicle_type = excluded.vehicle_type, category = excluded.category, make = excluded.make,
    model = excluded.model, color = excluded.color, seats = excluded.seats, year = excluded.year,
    is_active = true;
  update vehicles set is_active = false where driver_id = v_uid and plate_number <> v_plate;

  -- Preferred routes are optional now (matching is by category and distance).
  delete from driver_routes where driver_id = v_uid;
  if coalesce(array_length(p_route_ids, 1), 0) > 0 then
    insert into driver_routes (driver_id, route_id)
    select v_uid, r.id from routes r where r.id = any(p_route_ids) and r.is_active;
  end if;

  delete from driver_service_areas where driver_id = v_uid;
  insert into driver_service_areas (driver_id, service_area_id)
  select v_uid, s.id from service_areas s where s.id = any(coalesce(p_service_area_ids, '{}')) and s.is_active;

  return v_driver;
end;
$$;
revoke all on function public.save_driver_application(text, uuid, public.vehicle_type, text, text, text, text, int, int, uuid[], uuid[], text) from public;
grant execute on function public.save_driver_application(text, uuid, public.vehicle_type, text, text, text, text, int, int, uuid[], uuid[], text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Driver dashboard now also reports the vehicle's category
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_driver_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_driver drivers;
  v_tz text := 'Asia/Karachi';
  v_today timestamptz := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
begin
  select * into v_driver from drivers where id = v_uid;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'status', v_driver.status,
    'is_online', v_driver.is_online,
    'rejection_reason', v_driver.rejection_reason,
    'city_id', v_driver.current_city_id,
    'city_name', (select name from cities where id = v_driver.current_city_id),
    'rating', v_driver.rating_avg,
    'rating_count', v_driver.rating_count,
    'total_rides', v_driver.total_rides,
    'cnic', v_driver.cnic_number,
    'vehicle', (select jsonb_build_object('type', vehicle_type, 'category', category, 'make', make, 'model', model,
                                          'color', color, 'plate', plate_number, 'seats', seats, 'year', year)
                from vehicles where driver_id = v_uid and is_active order by created_at limit 1),
    'route_ids', coalesce((select jsonb_agg(route_id) from driver_routes where driver_id = v_uid), '[]'::jsonb),
    'documents', coalesce((select jsonb_agg(jsonb_build_object('type', doc_type, 'status', status))
                           from driver_documents where driver_id = v_uid), '[]'::jsonb),
    'earnings', jsonb_build_object(
      'today', coalesce((select sum(c.driver_earning) from commissions c
                         where c.driver_id = v_uid and c.created_at >= v_today), 0),
      'week',  coalesce((select sum(c.driver_earning) from commissions c
                         where c.driver_id = v_uid and c.created_at >= v_today - interval '6 days'), 0),
      'month', coalesce((select sum(c.driver_earning) from commissions c
                         where c.driver_id = v_uid and c.created_at >= v_today - interval '29 days'), 0),
      'rides_today', (select count(*) from commissions c where c.driver_id = v_uid and c.created_at >= v_today),
      'commission_due', coalesce((select balance_after from driver_ledger where driver_id = v_uid
                                  order by id desc limit 1), 0)
    ),
    'adda', (select jsonb_build_object('online_drivers', a.online_drivers, 'open_requests', a.open_requests)
             from get_adda_summary() a where a.city_id = v_driver.current_city_id),
    'recent_ratings', coalesce((select jsonb_agg(x) from (
        select r.stars, r.comment, r.created_at from ratings r
        where r.ratee_id = v_uid and r.ride_id in (select id from rides where driver_id = v_uid)
        order by r.created_at desc limit 5) x), '[]'::jsonb)
  );
end;
$$;
