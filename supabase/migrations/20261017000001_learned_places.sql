-- KAM GO learns its own address book.
--
-- Mohalla / street names in small towns are on no map. When a driver reaches a pickup, the
-- driver's GPS is the true spot of the words the passenger typed ("bilal town"), so that name and
-- position are saved as a place. The same happens with the drop-off when a one-way ride ends.
-- The next passenger who writes "bilal town" gets the exact spot and an exact distance.
-- Admin places are never changed by this; learned places are averaged as more rides confirm them.

alter table public.places
  add column source text not null default 'admin' check (source in ('admin', 'learned')),
  add column confirmations int not null default 0;

-- Normalise what the passenger typed into a place name, or null when it is not worth learning.
create or replace function public.learnable_label(p_label text)
returns text
language sql
immutable
as $$
  select case
    when n is null or char_length(n) < 3 or char_length(n) > 80 then null
    when lower(n) in ('map pin', 'my location', 'pinned location', 'selected location') then null
    when n ilike '%(town centre)' then null
    when n ilike 'hourly ·%' then null
    else n
  end
  from (select nullif(btrim(regexp_replace(split_part(coalesce(p_label, ''), ' — ', 1), '\s+', ' ', 'g')), '') as n) x;
$$;

create or replace function public.learn_place(p_label text, p_lat float8, p_lng float8)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := learnable_label(p_label);
  v_city record;
  v_place places;
begin
  if v_name is null or p_lat is null or p_lng is null then
    return;
  end if;
  -- Only inside a city we serve, and never a city's own name.
  select * into v_city from nearest_city(p_lat, p_lng);
  if v_city.id is null or v_city.km > (select service_radius_km from cities where id = v_city.id) then
    return;
  end if;
  if exists (select 1 from cities where lower(name) = lower(v_name)) then
    return;
  end if;
  -- An admin place with this name near here already says where it is.
  if exists (select 1 from places
             where lower(btrim(name)) = lower(v_name) and source = 'admin'
               and haversine_km(lat, lng, p_lat, p_lng) < 5) then
    return;
  end if;

  select * into v_place from places
   where lower(btrim(name)) = lower(v_name) and source = 'learned'
     and haversine_km(lat, lng, p_lat, p_lng) < 2
   order by haversine_km(lat, lng, p_lat, p_lng)
   limit 1
   for update;

  if found then
    -- One more ride confirms it: move it towards the new point (running average).
    update places set
      lat = (lat * confirmations + p_lat) / (confirmations + 1),
      lng = (lng * confirmations + p_lng) / (confirmations + 1),
      confirmations = confirmations + 1,
      updated_at = now()
    where id = v_place.id;
  else
    insert into places (name, kind, lat, lng, source, confirmations)
    values (v_name, 'place', p_lat, p_lng, 'learned', 1)
    on conflict do nothing;
  end if;
end;
$$;
revoke all on function public.learn_place(text, float8, float8) from public;

-- Where the driver is right now: what the app sends, else the ride's latest GPS point, else the
-- driver's last known position (only if it is fresh).
create or replace function public.driver_position_now(p_ride_id uuid, p_driver uuid)
returns table (lat float8, lng float8)
language sql
stable
security definer
set search_path = public
as $$
  select * from (
    select l.lat, l.lng from ride_locations l
     where l.ride_id = p_ride_id and l.recorded_at > now() - interval '3 minutes'
     order by l.recorded_at desc limit 1
  ) a
  union all
  select * from (
    select d.last_lat, d.last_lng from drivers d
     where d.id = p_driver and d.last_lat is not null and d.last_location_at > now() - interval '3 minutes'
  ) b
  limit 1;
$$;
revoke all on function public.driver_position_now(uuid, uuid) from public;

-- driver_arrived: the app may send where the driver is; the pickup words are learned there.
drop function if exists public.driver_arrived(uuid);
create or replace function public.driver_arrived(p_ride_id uuid, p_lat float8 default null, p_lng float8 default null)
returns public.rides
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_ride rides;
  v_lat float8 := p_lat;
  v_lng float8 := p_lng;
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

    if v_lat is not null and v_lng is not null then
      insert into ride_locations (ride_id, driver_id, lat, lng) values (p_ride_id, v_uid, v_lat, v_lng);
    else
      select lat, lng into v_lat, v_lng from driver_position_now(p_ride_id, v_uid);
    end if;
    perform learn_place((select pickup_label from ride_requests where id = v_ride.request_id), v_lat, v_lng);
  end if;
  return v_ride;
end;
$$;
revoke all on function public.driver_arrived(uuid, float8, float8) from public;
grant execute on function public.driver_arrived(uuid, float8, float8) to authenticated;

-- complete_ride: a one-way ride ends at the destination, so its words are learned there too.
do $$
declare
  v_src text;
  v_new text;
begin
  select pg_get_functiondef('public.complete_ride(uuid)'::regprocedure) into v_src;
  v_new := replace(v_src,
    'perform log_status(v_ride.request_id, p_ride_id, ''RIDE_STARTED'', ''COMPLETED'', ''DRIVER'');',
    'perform log_status(v_ride.request_id, p_ride_id, ''RIDE_STARTED'', ''COMPLETED'', ''DRIVER'');
  if v_ride.booking_type = ''one_way'' then
    perform learn_place((select dropoff_label from ride_requests where id = v_ride.request_id),
                        (select lat from driver_position_now(p_ride_id, v_ride.driver_id)),
                        (select lng from driver_position_now(p_ride_id, v_ride.driver_id)));
  end if;');
  if v_new = v_src then raise exception 'complete_ride patch failed'; end if;
  execute v_new;
end;
$$;
