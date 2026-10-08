-- KAM GO — demo / launch data.
-- Safe to run on a fresh database after the migrations. Uses fixed UUIDs so
-- the README and TESTING.md can refer to them.
--
-- Demo logins (enable these as Supabase test phone numbers, OTP 123456):
--   923000000001  Admin            KAM GO Admin
--   923000000002  Passenger        Ali Raza        (has ride history)
--   923000000003  Passenger        Sana Bibi       (has an open request)
--   923000000011  Driver A         Imran Ahmed     APPROVED, online,  Pir Mahal
--   923000000012  Driver B         Bilal Hussain   APPROVED, online,  Pir Mahal
--   923000000013  Driver C         Usman Tariq     APPROVED, online,  Pir Mahal
--   923000000014  Driver D         Kashif Mehmood  APPROVED, offline, Kamalia
--   923000000015  Driver E         Naveed Akhtar   PENDING,           Rajana

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cities, service areas, routes
-- Coordinates and distances are approximate; adjust from the admin panel.
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.cities (id, name, name_ur, lat, lng, sort_order) values
  ('11111111-1111-4111-8111-000000000001', 'Kamalia',   'کمالیہ',  30.7258, 72.6447, 1),
  ('11111111-1111-4111-8111-000000000002', 'Pir Mahal', 'پیر محل', 30.7667, 72.4333, 2),
  ('11111111-1111-4111-8111-000000000003', 'Rajana',    'رجانہ',   30.7340, 72.3070, 3),
  ('11111111-1111-4111-8111-000000000004', 'Chichawatni', 'چیچہ وطنی', 30.5301, 72.6917, 4),
  ('11111111-1111-4111-8111-000000000005', 'Toba Tek Singh', 'ٹوبہ ٹیک سنگھ', 30.9709, 72.4826, 5)
on conflict (id) do nothing;

insert into public.service_areas (city_id, name, lat, lng, radius_km)
select id, name || ' City', lat, lng, 6 from public.cities
on conflict (city_id, name) do nothing;

insert into public.routes (id, origin_city_id, destination_city_id, distance_km, est_duration_min) values
  ('22222222-2222-4222-8222-000000000001', '11111111-1111-4111-8111-000000000001', '11111111-1111-4111-8111-000000000002', 25, 35),
  ('22222222-2222-4222-8222-000000000002', '11111111-1111-4111-8111-000000000002', '11111111-1111-4111-8111-000000000001', 25, 35),
  ('22222222-2222-4222-8222-000000000003', '11111111-1111-4111-8111-000000000002', '11111111-1111-4111-8111-000000000003', 22, 30),
  ('22222222-2222-4222-8222-000000000004', '11111111-1111-4111-8111-000000000003', '11111111-1111-4111-8111-000000000002', 22, 30),
  ('22222222-2222-4222-8222-000000000005', '11111111-1111-4111-8111-000000000001', '11111111-1111-4111-8111-000000000003', 45, 60),
  ('22222222-2222-4222-8222-000000000006', '11111111-1111-4111-8111-000000000003', '11111111-1111-4111-8111-000000000001', 45, 60)
on conflict (id) do nothing;

-- ─────────────────────────────────────────────────────────────────────────────
-- Demo auth users (phone-only). The on_auth_user_created trigger creates the
-- matching profiles + passengers rows.
-- ─────────────────────────────────────────────────────────────────────────────
with demo(id, phone) as (values
  ('33333333-3333-4333-8333-000000000001'::uuid, '923000000001'),
  ('33333333-3333-4333-8333-000000000002'::uuid, '923000000002'),
  ('33333333-3333-4333-8333-000000000003'::uuid, '923000000003'),
  ('33333333-3333-4333-8333-000000000011'::uuid, '923000000011'),
  ('33333333-3333-4333-8333-000000000012'::uuid, '923000000012'),
  ('33333333-3333-4333-8333-000000000013'::uuid, '923000000013'),
  ('33333333-3333-4333-8333-000000000014'::uuid, '923000000014'),
  ('33333333-3333-4333-8333-000000000015'::uuid, '923000000015'),
  ('33333333-3333-4333-8333-000000000016'::uuid, '923000000016'),
  ('33333333-3333-4333-8333-000000000017'::uuid, '923000000017'),
  ('33333333-3333-4333-8333-000000000018'::uuid, '923000000018'),
  ('33333333-3333-4333-8333-000000000019'::uuid, '923000000019')
)
insert into auth.users (
  instance_id, id, aud, role, phone, phone_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  phone_change, phone_change_token, email_change_token_current, reauthentication_token
)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', phone, now(),
       '{"provider":"phone","providers":["phone"]}'::jsonb, '{}'::jsonb, now(), now(),
       '', '', '', '', '', '', '', ''
