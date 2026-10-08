-- Booking types: one way, hourly rental, round trip. Scheduled bookings.
--
-- Everything that is a number here is a row the admin panel edits: the hourly packages, the
-- per-category hour profit / extra-km / extra-hour rates, and the settings below. The fare
-- arithmetic exists once in SQL (this file) and once in Dart (FareService); both are covered
-- by tests that use the same worked examples.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Settings and per-category rates
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.settings (key, value, description) values
  ('round_trip_cost_factor',       '2',   'Round trip: the one-way running cost counts this many times (there and back)'),
  ('round_trip_profit_factor',     '1.5', 'Round trip: the one-way profit for the distance is multiplied by this'),
  ('round_trip_free_wait_minutes', '30',  'Round trip: free waiting at the destination before the hourly waiting charge starts'),
  ('scheduled_reminder_minutes',   '30',  'Remind driver and passenger this many minutes before a scheduled booking'),
  ('scheduled_buffer_minutes',     '30',  'Gap kept around a driver''s accepted scheduled booking (no overlapping offers)')
on conflict (key) do nothing;

alter table public.ride_categories
  add column hour_profit numeric(8,2) not null default 0,
  add column extra_km_rate numeric(8,2) not null default 0,
  add column extra_hour_rate numeric(8,2) not null default 0;

update public.ride_categories set hour_profit = 500, extra_km_rate = 60, extra_hour_rate = 560 where code = 'car_mini';
update public.ride_categories set hour_profit = 600, extra_km_rate = 70, extra_hour_rate = 670 where code = 'car_comfort';
update public.ride_categories set hour_profit = 700, extra_km_rate = 80, extra_hour_rate = 780 where code = 'car_xl';

grant update (hour_profit, extra_km_rate, extra_hour_rate) on public.ride_categories to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Hourly packages (admin-managed)
-- ─────────────────────────────────────────────────────────────────────────────
create table public.hourly_packages (
  id                uuid primary key default gen_random_uuid(),
  hours             int not null check (hours between 1 and 48),
  included_km       numeric(7,1) not null check (included_km > 0),
  profit_multiplier numeric(5,2) not null check (profit_multiplier > 0),
  sort_order        int not null default 0,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
insert into public.hourly_packages (hours, included_km, profit_multiplier, sort_order) values
  (2,  20,  1.1, 1),
  (4,  40,  1.0, 2),
  (8,  80,  0.9, 3),
  (12, 120, 0.8, 4);

alter table public.hourly_packages enable row level security;
grant select, insert, update, delete on public.hourly_packages to authenticated;
create policy hourly_packages_read on public.hourly_packages for select to authenticated
  using (is_active or public.is_admin());
create policy hourly_packages_admin_insert on public.hourly_packages for insert to authenticated
  with check (public.is_admin());
create policy hourly_packages_admin_update on public.hourly_packages for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy hourly_packages_admin_delete on public.hourly_packages for delete to authenticated
  using (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) What a request and a ride remember about the booking type
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.ride_requests
  add column booking_type text not null default 'one_way'
    check (booking_type in ('one_way', 'hourly', 'round_trip')),
  add column package_id uuid references public.hourly_packages(id) on delete set null,
  add column package_hours int,
  add column package_km numeric(7,1),
  add column expected_wait_min int not null default 0 check (expected_wait_min >= 0),
  add column expected_wait_charge numeric(10,2) not null default 0,
  add column scheduled_at timestamptz;

alter table public.rides
  add column booking_type text not null default 'one_way',
  add column package_hours int,
  add column package_km numeric(7,1),
  add column expected_wait_min int not null default 0,
  add column expected_wait_charge numeric(10,2) not null default 0,
  add column scheduled_at timestamptz,
  add column reminder_sent_at timestamptz,
  add column actual_km numeric(8,1) not null default 0,
  add column actual_minutes int,
  add column extra_km numeric(8,1) not null default 0,
  add column extra_km_charge numeric(10,2) not null default 0,
  add column extra_hours int not null default 0,
  add column extra_hour_charge numeric(10,2) not null default 0,
  add column dest_arrived_at timestamptz,
  add column return_started_at timestamptz,
  add column dest_waiting_minutes int not null default 0,
  add column dest_waiting_charge numeric(10,2) not null default 0,
  add column commission_amount numeric(10,2),
  add column driver_gets numeric(10,2);

-- Backfill from the commission rows that already exist.
update public.rides r set commission_amount = c.commission_amount, driver_gets = c.driver_earning
  from public.commissions c where c.ride_id = r.id;

create index ride_requests_scheduled_idx on public.ride_requests(scheduled_at) where scheduled_at is not null;
create index rides_scheduled_idx on public.rides(scheduled_at) where scheduled_at is not null;

create or replace function public.rides_copy_request_info()
returns trigger
language plpgsql
as $$
declare
  q ride_requests;
begin
  select * into q from ride_requests where id = new.request_id;
  if found then
    new.city_id := coalesce(new.city_id, q.city_id, q.origin_city_id);
    new.category := coalesce(new.category, q.category);
    new.recommended_fare := coalesce(new.recommended_fare, q.recommended_fare);
    new.is_night := q.is_night;
    new.booking_type := q.booking_type;
    new.package_hours := q.package_hours;
    new.package_km := q.package_km;
    new.expected_wait_min := q.expected_wait_min;
    new.expected_wait_charge := q.expected_wait_charge;
    new.scheduled_at := q.scheduled_at;
  end if;
  new.accepted_fare := coalesce(new.accepted_fare, new.final_fare);
  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) Fare functions
