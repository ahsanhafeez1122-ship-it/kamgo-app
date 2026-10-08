-- Cities with a service radius, the six vehicle categories with their fare configuration,
-- fare settings, vehicle models (model -> category), the driver's city, and the columns
-- that keep what we need for later review.
--
-- Nothing here is code: every number is a row that the admin panel edits.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Cities: service radius
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.cities
  add column service_radius_km numeric(6,1) not null default 25 check (service_radius_km > 0);

update public.cities set service_radius_km = 25 where name in ('Chichawatni', 'Kamalia', 'Toba Tek Singh');
update public.cities set service_radius_km = 20 where name in ('Rajana', 'Pir Mahal');

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Vehicle categories: new codes, fare configuration
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.ride_categories
  add column is_car boolean not null default false,
  add column city_mileage numeric(6,2),
  add column highway_mileage numeric(6,2),
  add column city_maint numeric(6,2),
  add column highway_maint numeric(6,2),
  add column min_fare numeric(8,2),
  add column waiting_per_min numeric(6,2),
  add column max_km numeric(6,1),
  add column loading_charge numeric(8,2) not null default 0,
  add column round_trip_wait_per_hour numeric(8,2) not null default 0,
  add column profit_points jsonb;

insert into public.ride_categories
  (code, name, name_ur, vehicle_type, is_car, max_passengers, sort_order, is_active,
   city_mileage, highway_mileage, city_maint, highway_maint, min_fare, waiting_per_min, max_km,
   loading_charge, round_trip_wait_per_hour, profit_points)
values
  ('car_mini',    'Car Mini',    'کار منی',     'CAR',        true,  4, 1, true, 14, 17, 10,  8, 450,  8, null,   0, 250,
   '[[0,200],[5,500],[10,500],[20,1200],[40,1200],[100,2400]]'),
  ('car_comfort', 'Car Comfort', 'کار کمفرٹ',   'CAR',        true,  4, 2, true, 11, 14, 14, 12, 490, 10, null,   0, 300,
   '[[0,240],[5,600],[10,600],[20,1440],[40,1440],[100,2880]]'),
  ('car_xl',      'Car XL',      'کار ایکس ایل', 'VAN',       true,  7, 3, true, 10, 12, 15, 13, 560, 12, null,   0, 400,
   '[[0,280],[5,700],[10,700],[20,1680],[40,1680],[100,3360]]'),
  ('bike',        'Bike',        'بائیک',       'MOTORCYCLE', false, 1, 4, true, 45, 45,  3,  3, 100,  3, 40,    0,   0,
   '[[0,40],[5,90],[10,90],[20,300],[40,300],[100,600]]'),
  ('rickshaw',    'Rickshaw',    'رکشہ',        'RICKSHAW',   false, 3, 5, true, 25, 25,  6,  6, 130,  5, 40,    0,   0,
   '[[0,60],[5,100],[10,100],[20,450],[40,450],[100,900]]'),
  ('loader',      'Loader',      'لوڈر',        'RICKSHAW',   false, 1, 6, true, 25, 25,  6,  6, 230,  5, 50,  100,   0,
   '[[0,60],[5,100],[10,100],[20,450],[40,450],[100,900]]');

-- Move what already points at the old codes to the new ones.
update public.vehicles set category = case category
    when 'MINI' then 'car_mini' when 'PREMIUM' then 'car_comfort' when 'COURIER' then 'loader'
    when 'BIKE' then 'bike' when 'RICKSHAW' then 'rickshaw' else category end
 where category in ('MINI', 'PREMIUM', 'COURIER', 'BIKE', 'RICKSHAW');
update public.ride_requests set category = case category
    when 'MINI' then 'car_mini' when 'PREMIUM' then 'car_comfort' when 'COURIER' then 'loader'
    when 'BIKE' then 'bike' when 'RICKSHAW' then 'rickshaw' else category end
 where category in ('MINI', 'PREMIUM', 'COURIER', 'BIKE', 'RICKSHAW');

alter table public.vehicles alter column category set default 'car_mini';
alter table public.ride_requests alter column category set default 'car_mini';

delete from public.vehicle_models;  -- reseeded below (the category codes changed)
delete from public.ride_categories where code in ('MINI', 'PREMIUM', 'COURIER', 'BIKE', 'RICKSHAW');

alter table public.ride_categories
  drop column base_fare,
  drop column per_km,
  drop column min_pct,
  drop column max_pct,
  alter column city_mileage set not null,
  alter column highway_mileage set not null,
  alter column city_maint set not null,
  alter column highway_maint set not null,
  alter column min_fare set not null,
  alter column waiting_per_min set not null,
  alter column profit_points set not null,
  add constraint ride_categories_mileage_check check (city_mileage > 0 and highway_mileage > 0);