from demo
on conflict (id) do nothing;

insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select u.id, u.id::text, u.id,
       jsonb_build_object('sub', u.id::text, 'phone', u.phone, 'phone_verified', true),
       'phone', now(), now(), now()
from auth.users u
where u.id::text like '33333333-3333-4333-8333-%'
on conflict do nothing;

-- ─────────────────────────────────────────────────────────────────────────────
-- Profiles, roles, drivers, vehicles
-- ─────────────────────────────────────────────────────────────────────────────
update public.profiles p
   set full_name = d.name, role = d.role::public.user_role, onboarded = true
  from (values
    ('33333333-3333-4333-8333-000000000001'::uuid, 'KAM GO Admin',   'ADMIN'),
    ('33333333-3333-4333-8333-000000000002'::uuid, 'Ali Raza',       'PASSENGER'),
    ('33333333-3333-4333-8333-000000000003'::uuid, 'Sana Bibi',      'PASSENGER'),
    ('33333333-3333-4333-8333-000000000011'::uuid, 'Imran Ahmed',    'DRIVER'),
    ('33333333-3333-4333-8333-000000000012'::uuid, 'Bilal Hussain',  'DRIVER'),
    ('33333333-3333-4333-8333-000000000013'::uuid, 'Usman Tariq',    'DRIVER'),
    ('33333333-3333-4333-8333-000000000014'::uuid, 'Kashif Mehmood', 'DRIVER'),
    ('33333333-3333-4333-8333-000000000015'::uuid, 'Naveed Akhtar',  'DRIVER'),
    ('33333333-3333-4333-8333-000000000016'::uuid, 'Zeeshan Bike',   'DRIVER'),
    ('33333333-3333-4333-8333-000000000017'::uuid, 'Rafiq Rickshaw', 'DRIVER'),
    ('33333333-3333-4333-8333-000000000018'::uuid, 'Akram Loader',   'DRIVER'),
    ('33333333-3333-4333-8333-000000000019'::uuid, 'Faisal XL',      'DRIVER')
  ) as d(id, name, role)
 where p.id = d.id;

update public.passengers set home_city_id = '11111111-1111-4111-8111-000000000002'
 where id in ('33333333-3333-4333-8333-000000000002', '33333333-3333-4333-8333-000000000003');

insert into public.admin_users (user_id, is_super)
values ('33333333-3333-4333-8333-000000000001', true)
on conflict (user_id) do nothing;

insert into public.drivers (id, status, is_online, current_city_id, cnic_number, rating_avg, rating_count, approved_at, approved_by, last_online_at) values
  ('33333333-3333-4333-8333-000000000011', 'APPROVED', true,  '11111111-1111-4111-8111-000000000002', '33100-0000011-1', 4.80, 0, now(), '33333333-3333-4333-8333-000000000001', now()),
  ('33333333-3333-4333-8333-000000000012', 'APPROVED', true,  '11111111-1111-4111-8111-000000000002', '33100-0000012-1', 4.90, 0, now(), '33333333-3333-4333-8333-000000000001', now()),
  ('33333333-3333-4333-8333-000000000013', 'APPROVED', true,  '11111111-1111-4111-8111-000000000002', '33100-0000013-1', 4.60, 0, now(), '33333333-3333-4333-8333-000000000001', now()),
  ('33333333-3333-4333-8333-000000000014', 'APPROVED', false, '11111111-1111-4111-8111-000000000001', '33100-0000014-1', 4.70, 0, now(), '33333333-3333-4333-8333-000000000001', null),
  ('33333333-3333-4333-8333-000000000015', 'PENDING',  false, '11111111-1111-4111-8111-000000000003', '33100-0000015-1', 5.00, 0, null,  null, null),
  ('33333333-3333-4333-8333-000000000016', 'APPROVED', true,  '11111111-1111-4111-8111-000000000002', '33100-0000016-1', 4.70, 0, now(), '33333333-3333-4333-8333-000000000001', now()),
  ('33333333-3333-4333-8333-000000000017', 'APPROVED', true,  '11111111-1111-4111-8111-000000000002', '33100-0000017-1', 4.60, 0, now(), '33333333-3333-4333-8333-000000000001', now()),
  ('33333333-3333-4333-8333-000000000018', 'APPROVED', true,  '11111111-1111-4111-8111-000000000002', '33100-0000018-1', 4.50, 0, now(), '33333333-3333-4333-8333-000000000001', now()),
  ('33333333-3333-4333-8333-000000000019', 'APPROVED', true,  '11111111-1111-4111-8111-000000000002', '33100-0000019-1', 4.80, 0, now(), '33333333-3333-4333-8333-000000000001', now())
