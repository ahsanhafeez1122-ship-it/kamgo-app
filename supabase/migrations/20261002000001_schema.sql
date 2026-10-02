-- KAM GO — core schema
-- Every city / route is data, never code: adding a city or route needs no
-- app release.

create extension if not exists pgcrypto;

-- ─────────────────────────────────────────────────────────────────────────────
-- Enums
-- ─────────────────────────────────────────────────────────────────────────────
create type public.user_role as enum ('PASSENGER', 'DRIVER', 'ADMIN');
create type public.account_status as enum ('ACTIVE', 'SUSPENDED');
create type public.driver_status as enum ('PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED');
create type public.vehicle_type as enum ('CAR', 'RICKSHAW', 'VAN', 'MOTORCYCLE');
create type public.document_type as enum (
  'CNIC_FRONT', 'CNIC_BACK', 'LICENSE', 'VEHICLE_REGISTRATION', 'SELFIE', 'VEHICLE_PHOTO'
);
create type public.review_status as enum ('PENDING', 'APPROVED', 'REJECTED');

-- EXPIRED is an addition to the spec's list: a request nobody answered in
-- time needs a terminal state that is not a cancellation.
create type public.ride_status as enum (
  'REQUESTED', 'SEARCHING', 'OFFER_RECEIVED', 'DRIVER_SELECTED', 'CONFIRMED',
  'DRIVER_ARRIVING', 'RIDE_STARTED', 'COMPLETED', 'CANCELLED', 'NO_SHOW', 'EXPIRED'
);
create type public.offer_type as enum ('ACCEPT', 'COUNTER');
create type public.offer_status as enum (
  'PENDING', 'SELECTED', 'UNAVAILABLE', 'REJECTED', 'WITHDRAWN', 'EXPIRED'
);
create type public.cancellation_reason as enum (
  'PASSENGER_CANCELLED', 'DRIVER_CANCELLED', 'DRIVER_NO_SHOW', 'PASSENGER_NO_SHOW', 'ADMIN_CANCELLED'
);
create type public.ride_actor as enum ('PASSENGER', 'DRIVER', 'SYSTEM', 'ADMIN');
create type public.commission_status as enum ('DUE', 'PAID', 'WAIVED');
create type public.ledger_entry_type as enum ('COMMISSION_DUE', 'COMMISSION_PAID', 'ADJUSTMENT');
create type public.complaint_type as enum ('DRIVER', 'PASSENGER', 'RIDE', 'OTHER');
create type public.complaint_status as enum ('OPEN', 'IN_REVIEW', 'RESOLVED', 'DISMISSED');