-- ─────────────────────────────────────────────────────────────────────────────
-- Hourly:  round10((included_km x city_cost_per_km + hours x hour_profit x multiplier) / (1 - commission))
--          city_cost_per_km = petrol / city_mileage + city_maint
create or replace function public.fare_calc_hourly(p_category text, p_package_id uuid)
returns table (recommended numeric, min_offer numeric, max_offer numeric, commission numeric, driver_gets numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c ride_categories;
  k hourly_packages;
  v_petrol float8 := setting_num('petrol_price', 400)::float8;
  v_comm float8 := setting_num('commission_percent', 10)::float8;
  v_min_pct float8 := setting_num('min_offer_percent', 85)::float8;
  v_max_pct float8 := setting_num('max_offer_percent', 200)::float8;
  v_raw float8;
  v_rec float8;
begin
  select * into c from ride_categories where code = p_category;
  if not found or not c.is_car or c.hour_profit <= 0 then
    raise exception 'Hourly booking is available for cars only' using errcode = '22023';
  end if;
  select * into k from hourly_packages where id = p_package_id and is_active;
  if not found then
    raise exception 'Choose an hourly package' using errcode = '22023';
  end if;
  v_raw := (k.included_km::float8 * (v_petrol / c.city_mileage::float8 + c.city_maint::float8)
            + k.hours::float8 * c.hour_profit::float8 * k.profit_multiplier::float8) / (1 - v_comm / 100);
  v_rec := floor(v_raw / 10 + 0.5) * 10;
  recommended := v_rec;
  min_offer := floor(v_rec * v_min_pct / 100 / 10 + 0.5) * 10;
  max_offer := floor(v_rec * v_max_pct / 100);
  commission := floor(v_rec * v_comm / 100 + 0.5);
  driver_gets := v_rec - commission;
  return next;
end;
$$;
revoke all on function public.fare_calc_hourly(text, uuid) from public;
grant execute on function public.fare_calc_hourly(text, uuid) to authenticated;

-- Waiting at the round-trip destination: free minutes first, then the category's rate per STARTED hour.
create or replace function public.round_trip_wait_charge(p_category text, p_minutes int)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select ceil(greatest(0, coalesce(p_minutes, 0) - setting_num('round_trip_free_wait_minutes', 30)) / 60.0)
         * coalesce((select round_trip_wait_per_hour from ride_categories where code = p_category), 0);
$$;
revoke all on function public.round_trip_wait_charge(text, int) from public;
grant execute on function public.round_trip_wait_charge(text, int) to authenticated;

-- Round trip for a ONE-WAY distance d:
--   round10((2 x one_way_cost_without_return + 1.5 x profit(d)) / (1 - commission)) + expected waiting charge
create or replace function public.fare_calc_round_trip(p_distance float8, p_category text, p_expected_wait_min int default 0)
returns table (recommended numeric, min_offer numeric, max_offer numeric, commission numeric, driver_gets numeric, wait_charge numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c ride_categories;
  v_petrol float8 := setting_num('petrol_price', 400)::float8;
  v_slab float8 := setting_num('slab_km', 8)::float8;
  v_comm float8 := setting_num('commission_percent', 10)::float8;
  v_min_pct float8 := setting_num('min_offer_percent', 85)::float8;
  v_max_pct float8 := setting_num('max_offer_percent', 200)::float8;
  v_cost_f float8 := setting_num('round_trip_cost_factor', 2)::float8;
  v_profit_f float8 := setting_num('round_trip_profit_factor', 1.5)::float8;
  v_cost float8;
  v_raw float8;
  v_base float8;
  v_rec float8;
begin
  select * into c from ride_categories where code = p_category;
  if not found or not c.is_car then
    raise exception 'Round trip is available for cars only' using errcode = '22023';
  end if;
  v_cost := least(p_distance, v_slab) * (v_petrol / c.city_mileage::float8 + c.city_maint::float8)
          + greatest(p_distance - v_slab, 0) * (v_petrol / c.highway_mileage::float8 + c.highway_maint::float8);
  v_raw := (v_cost_f * v_cost + v_profit_f * fare_profit(c.profit_points, p_distance)) / (1 - v_comm / 100);
  v_base := greatest(floor(v_raw / 10 + 0.5) * 10, c.min_fare::float8);
  wait_charge := round_trip_wait_charge(p_category, p_expected_wait_min);
  v_rec := v_base + wait_charge;
  recommended := v_rec;
  min_offer := floor(v_rec * v_min_pct / 100 / 10 + 0.5) * 10;
  max_offer := floor(v_rec * v_max_pct / 100);
  commission := floor(v_rec * v_comm / 100 + 0.5);
  driver_gets := v_rec - commission;
  return next;
end;
$$;
revoke all on function public.fare_calc_round_trip(float8, text, int) from public;
grant execute on function public.fare_calc_round_trip(float8, text, int) to authenticated;

-- How long a booking keeps the driver busy (used to keep scheduled bookings from overlapping).
create or replace function public.booking_duration_min(p_type text, p_hours int, p_km numeric, p_wait_min int)
returns int
language sql
immutable
as $$
  select case p_type
    when 'hourly' then coalesce(p_hours, 1) * 60
    when 'round_trip' then ceil(coalesce(p_km, 0) * 2 / 30.0 * 60)::int + coalesce(p_wait_min, 0)
    else ceil(coalesce(p_km, 0) / 30.0 * 60)::int + 15
  end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) Dispatch with scheduled bookings
-- ─────────────────────────────────────────────────────────────────────────────
-- Does the driver have an ACCEPTED scheduled booking that overlaps [p_start, p_start + p_dur)?
create or replace function public.driver_conflicts(p_driver uuid, p_start timestamptz, p_dur int)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from rides x
    where x.driver_id = p_driver
      and x.status in ('CONFIRMED', 'DRIVER_ARRIVING', 'RIDE_STARTED')
      and x.scheduled_at is not null
      and p_start < x.scheduled_at
                    + make_interval(mins => booking_duration_min(x.booking_type, x.package_hours,
                        (select q.distance_km from ride_requests q where q.id = x.request_id), x.expected_wait_min)
                        + setting_num('scheduled_buffer_minutes', 30)::int)
      and p_start + make_interval(mins => p_dur)
                    > x.scheduled_at - make_interval(mins => setting_num('scheduled_buffer_minutes', 30)::int)
  );
