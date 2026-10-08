-- inDrive-style fares and car models.
--
-- Fares: each ride type has a base fare and a rate per km. The *recommended* fare for a
-- trip is  base + km x rate  (rounded to Rs. 10). The passenger can offer less or more,
-- within min_pct .. max_pct of the recommended fare, and drivers can counter inside the
-- same band. (These numbers are a starting point: edit them in the admin Ride types page.)
--
-- Car models: Mini and Premium drivers pick their car from a fixed list.

alter table public.ride_categories
  add column base_fare numeric(8,2) not null default 0 check (base_fare >= 0),
  add column per_km    numeric(8,2) not null default 40 check (per_km > 0),
  add column min_pct   int not null default 70 check (min_pct between 10 and 100),
  add column max_pct   int not null default 200 check (max_pct >= 100);

update public.ride_categories set base_fare = 40,  per_km = 20, min_pct = 70, max_pct = 200 where code = 'BIKE';
update public.ride_categories set base_fare = 60,  per_km = 30, min_pct = 70, max_pct = 200 where code = 'RICKSHAW';
update public.ride_categories set base_fare = 100, per_km = 42, min_pct = 70, max_pct = 200 where code = 'MINI';
update public.ride_categories set base_fare = 150, per_km = 62, min_pct = 70, max_pct = 200 where code = 'PREMIUM';
update public.ride_categories set base_fare = 150, per_km = 55, min_pct = 70, max_pct = 200 where code = 'COURIER';

alter table public.ride_categories
  drop column min_fare_per_km,
  drop column max_fare_per_km;

grant update (base_fare, per_km, min_pct, max_pct) on public.ride_categories to authenticated;

-- Recommended fare for a distance in a ride type (the same formula the app uses).
create or replace function public.recommended_fare(p_distance numeric, p_category text)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select round((c.base_fare + p_distance * c.per_km) / 10) * 10
  from ride_categories c where c.code = p_category;
$$;
grant execute on function public.recommended_fare(numeric, text) to authenticated;

create or replace function public.assert_fare_for_category(p_distance numeric, p_fare numeric, p_category text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c ride_categories;
  v_rec numeric;
  v_min numeric;
  v_max numeric;
begin
  select * into c from ride_categories where code = p_category;
  if found then
    v_rec := round((c.base_fare + p_distance * c.per_km) / 10) * 10;
    v_min := ceil(v_rec * c.min_pct / 100.0);
    v_max := floor(v_rec * c.max_pct / 100.0);
  else
    -- Unknown ride type: the old global per-km range.
    v_min := ceil(p_distance * setting_num('min_fare_per_km', 20));
    v_max := floor(p_distance * setting_num('max_fare_per_km', 100));
  end if;
  if p_fare is null or p_fare < v_min or p_fare > v_max then
    raise exception 'Fare must be between Rs. % and Rs. % for this trip', v_min::bigint, v_max::bigint
      using errcode = '22023';
  end if;
end;
$$;
revoke all on function public.assert_fare_for_category(numeric, numeric, text) from public;

-- ─────────────────────────────────────────────────────────────────────────────
-- Car models per ride type
-- ─────────────────────────────────────────────────────────────────────────────
create table public.vehicle_models (
  id         uuid primary key default gen_random_uuid(),
  category   text not null references public.ride_categories(code) on delete cascade,
  make       text not null check (char_length(btrim(make)) between 2 and 40),
  model      text not null check (char_length(btrim(model)) between 1 and 40),
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index vehicle_models_unique_idx
  on public.vehicle_models (category, lower(btrim(make)), lower(btrim(model)));

insert into public.vehicle_models (category, make, model) values
  ('MINI',    'Suzuki', 'Alto'),
  ('MINI',    'Suzuki', 'Mehran'),
  ('MINI',    'Suzuki', 'Wagon R'),
  ('MINI',    'Suzuki', 'Cultus'),
  ('PREMIUM', 'Toyota', 'Corolla XLi'),
  ('PREMIUM', 'Toyota', 'Yaris'),
  ('PREMIUM', 'Honda',  'Civic'),
  ('PREMIUM', 'Honda',  'BR-V');

alter table public.vehicle_models enable row level security;
grant select on public.vehicle_models to authenticated;
grant insert, update, delete on public.vehicle_models to authenticated;
create policy vehicle_models_read on public.vehicle_models for select to authenticated
  using (is_active or public.is_admin());
create policy vehicle_models_admin_insert on public.vehicle_models for insert to authenticated
  with check (public.is_admin());
create policy vehicle_models_admin_update on public.vehicle_models for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy vehicle_models_admin_delete on public.vehicle_models for delete to authenticated
  using (public.is_admin());

-- A ride type that has a model list only accepts cars from it.
create or replace function public.vehicle_model_allowed(p_category text, p_make text, p_model text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (select 1 from vehicle_models where category = p_category and is_active)
      or exists (select 1 from vehicle_models
                  where category = p_category and is_active
                    and lower(btrim(make)) = lower(btrim(coalesce(p_make, '')))
                    and lower(btrim(model)) = lower(btrim(coalesce(p_model, ''))));
$$;
revoke all on function public.vehicle_model_allowed(text, text, text) from public;

drop function if exists public.save_driver_application(text, uuid, public.vehicle_type, text, text, text, text, int, int, uuid[], uuid[], text);

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
  if char_length(btrim(coalesce(p_vehicle_model, ''))) < 1 or char_length(v_plate) < 3 then
    raise exception 'Vehicle model and number plate are required' using errcode = '22023';
  end if;
  if p_seats is null or p_seats not between 1 and 20 then
    raise exception 'Seats must be 1–20' using errcode = '22023';
  end if;
  if exists (select 1 from vehicles where plate_number = v_plate and driver_id <> v_uid) then
    raise exception 'This number plate is already registered' using errcode = '23505';
  end if;

  select * into v_cat from ride_categories
   where code = coalesce(p_category, case v_type
       when 'MOTORCYCLE' then 'BIKE' when 'RICKSHAW' then 'RICKSHAW' else 'MINI' end)
     and is_active;
  if not found then
    raise exception 'Choose a ride type for your vehicle' using errcode = '22023';
  end if;
  if not vehicle_model_allowed(v_cat.code, p_vehicle_make, p_vehicle_model) then
    raise exception 'Choose your car from the list for % rides', v_cat.name using errcode = '22023';
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
