-- Every online driver of the right ride type gets the request, wherever they are.
-- (Set search_radius_km in the admin Settings to a number of km to limit it to drivers near the pickup.)
update public.settings
   set value = '0',
       description = 'Only drivers within this many km of the pickup get the request (0 = every driver of that ride type, wherever they are)'
 where key = 'search_radius_km';