$$;
revoke all on function public.driver_conflicts(uuid, timestamptz, int) from public;

-- A ride that is scheduled far ahead does not make the driver or passenger "busy" yet.
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
      and (status = 'RIDE_STARTED' or scheduled_at is null
           or scheduled_at <= now() + make_interval(mins => setting_num('scheduled_buffer_minutes', 30)::int))
  );
$$;

-- Last line of defence: a ride cannot be created for a driver who already has an overlapping
-- scheduled booking.
create or replace function public.rides_check_driver_conflict()
returns trigger
language plpgsql
as $$
declare
  q ride_requests;
begin
  select * into q from ride_requests where id = new.request_id;
  if found and driver_conflicts(new.driver_id, coalesce(q.scheduled_at, now()),
       booking_duration_min(q.booking_type, q.package_hours, q.distance_km, q.expected_wait_min)) then
    raise exception 'This driver already has a booking at that time' using errcode = '22023';
  end if;
  return new;
end;
$$;
create trigger rides_check_driver_conflict_trg before insert on public.rides
  for each row execute function public.rides_check_driver_conflict();

drop policy if exists ride_requests_read on public.ride_requests;
drop function if exists public.driver_sees_request(text, uuid, public.ride_status, timestamptz);

create or replace function public.driver_sees_request(
  p_category text,
  p_city_id uuid,
  p_status public.ride_status,
  p_expires_at timestamptz,
  p_scheduled_at timestamptz default null,
  p_duration_min int default 60
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
    and not has_active_ride(auth.uid())
    and not driver_conflicts(auth.uid(), coalesce(p_scheduled_at, now()), coalesce(p_duration_min, 60));
$$;

create policy ride_requests_read on public.ride_requests for select to authenticated
  using (
    passenger_id = auth.uid()
    or public.is_admin()
    or public.driver_sees_request(category, city_id, status, expires_at, scheduled_at,
         public.booking_duration_min(booking_type, package_hours, distance_km, expected_wait_min))
    or public.i_offered_on(id)
  );

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
  v_dur int;
begin
  select * into r from ride_requests where id = p_request_id;
  if not found then
    return 0;
  end if;
  v_dur := booking_duration_min(r.booking_type, r.package_hours, r.distance_km, r.expected_wait_min);
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
      and not driver_conflicts(d.id, coalesce(r.scheduled_at, now()), v_dur)
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
-- 6) Passenger creates a request (one way / hourly / round trip, now or scheduled)
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text, boolean, numeric);

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
  p_toll numeric default 0,
  p_booking_type text default 'one_way',
  p_package_id uuid default null,
  p_expected_wait_min int default 0,
  p_scheduled_at timestamptz default null
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
  v_pkg hourly_packages;
  v_type text := coalesce(p_booking_type, 'one_way');
  v_dist numeric;
  v_route_id uuid;
  v_req ride_requests;
  v_q record;
  v_night boolean := is_night_time(now());
  v_label text;
  v_badge text := '';
  v_wait int := greatest(coalesce(p_expected_wait_min, 0), 0);
  v_wait_charge numeric := 0;
  v_dlat float8 := p_dropoff_lat;
  v_dlng float8 := p_dropoff_lng;
  v_dlabel text := nullif(btrim(p_dropoff_label), '');
