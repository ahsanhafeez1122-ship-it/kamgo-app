-- Time-based booking scenarios that cannot be driven through the public API (they need a trip that lasted hours).
-- Run on a freshly reset local database:
--   Get-Content tools\test_booking_scenarios.sql | docker exec -i supabase_db_kamgo_app psql -U postgres
-- Everything is rolled back at the end.
-- Expected: hourly 5400 (3940 + 15 km x 60 + 1 h x 560); round trip 3780 (90 min waiting) and 4030 (120 min); reminder 1 then 0.

