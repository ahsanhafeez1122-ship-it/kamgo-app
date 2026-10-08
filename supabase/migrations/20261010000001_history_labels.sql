-- Ride history shows the places the way the passenger wrote or chose them (the
-- pickup / drop-off label), falling back to the town name for older rides.
create or replace function public.get_my_rides(p_limit int default 20, p_offset int default 0)
returns table (
  ride_id uuid, origin_name text, destination_name text, final_fare numeric, status ride_status,
  created_at timestamptz, completed_at timestamptz, other_name text, my_role text,
  driver_earning numeric, commission_amount numeric, my_rating int
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id,
         coalesce(nullif(btrim(q.pickup_label), ''), o.name),
         coalesce(nullif(btrim(q.dropoff_label), ''), d.name),
         r.final_fare, r.status, r.created_at, r.completed_at,
         case when r.passenger_id = auth.uid() then dp.full_name else pp.full_name end,
         case when r.passenger_id = auth.uid() then 'PASSENGER' else 'DRIVER' end,
         case when r.driver_id = auth.uid() then c.driver_earning end,
         case when r.driver_id = auth.uid() then c.commission_amount end,
         (select stars from ratings x where x.ride_id = r.id and x.rater_id = auth.uid())
  from rides r
  join ride_requests q on q.id = r.request_id
  join cities o on o.id = r.origin_city_id
  join cities d on d.id = r.destination_city_id
  join profiles dp on dp.id = r.driver_id
  join profiles pp on pp.id = r.passenger_id
  left join commissions c on c.ride_id = r.id
  where auth.uid() in (r.passenger_id, r.driver_id)
  order by r.created_at desc
  limit least(greatest(p_limit, 1), 50) offset greatest(p_offset, 0);
$$;
