-- The fare engine and city + category dispatch.
--
--  * fare_calc(): the one formula. The Dart FareService (lib/features/rides/domain/fare_service.dart)
--    does the same arithmetic so the apps can show a quote instantly; this is the authority.
--  * A request goes ONLY to drivers whose category is the ride's category AND whose city is the
--    ride's city (the active city nearest to the pickup) AND who are online, approved and free.

-- ─────────────────────────────────────────────────────────────────────────────
-- Fare engine
-- ─────────────────────────────────────────────────────────────────────────────
-- Linear interpolation of [[km, profit], ...]; past the last point it keeps the slope of the last two.
create or replace function public.fare_profit(p_points jsonb, p_d float8)
returns float8
language plpgsql
immutable
as $$
declare
  v_sorted jsonb;
  n int;
  i int;
  x0 float8; y0 float8; x1 float8; y1 float8;
begin
  select coalesce(jsonb_agg(e order by (e->>0)::float8), '[]'::jsonb) into v_sorted
    from jsonb_array_elements(p_points) e;
  n := jsonb_array_length(v_sorted);
  if n = 0 then
    return 0;
  elsif n = 1 then
    return (v_sorted->0->>1)::float8;
  end if;
  for i in 0 .. n - 2 loop
    x0 := (v_sorted->i->>0)::float8;       y0 := (v_sorted->i->>1)::float8;
    x1 := (v_sorted->(i + 1)->>0)::float8; y1 := (v_sorted->(i + 1)->>1)::float8;
    if p_d <= x1 or i = n - 2 then
      if x1 = x0 then
        return y0;
      end if;
      return y0 + (y1 - y0) * (p_d - x0) / (x1 - x0);
    end if;
  end loop;
  return 0;
end;
$$;

-- Is this moment inside the night window (Pakistan time)?
create or replace function public.is_night_time(p_at timestamptz default now())
returns boolean
language plpgsql
stable
as $$
declare
  h numeric := extract(hour from (p_at at time zone 'Asia/Karachi'));
  s numeric := setting_num('night_start_hour', 23);
  e numeric := setting_num('night_end_hour', 6);
begin
  if s > e then
    return h >= s or h < e;
  end if;
  return h >= s and h < e;
end;
$$;

