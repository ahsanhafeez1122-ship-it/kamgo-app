-- KAM GO — server-side helpers and Phase 1 RPCs.
-- All SECURITY DEFINER functions pin search_path and check the caller
-- themselves; the client is never trusted with role, money or status.

-- ─────────────────────────────────────────────────────────────────────────────
-- Settings (defaults live here, not in seed, because functions depend on them)
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.settings (key, value, description) values
  ('commission_percent',       '10',    'KAM GO commission on completed rides, in %'),
  ('offer_expiry_minutes',     '3',     'How long a driver offer stays valid'),
  ('request_expiry_minutes',   '15',    'How long a ride request stays open'),
  ('min_fare_per_km',          '20',    'Lowest allowed fare per km (Rs.)'),
  ('max_fare_per_km',          '100',   'Highest allowed fare per km (Rs.)'),
  ('max_passengers',           '6',     'Most passengers on one request'),
  ('cancellation_fee_enabled', 'false', 'Charge a fee on late cancellations'),
  ('cancellation_fee_amount',  '0',     'Fee in Rs. when enabled'),
  ('search_radius_km',         '15',    'Driver search radius around pickup'),
  ('support_whatsapp',         '"923000000000"', 'WhatsApp number for Contact KAM GO (no +)'),
  ('support_phone',            '"+923000000000"', 'Phone number for Contact KAM GO')
on conflict (key) do nothing;

