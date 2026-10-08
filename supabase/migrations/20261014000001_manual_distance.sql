-- Addresses that are not on the map: the passenger can say how far the trip is.
-- create_ride_request_geo gets an optional p_distance_km; when it is given it replaces the
-- pin-to-pin distance (and the "same place" check, since both addresses may sit on one pin).

do $$
declare
  v_src text;
  v_new text;
begin
  select pg_get_functiondef(
    'public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text, boolean, numeric, text, uuid, int, timestamptz)'::regprocedure
  ) into v_src;

  v_new := replace(v_src,
    'p_scheduled_at timestamp with time zone DEFAULT NULL::timestamp with time zone',
    'p_scheduled_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_distance_km numeric DEFAULT NULL::numeric');
  if v_new = v_src then raise exception 'signature patch failed'; end if;
  v_src := v_new;

  v_new := replace(v_src,
    'if haversine_km(p_pickup_lat, p_pickup_lng, v_dlat, v_dlng) < 0.3 then',
    'if p_distance_km is null and haversine_km(p_pickup_lat, p_pickup_lng, v_dlat, v_dlng) < 0.3 then');
  if v_new = v_src then raise exception 'same-place patch failed'; end if;
  v_src := v_new;

  v_new := replace(v_src,
    'v_dist := greatest(1, round((haversine_km(p_pickup_lat, p_pickup_lng, v_dlat, v_dlng) * 1.3)::numeric, 1));',
    'if p_distance_km is not null then
      if p_distance_km < 1 or p_distance_km > 300 then
        raise exception ''Distance must be between 1 and 300 km'' using errcode = ''22023'';
      end if;
      v_dist := round(p_distance_km, 1);
    else
      v_dist := greatest(1, round((haversine_km(p_pickup_lat, p_pickup_lng, v_dlat, v_dlng) * 1.3)::numeric, 1));
    end if;');
  if v_new = v_src then raise exception 'distance patch failed'; end if;

  drop function public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text, boolean, numeric, text, uuid, int, timestamptz);
  execute v_new;
end;
$$;

revoke all on function public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text, boolean, numeric, text, uuid, int, timestamptz, numeric) from public;
grant execute on function public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text, boolean, numeric, text, uuid, int, timestamptz, numeric) to authenticated;