-- Recommended fare, the offer band, commission and what the driver gets.
--   cost   = cityKm x (petrol/city_mileage + city_maint)
--          + outKm  x (petrol/highway_mileage + highway_maint) x (1 + return_factor)
--   fare   = max((cost + profit) / (1 - commission), min_fare), x night surcharge at night
--   recommended = round10(fare) + loading charge (if chosen) + toll
create or replace function public.fare_calc(
  p_distance float8,
  p_category text,
  p_night boolean default false,
  p_loading boolean default false,
  p_toll float8 default 0
)
returns table (recommended numeric, min_offer numeric, max_offer numeric, commission numeric, driver_gets numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c ride_categories;
  v_petrol float8 := setting_num('petrol_price', 400)::float8;
  v_slab float8 := setting_num('slab_km', 8)::float8;
  v_return float8 := setting_num('return_factor', 0.5)::float8;
  v_comm float8 := setting_num('commission_percent', 10)::float8;
  v_min_pct float8 := setting_num('min_offer_percent', 85)::float8;
  v_max_pct float8 := setting_num('max_offer_percent', 200)::float8;
  v_night float8 := setting_num('night_surcharge_percent', 20)::float8;
  v_city_km float8;
  v_out_km float8;
  v_cost float8;
  v_profit float8;
  v_fare float8;
  v_rec float8;
begin
  select * into c from ride_categories where code = p_category;
  if not found then
    raise exception 'Unknown ride type' using errcode = '22023';
  end if;
  v_city_km := least(p_distance, v_slab);
  v_out_km := greatest(p_distance - v_slab, 0);
  v_cost := v_city_km * (v_petrol / c.city_mileage::float8 + c.city_maint::float8)
          + v_out_km * (v_petrol / c.highway_mileage::float8 + c.highway_maint::float8) * (1 + v_return);
  v_profit := fare_profit(c.profit_points, p_distance);
  v_fare := greatest((v_cost + v_profit) / (1 - v_comm / 100), c.min_fare::float8);
  if p_night then
    v_fare := v_fare * (1 + v_night / 100);
  end if;
  v_rec := floor(v_fare / 10 + 0.5) * 10
         + case when p_loading then c.loading_charge::float8 else 0 end
         + coalesce(p_toll, 0);
  recommended := v_rec;
  min_offer := floor(v_rec * v_min_pct / 100 / 10 + 0.5) * 10;
  max_offer := floor(v_rec * v_max_pct / 100);
  commission := floor(v_rec * v_comm / 100 + 0.5);
  driver_gets := v_rec - commission;
  return next;
end;
$$;
revoke all on function public.fare_calc(float8, text, boolean, boolean, float8) from public;
grant execute on function public.fare_calc(float8, text, boolean, boolean, float8) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Dispatch: who can see / act on a request
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists ride_requests_read on public.ride_requests;

create or replace function public.driver_sees_request(
  p_category text,
  p_city_id uuid,
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
        and d.city_id is not null
        and d.city_id = p_city_id
        and exists (select 1 from vehicles v
                    where v.driver_id = d.id and v.is_active and v.category = p_category)
    )
    and not has_active_ride(auth.uid());
$$;

create policy ride_requests_read on public.ride_requests for select to authenticated
  using (
    passenger_id = auth.uid()
    or public.is_admin()
    or public.driver_sees_request(category, city_id, status, expires_at)
    or public.i_offered_on(id)
  );

drop function if exists public.driver_sees_request(text, float8, float8, public.ride_status, timestamptz);

-- Tell every matching driver at once.
create or replace function public.dispatch_request(p_request_id uuid, p_title text, p_body text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r ride_requests;
  v_driver record;
  v_count int := 0;
begin
  select * into r from ride_requests where id = p_request_id;
  if not found then
    return 0;
  end if;
  for v_driver in
    select d.id,
           exists (
             select 1 from rides x
             where x.driver_id = d.id and x.status = 'COMPLETED'
               and x.destination_city_id = r.origin_city_id
               and x.completed_at > now() - interval '3 hours'
           ) as is_return
    from drivers d
    join profiles p on p.id = d.id
    where d.status = 'APPROVED' and d.is_online and p.account_status = 'ACTIVE'
      and d.city_id = r.city_id
      and d.id <> r.passenger_id
      and exists (select 1 from vehicles v where v.driver_id = d.id and v.is_active and v.category = r.category)
      and not has_active_ride(d.id)
  loop
    perform notify(
      v_driver.id,
      case when v_driver.is_return then 'RETURN_RIDE' else 'NEW_REQUEST' end,
      case when v_driver.is_return then 'Return ride opportunity' else p_title end,
      p_body,
      jsonb_build_object('request_id', r.id));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.dispatch_request(uuid, text, text) from public;

-- ─────────────────────────────────────────────────────────────────────────────
-- Passenger creates a request
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text);

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
  p_category text default 'car_mini',
  p_loading boolean default false,
  p_toll numeric default 0
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
  v_city cities;
  v_cat ride_categories;
  v_dist numeric;
  v_route_id uuid;
  v_req ride_requests;
  v_q record;
  v_night boolean := is_night_time(now());
  v_label text;
begin
  select * into v_cat from ride_categories where code = coalesce(p_category, 'car_mini') and is_active;
  if not found then
    raise exception 'This ride type is not available' using errcode = '22023';
  end if;

  if p_pickup_lat is null or p_pickup_lng is null or p_dropoff_lat is null or p_dropoff_lng is null
     or p_pickup_lat not between -90 and 90 or p_dropoff_lat not between -90 and 90
     or p_pickup_lng not between -180 and 180 or p_dropoff_lng not between -180 and 180 then
    raise exception 'Choose a pickup and a destination on the map' using errcode = '22023';
  end if;

  -- The ride city is the active city nearest to the PICKUP; the pickup must be inside its radius.
  select * into v_o from nearest_city(p_pickup_lat, p_pickup_lng);
  if v_o.id is null then
    raise exception 'Service is not available here yet' using errcode = '22023';
  end if;
  select * into v_city from cities where id = v_o.id;
  if v_o.km > v_city.service_radius_km then
    raise exception 'Service is not available here yet' using errcode = '22023';
  end if;
  -- The destination may be anywhere (city-to-city rides); we only need the nearest town for the route.
  select * into v_d from nearest_city(p_dropoff_lat, p_dropoff_lng);

  if haversine_km(p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng) < 0.3 then
    raise exception 'Pickup and destination are the same place' using errcode = '22023';
  end if;
  -- Straight line x 1.3 road factor, one decimal. The app uses the same rule.
  v_dist := greatest(1, round((haversine_km(p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng) * 1.3)::numeric, 1));

  if v_cat.max_km is not null and v_dist > v_cat.max_km then
    raise exception '% is available for trips up to % km', v_cat.name, v_cat.max_km::int using errcode = '22023';
  end if;

  if p_passenger_count is null or p_passenger_count < 1 or p_passenger_count > v_cat.max_passengers then
    raise exception 'Passengers must be between 1 and %', v_cat.max_passengers using errcode = '22023';
  end if;

  select * into v_q from fare_calc(v_dist::float8, v_cat.code, v_night,
                                   coalesce(p_loading, false) and v_cat.loading_charge > 0, coalesce(p_toll, 0)::float8);
  if p_offered_fare is null or p_offered_fare < v_q.min_offer or p_offered_fare > v_q.max_offer then
    raise exception 'Fare must be between Rs. % and Rs. % for this trip', v_q.min_offer::bigint, v_q.max_offer::bigint
      using errcode = '22023';
  end if;

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
    passenger_id, route_id, origin_city_id, destination_city_id, city_id,
    pickup_label, pickup_lat, pickup_lng, dropoff_label, dropoff_lat, dropoff_lng,
    passenger_count, offered_fare, distance_km, status, expires_at, notes, category,
    recommended_fare, min_offer_fare, max_offer_fare, is_night, loading_selected, toll_amount
  ) values (
    v_uid, v_route_id, v_o.id, v_d.id, v_o.id,
    coalesce(nullif(btrim(p_pickup_label), ''), 'Map pin'), p_pickup_lat, p_pickup_lng,
    coalesce(nullif(btrim(p_dropoff_label), ''), 'Map pin'), p_dropoff_lat, p_dropoff_lng,
    p_passenger_count, round(p_offered_fare), v_dist, 'SEARCHING',
    now() + make_interval(mins => setting_num('request_expiry_minutes', 15)::int),
    nullif(btrim(p_notes), ''), v_cat.code,
    v_q.recommended, v_q.min_offer, v_q.max_offer, v_night,
    coalesce(p_loading, false) and v_cat.loading_charge > 0, coalesce(p_toll, 0)
  )
  returning * into v_req;

  perform log_status(v_req.id, null, null, 'REQUESTED', 'PASSENGER');
  perform log_status(v_req.id, null, 'REQUESTED', 'SEARCHING', 'SYSTEM');

  v_label := v_cat.name || ' · ' || coalesce(nullif(btrim(p_pickup_label), ''), v_city.name)
             || ' → ' || coalesce(nullif(btrim(p_dropoff_label), ''), v_d.name);
  perform notify(v_uid, 'REQUEST_SENT', 'Request sent',
    v_label || ' · ' || fmt_rs(v_req.offered_fare) || ' · finding drivers',
    jsonb_build_object('request_id', v_req.id));

  perform dispatch_request(v_req.id, 'New ride request',
    v_label || ' · ' || v_req.passenger_count || ' passenger(s) · offer ' || fmt_rs(v_req.offered_fare));
  return v_req;
