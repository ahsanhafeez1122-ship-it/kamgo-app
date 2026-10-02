-- KAM GO — Row Level Security and table privileges.
--
-- Principles:
--   * RLS is on for every table. anon gets nothing.
--   * Signed-in users read only what concerns them.
--   * Writes that touch money, ride status or roles go through SECURITY
--     DEFINER functions only — there is no table-level write grant for them.
--   * Admins are identified through admin_users (is_admin()), never through
--     anything the client sends.

-- ─────────────────────────────────────────────────────────────────────────────
-- Privileges
-- ─────────────────────────────────────────────────────────────────────────────
revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;
grant select on all tables in schema public to authenticated;
grant usage on all sequences in schema public to authenticated;

-- Profile: users may edit only their personal fields. role, account_status
-- and onboarded can only change through complete_profile() / admin RPCs.
grant update (full_name, avatar_url, emergency_contact_name, emergency_contact_phone, preferred_language)
  on public.profiles to authenticated;

-- Driver self-service (registration details; status stays server-side).
grant insert, update on public.vehicles to authenticated;
grant insert on public.driver_documents to authenticated;
grant insert, delete on public.driver_routes, public.driver_service_areas to authenticated;
grant insert on public.ride_locations to authenticated;

-- Personal data.
grant update (read_at) on public.notifications to authenticated;
grant insert, update, delete on public.device_tokens to authenticated;
grant insert on public.complaints to authenticated;
grant insert, update, delete on public.saved_routes to authenticated;

-- Admin-editable catalog & moderation (RLS below limits these to admins).
grant insert, update on public.cities, public.service_areas, public.routes, public.settings
  to authenticated;
grant insert, update, delete on public.route_stops to authenticated;
grant update (status, reviewed_by, reviewed_at, note) on public.driver_documents to authenticated;
grant update (status, admin_note) on public.complaints to authenticated;

-- Deliberately NO write grants on: ride_requests, ride_offers, rides,
-- ride_status_log, ratings, cancellations, commissions, driver_ledger,
-- payments, drivers, passengers, admin_users, ride_status_transitions.

-- ─────────────────────────────────────────────────────────────────────────────
-- Enable RLS everywhere
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Catalog: readable by any signed-in user, editable by admins
-- ─────────────────────────────────────────────────────────────────────────────
create policy cities_read on public.cities for select to authenticated
  using (is_active or public.is_admin());
create policy cities_admin_insert on public.cities for insert to authenticated
  with check (public.is_admin());
create policy cities_admin_update on public.cities for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy service_areas_read on public.service_areas for select to authenticated
  using (is_active or public.is_admin());
create policy service_areas_admin_insert on public.service_areas for insert to authenticated
  with check (public.is_admin());
create policy service_areas_admin_update on public.service_areas for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy routes_read on public.routes for select to authenticated
  using (is_active or public.is_admin());
create policy routes_admin_insert on public.routes for insert to authenticated
  with check (public.is_admin());
create policy routes_admin_update on public.routes for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy route_stops_read on public.route_stops for select to authenticated
  using (true);
create policy route_stops_admin_all on public.route_stops for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy settings_read on public.settings for select to authenticated
  using (true);
create policy settings_admin_insert on public.settings for insert to authenticated
  with check (public.is_admin());
create policy settings_admin_update on public.settings for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy transitions_read on public.ride_status_transitions for select to authenticated
  using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- People
-- ─────────────────────────────────────────────────────────────────────────────
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin() or public.shares_ride_with(id));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy admin_users_read on public.admin_users for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create policy passengers_read on public.passengers for select to authenticated
  using (id = auth.uid() or public.is_admin() or public.shares_ride_with(id));

create policy drivers_read on public.drivers for select to authenticated
  using (id = auth.uid() or public.is_admin() or public.shares_ride_with(id));

create policy vehicles_read on public.vehicles for select to authenticated
  using (driver_id = auth.uid() or public.is_admin() or public.shares_ride_with(driver_id));
