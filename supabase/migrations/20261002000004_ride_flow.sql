-- KAM GO — ride marketplace logic (Phases 2 & 3).
-- Every money / status change happens here, inside SECURITY DEFINER
-- functions that check who is calling. The app only ever calls these RPCs.

-- ─────────────────────────────────────────────────────────────────────────────
-- Drivers can hide a request they don't want ("Reject").
-- ─────────────────────────────────────────────────────────────────────────────
create table public.request_dismissals (
  driver_id   uuid not null references public.drivers(id) on delete cascade,
  request_id  uuid not null references public.ride_requests(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (driver_id, request_id)
);
alter table public.request_dismissals enable row level security;
grant select on public.request_dismissals to authenticated;
create policy request_dismissals_read on public.request_dismissals for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());

-- Requests a driver dismissed no longer match them.
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
        and d.current_city_id = p_origin_city_id
        and (
          not exists (select 1 from driver_routes dr where dr.driver_id = d.id)
          or exists (
            select 1 from driver_routes dr
            where dr.driver_id = d.id and dr.route_id = p_route_id
          )
        )
    );
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Small helpers
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.haversine_km(lat1 float8, lng1 float8, lat2 float8, lng2 float8)
returns float8
language sql
immutable
as $$
  select 2 * 6371 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

create or replace function public.notify(
  p_user_id uuid, p_type text, p_title text, p_body text, p_data jsonb default '{}'::jsonb
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into notifications (user_id, type, title, body, data)
  values (p_user_id, p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb));
$$;