end;
$$;
revoke all on function public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text, boolean, numeric) from public;
grant execute on function public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text, boolean, numeric) to authenticated;

-- Passenger raises the fare while nobody has taken it ("raise your offer or try again").
create or replace function public.raise_request_fare(p_request_id uuid, p_new_fare numeric)
returns public.ride_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_req ride_requests;
begin
  select * into v_req from ride_requests where id = p_request_id for update;
  if not found or v_req.passenger_id <> v_uid then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  if v_req.status not in ('SEARCHING', 'OFFER_RECEIVED') or v_req.expires_at <= now() then
    raise exception 'This request is no longer open' using errcode = '22023';
  end if;
  if p_new_fare is null or p_new_fare <= v_req.offered_fare then
    raise exception 'Offer more than Rs. %', v_req.offered_fare::bigint using errcode = '22023';
  end if;
  if v_req.min_offer_fare is not null
     and (p_new_fare < v_req.min_offer_fare or p_new_fare > v_req.max_offer_fare) then
    raise exception 'Fare must be between Rs. % and Rs. % for this trip',
      v_req.min_offer_fare::bigint, v_req.max_offer_fare::bigint using errcode = '22023';
  end if;

  update ride_requests
     set offered_fare = round(p_new_fare),
         expires_at = greatest(expires_at, now() + make_interval(mins => setting_num('request_expiry_minutes', 15)::int)),
         nudged_at = null
   where id = p_request_id
  returning * into v_req;

  perform dispatch_request(v_req.id, 'Fare raised',
    'The passenger now offers ' || fmt_rs(v_req.offered_fare) || ' · ' || coalesce(v_req.pickup_label, '') || ' → ' || coalesce(v_req.dropoff_label, ''));
  return v_req;