begin
  if v_type not in ('one_way', 'hourly', 'round_trip') then
    raise exception 'Unknown booking type' using errcode = '22023';
  end if;
  select * into v_cat from ride_categories where code = coalesce(p_category, 'car_mini') and is_active;
  if not found then
    raise exception 'This ride type is not available' using errcode = '22023';
  end if;
  if v_type <> 'one_way' and not v_cat.is_car then
    raise exception '% takes one-way trips only', v_cat.name using errcode = '22023';
  end if;
  if p_scheduled_at is not null
     and (p_scheduled_at < now() - interval '5 minutes' or p_scheduled_at > now() + interval '30 days') then
    raise exception 'Choose a pickup time within the next 30 days' using errcode = '22023';
  end if;
  if v_wait > 1440 then
    raise exception 'Waiting time is too long' using errcode = '22023';
  end if;

  if p_pickup_lat is null or p_pickup_lng is null
     or p_pickup_lat not between -90 and 90 or p_pickup_lng not between -180 and 180 then
    raise exception 'Choose a pickup on the map' using errcode = '22023';
  end if;
  if v_type = 'hourly' then
    v_dlat := p_pickup_lat;  -- an hourly rental has no fixed destination
    v_dlng := p_pickup_lng;
  elsif v_dlat is null or v_dlng is null or v_dlat not between -90 and 90 or v_dlng not between -180 and 180 then
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
  select * into v_d from nearest_city(v_dlat, v_dlng);

  if v_type = 'hourly' then
    select * into v_pkg from hourly_packages where id = p_package_id and is_active;
    if not found then
      raise exception 'Choose an hourly package' using errcode = '22023';
    end if;
    v_dist := v_pkg.included_km;
    select * into v_q from fare_calc_hourly(v_cat.code, v_pkg.id);
    v_badge := 'Hourly ' || v_pkg.hours || 'h';
    v_dlabel := coalesce(v_dlabel, 'Hourly · ' || v_pkg.hours || ' h / ' || v_pkg.included_km::int || ' km');
  else
    if haversine_km(p_pickup_lat, p_pickup_lng, v_dlat, v_dlng) < 0.3 then
      raise exception 'Pickup and destination are the same place' using errcode = '22023';
    end if;
    -- Straight line x 1.3 road factor, one decimal. The app uses the same rule.
    v_dist := greatest(1, round((haversine_km(p_pickup_lat, p_pickup_lng, v_dlat, v_dlng) * 1.3)::numeric, 1));
    if v_cat.max_km is not null and v_dist > v_cat.max_km then
      raise exception '% is available for trips up to % km', v_cat.name, v_cat.max_km::int using errcode = '22023';
    end if;
    if v_type = 'round_trip' then
      select recommended, min_offer, max_offer, commission, driver_gets, wait_charge
        into v_q from fare_calc_round_trip(v_dist::float8, v_cat.code, v_wait);
      v_wait_charge := v_q.wait_charge;
      v_badge := 'Round Trip';
    else
      v_wait := 0;
      select * into v_q from fare_calc(v_dist::float8, v_cat.code, v_night,
                                       coalesce(p_loading, false) and v_cat.loading_charge > 0, coalesce(p_toll, 0)::float8);
    end if;
  end if;
  if v_type <> 'round_trip' then
    v_wait := 0;
  end if;

  if p_passenger_count is null or p_passenger_count < 1 or p_passenger_count > v_cat.max_passengers then
    raise exception 'Passengers must be between 1 and %', v_cat.max_passengers using errcode = '22023';
  end if;
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
    recommended_fare, min_offer_fare, max_offer_fare, is_night, loading_selected, toll_amount,
    booking_type, package_id, package_hours, package_km, expected_wait_min, expected_wait_charge, scheduled_at
  ) values (
    v_uid, v_route_id, v_o.id, v_d.id, v_o.id,
    coalesce(nullif(btrim(p_pickup_label), ''), 'Map pin'), p_pickup_lat, p_pickup_lng,
    coalesce(v_dlabel, 'Map pin'), v_dlat, v_dlng,
    p_passenger_count, round(p_offered_fare), v_dist, 'SEARCHING',
    now() + make_interval(mins => setting_num('request_expiry_minutes', 15)::int),
    nullif(btrim(p_notes), ''), v_cat.code,
    v_q.recommended, v_q.min_offer, v_q.max_offer,
    v_night and v_type = 'one_way',
    v_type = 'one_way' and coalesce(p_loading, false) and v_cat.loading_charge > 0,
    case when v_type = 'one_way' then coalesce(p_toll, 0) else 0 end,
    v_type, case when v_type = 'hourly' then v_pkg.id end,
    case when v_type = 'hourly' then v_pkg.hours end,
    case when v_type = 'hourly' then v_pkg.included_km end,
    v_wait, v_wait_charge, p_scheduled_at
  )
  returning * into v_req;

  perform log_status(v_req.id, null, null, 'REQUESTED', 'PASSENGER');
  perform log_status(v_req.id, null, 'REQUESTED', 'SEARCHING', 'SYSTEM');

  v_label := v_cat.name || coalesce(' · ' || nullif(v_badge, ''), '') || ' · '
             || coalesce(nullif(btrim(p_pickup_label), ''), v_city.name)
             || case when v_type = 'hourly' then '' else ' → ' || coalesce(v_dlabel, v_d.name) end
             || case when p_scheduled_at is not null
                     then ' · ' || to_char(p_scheduled_at at time zone 'Asia/Karachi', 'DD Mon HH24:MI') else '' end;
  perform notify(v_uid, 'REQUEST_SENT', 'Request sent',
    v_label || ' · ' || fmt_rs(v_req.offered_fare) || ' · finding drivers',
    jsonb_build_object('request_id', v_req.id));

  perform dispatch_request(v_req.id, 'New ride request',
    v_label || ' · ' || v_req.passenger_count || ' passenger(s) · offer ' || fmt_rs(v_req.offered_fare));
  return v_req;