on conflict (id) do nothing;

insert into public.vehicles (id, driver_id, vehicle_type, make, model, color, plate_number, seats, year) values
  ('44444444-4444-4444-8444-000000000011', '33333333-3333-4333-8333-000000000011', 'CAR',      'Suzuki', 'Alto',    'White',  'TTA-1101', 4,  2021),
  ('44444444-4444-4444-8444-000000000012', '33333333-3333-4333-8333-000000000012', 'CAR',      'Suzuki', 'Cultus',  'Silver', 'TTA-1202', 4,  2018),
  ('44444444-4444-4444-8444-000000000013', '33333333-3333-4333-8333-000000000013', 'CAR',      'Suzuki', 'Wagon R', 'White',  'TTA-1303', 4,  2019),
  ('44444444-4444-4444-8444-000000000014', '33333333-3333-4333-8333-000000000014', 'CAR',      'Honda',  'Civic',   'Black',  'TTA-1404', 4,  2020),
  ('44444444-4444-4444-8444-000000000015', '33333333-3333-4333-8333-000000000015', 'RICKSHAW', 'Qingqi', 'Auto Rickshaw','Green',  'TTA-1505', 3,  2022),
  ('44444444-4444-4444-8444-000000000016', '33333333-3333-4333-8333-000000000016', 'MOTORCYCLE', 'Honda', 'CD 70',   'Red',    'TTA-1606', 1,  2022),
  ('44444444-4444-4444-8444-000000000017', '33333333-3333-4333-8333-000000000017', 'RICKSHAW', 'Qingqi', 'Auto Rickshaw','Yellow', 'TTA-1707', 3,  2021),
  ('44444444-4444-4444-8444-000000000018', '33333333-3333-4333-8333-000000000018', 'RICKSHAW', 'Suzuki', 'Bolan Cargo', 'Blue', 'TTA-1808', 1, 2020),
  ('44444444-4444-4444-8444-000000000019', '33333333-3333-4333-8333-000000000019', 'VAN',      'Honda',  'BR-V',    'White', 'TTA-1909', 7, 2021)
on conflict (id) do nothing;