end;
$$;
revoke all on function public.raise_request_fare(uuid, numeric) from public;
grant execute on function public.raise_request_fare(uuid, numeric) to authenticated;

-- "No driver yet": tell the passenger to raise the fare or try again.
create or replace function public.nudge_unanswered_requests()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req record;
  v_count int := 0;
begin
  for v_req in
    select id, passenger_id from ride_requests
     where status = 'SEARCHING' and nudged_at is null and expires_at > now()
       and created_at <= now() - make_interval(mins => setting_num('no_driver_notify_minutes', 3)::int)
       and not exists (select 1 from ride_offers o where o.request_id = ride_requests.id and o.status = 'PENDING')
  loop
    update ride_requests set nudged_at = now() where id = v_req.id;
    perform notify(v_req.passenger_id, 'NO_DRIVER_YET', 'No driver yet',
      'Raise your offer a little, or try again.', jsonb_build_object('request_id', v_req.id));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.nudge_unanswered_requests() from public;

do $$
begin
  perform cron.schedule('kamgo-nudge-requests', '* * * * *', 'select public.nudge_unanswered_requests()');
exception when others then
  raise notice 'pg_cron not available (%); call public.nudge_unanswered_requests() from a scheduler instead', sqlerrm;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Driver offers: new visibility rule, the request's own offer band