end;
$$;
revoke all on function public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text, boolean, numeric, text, uuid, int, timestamptz) from public;
grant execute on function public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text, boolean, numeric, text, uuid, int, timestamptz) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7) Offers and the driver feed use the new visibility rule
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_src text;
begin
  -- submit_offer: only the visibility call changes.
  select pg_get_functiondef('public.submit_offer(uuid, public.offer_type, numeric, float8, float8, int)'::regprocedure) into v_src;
  v_src := replace(v_src,
    'driver_sees_request(v_req.category, v_req.city_id, v_req.status, v_req.expires_at)',
    'driver_sees_request(v_req.category, v_req.city_id, v_req.status, v_req.expires_at, v_req.scheduled_at, booking_duration_min(v_req.booking_type, v_req.package_hours, v_req.distance_km, v_req.expected_wait_min))');
  execute v_src;
end;
$$;

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
  commission numeric, driver_gets numeric, is_night boolean, loading_selected boolean,
  booking_type text, package_hours int, package_km numeric, expected_wait_min int, scheduled_at timestamptz
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
         r.is_night, r.loading_selected,
         r.booking_type, r.package_hours, r.package_km, r.expected_wait_min, r.scheduled_at
  from ride_requests r
  join cities o on o.id = r.origin_city_id
  join cities d on d.id = r.destination_city_id
  join profiles p on p.id = r.passenger_id
  left join passengers pa on pa.id = r.passenger_id
  left join drivers me on me.id = auth.uid()
  left join ride_offers mo on mo.request_id = r.id and mo.driver_id = auth.uid() and mo.status = 'PENDING'
  where driver_sees_request(r.category, r.city_id, r.status, r.expires_at, r.scheduled_at,
          booking_duration_min(r.booking_type, r.package_hours, r.distance_km, r.expected_wait_min))
    and r.passenger_id <> auth.uid()
    and not exists (select 1 from request_dismissals x where x.driver_id = auth.uid() and x.request_id = r.id)
  order by 21 nulls last, r.created_at desc
  limit 50;
