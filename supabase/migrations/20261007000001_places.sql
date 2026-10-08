-- Places: villages, addas, stops and landmarks along the routes. They appear first in
-- the map search, so a passenger can type "Chak 360 GB" or "Bus Stand Kamalia" and pick
-- it. Admins add and edit them in the admin panel (Places).

create table public.places (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 2 and 80),
  kind        text not null default 'place'
              check (kind in ('town', 'village', 'hamlet', 'stop', 'landmark', 'place')),
  lat         double precision not null check (lat between -90 and 90),
  lng         double precision not null check (lng between -180 and 180),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index places_name_pos_idx
  on public.places (lower(btrim(name)), round(lat::numeric, 3), round(lng::numeric, 3));
create index places_name_idx on public.places (lower(name));

alter table public.places enable row level security;
grant select on public.places to authenticated;
grant insert, update, delete on public.places to authenticated;

create policy places_read on public.places for select to authenticated
  using (is_active or public.is_admin());
create policy places_admin_insert on public.places for insert to authenticated
  with check (public.is_admin());
create policy places_admin_update on public.places for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy places_admin_delete on public.places for delete to authenticated
  using (public.is_admin());