-- ─────────────────────────────────────────────────────────────────────────────
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
     or not driver_sees_request(v_req.category, v_req.city_id, v_req.status, v_req.expires_at)
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
    if v_req.min_offer_fare is not null then
      if v_fare < v_req.min_offer_fare or v_fare > v_req.max_offer_fare then
        raise exception 'Fare must be between Rs. % and Rs. % for this trip',
          v_req.min_offer_fare::bigint, v_req.max_offer_fare::bigint using errcode = '22023';
      end if;
    else
      perform assert_fare_allowed(v_req.route_id, v_fare);
    end if;
    if v_fare = v_req.offered_fare then
      v_type := 'ACCEPT';
    end if;
  end if;

  if p_driver_lat is not null and p_driver_lng is not null
     and v_req.pickup_lat is not null and v_req.pickup_lng is not null then
    v_dist := haversine_km(p_driver_lat, p_driver_lng, v_req.pickup_lat, v_req.pickup_lng) * 1.3;
  end if;
  v_eta := coalesce(p_eta_min, case when v_dist is not null then greatest(2, ceil(v_dist / 30.0 * 60)::int) end);

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
-- Driver feed: matching requests with the money split
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists public.get_driver_feed();
create or replace function public.get_driver_feed()
returns table (
  request_id uuid, route_id uuid, origin_city_id uuid, destination_city_id uuid,
  origin_name text, destination_name text, pickup_label text, dropoff_label text,
  passenger_first_name text, passenger_rating numeric, passenger_count int,
  offered_fare numeric, distance_km numeric, created_at timestamptz, expires_at timestamptz,
  my_offer_id uuid, my_offer_type offer_type, my_offer_fare numeric, is_return boolean,
  category text, pickup_km numeric,
  recommended_fare numeric, min_offer numeric, max_offer numeric,
  commission numeric, driver_gets numeric, is_night boolean, loading_selected boolean
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
              else round((haversine_km(me.last_lat, me.last_lng, r.pickup_lat, r.pickup_lng) * 1.3)::numeric, 1) end,
         r.recommended_fare, r.min_offer_fare, r.max_offer_fare,
         floor(r.offered_fare * setting_num('commission_percent', 10) / 100 + 0.5),
         r.offered_fare - floor(r.offered_fare * setting_num('commission_percent', 10) / 100 + 0.5),
         r.is_night, r.loading_selected
  from ride_requests r
  join cities o on o.id = r.origin_city_id
  join cities d on d.id = r.destination_city_id
  join profiles p on p.id = r.passenger_id
  left join passengers pa on pa.id = r.passenger_id
  left join drivers me on me.id = auth.uid()
  left join ride_offers mo on mo.request_id = r.id and mo.driver_id = auth.uid() and mo.status = 'PENDING'
  where driver_sees_request(r.category, r.city_id, r.status, r.expires_at)
    and r.passenger_id <> auth.uid()
    and not exists (select 1 from request_dismissals x where x.driver_id = auth.uid() and x.request_id = r.id)
  order by 21 nulls last, r.created_at desc
  limit 50;
$$;
revoke all on function public.get_driver_feed() from public;
grant execute on function public.get_driver_feed() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Waiting at the pickup, charged when the ride is completed
-- ─────────────────────────────────────────────────────────────────────────────
-- The driver taps "I've arrived"; the waiting clock runs until the ride starts.
create or replace function public.driver_arrived(p_ride_id uuid)
returns public.rides
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_ride rides;
begin
  select * into v_ride from rides where id = p_ride_id for update;
  if not found or v_ride.driver_id <> v_uid then
    raise exception 'Ride not found' using errcode = 'P0002';
  end if;
  if v_ride.status not in ('CONFIRMED', 'DRIVER_ARRIVING') then
    raise exception 'The ride has already started' using errcode = '22023';
  end if;
  if v_ride.arrived_at is null then
    update rides set arrived_at = now() where id = p_ride_id returning * into v_ride;
    perform notify(v_ride.passenger_id, 'DRIVER_ARRIVED', 'Your driver has arrived',
      'Waiting is free for ' || setting_num('waiting_free_minutes', 5)::int || ' minutes.',
      jsonb_build_object('ride_id', p_ride_id));
  end if;
  return v_ride;
end;
$$;
revoke all on function public.driver_arrived(uuid) from public;
grant execute on function public.driver_arrived(uuid) to authenticated;

-- Commission and earnings are computed here and nowhere else. The final fare is the accepted
-- fare plus the waiting charge (free minutes first, then the category's rate per minute).
create or replace function public.complete_ride(p_ride_id uuid)
returns public.commissions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_ride rides;
  v_pct numeric := setting_num('commission_percent', 10);
  v_commission numeric;
  v_row commissions;
  v_balance numeric;
  v_wait_min int := 0;
  v_wait_charge numeric := 0;
  v_per_min numeric;
begin
  select * into v_ride from rides where id = p_ride_id for update;
  if not found or v_ride.driver_id <> v_uid then
    raise exception 'Ride not found' using errcode = 'P0002';
  end if;
  if not can_transition(v_ride.status, 'COMPLETED', 'DRIVER') then
    raise exception 'Only a started ride can be completed' using errcode = '22023';
  end if;

  if v_ride.arrived_at is not null and v_ride.started_at is not null and v_ride.started_at > v_ride.arrived_at then
    v_wait_min := floor(extract(epoch from (v_ride.started_at - v_ride.arrived_at)) / 60)::int;
    select waiting_per_min into v_per_min from ride_categories where code = v_ride.category;
    v_wait_charge := greatest(0, v_wait_min - setting_num('waiting_free_minutes', 5)::int) * coalesce(v_per_min, 0);
  end if;

  update rides set
    status = 'COMPLETED', completed_at = now(),
    waiting_minutes = v_wait_min, waiting_charge = v_wait_charge,
    final_fare = final_fare + v_wait_charge
  where id = p_ride_id
  returning * into v_ride;
  perform log_status(v_ride.request_id, p_ride_id, 'RIDE_STARTED', 'COMPLETED', 'DRIVER');

  v_commission := round(v_ride.final_fare * v_pct / 100, 2);
  insert into commissions (ride_id, driver_id, final_fare, commission_percent, commission_amount, driver_earning)
  values (p_ride_id, v_ride.driver_id, v_ride.final_fare, v_pct, v_commission, v_ride.final_fare - v_commission)
  returning * into v_row;

  -- Serialise ledger writes per driver.
  perform 1 from drivers where id = v_ride.driver_id for update;
  select coalesce((select balance_after from driver_ledger where driver_id = v_ride.driver_id
                   order by id desc limit 1), 0) + v_commission
    into v_balance;
  insert into driver_ledger (driver_id, ride_id, commission_id, entry_type, amount, balance_after, note)
  values (v_ride.driver_id, p_ride_id, v_row.id, 'COMMISSION_DUE', v_commission, v_balance,
          'Commission on ' || route_label(v_ride.route_id));

  update drivers set total_rides = total_rides + 1, current_city_id = v_ride.destination_city_id
   where id = v_ride.driver_id;
  update passengers set total_rides = total_rides + 1 where id = v_ride.passenger_id;

  perform notify(v_ride.passenger_id, 'RIDE_COMPLETED', 'Ride completed',
    route_label(v_ride.route_id) || ' · ' || fmt_rs(v_ride.final_fare) || ' · please rate your driver',
    jsonb_build_object('ride_id', p_ride_id));
  perform notify(v_ride.driver_id, 'RIDE_COMPLETED', 'Ride completed',
    'You earned ' || fmt_rs(v_row.driver_earning) || ' · KAM GO commission ' || fmt_rs(v_commission),
    jsonb_build_object('ride_id', p_ride_id));

  return v_row;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ride details: also the money breakdown
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
    'accepted_fare', r.accepted_fare,
    'recommended_fare', r.recommended_fare,
    'category', r.category,
    'category_name', k.name,
    'is_night', r.is_night,
    'arrived_at', r.arrived_at,
    'waiting_minutes', r.waiting_minutes,
    'waiting_charge', r.waiting_charge,
    'passenger_count', r.passenger_count,
    'confirmed_at', r.confirmed_at,
    'started_at', r.started_at,
    'completed_at', r.completed_at,
    'route_id', r.route_id,
    'distance_km', coalesce(q.distance_km, rt.distance_km),
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
  left join ride_categories k on k.code = r.category
  where r.id = p_ride_id;
  return v;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Driver registration: city + vehicle model (+ AC). The model decides the category.
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists public.save_driver_application(text, uuid, public.vehicle_type, text, text, text, text, int, int, uuid[], uuid[], text);

create or replace function public.save_driver_application(
  p_cnic text,
  p_city_id uuid,
  p_vehicle_make text,
  p_vehicle_model text,
  p_vehicle_color text,
  p_plate_number text,
  p_seats int,
  p_vehicle_year int,
  p_ac_available boolean default false
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
  v_model vehicle_models;
  v_cat ride_categories;
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
  if p_city_id is null or not exists (select 1 from cities where id = p_city_id and is_active) then
    raise exception 'Please choose your city' using errcode = '22023';
  end if;
  if char_length(v_plate) < 3 then
    raise exception 'Number plate is required' using errcode = '22023';
  end if;
  if p_seats is null or p_seats not between 1 and 20 then
    raise exception 'Seats must be 1–20' using errcode = '22023';
  end if;
  if exists (select 1 from vehicles where plate_number = v_plate and driver_id <> v_uid) then
    raise exception 'This number plate is already registered' using errcode = '23505';
  end if;

  select * into v_model from vehicle_models
   where is_active and lower(btrim(make)) = lower(btrim(coalesce(p_vehicle_make, '')))
     and lower(btrim(model)) = lower(btrim(coalesce(p_vehicle_model, '')));
  if not found then
    raise exception 'Choose your vehicle from the list' using errcode = '22023';
  end if;
  select * into v_cat from ride_categories where code = v_model.category and is_active;
  if not found then
    raise exception 'This vehicle type is not available right now' using errcode = '22023';
  end if;

  update drivers set
    cnic_number = substr(v_cnic, 1, 5) || '-' || substr(v_cnic, 6, 7) || '-' || substr(v_cnic, 13, 1),
    city_id = p_city_id,
    current_city_id = p_city_id,
    status = 'PENDING',
    rejection_reason = null
  where id = v_uid
  returning * into v_driver;

  insert into vehicles (driver_id, vehicle_type, category, make, model, color, plate_number, seats, year, ac_available)
  values (v_uid, v_cat.vehicle_type, v_cat.code, v_model.make, v_model.model,
          nullif(btrim(p_vehicle_color), ''), v_plate, p_seats, p_vehicle_year,
          coalesce(p_ac_available, false) and v_cat.is_car)
  on conflict (plate_number) do update set
    vehicle_type = excluded.vehicle_type, category = excluded.category, make = excluded.make,
    model = excluded.model, color = excluded.color, seats = excluded.seats, year = excluded.year,
    ac_available = excluded.ac_available, is_active = true;
  update vehicles set is_active = false where driver_id = v_uid and plate_number <> v_plate;

  return v_driver;
end;
$$;
revoke all on function public.save_driver_application(text, uuid, text, text, text, text, int, int, boolean) from public;
grant execute on function public.save_driver_application(text, uuid, text, text, text, text, int, int, boolean) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Admin: change a driver's city / category, list drivers with both, fare report
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.admin_set_driver_city(p_driver_id uuid, p_city_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform require_admin();
  if not exists (select 1 from cities where id = p_city_id and is_active) then
    raise exception 'Choose an active city' using errcode = '22023';
  end if;
  update drivers set city_id = p_city_id, current_city_id = p_city_id where id = p_driver_id;
  if not found then
    raise exception 'Driver not found' using errcode = 'P0002';
  end if;
  update ride_offers set status = 'WITHDRAWN' where driver_id = p_driver_id and status = 'PENDING';
end;
$$;

create or replace function public.admin_set_driver_category(p_driver_id uuid, p_category text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cat ride_categories;
begin
  perform require_admin();
  select * into v_cat from ride_categories where code = p_category and is_active;
  if not found then
    raise exception 'Choose an active ride type' using errcode = '22023';
  end if;
  update vehicles set category = v_cat.code, vehicle_type = v_cat.vehicle_type
   where driver_id = p_driver_id and is_active;
  if not found then
    raise exception 'The driver has no vehicle on file' using errcode = '22023';
  end if;
  update ride_offers set status = 'WITHDRAWN' where driver_id = p_driver_id and status = 'PENDING';
end;
$$;
revoke all on function public.admin_set_driver_city(uuid, uuid) from public;
revoke all on function public.admin_set_driver_category(uuid, text) from public;
grant execute on function public.admin_set_driver_city(uuid, uuid) to authenticated;
grant execute on function public.admin_set_driver_category(uuid, text) to authenticated;

drop function if exists public.admin_list_drivers(public.driver_status);
create or replace function public.admin_list_drivers(p_status public.driver_status default null)
returns table (
  driver_id uuid, full_name text, phone text, status driver_status, account_status account_status,
  is_online boolean, city_name text, cnic text, rating numeric, total_rides int,
  vehicle text, plate text, commission_due numeric, document_count int, created_at timestamptz,
  rejection_reason text, city_id uuid, category text, category_name text, ac_available boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform require_admin();
  return query
  select d.id, p.full_name, '+' || p.phone, d.status, p.account_status, d.is_online, c.name, d.cnic_number,
         d.rating_avg, d.total_rides,
         (select trim(coalesce(v.make, '') || ' ' || v.model)
            from vehicles v where v.driver_id = d.id and v.is_active limit 1),
         (select v.plate_number from vehicles v where v.driver_id = d.id and v.is_active limit 1),
         coalesce((select l.balance_after from driver_ledger l where l.driver_id = d.id order by l.id desc limit 1), 0),
         (select count(*)::int from driver_documents x where x.driver_id = d.id),
         d.created_at, d.rejection_reason, d.city_id,
         (select v.category from vehicles v where v.driver_id = d.id and v.is_active limit 1),
         (select k.name from vehicles v join ride_categories k on k.code = v.category
           where v.driver_id = d.id and v.is_active limit 1),
         (select v.ac_available from vehicles v where v.driver_id = d.id and v.is_active limit 1)
  from drivers d
  join profiles p on p.id = d.id
  left join cities c on c.id = d.city_id
  where p_status is null or d.status = p_status
  order by (d.status = 'PENDING') desc, d.created_at desc;
end;
$$;
revoke all on function public.admin_list_drivers(public.driver_status) from public;
grant execute on function public.admin_list_drivers(public.driver_status) to authenticated;

-- Average accepted fare vs the recommended fare, per city and category.
create or replace function public.admin_fare_report(p_from date default null, p_to date default null)
returns table (
  city_name text, category text, category_name text, rides bigint,
  avg_recommended numeric, avg_accepted numeric, accepted_vs_recommended_pct numeric,
  total_commission numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform require_admin();
  return query
  select c.name, r.category, k.name, count(*),
         round(avg(r.recommended_fare), 0), round(avg(r.accepted_fare), 0),
         round(100 * avg(r.accepted_fare) / nullif(avg(r.recommended_fare), 0), 1),
         coalesce(sum(cm.commission_amount), 0)
  from rides r
  join cities c on c.id = r.city_id
  join ride_categories k on k.code = r.category
  left join commissions cm on cm.ride_id = r.id
  where r.status = 'COMPLETED' and r.recommended_fare is not null
    and (p_from is null or r.completed_at >= p_from)
    and (p_to is null or r.completed_at < p_to + 1)
  group by c.name, r.category, k.name, k.sort_order
  order by c.name, k.sort_order;
end;
$$;
revoke all on function public.admin_fare_report(date, date) from public;
grant execute on function public.admin_fare_report(date, date) to authenticated;
