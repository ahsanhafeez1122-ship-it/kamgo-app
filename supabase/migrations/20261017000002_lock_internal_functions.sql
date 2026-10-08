-- Internal helpers must not be callable from the app's API. New functions get EXECUTE for the
-- API roles by default, so "revoke ... from public" alone was not enough: a signed-in user could
-- call notify() (fake notifications to anyone), dispatch_request() (spam drivers), log_status(),
-- learn_place() or driver_position_now() (a driver's location) directly.
-- They keep working inside the SECURITY DEFINER functions, cron jobs and triggers that use them.
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('notify', 'log_status', 'dispatch_request', 'ensure_route', 'expire_stale',
                        'nudge_unanswered_requests', 'learn_place', 'driver_position_now', 'handle_new_user')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
  end loop;
end;
$$;