create policy vehicles_insert_own on public.vehicles for insert to authenticated
  with check (driver_id = auth.uid());
create policy vehicles_update_own on public.vehicles for update to authenticated
  using (driver_id = auth.uid()) with check (driver_id = auth.uid());

create policy driver_documents_read on public.driver_documents for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());
create policy driver_documents_insert_own on public.driver_documents for insert to authenticated
  with check (driver_id = auth.uid() and status = 'PENDING' and reviewed_by is null);
create policy driver_documents_admin_update on public.driver_documents for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy driver_routes_read on public.driver_routes for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());
create policy driver_routes_insert_own on public.driver_routes for insert to authenticated
  with check (driver_id = auth.uid());
create policy driver_routes_delete_own on public.driver_routes for delete to authenticated
  using (driver_id = auth.uid());

create policy driver_service_areas_read on public.driver_service_areas for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());
create policy driver_service_areas_insert_own on public.driver_service_areas for insert to authenticated
  with check (driver_id = auth.uid());
create policy driver_service_areas_delete_own on public.driver_service_areas for delete to authenticated
  using (driver_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- Rides (read-only from the client; all writes via RPC)
-- ─────────────────────────────────────────────────────────────────────────────
create policy ride_requests_read on public.ride_requests for select to authenticated
  using (
    passenger_id = auth.uid()
    or public.is_admin()
    or public.driver_can_see_request(origin_city_id, route_id, status, expires_at)
    or public.i_offered_on(id)
  );

create policy ride_offers_read on public.ride_offers for select to authenticated
  using (driver_id = auth.uid() or public.is_my_request(request_id) or public.is_admin());

create policy rides_read on public.rides for select to authenticated
  using (auth.uid() in (passenger_id, driver_id) or public.is_admin());

create policy ride_status_log_read on public.ride_status_log for select to authenticated
  using (
    public.is_admin()
    or (ride_id is not null and public.is_ride_party(ride_id))
    or (request_id is not null and public.is_my_request(request_id))
  );

create policy ride_locations_read on public.ride_locations for select to authenticated
  using (public.is_ride_party(ride_id) or public.is_admin());
create policy ride_locations_insert_driver on public.ride_locations for insert to authenticated
  with check (
    driver_id = auth.uid()
    and exists (
      select 1 from public.rides r
      where r.id = ride_id
        and r.driver_id = auth.uid()
        and r.status in ('CONFIRMED', 'DRIVER_ARRIVING', 'RIDE_STARTED')
    )
  );

create policy ratings_read on public.ratings for select to authenticated
  using (auth.uid() in (rater_id, ratee_id) or public.is_admin());

create policy cancellations_read on public.cancellations for select to authenticated
  using (
    public.is_admin()
    or (ride_id is not null and public.is_ride_party(ride_id))
    or (request_id is not null and public.is_my_request(request_id))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- Money: drivers see their own rows, admins see all, nobody writes.
-- ─────────────────────────────────────────────────────────────────────────────
create policy commissions_read on public.commissions for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());

create policy driver_ledger_read on public.driver_ledger for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());

create policy payments_read on public.payments for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- Notifications, devices, support
-- ─────────────────────────────────────────────────────────────────────────────
create policy notifications_read on public.notifications for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy notifications_mark_read on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy device_tokens_own on public.device_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy complaints_read on public.complaints for select to authenticated
  using (reporter_id = auth.uid() or public.is_admin());
create policy complaints_insert_own on public.complaints for insert to authenticated
  with check (reporter_id = auth.uid() and status = 'OPEN' and admin_note is null);
create policy complaints_admin_update on public.complaints for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy saved_routes_own on public.saved_routes for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- Realtime: tables the apps subscribe to (RLS still applies to every event).
-- ─────────────────────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime
      add table public.ride_requests, public.ride_offers, public.rides, public.notifications;
  end if;
end;
$$;