grant update (name, name_ur, max_passengers, sort_order, is_active, is_car, city_mileage, highway_mileage,
              city_maint, highway_maint, min_fare, waiting_per_min, max_km, loading_charge,
              round_trip_wait_per_hour, profit_points)
  on public.ride_categories to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Fare settings (global)
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.settings (key, value, description) values
  ('petrol_price',            '400',  'Petrol price in Rs. per litre'),
  ('slab_km',                 '8',    'First km of a trip priced with the city mileage; after that the highway mileage'),
  ('return_factor',           '0.5',  'Share of the empty return trip added to the km after the slab'),
  ('min_offer_percent',       '85',   'Lowest offer, as a % of the recommended fare'),
  ('max_offer_percent',       '200',  'Highest offer, as a % of the recommended fare'),
  ('night_surcharge_percent', '20',   'Extra % on the fare during the night window'),
  ('night_start_hour',        '23',   'Night window starts at this hour (Pakistan time, 0-23)'),
  ('night_end_hour',          '6',    'Night window ends at this hour (Pakistan time, 0-23)'),
  ('waiting_free_minutes',    '5',    'Free waiting at the pickup before the waiting charge starts'),
  ('no_driver_notify_minutes','3',    'Tell the passenger to raise the fare if no driver has answered in this many minutes')
on conflict (key) do nothing;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) Vehicle models: model -> category (the category is never chosen by the driver)
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.vehicle_models (category, make, model) values
  ('car_mini',    'Suzuki', 'Mehran'),
  ('car_mini',    'Suzuki', 'Alto'),
  ('car_mini',    'Suzuki', 'Wagon R'),
  ('car_mini',    'Suzuki', 'Cultus'),
  ('car_mini',    'Suzuki', 'Swift'),
  ('car_comfort', 'Toyota', 'Corolla'),
  ('car_comfort', 'Honda',  'City'),
  ('car_comfort', 'Toyota', 'Yaris'),
  ('car_comfort', 'Honda',  'Civic'),
  ('car_xl',      'Suzuki', 'APV'),
  ('car_xl',      'Honda',  'BR-V'),
  ('car_xl',      'Suzuki', 'Bolan'),
  ('car_xl',      'Toyota', 'Hiace'),
  ('bike',        'Honda',  'CD 70'),
  ('bike',        'Honda',  'CG 125'),
  ('bike',        'Honda',  'Pridor'),
  ('bike',        'Honda',  'CB 125F'),
  ('bike',        'Yamaha', 'YB125Z'),
  ('bike',        'Suzuki', 'GD 110'),
  ('rickshaw',    'Qingqi', 'Auto Rickshaw'),
  ('rickshaw',    'Piaggio', 'Auto Rickshaw'),
  ('loader',      'Qingqi', 'Loader Rickshaw'),
  ('loader',      'Suzuki', 'Bolan Cargo');

-- A model belongs to exactly one category (so the category can follow from the model).
create unique index vehicle_models_make_model_idx
  on public.vehicle_models (lower(btrim(make)), lower(btrim(model)));

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) Drivers: their city; vehicles: AC
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.drivers add column city_id uuid references public.cities(id);
update public.drivers set city_id = current_city_id where city_id is null;
create index drivers_city_idx on public.drivers(city_id) where is_online;

-- A driver always has a city: fall back to the legacy field.
create or replace function public.drivers_default_city()
returns trigger
language plpgsql
as $$
begin
  if new.city_id is null then
    new.city_id := new.current_city_id;
  end if;
  return new;
end;
$$;
create trigger drivers_default_city_trg before insert or update on public.drivers
  for each row execute function public.drivers_default_city();

alter table public.vehicles add column ac_available boolean not null default false;
revoke insert, update on public.vehicles from authenticated;
grant insert (driver_id, vehicle_type, make, model, color, plate_number, seats, year, is_active, ac_available)
  on public.vehicles to authenticated;
grant update (vehicle_type, make, model, color, plate_number, seats, year, is_active, ac_available)
  on public.vehicles to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) What we keep on every request and ride, for review later
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.ride_requests
  add column city_id uuid references public.cities(id),
  add column recommended_fare numeric(10,2),
  add column min_offer_fare numeric(10,2),
  add column max_offer_fare numeric(10,2),
  add column is_night boolean not null default false,
  add column loading_selected boolean not null default false,
  add column toll_amount numeric(10,2) not null default 0,
  add column nudged_at timestamptz;

-- Requests made before this change (and the legacy route-based RPC) belong to the origin city.
update public.ride_requests set city_id = origin_city_id where city_id is null;
create or replace function public.ride_requests_default_city()
returns trigger
language plpgsql
as $$
begin
  if new.city_id is null then
    new.city_id := new.origin_city_id;
  end if;
  return new;
end;
$$;
create trigger ride_requests_default_city_trg before insert on public.ride_requests
  for each row execute function public.ride_requests_default_city();
create index ride_requests_city_idx on public.ride_requests(city_id, category)
  where status in ('REQUESTED', 'SEARCHING', 'OFFER_RECEIVED');

alter table public.rides
  add column city_id uuid references public.cities(id),
  add column category text references public.ride_categories(code),
  add column recommended_fare numeric(10,2),
  add column accepted_fare numeric(10,2),
  add column is_night boolean not null default false,
  add column arrived_at timestamptz,
  add column waiting_minutes int not null default 0,
  add column waiting_charge numeric(10,2) not null default 0;

-- A ride copies what it needs from its request when it is created.
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
  end if;
  new.accepted_fare := coalesce(new.accepted_fare, new.final_fare);
  return new;
end;
$$;
create trigger rides_copy_request_info_trg before insert on public.rides
  for each row execute function public.rides_copy_request_info();

update public.rides r set
  city_id = coalesce(q.city_id, q.origin_city_id), category = q.category,
  recommended_fare = q.recommended_fare, accepted_fare = r.final_fare, is_night = q.is_night
  from public.ride_requests q where q.id = r.request_id and r.category is null;