$$;
revoke all on function public.get_driver_feed() from public;
grant execute on function public.get_driver_feed() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8) During the trip: km counter, destination stop for round trips
-- ─────────────────────────────────────────────────────────────────────────────
-- The driver app counts the distance travelled and reports it; it only ever grows.
create or replace function public.update_ride_progress(p_ride_id uuid, p_actual_km numeric)
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
  if v_ride.status <> 'RIDE_STARTED' then
    raise exception 'The ride is not in progress' using errcode = '22023';
  end if;
  if p_actual_km is null or p_actual_km < 0 or p_actual_km > 2000 then
    raise exception 'Invalid distance' using errcode = '22023';
  end if;
  update rides set actual_km = greatest(actual_km, round(p_actual_km, 1))
   where id = p_ride_id returning * into v_ride;
  return v_ride;
end;
$$;
revoke all on function public.update_ride_progress(uuid, numeric) from public;
grant execute on function public.update_ride_progress(uuid, numeric) to authenticated;

-- Round trip: the driver taps "Arrived at destination" and later "Return started".
create or replace function public.driver_reached_destination(p_ride_id uuid)
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
  if v_ride.booking_type <> 'round_trip' or v_ride.status <> 'RIDE_STARTED' then
    raise exception 'This is only for a round trip in progress' using errcode = '22023';
  end if;
  if v_ride.dest_arrived_at is null then
    update rides set dest_arrived_at = now() where id = p_ride_id returning * into v_ride;
    perform notify(v_ride.passenger_id, 'DESTINATION_REACHED', 'You have reached the destination',
      'Waiting is free for ' || setting_num('round_trip_free_wait_minutes', 30)::int || ' minutes.',
      jsonb_build_object('ride_id', p_ride_id));
  end if;
  return v_ride;
end;
$$;
revoke all on function public.driver_reached_destination(uuid) from public;
grant execute on function public.driver_reached_destination(uuid) to authenticated;

create or replace function public.driver_return_started(p_ride_id uuid)
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
  if v_ride.booking_type <> 'round_trip' or v_ride.status <> 'RIDE_STARTED' then
    raise exception 'This is only for a round trip in progress' using errcode = '22023';
  end if;
  if v_ride.dest_arrived_at is null then
    raise exception 'Tap "Arrived at destination" first' using errcode = '22023';
  end if;
  if v_ride.return_started_at is null then
    update rides set return_started_at = now() where id = p_ride_id returning * into v_ride;
  end if;
  return v_ride;