-- Ride categories (set from each vehicle's model by the app; here by plate for the demo data) and cities.
-- Car Mini: Imran (Alto), Bilal (Cultus), Usman (Wagon R).  Car Comfort: Kashif (Civic, offline).
-- Rickshaw: Naveed (pending), Rafiq.  Bike: Zeeshan.  Loader: Akram.  Car XL: Faisal (BR-V).
update public.vehicles set category = 'car_mini'    where plate_number in ('TTA-1101', 'TTA-1202', 'TTA-1303');
update public.vehicles set category = 'car_comfort', ac_available = true where plate_number = 'TTA-1404';
update public.vehicles set category = 'car_xl',      ac_available = true where plate_number = 'TTA-1909';
update public.vehicles set category = 'rickshaw'    where plate_number in ('TTA-1505', 'TTA-1707');
update public.vehicles set category = 'bike'        where plate_number = 'TTA-1606';
update public.vehicles set category = 'loader'      where plate_number = 'TTA-1808';

-- Each driver belongs to one city (dispatch is city + category). Toba Tek Singh has one driver of
-- every type; Kamalia and Pir Mahal have a Mini driver each.
update public.drivers set city_id = '11111111-1111-4111-8111-000000000005' where id in (
  '33333333-3333-4333-8333-000000000012', '33333333-3333-4333-8333-000000000014',
  '33333333-3333-4333-8333-000000000016', '33333333-3333-4333-8333-000000000017',
  '33333333-3333-4333-8333-000000000018', '33333333-3333-4333-8333-000000000019');
update public.drivers set city_id = '11111111-1111-4111-8111-000000000001' where id = '33333333-3333-4333-8333-000000000011';
update public.drivers set city_id = '11111111-1111-4111-8111-000000000002' where id = '33333333-3333-4333-8333-000000000013';
update public.drivers set city_id = '11111111-1111-4111-8111-000000000003' where id = '33333333-3333-4333-8333-000000000015';
update public.drivers set current_city_id = city_id;
-- Preferred routes. A, B, C work the Pir Mahal ⇄ Rajana corridor (and A also
-- Pir Mahal → Kamalia); D works Kamalia ⇄ Pir Mahal; E has none yet.
insert into public.driver_routes (driver_id, route_id) values
  ('33333333-3333-4333-8333-000000000011', '22222222-2222-4222-8222-000000000003'),
  ('33333333-3333-4333-8333-000000000011', '22222222-2222-4222-8222-000000000004'),
  ('33333333-3333-4333-8333-000000000011', '22222222-2222-4222-8222-000000000002'),
  ('33333333-3333-4333-8333-000000000012', '22222222-2222-4222-8222-000000000003'),
  ('33333333-3333-4333-8333-000000000012', '22222222-2222-4222-8222-000000000004'),
  ('33333333-3333-4333-8333-000000000013', '22222222-2222-4222-8222-000000000003'),
  ('33333333-3333-4333-8333-000000000013', '22222222-2222-4222-8222-000000000004'),
  ('33333333-3333-4333-8333-000000000014', '22222222-2222-4222-8222-000000000001'),
  ('33333333-3333-4333-8333-000000000014', '22222222-2222-4222-8222-000000000002')
on conflict (driver_id, route_id) do nothing;

-- ─────────────────────────────────────────────────────────────────────────────
-- History: two completed rides for Ali Raza, with commission + ledger rows
-- calculated exactly as complete_ride() will (fare × % / 100, to paisa).
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.ride_requests (id, passenger_id, route_id, origin_city_id, destination_city_id,
  pickup_label, dropoff_label, passenger_count, offered_fare, distance_km, status, expires_at, created_at) values
  ('55555555-5555-4555-8555-000000000001', '33333333-3333-4333-8333-000000000002',
   '22222222-2222-4222-8222-000000000001', '11111111-1111-4111-8111-000000000001', '11111111-1111-4111-8111-000000000002',
   'Kamalia Chowk', 'Pir Mahal Bus Adda', 1, 750, 25, 'CONFIRMED', now() - interval '3 days', now() - interval '3 days 20 minutes'),
  ('55555555-5555-4555-8555-000000000002', '33333333-3333-4333-8333-000000000002',
   '22222222-2222-4222-8222-000000000003', '11111111-1111-4111-8111-000000000002', '11111111-1111-4111-8111-000000000003',
   'Pir Mahal Bus Adda', 'Rajana Main Bazaar', 2, 1100, 22, 'CONFIRMED', now() - interval '1 day', now() - interval '1 day 20 minutes')
on conflict (id) do nothing;

insert into public.ride_offers (id, request_id, driver_id, vehicle_id, offer_type, fare, status, eta_min, distance_to_pickup_km, expires_at, created_at) values
  ('66666666-6666-4666-8666-000000000001', '55555555-5555-4555-8555-000000000001', '33333333-3333-4333-8333-000000000014',
   '44444444-4444-4444-8444-000000000014', 'COUNTER', 800, 'SELECTED', 6, 1.8, now() - interval '3 days', now() - interval '3 days 18 minutes'),
  ('66666666-6666-4666-8666-000000000002', '55555555-5555-4555-8555-000000000002', '33333333-3333-4333-8333-000000000011',
   '44444444-4444-4444-8444-000000000011', 'ACCEPT', 1100, 'UNAVAILABLE', 4, 1.1, now() - interval '1 day', now() - interval '1 day 18 minutes'),
  ('66666666-6666-4666-8666-000000000003', '55555555-5555-4555-8555-000000000002', '33333333-3333-4333-8333-000000000012',
   '44444444-4444-4444-8444-000000000012', 'COUNTER', 1200, 'SELECTED', 5, 1.4, now() - interval '1 day', now() - interval '1 day 17 minutes')
on conflict (id) do nothing;

update public.ride_requests set selected_offer_id = '66666666-6666-4666-8666-000000000001'
 where id = '55555555-5555-4555-8555-000000000001';
update public.ride_requests set selected_offer_id = '66666666-6666-4666-8666-000000000003'
 where id = '55555555-5555-4555-8555-000000000002';

insert into public.rides (id, request_id, offer_id, passenger_id, driver_id, vehicle_id, route_id,
  origin_city_id, destination_city_id, passenger_count, final_fare, status,
  confirmed_at, started_at, completed_at, created_at) values
  ('77777777-7777-4777-8777-000000000001', '55555555-5555-4555-8555-000000000001', '66666666-6666-4666-8666-000000000001',
   '33333333-3333-4333-8333-000000000002', '33333333-3333-4333-8333-000000000014', '44444444-4444-4444-8444-000000000014',
   '22222222-2222-4222-8222-000000000001', '11111111-1111-4111-8111-000000000001', '11111111-1111-4111-8111-000000000002',
   1, 800, 'COMPLETED',
   now() - interval '3 days 15 minutes', now() - interval '3 days 5 minutes', now() - interval '3 days' + interval '30 minutes',
   now() - interval '3 days 15 minutes'),
  ('77777777-7777-4777-8777-000000000002', '55555555-5555-4555-8555-000000000002', '66666666-6666-4666-8666-000000000003',
   '33333333-3333-4333-8333-000000000002', '33333333-3333-4333-8333-000000000012', '44444444-4444-4444-8444-000000000012',
   '22222222-2222-4222-8222-000000000003', '11111111-1111-4111-8111-000000000002', '11111111-1111-4111-8111-000000000003',
   2, 1200, 'COMPLETED',
   now() - interval '1 day 15 minutes', now() - interval '1 day 5 minutes', now() - interval '1 day' + interval '25 minutes',
   now() - interval '1 day 15 minutes')
on conflict (id) do nothing;

insert into public.ride_status_log (ride_id, request_id, from_status, to_status, actor, changed_by, created_at)
select r.id, r.request_id, s.from_s::public.ride_status, s.to_s::public.ride_status, s.actor::public.ride_actor,
       case s.actor when 'DRIVER' then r.driver_id when 'PASSENGER' then r.passenger_id end,
       r.confirmed_at + s.offset_i
from public.rides r
cross join (values
  (null,              'REQUESTED',       'PASSENGER', interval '-5 minutes'),
  ('OFFER_RECEIVED',  'DRIVER_SELECTED', 'PASSENGER', interval '0'),
  ('DRIVER_SELECTED', 'CONFIRMED',       'SYSTEM',    interval '0'),
  ('CONFIRMED',       'RIDE_STARTED',    'DRIVER',    interval '10 minutes'),
  ('RIDE_STARTED',    'COMPLETED',       'DRIVER',    interval '45 minutes')
) as s(from_s, to_s, actor, offset_i)
where r.id in ('77777777-7777-4777-8777-000000000001', '77777777-7777-4777-8777-000000000002')
  and not exists (select 1 from public.ride_status_log l where l.ride_id = r.id);

insert into public.commissions (id, ride_id, driver_id, final_fare, commission_percent, commission_amount, driver_earning)
select gen_random_uuid(), r.id, r.driver_id, r.final_fare, pct,
       round(r.final_fare * pct / 100, 2),
       r.final_fare - round(r.final_fare * pct / 100, 2)
from public.rides r
cross join (select public.setting_num('commission_percent', 10) as pct) s
where r.status = 'COMPLETED'
on conflict (ride_id) do nothing;

insert into public.driver_ledger (driver_id, ride_id, commission_id, entry_type, amount, balance_after, note, created_at)
select c.driver_id, c.ride_id, c.id, 'COMMISSION_DUE', c.commission_amount,
       sum(c.commission_amount) over (partition by c.driver_id order by c.created_at, c.id),
       'Commission on completed ride', c.created_at
from public.commissions c
where not exists (select 1 from public.driver_ledger l where l.commission_id = c.id);

insert into public.ratings (ride_id, rater_id, ratee_id, stars, comment) values
  ('77777777-7777-4777-8777-000000000001', '33333333-3333-4333-8333-000000000002', '33333333-3333-4333-8333-000000000014', 5, 'On time, clean car.'),
  ('77777777-7777-4777-8777-000000000002', '33333333-3333-4333-8333-000000000002', '33333333-3333-4333-8333-000000000012', 5, 'Very polite driver.'),
  ('77777777-7777-4777-8777-000000000002', '33333333-3333-4333-8333-000000000012', '33333333-3333-4333-8333-000000000002', 5, null)
on conflict (ride_id, rater_id) do nothing;

update public.drivers d
   set total_rides = s.n, rating_count = s.rc
  from (
    select r.driver_id,
           count(*) as n,
           (select count(*) from public.ratings ra where ra.ratee_id = r.driver_id) as rc
    from public.rides r where r.status = 'COMPLETED' group by r.driver_id
  ) s
 where d.id = s.driver_id;

update public.passengers set total_rides = 2 where id = '33333333-3333-4333-8333-000000000002';

-- ─────────────────────────────────────────────────────────────────────────────
-- A live open request (Sana, Pir Mahal → Kamalia) with two offers, so the
-- adda counters and offer lists have something to show. It expires 30 min
-- after seeding — re-run the block below to refresh it.
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.ride_requests (id, passenger_id, route_id, origin_city_id, destination_city_id,
  pickup_label, dropoff_label, passenger_count, offered_fare, distance_km, status, expires_at) values
  ('55555555-5555-4555-8555-000000000010', '33333333-3333-4333-8333-000000000003',
   '22222222-2222-4222-8222-000000000002', '11111111-1111-4111-8111-000000000002', '11111111-1111-4111-8111-000000000001',
   'Pir Mahal Railway Road', 'Kamalia Chowk', 1, 700, 25, 'OFFER_RECEIVED', now() + interval '30 minutes')
on conflict (id) do update set expires_at = excluded.expires_at, status = 'OFFER_RECEIVED';

insert into public.ride_offers (id, request_id, driver_id, vehicle_id, offer_type, fare, status, eta_min, distance_to_pickup_km, expires_at) values
  ('66666666-6666-4666-8666-000000000010', '55555555-5555-4555-8555-000000000010', '33333333-3333-4333-8333-000000000011',
   '44444444-4444-4444-8444-000000000011', 'ACCEPT', 700, 'PENDING', 4, 1.2, now() + interval '3 minutes'),
  ('66666666-6666-4666-8666-000000000011', '55555555-5555-4555-8555-000000000010', '33333333-3333-4333-8333-000000000013',
   '44444444-4444-4444-8444-000000000013', 'COUNTER', 850, 'PENDING', 7, 2.6, now() + interval '3 minutes')
on conflict (id) do update set expires_at = excluded.expires_at, status = 'PENDING';

insert into public.ride_status_log (request_id, from_status, to_status, actor, changed_by)
select '55555555-5555-4555-8555-000000000010', null, 'REQUESTED', 'PASSENGER', '33333333-3333-4333-8333-000000000003'
where not exists (select 1 from public.ride_status_log where request_id = '55555555-5555-4555-8555-000000000010');

-- ─────────────────────────────────────────────────────────────────────────────
-- A couple of in-app notifications
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.notifications (user_id, type, title, body, read_at, created_at)
select * from (values
  ('33333333-3333-4333-8333-000000000002'::uuid, 'RIDE_COMPLETED', 'Ride completed',
   'Pir Mahal → Rajana with Bilal Hussain · Rs. 1,200', now() - interval '1 day', now() - interval '1 day'),
  ('33333333-3333-4333-8333-000000000002'::uuid, 'WELCOME', 'Welcome to KAM GO',
   'Apni Ride, Apna Fare. Offer your fare and pick your driver.', null::timestamptz, now() - interval '2 hours'),
  ('33333333-3333-4333-8333-000000000015'::uuid, 'DRIVER_PENDING', 'Application received',
   'KAM GO is reviewing your documents. We will notify you once approved.', null::timestamptz, now())
) as n(user_id, type, title, body, read_at, created_at)
where not exists (select 1 from public.notifications x where x.user_id = n.user_id and x.type = n.type);

commit;