create or replace function public.log_status(
  p_request_id uuid, p_ride_id uuid,
  p_from public.ride_status, p_to public.ride_status,
  p_actor public.ride_actor, p_note text default null
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into ride_status_log (request_id, ride_id, from_status, to_status, actor, changed_by, note)
  values (p_request_id, p_ride_id, p_from, p_to, p_actor, auth.uid(), p_note);
$$;

create or replace function public.fmt_rs(p numeric)
returns text
language sql
immutable
as $$ select 'Rs. ' || to_char(round(p), 'FM999,999,990'); $$;

create or replace function public.route_label(p_route_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select o.name || ' → ' || d.name
  from routes r join cities o on o.id = r.origin_city_id join cities d on d.id = r.destination_city_id
  where r.id = p_route_id;
$$;

create or replace function public.has_active_ride(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from rides
    where p_user_id in (passenger_id, driver_id)
      and status in ('DRIVER_SELECTED', 'CONFIRMED', 'DRIVER_ARRIVING', 'RIDE_STARTED')
  );
$$;

create or replace function public.require_active_account()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if exists (select 1 from profiles where id = v_uid and account_status = 'SUSPENDED') then
    raise exception 'This account is suspended' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 2 — passenger creates a request
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.create_ride_request(
  p_route_id uuid,
  p_passenger_count int,
  p_offered_fare numeric,
  p_pickup_label text default null,
  p_pickup_lat float8 default null,
  p_pickup_lng float8 default null,
  p_dropoff_label text default null,
  p_dropoff_lat float8 default null,
  p_dropoff_lng float8 default null,
  p_notes text default null
)
returns public.ride_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_route record;
  v_req ride_requests;
  v_driver record;
  v_label text;
begin
  select r.*, o.lat as o_lat, o.lng as o_lng, d.lat as d_lat, d.lng as d_lng
    into v_route
    from routes r
    join cities o on o.id = r.origin_city_id and o.is_active
    join cities d on d.id = r.destination_city_id and d.is_active
   where r.id = p_route_id and r.is_active;
  if not found then
    raise exception 'This route is not available' using errcode = '22023';
  end if;

  if p_passenger_count is null
     or p_passenger_count < 1
     or p_passenger_count > setting_num('max_passengers', 6) then
    raise exception 'Passengers must be between 1 and %', setting_num('max_passengers', 6)::int
      using errcode = '22023';
  end if;

  perform assert_fare_allowed(p_route_id, p_offered_fare);

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

  insert into ride_requests (
    passenger_id, route_id, origin_city_id, destination_city_id,
    pickup_label, pickup_lat, pickup_lng, dropoff_label, dropoff_lat, dropoff_lng,
    passenger_count, offered_fare, distance_km, status, expires_at, notes
  ) values (
    v_uid, p_route_id, v_route.origin_city_id, v_route.destination_city_id,
    nullif(btrim(p_pickup_label), ''), coalesce(p_pickup_lat, v_route.o_lat), coalesce(p_pickup_lng, v_route.o_lng),
    nullif(btrim(p_dropoff_label), ''), coalesce(p_dropoff_lat, v_route.d_lat), coalesce(p_dropoff_lng, v_route.d_lng),
    p_passenger_count, round(p_offered_fare), v_route.distance_km, 'SEARCHING',
    now() + make_interval(mins => setting_num('request_expiry_minutes', 15)::int),
    nullif(btrim(p_notes), '')
  )
  returning * into v_req;

  perform log_status(v_req.id, null, null, 'REQUESTED', 'PASSENGER');
  perform log_status(v_req.id, null, 'REQUESTED', 'SEARCHING', 'SYSTEM');

  v_label := route_label(p_route_id);
  perform notify(v_uid, 'REQUEST_SENT', 'Request sent',
    v_label || ' · ' || fmt_rs(v_req.offered_fare) || ' · finding drivers',
    jsonb_build_object('request_id', v_req.id));

  -- Tell matching drivers: approved, online, active, same city, route match.
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
      and d.current_city_id = v_req.origin_city_id
      and d.id <> v_uid
      and (
        not exists (select 1 from driver_routes dr where dr.driver_id = d.id)
        or exists (select 1 from driver_routes dr where dr.driver_id = d.id and dr.route_id = v_req.route_id)
      )
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

-- Passenger cancels a request that is still collecting offers.
create or replace function public.cancel_request(p_request_id uuid)
returns public.ride_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_req ride_requests;
  v_offer record;
begin
  select * into v_req from ride_requests where id = p_request_id for update;
  if not found or v_req.passenger_id <> v_uid then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  if v_req.status not in ('REQUESTED', 'SEARCHING', 'OFFER_RECEIVED') then
    raise exception 'This request can no longer be cancelled' using errcode = '22023';
  end if;

  for v_offer in
    update ride_offers set status = 'UNAVAILABLE'
    where request_id = p_request_id and status = 'PENDING'
    returning driver_id
  loop
    perform notify(v_offer.driver_id, 'REQUEST_CANCELLED', 'Request cancelled',
      'The passenger cancelled ' || route_label(v_req.route_id) || '.',
      jsonb_build_object('request_id', p_request_id));
  end loop;

  update ride_requests set status = 'CANCELLED' where id = p_request_id returning * into v_req;
  insert into cancellations (request_id, cancelled_by, reason) values (p_request_id, v_uid, 'PASSENGER_CANCELLED');
  perform log_status(p_request_id, null, v_req.status, 'CANCELLED', 'PASSENGER');
  return v_req;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 2 — driver accepts or counters
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
    perform assert_fare_allowed(v_req.route_id, v_fare);
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

-- Driver hides a request (and withdraws any offer on it).
create or replace function public.dismiss_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
begin
  if not exists (select 1 from drivers where id = v_uid) then
    raise exception 'Drivers only' using errcode = '42501';
  end if;
  insert into request_dismissals (driver_id, request_id) values (v_uid, p_request_id)
  on conflict do nothing;
  update ride_offers set status = 'WITHDRAWN'
   where request_id = p_request_id and driver_id = v_uid and status = 'PENDING';
end;
$$;

-- Passenger turns down one offer.
create or replace function public.reject_offer(p_offer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_offer ride_offers;
begin
  select o.* into v_offer from ride_offers o
    join ride_requests r on r.id = o.request_id
   where o.id = p_offer_id and r.passenger_id = v_uid
   for update of o;
  if not found then
    raise exception 'Offer not found' using errcode = 'P0002';
  end if;
  if v_offer.status = 'PENDING' then
    update ride_offers set status = 'REJECTED' where id = p_offer_id;
    perform notify(v_offer.driver_id, 'OFFER_REJECTED', 'Offer not chosen',
      'The passenger chose not to take your offer of ' || fmt_rs(v_offer.fare) || '.',
      jsonb_build_object('request_id', v_offer.request_id));
  end if;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 3 — passenger selects a driver. Row locks guarantee exactly one wins.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.select_offer(p_offer_id uuid)
returns public.rides
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
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
  if v_req.passenger_id <> v_uid then
    raise exception 'Offer not found' using errcode = 'P0002';
  end if;
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
    perform notify(v_other.driver_id, 'OFFER_UNAVAILABLE', 'Passenger chose another driver',
      route_label(v_req.route_id), jsonb_build_object('request_id', v_request_id));
  end loop;

  update ride_requests set status = 'DRIVER_SELECTED', selected_offer_id = p_offer_id where id = v_request_id;
  perform log_status(v_request_id, null, 'OFFER_RECEIVED', 'DRIVER_SELECTED', 'PASSENGER');

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
  perform notify(v_uid, 'RIDE_CONFIRMED', 'Ride confirmed',
    (select full_name from profiles where id = v_offer.driver_id) || ' is your driver · ' || fmt_rs(v_offer.fare),
    jsonb_build_object('ride_id', v_ride.id));

  return v_ride;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 3 — ride lifecycle
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.ride_actor_for(v_ride public.rides)
returns public.ride_actor
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.uid() = v_ride.driver_id then 'DRIVER'::ride_actor
    when auth.uid() = v_ride.passenger_id then 'PASSENGER'::ride_actor
    when is_admin() then 'ADMIN'::ride_actor
  end;
$$;

create or replace function public.update_ride_status(p_ride_id uuid, p_new_status public.ride_status)
returns public.rides
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_ride rides;
  v_actor ride_actor;
  v_from ride_status;
begin
  if p_new_status in ('COMPLETED', 'CANCELLED', 'NO_SHOW') then
    raise exception 'Use complete_ride / cancel_ride for this change' using errcode = '22023';
  end if;

  select * into v_ride from rides where id = p_ride_id for update;
  if not found then
    raise exception 'Ride not found' using errcode = 'P0002';
  end if;
  v_actor := ride_actor_for(v_ride);
  if v_actor is null then
    raise exception 'Ride not found' using errcode = 'P0002';
  end if;
  v_from := v_ride.status;
  if not can_transition(v_from, p_new_status, v_actor) then
    raise exception 'Cannot change ride from % to %', v_from, p_new_status using errcode = '22023';
  end if;

  update rides set
    status = p_new_status,
    arriving_at = case when p_new_status = 'DRIVER_ARRIVING' then now() else arriving_at end,
    started_at = case when p_new_status = 'RIDE_STARTED' then now() else started_at end
  where id = p_ride_id
  returning * into v_ride;

  perform log_status(v_ride.request_id, p_ride_id, v_from, p_new_status, v_actor);

  if p_new_status = 'DRIVER_ARRIVING' then
    perform notify(v_ride.passenger_id, 'DRIVER_ARRIVING', 'Your driver is on the way',
      route_label(v_ride.route_id), jsonb_build_object('ride_id', p_ride_id));
  elsif p_new_status = 'RIDE_STARTED' then
    perform notify(v_ride.passenger_id, 'RIDE_STARTED', 'Ride started',
      route_label(v_ride.route_id) || ' · have a safe trip', jsonb_build_object('ride_id', p_ride_id));
  end if;
  return v_ride;
end;
$$;

-- Driver completes a started ride. Commission and earnings are computed
-- here and nowhere else.
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
begin
  select * into v_ride from rides where id = p_ride_id for update;
  if not found or v_ride.driver_id <> v_uid then
    raise exception 'Ride not found' using errcode = 'P0002';
  end if;
  if not can_transition(v_ride.status, 'COMPLETED', 'DRIVER') then
    raise exception 'Only a started ride can be completed' using errcode = '22023';
  end if;

  v_commission := round(v_ride.final_fare * v_pct / 100, 2);

  update rides set status = 'COMPLETED', completed_at = now() where id = p_ride_id;
  perform log_status(v_ride.request_id, p_ride_id, v_ride.status, 'COMPLETED', 'DRIVER');

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

  -- The driver is now in the destination city: return-ride matching uses this.
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

create or replace function public.cancel_ride(
  p_ride_id uuid,
  p_reason public.cancellation_reason,
  p_note text default null
)
returns public.rides
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_ride rides;
  v_actor ride_actor;
  v_to ride_status;
  v_from ride_status;
  v_fee numeric := 0;
  v_other uuid;
begin
  select * into v_ride from rides where id = p_ride_id for update;
  if not found then
    raise exception 'Ride not found' using errcode = 'P0002';
  end if;
  v_actor := ride_actor_for(v_ride);
  if v_actor is null then
    raise exception 'Ride not found' using errcode = 'P0002';
  end if;

  -- Each reason belongs to one kind of caller.
  if not (
       (p_reason = 'PASSENGER_CANCELLED' and v_actor = 'PASSENGER')
    or (p_reason = 'DRIVER_CANCELLED'    and v_actor = 'DRIVER')
    or (p_reason = 'DRIVER_NO_SHOW'      and v_actor = 'PASSENGER')
    or (p_reason = 'PASSENGER_NO_SHOW'   and v_actor = 'DRIVER')
    or (p_reason = 'ADMIN_CANCELLED'     and v_actor = 'ADMIN')
  ) then
    raise exception 'That reason cannot be used here' using errcode = '22023';
  end if;

  v_to := case when p_reason in ('DRIVER_NO_SHOW', 'PASSENGER_NO_SHOW') then 'NO_SHOW' else 'CANCELLED' end;
  if not can_transition(v_ride.status, v_to, v_actor) then
    raise exception 'This ride can no longer be cancelled' using errcode = '22023';
  end if;

  if v_actor = 'PASSENGER' and p_reason = 'PASSENGER_CANCELLED'
     and setting_bool('cancellation_fee_enabled', false)
     and v_ride.status = 'DRIVER_ARRIVING' then
    v_fee := setting_num('cancellation_fee_amount', 0);
  end if;

  v_from := v_ride.status;
  update rides set status = v_to, cancelled_at = now() where id = p_ride_id returning * into v_ride;
  insert into cancellations (ride_id, request_id, cancelled_by, reason, note, fee_amount)
  values (p_ride_id, v_ride.request_id, v_uid, p_reason, nullif(btrim(p_note), ''), v_fee);
  perform log_status(v_ride.request_id, p_ride_id, v_from, v_to, v_actor, p_reason::text);

  foreach v_other in array array[v_ride.passenger_id, v_ride.driver_id] loop
    if v_other <> v_uid then
      perform notify(v_other, 'RIDE_CANCELLED', 'Ride cancelled',
        route_label(v_ride.route_id) || ' was cancelled.', jsonb_build_object('ride_id', p_ride_id));
    end if;
  end loop;
  return v_ride;
end;
$$;

create or replace function public.rate_ride(p_ride_id uuid, p_stars int, p_comment text default null)
returns public.ratings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_ride rides;
  v_ratee uuid;
  v_row ratings;
begin
  select * into v_ride from rides where id = p_ride_id;
  if not found or v_uid not in (v_ride.passenger_id, v_ride.driver_id) then
    raise exception 'Ride not found' using errcode = 'P0002';
  end if;
  if v_ride.status <> 'COMPLETED' then
    raise exception 'You can rate a ride once it is completed' using errcode = '22023';
  end if;
  if p_stars is null or p_stars not between 1 and 5 then
    raise exception 'Rating must be 1 to 5 stars' using errcode = '22023';
  end if;

  v_ratee := case when v_uid = v_ride.passenger_id then v_ride.driver_id else v_ride.passenger_id end;
  insert into ratings (ride_id, rater_id, ratee_id, stars, comment)
  values (p_ride_id, v_uid, v_ratee, p_stars, nullif(btrim(p_comment), ''))
  on conflict (ride_id, rater_id) do update set stars = excluded.stars, comment = excluded.comment
  returning * into v_row;

  if v_ratee = v_ride.driver_id then
    update drivers set
      rating_avg = (select round(avg(stars), 2) from ratings where ratee_id = v_ratee and rater_id <> v_ratee
                    and ride_id in (select id from rides where driver_id = v_ratee)),
      rating_count = (select count(*) from ratings where ratee_id = v_ratee
                    and ride_id in (select id from rides where driver_id = v_ratee))
    where id = v_ratee;
  else
    update passengers set
      rating_avg = (select round(avg(stars), 2) from ratings where ratee_id = v_ratee
                    and ride_id in (select id from rides where passenger_id = v_ratee)),
      rating_count = (select count(*) from ratings where ratee_id = v_ratee
                    and ride_id in (select id from rides where passenger_id = v_ratee))
    where id = v_ratee;
  end if;
  return v_row;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Read models for the app (one round-trip per screen)
-- ─────────────────────────────────────────────────────────────────────────────

-- Offers on the caller's request, with driver + vehicle details.
create or replace function public.get_request_offers(p_request_id uuid)
returns table (
  offer_id uuid, driver_id uuid, driver_name text, rating numeric, rating_count int,
  vehicle text, vehicle_type vehicle_type, plate text, offer_type offer_type, fare numeric,
  status offer_status, eta_min int, distance_km numeric, expires_at timestamptz, created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select o.id, o.driver_id, p.full_name, d.rating_avg, d.rating_count,
         trim(coalesce(v.make, '') || ' ' || v.model), v.vehicle_type, v.plate_number,
         o.offer_type, o.fare, o.status, o.eta_min, o.distance_to_pickup_km, o.expires_at, o.created_at
  from ride_offers o
  join ride_requests r on r.id = o.request_id
  join drivers d on d.id = o.driver_id
  join profiles p on p.id = o.driver_id
  left join vehicles v on v.id = o.vehicle_id
  where o.request_id = p_request_id
    and (r.passenger_id = auth.uid() or is_admin())
  order by (o.offer_type = 'ACCEPT') desc, o.fare, o.created_at;
$$;

-- Open requests the calling driver can act on, with their own offer if any.
create or replace function public.get_driver_feed()
returns table (
  request_id uuid, route_id uuid, origin_city_id uuid, destination_city_id uuid,
  origin_name text, destination_name text, pickup_label text, dropoff_label text,
  passenger_first_name text, passenger_rating numeric, passenger_count int,
  offered_fare numeric, distance_km numeric, created_at timestamptz, expires_at timestamptz,
  my_offer_id uuid, my_offer_type offer_type, my_offer_fare numeric, is_return boolean
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
         )
  from ride_requests r
  join cities o on o.id = r.origin_city_id
  join cities d on d.id = r.destination_city_id
  join profiles p on p.id = r.passenger_id
  left join passengers pa on pa.id = r.passenger_id
  left join ride_offers mo on mo.request_id = r.id and mo.driver_id = auth.uid() and mo.status = 'PENDING'
  where driver_can_see_request(r.origin_city_id, r.route_id, r.status, r.expires_at)
    and r.passenger_id <> auth.uid()
    and not exists (select 1 from request_dismissals x where x.driver_id = auth.uid() and x.request_id = r.id)
  order by r.created_at desc
  limit 50;
$$;

-- Everything both parties need on the ride screens. Phone numbers are
-- shared only while the ride is active.
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

-- The caller's current request or ride, so the app can resume after restart.
create or replace function public.get_my_active()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'ride_id', (select id from rides
                where auth.uid() in (passenger_id, driver_id)
                  and status in ('CONFIRMED', 'DRIVER_ARRIVING', 'RIDE_STARTED')
                order by created_at desc limit 1),
    'request_id', (select id from ride_requests
                   where passenger_id = auth.uid()
                     and status in ('REQUESTED', 'SEARCHING', 'OFFER_RECEIVED')
                     and expires_at > now()
                   order by created_at desc limit 1),
    'unrated_ride_id', (select r.id from rides r
                        where r.passenger_id = auth.uid() and r.status = 'COMPLETED'
                          and r.completed_at > now() - interval '1 day'
                          and not exists (select 1 from ratings x where x.ride_id = r.id and x.rater_id = auth.uid())
                        order by r.completed_at desc limit 1)
  );
$$;

-- Ride history for either role, paginated.
create or replace function public.get_my_rides(p_limit int default 20, p_offset int default 0)
returns table (
  ride_id uuid, origin_name text, destination_name text, final_fare numeric, status ride_status,
  created_at timestamptz, completed_at timestamptz, other_name text, my_role text,
  driver_earning numeric, commission_amount numeric, my_rating int
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, o.name, d.name, r.final_fare, r.status, r.created_at, r.completed_at,
         case when r.passenger_id = auth.uid() then dp.full_name else pp.full_name end,
         case when r.passenger_id = auth.uid() then 'PASSENGER' else 'DRIVER' end,
         case when r.driver_id = auth.uid() then c.driver_earning end,
         case when r.driver_id = auth.uid() then c.commission_amount end,
         (select stars from ratings x where x.ride_id = r.id and x.rater_id = auth.uid())
  from rides r
  join cities o on o.id = r.origin_city_id
  join cities d on d.id = r.destination_city_id
  join profiles dp on dp.id = r.driver_id
  join profiles pp on pp.id = r.passenger_id
  left join commissions c on c.ride_id = r.id
  where auth.uid() in (r.passenger_id, r.driver_id)
  order by r.created_at desc
  limit least(greatest(p_limit, 1), 50) offset greatest(p_offset, 0);
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Expiry job: stale requests and offers
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.expire_stale()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
  v_req record;
begin
  update ride_offers set status = 'EXPIRED'
   where status = 'PENDING' and expires_at <= now();

  for v_req in
    update ride_requests set status = 'EXPIRED'
     where status in ('REQUESTED', 'SEARCHING', 'OFFER_RECEIVED') and expires_at <= now()
    returning id, passenger_id, route_id
  loop
    v_count := v_count + 1;
    insert into ride_status_log (request_id, to_status, actor, note)
    values (v_req.id, 'EXPIRED', 'SYSTEM', 'No driver selected in time');
    update ride_offers set status = 'EXPIRED' where request_id = v_req.id and status = 'PENDING';
    insert into notifications (user_id, type, title, body, data)
    values (v_req.passenger_id, 'REQUEST_EXPIRED', 'Request expired',
            route_label(v_req.route_id) || ' · try again or raise your offer',
            jsonb_build_object('request_id', v_req.id));
  end loop;
  return v_count;
end;
$$;

-- Run it every minute when pg_cron is available (it is on Supabase).
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('kamgo-expire-stale', '* * * * *', 'select public.expire_stale()');
exception when others then
  raise notice 'pg_cron not available (%); call public.expire_stale() from a scheduler instead', sqlerrm;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Permissions
-- ─────────────────────────────────────────────────────────────────────────────
revoke execute on all functions in schema public from public, anon;

grant execute on function
  public.create_ride_request(uuid, int, numeric, text, float8, float8, text, float8, float8, text),
  public.cancel_request(uuid),
  public.submit_offer(uuid, public.offer_type, numeric, float8, float8),
  public.dismiss_request(uuid),
  public.reject_offer(uuid),
  public.select_offer(uuid),
  public.update_ride_status(uuid, public.ride_status),
  public.complete_ride(uuid),
  public.cancel_ride(uuid, public.cancellation_reason, text),
  public.rate_ride(uuid, int, text),
  public.get_request_offers(uuid),
  public.get_driver_feed(),
  public.get_ride_details(uuid),
  public.get_my_active(),
  public.get_my_rides(int, int),
  public.driver_can_see_request(uuid, uuid, public.ride_status, timestamptz),
  public.haversine_km(float8, float8, float8, float8)
to authenticated;

-- Re-grant the Phase 1 helpers revoked by the blanket statement above.
grant execute on function
  public.is_admin(), public.is_my_request(uuid), public.i_offered_on(uuid), public.is_ride_party(uuid),
  public.shares_ride_with(uuid), public.setting_num(text, numeric), public.setting_bool(text, boolean),
  public.fare_bounds(uuid), public.can_transition(public.ride_status, public.ride_status, public.ride_actor),
  public.complete_profile(text, public.user_role, uuid), public.get_adda_summary(), public.get_popular_route(uuid)
to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.ride_locations;
  end if;
end;
$$;
