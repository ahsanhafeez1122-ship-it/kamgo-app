-- Destinations: only places inside a city we serve. A trip inside one city is a "city" trip, a trip
-- to another of our cities is "intercity". Same-area addresses get a default distance estimate.

alter table public.ride_requests add column trip_scope text not null default 'city'
  check (trip_scope in ('city', 'intercity'));
update public.ride_requests set trip_scope = case when origin_city_id = destination_city_id then 'city' else 'intercity' end;

create or replace function public.ride_requests_set_scope()
returns trigger
language plpgsql
as $$
begin
  new.trip_scope := case when new.origin_city_id = new.destination_city_id then 'city' else 'intercity' end;
  return new;
end;
$$;
create trigger ride_requests_set_scope_trg before insert on public.ride_requests
  for each row execute function public.ride_requests_set_scope();

insert into public.settings (key, value, description) values
  ('same_area_default_km', '3', 'Distance assumed for a trip when both addresses are in the same area and the app cannot tell them apart')
on conflict (key) do nothing;

-- create_ride_request_geo: the destination must be inside the service radius of one of our cities.
do $$
declare
  v_sig text := 'public.create_ride_request_geo(float8, float8, float8, float8, int, numeric, text, text, text, text, boolean, numeric, text, uuid, int, timestamptz, numeric)';
  v_src text;
  v_new text;
begin
  select pg_get_functiondef(v_sig::regprocedure) into v_src;
  v_new := replace(v_src,
    'select * into v_d from nearest_city(v_dlat, v_dlng);',
    'select * into v_d from nearest_city(v_dlat, v_dlng);
  if v_d.id is null or v_d.km > (select service_radius_km from cities where id = v_d.id) then
    raise exception ''We do not serve that destination yet'' using errcode = ''22023'';
  end if;');
  if v_new = v_src then raise exception 'destination patch failed'; end if;
  execute v_new;
end;
$$;