create or replace function public.setting_num(p_key text, p_default numeric)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select (value #>> '{}')::numeric from settings where key = p_key), p_default);
$$;

create or replace function public.setting_bool(p_key text, p_default boolean)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select (value #>> '{}')::boolean from settings where key = p_key), p_default);
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Identity helpers (used by RLS policies; definer so they never recurse)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from admin_users where user_id = auth.uid());
$$;

-- Caller's request?
create or replace function public.is_my_request(p_request_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from ride_requests where id = p_request_id and passenger_id = auth.uid()
  );
$$;

-- Caller (a driver) has made an offer on this request?
create or replace function public.i_offered_on(p_request_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from ride_offers where request_id = p_request_id and driver_id = auth.uid()
  );
$$;

-- Caller is the passenger or driver on this ride?
create or replace function public.is_ride_party(p_ride_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from rides
    where id = p_ride_id and auth.uid() in (passenger_id, driver_id)
  );
$$;

-- May the caller see basic profile info of p_other? True when they share a
-- ride, or one of them has offered on the other's request.
create or replace function public.shares_ride_with(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from rides
    where (passenger_id = auth.uid() and driver_id = p_other)
       or (driver_id = auth.uid() and passenger_id = p_other)
  )
  or exists (
    select 1 from ride_offers o
    join ride_requests r on r.id = o.request_id
    where (r.passenger_id = auth.uid() and o.driver_id = p_other)
       or (o.driver_id = auth.uid() and r.passenger_id = p_other)
  );
$$;

-- Is the caller an approved, online, active driver who should see this open
-- request? Only drivers in the request's origin city whose preferred routes
-- include it (or who have no preferences yet) qualify — never the whole region.
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
-- Fare guardrails
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fare_bounds(p_route_id uuid)
returns table (distance_km numeric, min_fare numeric, max_fare numeric)
language sql
stable
security definer
set search_path = public
as $$
  select r.distance_km,
         ceil(r.distance_km * setting_num('min_fare_per_km', 20)),
         floor(r.distance_km * setting_num('max_fare_per_km', 100))
  from routes r
  where r.id = p_route_id;
$$;

-- Raises a readable error when a fare is outside the route's bounds.
create or replace function public.assert_fare_allowed(p_route_id uuid, p_fare numeric)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  b record;
begin
  select * into b from fare_bounds(p_route_id);
  if not found then
    raise exception 'Route not found' using errcode = 'P0002';
  end if;
  if p_fare is null or p_fare < b.min_fare or p_fare > b.max_fare then
    raise exception 'Fare must be between Rs. % and Rs. % for this route',
      b.min_fare::bigint, b.max_fare::bigint
      using errcode = '22023';
  end if;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ride state machine (mirrors lib/features/rides/domain/ride_status.dart)
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.ride_status_transitions (from_status, to_status, actor) values
  ('REQUESTED',       'SEARCHING',       'SYSTEM'),
  ('REQUESTED',       'CANCELLED',       'PASSENGER'),
  ('REQUESTED',       'CANCELLED',       'ADMIN'),
  ('REQUESTED',       'EXPIRED',         'SYSTEM'),
  ('SEARCHING',       'OFFER_RECEIVED',  'SYSTEM'),
  ('SEARCHING',       'CANCELLED',       'PASSENGER'),
  ('SEARCHING',       'CANCELLED',       'ADMIN'),
  ('SEARCHING',       'EXPIRED',         'SYSTEM'),
  ('OFFER_RECEIVED',  'DRIVER_SELECTED', 'PASSENGER'),
  ('OFFER_RECEIVED',  'CANCELLED',       'PASSENGER'),
  ('OFFER_RECEIVED',  'CANCELLED',       'ADMIN'),
  ('OFFER_RECEIVED',  'EXPIRED',         'SYSTEM'),
  ('DRIVER_SELECTED', 'CONFIRMED',       'SYSTEM'),
  ('DRIVER_SELECTED', 'CANCELLED',       'PASSENGER'),
  ('DRIVER_SELECTED', 'CANCELLED',       'DRIVER'),
  ('DRIVER_SELECTED', 'CANCELLED',       'ADMIN'),
  ('CONFIRMED',       'DRIVER_ARRIVING', 'DRIVER'),
  ('CONFIRMED',       'RIDE_STARTED',    'DRIVER'),
  ('CONFIRMED',       'CANCELLED',       'PASSENGER'),
  ('CONFIRMED',       'CANCELLED',       'DRIVER'),
  ('CONFIRMED',       'CANCELLED',       'ADMIN'),
  ('CONFIRMED',       'NO_SHOW',         'DRIVER'),
  ('CONFIRMED',       'NO_SHOW',         'PASSENGER'),
  ('DRIVER_ARRIVING', 'RIDE_STARTED',    'DRIVER'),
  ('DRIVER_ARRIVING', 'CANCELLED',       'PASSENGER'),
  ('DRIVER_ARRIVING', 'CANCELLED',       'DRIVER'),
  ('DRIVER_ARRIVING', 'CANCELLED',       'ADMIN'),
  ('DRIVER_ARRIVING', 'NO_SHOW',         'DRIVER'),
  ('DRIVER_ARRIVING', 'NO_SHOW',         'PASSENGER'),
  ('RIDE_STARTED',    'COMPLETED',       'DRIVER'),
  ('RIDE_STARTED',    'CANCELLED',       'ADMIN')
on conflict do nothing;

create or replace function public.can_transition(
  p_from public.ride_status,
  p_to public.ride_status,
  p_actor public.ride_actor
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from ride_status_transitions
    where from_status = p_from and to_status = p_to and actor = p_actor
  );
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- New auth user → profile + passenger row
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Role is never read from client-supplied metadata: everyone starts as a
  -- PASSENGER and picks driver mode through complete_profile().
  insert into profiles (id, phone) values (new.id, new.phone)
  on conflict (id) do nothing;
  insert into passengers (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────────────────────────────────────
-- complete_profile: finishes onboarding. Only PASSENGER or DRIVER may be
-- chosen; drivers start PENDING and need admin approval.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.complete_profile(
  p_full_name text,
  p_role public.user_role,
  p_city_id uuid default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile profiles;
  v_name text := btrim(p_full_name);
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if p_role not in ('PASSENGER', 'DRIVER') then
    raise exception 'Invalid role' using errcode = '42501';
  end if;
  if v_name is null or char_length(v_name) not between 2 and 80 then
    raise exception 'Please enter your name (2–80 characters)' using errcode = '22023';
  end if;

  select * into v_profile from profiles where id = v_uid for update;
  if not found then
    -- Trigger missed (e.g. user created before migrations ran).
    insert into profiles (id, phone)
    select id, phone from auth.users where id = v_uid
    returning * into v_profile;
  end if;

  if v_profile.account_status = 'SUSPENDED' then
    raise exception 'This account is suspended' using errcode = '42501';
  end if;
  if v_profile.role = 'ADMIN' then
    raise exception 'Admin accounts are managed by KAM GO' using errcode = '42501';
  end if;
  if v_profile.onboarded and v_profile.role <> p_role then
    raise exception 'Your account type cannot be changed here' using errcode = '42501';
  end if;

  if p_role = 'DRIVER' then
    if p_city_id is null
       or not exists (select 1 from cities where id = p_city_id and is_active) then
      raise exception 'Please choose an active city' using errcode = '22023';
    end if;
    insert into drivers (id, current_city_id) values (v_uid, p_city_id)
    on conflict (id) do update
      set current_city_id = excluded.current_city_id
      where drivers.status = 'PENDING';
  end if;

  insert into passengers (id, home_city_id) values (v_uid, p_city_id)
  on conflict (id) do nothing;

  update profiles
     set full_name = v_name,
         role = p_role,
         onboarded = true
   where id = v_uid
  returning * into v_profile;

  return v_profile;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Digital adda: live counts per active city
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_adda_summary()
returns table (city_id uuid, city_name text, online_drivers int, open_requests int)
language sql
stable
security definer
set search_path = public
as $$
  select c.id,
         c.name,
         (select count(*)::int
            from drivers d
            join profiles p on p.id = d.id
           where d.current_city_id = c.id
             and d.status = 'APPROVED'
             and d.is_online
             and p.account_status = 'ACTIVE'),
         (select count(*)::int
            from ride_requests r
           where r.origin_city_id = c.id
             and r.status in ('REQUESTED', 'SEARCHING', 'OFFER_RECEIVED')
             and r.expires_at > now())
  from cities c
  where c.is_active
    and auth.uid() is not null
  order by c.sort_order, c.name;
$$;

-- Most-travelled active route in the last 30 days (optionally from one city),
-- with an approximate fare: the average completed fare, or the midpoint of
-- the guardrails when there is no history yet. Rounded to Rs. 50.
create or replace function public.get_popular_route(p_origin_city_id uuid default null)
returns table (route_id uuid, origin_name text, destination_name text, approx_fare numeric)
language sql
stable
security definer
set search_path = public
as $$
  with stats as (
    select route_id, count(*) as n, avg(final_fare) as avg_fare
    from rides
    where status = 'COMPLETED' and completed_at > now() - interval '30 days'
    group by route_id
  )
  select r.id,
         o.name,
         d.name,
         round(
           coalesce(
             s.avg_fare,
             r.distance_km * (setting_num('min_fare_per_km', 20) + setting_num('max_fare_per_km', 100)) / 2
           ) / 50
         ) * 50
  from routes r
  join cities o on o.id = r.origin_city_id and o.is_active
  join cities d on d.id = r.destination_city_id and d.is_active
  left join stats s on s.route_id = r.id
  where r.is_active
    and auth.uid() is not null
    and (p_origin_city_id is null or r.origin_city_id = p_origin_city_id)
  order by coalesce(s.n, 0) desc, r.distance_km
  limit 1;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Execute permissions: nothing for anon; RPCs for signed-in users only.
-- ─────────────────────────────────────────────────────────────────────────────
revoke execute on all functions in schema public from public, anon;

grant execute on function
  public.is_admin(),
  public.is_my_request(uuid),
  public.i_offered_on(uuid),
  public.is_ride_party(uuid),
  public.shares_ride_with(uuid),
  public.driver_can_see_request(uuid, uuid, public.ride_status, timestamptz),
  public.setting_num(text, numeric),
  public.setting_bool(text, boolean),
  public.fare_bounds(uuid),
  public.can_transition(public.ride_status, public.ride_status, public.ride_actor),
  public.complete_profile(text, public.user_role, uuid),
  public.get_adda_summary(),
  public.get_popular_route(uuid)
to authenticated;