-- ─────────────────────────────────────────────────────────────────────────────
-- updated_at helper
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Places
-- ─────────────────────────────────────────────────────────────────────────────
create table public.cities (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  name_ur     text,
  lat         double precision,
  lng         double precision,
  is_active   boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.service_areas (
  id          uuid primary key default gen_random_uuid(),
  city_id     uuid not null references public.cities(id) on delete cascade,
  name        text not null,
  lat         double precision,
  lng         double precision,
  radius_km   numeric(6,2) not null default 5 check (radius_km > 0),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (city_id, name)
);
create index service_areas_city_idx on public.service_areas(city_id);

create table public.routes (
  id                  uuid primary key default gen_random_uuid(),
  origin_city_id      uuid not null references public.cities(id),
  destination_city_id uuid not null references public.cities(id),
  distance_km         numeric(7,2) not null check (distance_km > 0),
  est_duration_min    int check (est_duration_min > 0),
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (origin_city_id, destination_city_id),
  check (origin_city_id <> destination_city_id)
);
create index routes_origin_idx on public.routes(origin_city_id) where is_active;
create index routes_destination_idx on public.routes(destination_city_id);

create table public.route_stops (
  id          uuid primary key default gen_random_uuid(),
  route_id    uuid not null references public.routes(id) on delete cascade,
  name        text not null,
  city_id     uuid references public.cities(id),
  lat         double precision,
  lng         double precision,
  stop_order  int not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (route_id, stop_order)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- People
-- ─────────────────────────────────────────────────────────────────────────────
create table public.profiles (
  id                       uuid primary key references auth.users(id) on delete cascade,
  role                     public.user_role not null default 'PASSENGER',
  full_name                text check (char_length(full_name) <= 80),
  phone                    text,
  avatar_url               text,
  emergency_contact_name   text check (char_length(emergency_contact_name) <= 80),
  emergency_contact_phone  text check (char_length(emergency_contact_phone) <= 20),
  preferred_language       text not null default 'en' check (preferred_language in ('en', 'ur')),
  account_status           public.account_status not null default 'ACTIVE',
  onboarded                boolean not null default false,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
create index profiles_role_idx on public.profiles(role);

create table public.admin_users (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  is_super    boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.passengers (
  id            uuid primary key references public.profiles(id) on delete cascade,
  home_city_id  uuid references public.cities(id),
  rating_avg    numeric(3,2) not null default 5.00,
  rating_count  int not null default 0,
  total_rides   int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.drivers (
  id                uuid primary key references public.profiles(id) on delete cascade,
  status            public.driver_status not null default 'PENDING',
  is_online         boolean not null default false,
  current_city_id   uuid references public.cities(id),
  cnic_number       text,
  rating_avg        numeric(3,2) not null default 5.00,
  rating_count      int not null default 0,
  total_rides       int not null default 0,
  last_online_at    timestamptz,
  approved_at       timestamptz,
  approved_by       uuid references public.profiles(id),
  rejection_reason  text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  -- Only approved drivers can ever be online.
  check (not is_online or status = 'APPROVED')
);
create index drivers_online_city_idx on public.drivers(current_city_id)
  where is_online and status = 'APPROVED';
create index drivers_status_idx on public.drivers(status);

create table public.vehicles (
  id            uuid primary key default gen_random_uuid(),
  driver_id     uuid not null references public.drivers(id) on delete cascade,
  vehicle_type  public.vehicle_type not null,
  make          text,
  model         text not null,
  color         text,
  plate_number  text not null unique,
  seats         int not null default 4 check (seats between 1 and 20),
  year          int check (year between 1980 and 2100),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index vehicles_driver_idx on public.vehicles(driver_id);

create table public.driver_documents (
  id            uuid primary key default gen_random_uuid(),
  driver_id     uuid not null references public.drivers(id) on delete cascade,
  doc_type      public.document_type not null,
  storage_path  text not null,
  status        public.review_status not null default 'PENDING',
  reviewed_by   uuid references public.profiles(id),
  reviewed_at   timestamptz,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index driver_documents_driver_idx on public.driver_documents(driver_id);

create table public.driver_routes (
  id          uuid primary key default gen_random_uuid(),
  driver_id   uuid not null references public.drivers(id) on delete cascade,
  route_id    uuid not null references public.routes(id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (driver_id, route_id)
);
create index driver_routes_route_idx on public.driver_routes(route_id);

create table public.driver_service_areas (
  id               uuid primary key default gen_random_uuid(),
  driver_id        uuid not null references public.drivers(id) on delete cascade,
  service_area_id  uuid not null references public.service_areas(id) on delete cascade,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (driver_id, service_area_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Rides
-- ─────────────────────────────────────────────────────────────────────────────
create table public.ride_requests (
  id                   uuid primary key default gen_random_uuid(),
  passenger_id         uuid not null references public.passengers(id),
  route_id             uuid not null references public.routes(id),
  origin_city_id       uuid not null references public.cities(id),
  destination_city_id  uuid not null references public.cities(id),
  pickup_label         text,
  pickup_lat           double precision,
  pickup_lng           double precision,
  dropoff_label        text,
  dropoff_lat          double precision,
  dropoff_lng          double precision,
  passenger_count      int not null check (passenger_count between 1 and 20),
  offered_fare         numeric(10,2) not null check (offered_fare > 0),
  distance_km          numeric(7,2) not null,
  status               public.ride_status not null default 'REQUESTED',
  expires_at           timestamptz not null,
  selected_offer_id    uuid,
  notes                text check (char_length(notes) <= 300),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index ride_requests_open_idx on public.ride_requests(origin_city_id, route_id, expires_at)
  where status in ('REQUESTED', 'SEARCHING', 'OFFER_RECEIVED');
create index ride_requests_passenger_idx on public.ride_requests(passenger_id, created_at desc);

create table public.ride_offers (
  id                     uuid primary key default gen_random_uuid(),
  request_id             uuid not null references public.ride_requests(id) on delete cascade,
  driver_id              uuid not null references public.drivers(id),
  vehicle_id             uuid references public.vehicles(id),
  offer_type             public.offer_type not null,
  fare                   numeric(10,2) not null check (fare > 0),
  status                 public.offer_status not null default 'PENDING',
  eta_min                int,
  distance_to_pickup_km  numeric(7,2),
  expires_at             timestamptz not null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);
-- One live offer per driver per request.
create unique index ride_offers_one_pending_idx on public.ride_offers(request_id, driver_id)
  where status = 'PENDING';
create index ride_offers_request_idx on public.ride_offers(request_id, created_at);
create index ride_offers_driver_idx on public.ride_offers(driver_id, created_at desc);

alter table public.ride_requests
  add constraint ride_requests_selected_offer_fk
  foreign key (selected_offer_id) references public.ride_offers(id);

create table public.rides (
  id                   uuid primary key default gen_random_uuid(),
  request_id           uuid not null unique references public.ride_requests(id),
  offer_id             uuid not null unique references public.ride_offers(id),
  passenger_id         uuid not null references public.passengers(id),
  driver_id            uuid not null references public.drivers(id),
  vehicle_id           uuid references public.vehicles(id),
  route_id             uuid not null references public.routes(id),
  origin_city_id       uuid not null references public.cities(id),
  destination_city_id  uuid not null references public.cities(id),
  passenger_count      int not null,
  final_fare           numeric(10,2) not null check (final_fare > 0),
  status               public.ride_status not null default 'CONFIRMED',
  confirmed_at         timestamptz not null default now(),
  arriving_at          timestamptz,
  started_at           timestamptz,
  completed_at         timestamptz,
  cancelled_at         timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index rides_passenger_idx on public.rides(passenger_id, created_at desc);
create index rides_driver_idx on public.rides(driver_id, created_at desc);
create index rides_status_idx on public.rides(status);
create index rides_route_completed_idx on public.rides(route_id) where status = 'COMPLETED';

-- The server-enforced state machine (who may move a ride from A to B).
create table public.ride_status_transitions (
  from_status  public.ride_status not null,
  to_status    public.ride_status not null,
  actor        public.ride_actor not null,
  primary key (from_status, to_status, actor)
);

create table public.ride_status_log (
  id           bigint generated always as identity primary key,
  request_id   uuid references public.ride_requests(id) on delete cascade,
  ride_id      uuid references public.rides(id) on delete cascade,
  from_status  public.ride_status,
  to_status    public.ride_status not null,
  changed_by   uuid references public.profiles(id),
  actor        public.ride_actor not null,
  note         text,
  created_at   timestamptz not null default now(),
  check (request_id is not null or ride_id is not null)
);
create index ride_status_log_request_idx on public.ride_status_log(request_id);
create index ride_status_log_ride_idx on public.ride_status_log(ride_id);

create table public.ride_locations (
  id           bigint generated always as identity primary key,
  ride_id      uuid not null references public.rides(id) on delete cascade,
  driver_id    uuid not null references public.drivers(id),
  lat          double precision not null check (lat between -90 and 90),
  lng          double precision not null check (lng between -180 and 180),
  heading      real,
  speed_kmh    real,
  recorded_at  timestamptz not null default now()
);
create index ride_locations_ride_idx on public.ride_locations(ride_id, recorded_at desc);

create table public.ratings (
  id          uuid primary key default gen_random_uuid(),
  ride_id     uuid not null references public.rides(id) on delete cascade,
  rater_id    uuid not null references public.profiles(id),
  ratee_id    uuid not null references public.profiles(id),
  stars       int not null check (stars between 1 and 5),
  comment     text check (char_length(comment) <= 500),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (ride_id, rater_id)
);
create index ratings_ratee_idx on public.ratings(ratee_id);

create table public.cancellations (
  id            uuid primary key default gen_random_uuid(),
  request_id    uuid references public.ride_requests(id) on delete cascade,
  ride_id       uuid references public.rides(id) on delete cascade,
  cancelled_by  uuid references public.profiles(id),
  reason        public.cancellation_reason not null,
  note          text,
  fee_amount    numeric(10,2) not null default 0 check (fee_amount >= 0),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (request_id is not null or ride_id is not null)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Money (server-written only — see RLS migration)
-- ─────────────────────────────────────────────────────────────────────────────
create table public.commissions (
  id                  uuid primary key default gen_random_uuid(),
  ride_id             uuid not null unique references public.rides(id),
  driver_id           uuid not null references public.drivers(id),
  final_fare          numeric(10,2) not null,
  commission_percent  numeric(5,2) not null check (commission_percent between 0 and 100),
  commission_amount   numeric(10,2) not null check (commission_amount >= 0),
  driver_earning      numeric(10,2) not null check (driver_earning >= 0),
  status              public.commission_status not null default 'DUE',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (commission_amount + driver_earning = final_fare)
);
create index commissions_driver_idx on public.commissions(driver_id, created_at desc);

-- Positive amount = driver owes KAM GO; negative = paid / credited.
create table public.driver_ledger (
  id             bigint generated always as identity primary key,
  driver_id      uuid not null references public.drivers(id),
  ride_id        uuid references public.rides(id),
  commission_id  uuid references public.commissions(id),
  entry_type     public.ledger_entry_type not null,
  amount         numeric(10,2) not null,
  balance_after  numeric(12,2) not null,
  note           text,
  created_at     timestamptz not null default now()
);
create index driver_ledger_driver_idx on public.driver_ledger(driver_id, id desc);

-- Stub for a future gateway / wallet. Nothing writes to it yet.
create table public.payments (
  id          uuid primary key default gen_random_uuid(),
  driver_id   uuid references public.drivers(id),
  amount      numeric(10,2) not null,
  method      text,
  status      text not null default 'PENDING',
  reference   text,
  meta        jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Engagement & support
-- ─────────────────────────────────────────────────────────────────────────────
create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  type        text not null,
  title       text not null,
  body        text,
  data        jsonb not null default '{}'::jsonb,
  read_at     timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index notifications_user_idx on public.notifications(user_id, created_at desc);

create table public.device_tokens (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  token         text not null unique,
  platform      text not null default 'android',
  last_seen_at  timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens(user_id);

create table public.complaints (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid not null references public.profiles(id),
  against_user_id  uuid references public.profiles(id),
  ride_id          uuid references public.rides(id),
  complaint_type   public.complaint_type not null,
  description      text not null check (char_length(description) between 5 and 2000),
  status           public.complaint_status not null default 'OPEN',
  admin_note       text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index complaints_status_idx on public.complaints(status, created_at desc);

create table public.saved_routes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  route_id    uuid not null references public.routes(id) on delete cascade,
  label       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, route_id)
);

create table public.settings (
  key          text primary key,
  value        jsonb not null,
  description  text,
  updated_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- updated_at triggers on every table that has the column
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  t text;
begin
  for t in
    select c.table_name
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name
    where c.table_schema = 'public'
      and c.column_name = 'updated_at'
      and tb.table_type = 'BASE TABLE'
  loop
    execute format(
      'create trigger %I before update on public.%I
         for each row execute function public.touch_updated_at()',
      t || '_touch_updated_at', t
    );
  end loop;
end;
$$;