end;
$$;
revoke all on function public.driver_return_started(uuid) from public;
grant execute on function public.driver_return_started(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9) Completing a ride: final fare per booking type
-- ─────────────────────────────────────────────────────────────────────────────
--   one way     final = agreed fare + pickup waiting
--   hourly      final = agreed package price + extra km x rate + started extra hours x rate (+ pickup waiting)
--   round trip  final = agreed fare - expected waiting charge + actual destination waiting charge (+ pickup waiting)
create or replace function public.complete_ride(p_ride_id uuid)
returns public.commissions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_ride rides;
  v_cat ride_categories;
  v_pct numeric := setting_num('commission_percent', 10);
  v_commission numeric;
  v_row commissions;
  v_balance numeric;
  v_wait_min int := 0;
  v_wait_charge numeric := 0;
  v_actual_min int;
  v_extra_km numeric := 0;
  v_extra_km_charge numeric := 0;
  v_extra_hours int := 0;
  v_extra_hour_charge numeric := 0;
  v_dest_min int := 0;
  v_dest_charge numeric := 0;
  v_final numeric;
begin
  select * into v_ride from rides where id = p_ride_id for update;
  if not found or v_ride.driver_id <> v_uid then
    raise exception 'Ride not found' using errcode = 'P0002';
  end if;
  if not can_transition(v_ride.status, 'COMPLETED', 'DRIVER') then
    raise exception 'Only a started ride can be completed' using errcode = '22023';
  end if;
  select * into v_cat from ride_categories where code = v_ride.category;

  -- Waiting at the pickup (free minutes, then per minute).
  if v_ride.arrived_at is not null and v_ride.started_at is not null and v_ride.started_at > v_ride.arrived_at then
    v_wait_min := floor(extract(epoch from (v_ride.started_at - v_ride.arrived_at)) / 60)::int;
    v_wait_charge := greatest(0, v_wait_min - setting_num('waiting_free_minutes', 5)::int) * coalesce(v_cat.waiting_per_min, 0);
  end if;

  v_actual_min := greatest(0, floor(extract(epoch from (now() - coalesce(v_ride.started_at, now()))) / 60)::int);
  v_final := coalesce(v_ride.accepted_fare, v_ride.final_fare) + v_wait_charge;

  if v_ride.booking_type = 'hourly' then
    v_extra_km := greatest(0, v_ride.actual_km - coalesce(v_ride.package_km, 0));
    v_extra_km_charge := round(v_extra_km * v_cat.extra_km_rate);
    v_extra_hours := ceil(greatest(0, v_actual_min - coalesce(v_ride.package_hours, 0) * 60) / 60.0)::int;
    v_extra_hour_charge := v_extra_hours * v_cat.extra_hour_rate;
    v_final := v_final + v_extra_km_charge + v_extra_hour_charge;
  elsif v_ride.booking_type = 'round_trip' then
    if v_ride.dest_arrived_at is not null then
      v_dest_min := floor(extract(epoch from (coalesce(v_ride.return_started_at, now()) - v_ride.dest_arrived_at)) / 60)::int;
    end if;
    v_dest_charge := round_trip_wait_charge(v_ride.category, v_dest_min);
    v_final := v_final - coalesce(v_ride.expected_wait_charge, 0) + v_dest_charge;
  end if;

  v_commission := round(v_final * v_pct / 100, 2);
  update rides set
    status = 'COMPLETED', completed_at = now(),
    waiting_minutes = v_wait_min, waiting_charge = v_wait_charge,
    actual_minutes = v_actual_min,
    extra_km = v_extra_km, extra_km_charge = v_extra_km_charge,
    extra_hours = v_extra_hours, extra_hour_charge = v_extra_hour_charge,
    dest_waiting_minutes = v_dest_min, dest_waiting_charge = v_dest_charge,
    final_fare = v_final,
    commission_amount = v_commission, driver_gets = v_final - v_commission
  where id = p_ride_id
  returning * into v_ride;
  perform log_status(v_ride.request_id, p_ride_id, 'RIDE_STARTED', 'COMPLETED', 'DRIVER');

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

  update drivers set total_rides = total_rides + 1,
         current_city_id = case when v_ride.booking_type = 'one_way' then v_ride.destination_city_id else current_city_id end
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
-- 10) Ride details: booking type, live timer data, the full breakdown
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_src text;
begin
  select pg_get_functiondef('public.get_ride_details(uuid)'::regprocedure) into v_src;
  v_src := replace(v_src,
    '''waiting_charge'', r.waiting_charge,',
    '''waiting_charge'', r.waiting_charge,
    ''booking_type'', r.booking_type,
    ''package_hours'', r.package_hours,
    ''package_km'', r.package_km,
    ''expected_wait_min'', r.expected_wait_min,
    ''expected_wait_charge'', r.expected_wait_charge,
    ''scheduled_at'', r.scheduled_at,
    ''actual_km'', r.actual_km,
    ''actual_minutes'', coalesce(r.actual_minutes,
        case when r.status = ''RIDE_STARTED'' then floor(extract(epoch from (now() - r.started_at)) / 60)::int end),
    ''extra_km'', r.extra_km,
    ''extra_km_charge'', r.extra_km_charge,
    ''extra_hours'', r.extra_hours,
    ''extra_hour_charge'', r.extra_hour_charge,
    ''dest_arrived_at'', r.dest_arrived_at,
    ''return_started_at'', r.return_started_at,
    ''dest_waiting_minutes'', r.dest_waiting_minutes,
    ''dest_waiting_charge'', r.dest_waiting_charge,
    ''driver_gets'', case when auth.uid() = r.driver_id or is_admin() then r.driver_gets end,
    ''commission_amount'', case when auth.uid() = r.driver_id or is_admin() then r.commission_amount end,
    ''extra_km_rate'', k.extra_km_rate,
    ''extra_hour_rate'', k.extra_hour_rate,
    ''round_trip_wait_per_hour'', k.round_trip_wait_per_hour,');
  execute v_src;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11) Scheduled bookings: reminder before pickup
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.remind_scheduled_rides()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ride record;
  v_count int := 0;
