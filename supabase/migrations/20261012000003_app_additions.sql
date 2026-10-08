-- Small additions for the app: the dashboard reports AC, and a switch for showing prices on the
-- ride-type cards (off: the passenger sees the recommended fare for the chosen type below the cards).
insert into public.settings (key, value, description) values
  ('show_category_prices', 'false', 'Show each ride type''s recommended fare on its card')
on conflict (key) do nothing;

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
    'city_id', v_driver.city_id,
    'city_name', (select name from cities where id = v_driver.city_id),
    'rating', v_driver.rating_avg,
    'rating_count', v_driver.rating_count,
    'total_rides', v_driver.total_rides,
    'cnic', v_driver.cnic_number,
    'vehicle', (select jsonb_build_object('type', vehicle_type, 'category', category, 'make', make, 'model', model,
                                          'color', color, 'plate', plate_number, 'seats', seats, 'year', year,
                                          'ac', ac_available)
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
             from get_adda_summary() a where a.city_id = v_driver.city_id),
    'recent_ratings', coalesce((select jsonb_agg(x) from (
        select r.stars, r.comment, r.created_at from ratings r
        where r.ratee_id = v_uid and r.ride_id in (select id from rides where driver_id = v_uid)
        order by r.created_at desc limit 5) x), '[]'::jsonb)
  );
end;
$$;

-- "Right now" on the driver dashboard: drivers online and open requests in the driver's own city.
create or replace function public.get_adda_summary()
returns table (city_id uuid, city_name text, online_drivers int, open_requests int)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.name,
         (select count(*)::int from drivers d
           where d.city_id = c.id and d.is_online and d.status = 'APPROVED'),
         (select count(*)::int from ride_requests r
           where r.city_id = c.id and r.status in ('REQUESTED', 'SEARCHING', 'OFFER_RECEIVED')
             and r.expires_at > now())
  from cities c
  where c.is_active
  order by c.sort_order, c.name;
$$;
