-- KAM GO — driver onboarding, online/offline, earnings, admin (Phases 4 & 5).

-- ─────────────────────────────────────────────────────────────────────────────
-- Storage: private driver documents, public avatars. Files live under
-- "<user id>/…" and users can only write inside their own folder.
-- ─────────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('driver-documents', 'driver-documents', false, 1048576, array['image/jpeg', 'image/png', 'image/webp']),
  ('avatars', 'avatars', true, 524288, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "driver docs: owner uploads" on storage.objects for insert to authenticated
  with check (bucket_id = 'driver-documents' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "driver docs: owner or admin reads" on storage.objects for select to authenticated
  using (bucket_id = 'driver-documents'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

create policy "avatars: owner uploads" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars: owner replaces" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars: anyone signed in reads" on storage.objects for select to authenticated
  using (bucket_id = 'avatars');

-- ─────────────────────────────────────────────────────────────────────────────
-- Settings validation (admins edit these from the web panel)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.validate_setting()
returns trigger
language plpgsql
as $$
declare
  n numeric;
begin
  if new.key in ('commission_percent', 'offer_expiry_minutes', 'request_expiry_minutes',
                 'min_fare_per_km', 'max_fare_per_km', 'max_passengers',
                 'cancellation_fee_amount', 'search_radius_km') then
    begin
      n := (new.value #>> '{}')::numeric;
    exception when others then
      raise exception '% must be a number', new.key using errcode = '22023';
    end;
    if new.key = 'commission_percent' and (n < 0 or n > 50) then
      raise exception 'Commission must be between 0 and 50%%' using errcode = '22023';
    elsif new.key in ('offer_expiry_minutes', 'request_expiry_minutes') and (n < 1 or n > 120) then
      raise exception '% must be 1–120 minutes', new.key using errcode = '22023';
    elsif new.key = 'max_passengers' and (n < 1 or n > 20) then
      raise exception 'Max passengers must be 1–20' using errcode = '22023';
    elsif n < 0 then
      raise exception '% cannot be negative', new.key using errcode = '22023';
    end if;
    if new.key = 'min_fare_per_km' and n > setting_num('max_fare_per_km', 100) then
      raise exception 'Minimum fare per km cannot exceed the maximum' using errcode = '22023';
    elsif new.key = 'max_fare_per_km' and n < setting_num('min_fare_per_km', 20) then
      raise exception 'Maximum fare per km cannot be below the minimum' using errcode = '22023';
    end if;
  elsif new.key = 'cancellation_fee_enabled' and jsonb_typeof(new.value) <> 'boolean' then
    raise exception 'cancellation_fee_enabled must be true or false' using errcode = '22023';
  end if;
  new.updated_by := auth.uid();
  return new;
end;
$$;

create trigger settings_validate before insert or update on public.settings
  for each row execute function public.validate_setting();

-- ─────────────────────────────────────────────────────────────────────────────
-- Driver registration (Phase 4). Allowed while PENDING or REJECTED; a
-- rejected driver who resubmits goes back to PENDING.
-- ─────────────────────────────────────────────────────────────────────────────
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
  p_route_ids uuid[],
  p_service_area_ids uuid[] default '{}'
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
  if coalesce(array_length(p_route_ids, 1), 0) = 0 then
    raise exception 'Choose at least one route you drive' using errcode = '22023';
  end if;

  update drivers set
    cnic_number = substr(v_cnic, 1, 5) || '-' || substr(v_cnic, 6, 7) || '-' || substr(v_cnic, 13, 1),
    current_city_id = p_city_id,
    status = 'PENDING',
    rejection_reason = null
  where id = v_uid
  returning * into v_driver;

  insert into vehicles (driver_id, vehicle_type, make, model, color, plate_number, seats, year)
  values (v_uid, p_vehicle_type, nullif(btrim(p_vehicle_make), ''), btrim(p_vehicle_model),
          nullif(btrim(p_vehicle_color), ''), v_plate, p_seats, p_vehicle_year)
  on conflict (plate_number) do update set
    vehicle_type = excluded.vehicle_type, make = excluded.make, model = excluded.model,
    color = excluded.color, seats = excluded.seats, year = excluded.year, is_active = true;
  update vehicles set is_active = false where driver_id = v_uid and plate_number <> v_plate;

  delete from driver_routes where driver_id = v_uid;
  insert into driver_routes (driver_id, route_id)
  select v_uid, r.id from routes r where r.id = any(p_route_ids) and r.is_active;

  delete from driver_service_areas where driver_id = v_uid;
  insert into driver_service_areas (driver_id, service_area_id)
  select v_uid, s.id from service_areas s where s.id = any(coalesce(p_service_area_ids, '{}')) and s.is_active;

  return v_driver;
end;
$$;

-- Approved drivers can change their preferred routes any time.
create or replace function public.set_driver_routes(p_route_ids uuid[])
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
  if coalesce(array_length(p_route_ids, 1), 0) = 0 then
    raise exception 'Choose at least one route' using errcode = '22023';
  end if;
  delete from driver_routes where driver_id = v_uid;
  insert into driver_routes (driver_id, route_id)
  select v_uid, r.id from routes r where r.id = any(p_route_ids) and r.is_active;
end;
$$;

create or replace function public.set_driver_online(p_online boolean, p_city_id uuid default null)
returns public.drivers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_driver drivers;
begin
  select * into v_driver from drivers where id = v_uid for update;
  if not found then
    raise exception 'Drivers only' using errcode = '42501';
  end if;
  if p_online then
    if v_driver.status <> 'APPROVED' then
      raise exception 'You can go online once KAM GO approves your account' using errcode = '42501';
    end if;
    if not exists (select 1 from vehicles where driver_id = v_uid and is_active) then
      raise exception 'Add your vehicle first' using errcode = '22023';
    end if;
    if p_city_id is not null and not exists (select 1 from cities where id = p_city_id and is_active) then
      raise exception 'Unknown city' using errcode = '22023';
    end if;
  else
    -- Going offline withdraws live offers so passengers don't pick a ghost.
    update ride_offers set status = 'WITHDRAWN' where driver_id = v_uid and status = 'PENDING';
  end if;

  update drivers set
    is_online = p_online,
    current_city_id = coalesce(p_city_id, current_city_id),
    last_online_at = case when p_online then now() else last_online_at end
  where id = v_uid
  returning * into v_driver;
  return v_driver;
end;
$$;

-- Everything the driver dashboard + earnings tab need, in one call.
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
    'vehicle', (select jsonb_build_object('type', vehicle_type, 'make', make, 'model', model,
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Admin (Phase 5). Every function checks is_admin() itself.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.require_admin()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.admin_set_driver_status(
  p_driver_id uuid, p_status public.driver_status, p_reason text default null
)
returns public.drivers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver drivers;
begin
  perform require_admin();
  select * into v_driver from drivers where id = p_driver_id for update;
  if not found then
    raise exception 'Driver not found' using errcode = 'P0002';
  end if;
  if p_status = 'APPROVED' and not exists (select 1 from vehicles where driver_id = p_driver_id and is_active) then
    raise exception 'Driver has no vehicle on file' using errcode = '22023';
  end if;
  if p_status in ('REJECTED', 'SUSPENDED') and nullif(btrim(p_reason), '') is null then
    raise exception 'Please give a reason' using errcode = '22023';
  end if;

  update drivers set
    status = p_status,
    is_online = case when p_status = 'APPROVED' then is_online else false end,
    approved_at = case when p_status = 'APPROVED' then now() else approved_at end,
    approved_by = case when p_status = 'APPROVED' then auth.uid() else approved_by end,
    rejection_reason = case when p_status in ('REJECTED', 'SUSPENDED') then btrim(p_reason) end
  where id = p_driver_id
  returning * into v_driver;

  if p_status <> 'APPROVED' then
    update ride_offers set status = 'WITHDRAWN' where driver_id = p_driver_id and status = 'PENDING';
  end if;
  update driver_documents set
    status = case p_status when 'APPROVED' then 'APPROVED'::review_status
                           when 'REJECTED' then 'REJECTED'::review_status else status end,
    reviewed_by = auth.uid(), reviewed_at = now()
  where driver_id = p_driver_id and status = 'PENDING' and p_status in ('APPROVED', 'REJECTED');

  perform notify(p_driver_id, 'DRIVER_' || p_status::text,
    case p_status
      when 'APPROVED' then 'You are approved!'
      when 'REJECTED' then 'Application not approved'
      when 'SUSPENDED' then 'Account suspended'
      else 'Application under review' end,
    case p_status
      when 'APPROVED' then 'Go online to start receiving ride requests.'
      else coalesce(btrim(p_reason), 'KAM GO will contact you.') end);
  return v_driver;
end;
$$;

create or replace function public.admin_set_account_status(p_user_id uuid, p_status public.account_status)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile profiles;
begin
  perform require_admin();
  if p_user_id = auth.uid() then
    raise exception 'You cannot suspend yourself' using errcode = '22023';
  end if;
  update profiles set account_status = p_status where id = p_user_id returning * into v_profile;
  if not found then
    raise exception 'User not found' using errcode = 'P0002';
  end if;
  if p_status = 'SUSPENDED' then
    update drivers set is_online = false where id = p_user_id;
    update ride_offers set status = 'WITHDRAWN' where driver_id = p_user_id and status = 'PENDING';
  end if;
  return v_profile;
end;
$$;

-- Cash collected from a driver for commission they owed.
create or replace function public.admin_record_commission_payment(
  p_driver_id uuid, p_amount numeric, p_note text default null
)
returns public.driver_ledger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance numeric;
  v_row driver_ledger;
begin
  perform require_admin();
  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be positive' using errcode = '22023';
  end if;
  perform 1 from drivers where id = p_driver_id for update;
  if not found then
    raise exception 'Driver not found' using errcode = 'P0002';
  end if;
  select coalesce((select balance_after from driver_ledger where driver_id = p_driver_id
                   order by id desc limit 1), 0) - p_amount into v_balance;
  insert into driver_ledger (driver_id, entry_type, amount, balance_after, note)
  values (p_driver_id, 'COMMISSION_PAID', -p_amount, v_balance,
          coalesce(nullif(btrim(p_note), ''), 'Cash collected by KAM GO'))
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Karachi') at time zone 'Asia/Karachi';
begin
  perform require_admin();
  return jsonb_build_object(
    'passengers', (select count(*) from profiles where role = 'PASSENGER' and onboarded),
    'drivers', (select count(*) from drivers),
    'online_drivers', (select count(*) from drivers where is_online and status = 'APPROVED'),
    'pending_drivers', (select count(*) from drivers where status = 'PENDING'),
    'rides_today', (select count(*) from rides where created_at >= v_today),
    'completed_rides', (select count(*) from rides where status = 'COMPLETED'),
    'cancelled_rides', (select count(*) from rides where status in ('CANCELLED', 'NO_SHOW')),
    'open_requests', (select count(*) from ride_requests
                      where status in ('REQUESTED', 'SEARCHING', 'OFFER_RECEIVED') and expires_at > now()),
    'total_ride_value', coalesce((select sum(final_fare) from rides where status = 'COMPLETED'), 0),
    'total_commission', coalesce((select sum(commission_amount) from commissions), 0),
    'commission_outstanding', coalesce((select sum(b) from (
        select distinct on (driver_id) balance_after as b from driver_ledger order by driver_id, id desc) x), 0),
    'active_cities', (select count(*) from cities where is_active),
    'open_complaints', (select count(*) from complaints where status in ('OPEN', 'IN_REVIEW'))
  );
end;
$$;

create or replace function public.admin_list_rides(
  p_status public.ride_status default null,
  p_city_id uuid default null,
  p_route_id uuid default null,
  p_search text default null,
  p_from date default null,
  p_to date default null,
  p_limit int default 50,
  p_offset int default 0
)
returns table (
  ride_id uuid, created_at timestamptz, status ride_status, route text, origin_city_id uuid,
  passenger_name text, passenger_phone text, driver_name text, driver_phone text,
  final_fare numeric, commission_amount numeric, driver_earning numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform require_admin();
  return query
  select r.id, r.created_at, r.status, o.name || ' → ' || d.name, r.origin_city_id,
         pp.full_name, '+' || pp.phone, dp.full_name, '+' || dp.phone,
         r.final_fare, c.commission_amount, c.driver_earning
  from rides r
  join cities o on o.id = r.origin_city_id
  join cities d on d.id = r.destination_city_id
  join profiles pp on pp.id = r.passenger_id
  join profiles dp on dp.id = r.driver_id
  left join commissions c on c.ride_id = r.id
  where (p_status is null or r.status = p_status)
    and (p_city_id is null or r.origin_city_id = p_city_id or r.destination_city_id = p_city_id)
    and (p_route_id is null or r.route_id = p_route_id)
    and (p_from is null or r.created_at >= p_from)
    and (p_to is null or r.created_at < p_to + 1)
    and (p_search is null or pp.full_name ilike '%' || p_search || '%' or dp.full_name ilike '%' || p_search || '%'
         or pp.phone like '%' || p_search || '%' or dp.phone like '%' || p_search || '%')
  order by r.created_at desc
  limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0);
end;
$$;

create or replace function public.admin_list_drivers(p_status public.driver_status default null)
returns table (
  driver_id uuid, full_name text, phone text, status driver_status, account_status account_status,
  is_online boolean, city_name text, cnic text, rating numeric, total_rides int,
  vehicle text, plate text, commission_due numeric, document_count int, created_at timestamptz,
  rejection_reason text
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
         (select v.vehicle_type::text || ' · ' || trim(coalesce(v.make, '') || ' ' || v.model)
            from vehicles v where v.driver_id = d.id and v.is_active limit 1),
         (select v.plate_number from vehicles v where v.driver_id = d.id and v.is_active limit 1),
         coalesce((select l.balance_after from driver_ledger l where l.driver_id = d.id order by l.id desc limit 1), 0),
         (select count(*)::int from driver_documents x where x.driver_id = d.id),
         d.created_at, d.rejection_reason
  from drivers d
  join profiles p on p.id = d.id
  left join cities c on c.id = d.current_city_id
  where p_status is null or d.status = p_status
  order by (d.status = 'PENDING') desc, d.created_at desc;
end;
$$;

create or replace function public.admin_list_passengers(p_search text default null)
returns table (
  user_id uuid, full_name text, phone text, account_status account_status, total_rides int,
  rating numeric, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform require_admin();
  return query
  select p.id, p.full_name, '+' || p.phone, p.account_status, coalesce(pa.total_rides, 0), pa.rating_avg, p.created_at
  from profiles p
  left join passengers pa on pa.id = p.id
  where p.role = 'PASSENGER'
    and (p_search is null or p.full_name ilike '%' || p_search || '%' or p.phone like '%' || p_search || '%')
  order by p.created_at desc
  limit 200;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Support (Phase 5)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.submit_complaint(
  p_type public.complaint_type, p_description text, p_ride_id uuid default null
)
returns public.complaints
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := require_active_account();
  v_ride rides;
  v_against uuid;
  v_row complaints;
begin
  if p_ride_id is not null then
    select * into v_ride from rides where id = p_ride_id;
    if not found or v_uid not in (v_ride.passenger_id, v_ride.driver_id) then
      raise exception 'Ride not found' using errcode = 'P0002';
    end if;
    v_against := case
      when p_type = 'DRIVER' then v_ride.driver_id
      when p_type = 'PASSENGER' then v_ride.passenger_id end;
  end if;
  insert into complaints (reporter_id, against_user_id, ride_id, complaint_type, description)
  values (v_uid, v_against, p_ride_id, p_type, btrim(p_description))
  returning * into v_row;
  return v_row;
end;
$$;

-- Device token registration for push (one row per token).
create or replace function public.register_device_token(p_token text, p_platform text default 'android')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or nullif(btrim(p_token), '') is null then
    return;
  end if;
  insert into device_tokens (user_id, token, platform, last_seen_at)
  values (v_uid, p_token, coalesce(p_platform, 'android'), now())
  on conflict (token) do update set user_id = excluded.user_id, last_seen_at = now();
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Permissions
-- ─────────────────────────────────────────────────────────────────────────────
revoke execute on function
  public.save_driver_application(text, uuid, public.vehicle_type, text, text, text, text, int, int, uuid[], uuid[]),
  public.set_driver_routes(uuid[]),
  public.set_driver_online(boolean, uuid),
  public.get_driver_dashboard(),
  public.require_admin(),
  public.admin_set_driver_status(uuid, public.driver_status, text),
  public.admin_set_account_status(uuid, public.account_status),
  public.admin_record_commission_payment(uuid, numeric, text),
  public.admin_dashboard_stats(),
  public.admin_list_rides(public.ride_status, uuid, uuid, text, date, date, int, int),
  public.admin_list_drivers(public.driver_status),
  public.admin_list_passengers(text),
  public.submit_complaint(public.complaint_type, text, uuid),
  public.register_device_token(text, text),
  public.validate_setting()
from public, anon;

grant execute on function
  public.save_driver_application(text, uuid, public.vehicle_type, text, text, text, text, int, int, uuid[], uuid[]),
  public.set_driver_routes(uuid[]),
  public.set_driver_online(boolean, uuid),
  public.get_driver_dashboard(),
  public.admin_set_driver_status(uuid, public.driver_status, text),
  public.admin_set_account_status(uuid, public.account_status),
  public.admin_record_commission_payment(uuid, numeric, text),
  public.admin_dashboard_stats(),
  public.admin_list_rides(public.ride_status, uuid, uuid, text, date, date, int, int),
  public.admin_list_drivers(public.driver_status),
  public.admin_list_passengers(text),
  public.submit_complaint(public.complaint_type, text, uuid),
  public.register_device_token(text, text)
to authenticated;

-- Admin-editable catalog needs delete on stops only; cities/routes are
-- disabled, never deleted (history references them).