begin
  for v_ride in
    select r.id, r.passenger_id, r.driver_id, r.scheduled_at, q.pickup_label
    from rides r
    join ride_requests q on q.id = r.request_id
    where r.status in ('CONFIRMED', 'DRIVER_ARRIVING')
      and r.scheduled_at is not null
      and r.reminder_sent_at is null
      and r.scheduled_at <= now() + make_interval(mins => setting_num('scheduled_reminder_minutes', 30)::int)
      and r.scheduled_at > now() - interval '3 hours'
    for update of r skip locked
  loop
    update rides set reminder_sent_at = now() where id = v_ride.id;
    perform notify(v_ride.driver_id, 'SCHEDULED_REMINDER', 'Scheduled ride soon',
      'Pickup at ' || to_char(v_ride.scheduled_at at time zone 'Asia/Karachi', 'HH24:MI')
        || ' · ' || coalesce(v_ride.pickup_label, ''),
      jsonb_build_object('ride_id', v_ride.id));
    perform notify(v_ride.passenger_id, 'SCHEDULED_REMINDER', 'Your ride is coming up',
      'Pickup at ' || to_char(v_ride.scheduled_at at time zone 'Asia/Karachi', 'HH24:MI')
        || ' · ' || coalesce(v_ride.pickup_label, ''),
      jsonb_build_object('ride_id', v_ride.id));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.remind_scheduled_rides() from public;
grant execute on function public.remind_scheduled_rides() to authenticated;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('kamgo-scheduled-reminders', '* * * * *', 'select public.remind_scheduled_rides()');
exception when others then
  raise notice 'pg_cron not available (%); call public.remind_scheduled_rides() from a scheduler instead', sqlerrm;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12) Fare report by booking type
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists public.admin_fare_report(date, date);
create or replace function public.admin_fare_report(p_from date default null, p_to date default null, p_booking_type text default null)
returns table (
  city_name text, category text, category_name text, booking_type text, rides bigint,
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
  select c.name, r.category, k.name, r.booking_type, count(*),
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
    and (p_booking_type is null or r.booking_type = p_booking_type)
  group by c.name, r.category, k.name, k.sort_order, r.booking_type
  order by c.name, k.sort_order, r.booking_type;
end;
$$;
revoke all on function public.admin_fare_report(date, date, text) from public;
grant execute on function public.admin_fare_report(date, date, text) to authenticated;
