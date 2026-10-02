#!/usr/bin/env bash
# KAM GO — Section 21 acceptance test, run against the LOCAL Supabase stack
# through the public API with real user sessions (exactly what the app does).
#
#   supabase db reset          # fresh seed
#   tools/acceptance_test.sh
set -uo pipefail
SUPABASE=${SUPABASE:-supabase}
API=http://127.0.0.1:54321
KEY=$($SUPABASE status -o env 2>/dev/null | sed -n 's/^PUBLISHABLE_KEY="\(.*\)"/\1/p')
[ -z "$KEY" ] && { echo "Local Supabase is not running"; exit 1; }

PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got: $2, want: $3)"; fi; }

login() {
  curl -s -X POST "$API/auth/v1/otp" -H "apikey: $KEY" -H 'Content-Type: application/json' -d "{\"phone\":\"$1\"}" >/dev/null
  curl -s -X POST "$API/auth/v1/verify" -H "apikey: $KEY" -H 'Content-Type: application/json' \
    -d "{\"phone\":\"$1\",\"token\":\"123456\",\"type\":\"sms\"}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])'
}
get()  { curl -s "$API/rest/v1/$2" -H "apikey: $KEY" -H "Authorization: Bearer $1"; }
rpc()  { curl -s -X POST "$API/rest/v1/rpc/$2" -H "apikey: $KEY" -H "Authorization: Bearer $1" -H 'Content-Type: application/json' -d "${3:-{\}}"; }
post() { curl -s -X POST "$API/rest/v1/$2" -H "apikey: $KEY" -H "Authorization: Bearer $1" -H 'Content-Type: application/json' -d "$3"; }
patch(){ curl -s -X PATCH "$API/rest/v1/$2" -H "apikey: $KEY" -H "Authorization: Bearer $1" -H 'Content-Type: application/json' -H 'Prefer: return=representation' -d "$3"; }
py()   { python3 -c "import json,sys;d=json.load(sys.stdin);$1"; }

R_PM_RAJ=22222222-2222-4222-8222-000000000003
R_RAJ_PM=22222222-2222-4222-8222-000000000004

echo "Signing in demo users…"
P=$(login +923000000002)   # passenger Ali, Pir Mahal
A=$(login +923000000011); B=$(login +923000000012); C=$(login +923000000013)
D=$(login +923000000014)   # approved but OFFLINE
E=$(login +923000000015)   # PENDING
S=$(login +923000000003)   # passenger Sana

echo "Fare guardrails"
check "Rs. 10 rejected by server" "$(rpc $P create_ride_request "{\"p_route_id\":\"$R_PM_RAJ\",\"p_passenger_count\":2,\"p_offered_fare\":10}" | py 'print(d.get("code"))')" "22023"
check "Rs. 50,000 rejected by server" "$(rpc $P create_ride_request "{\"p_route_id\":\"$R_PM_RAJ\",\"p_passenger_count\":2,\"p_offered_fare\":50000}" | py 'print(d.get("code"))')" "22023"

echo "Passenger in Pir Mahal offers Rs. 1,100 to Rajana for 2"
REQ=$(rpc $P create_ride_request "{\"p_route_id\":\"$R_PM_RAJ\",\"p_passenger_count\":2,\"p_offered_fare\":1100,\"p_pickup_label\":\"Bus Adda\"}" | py 'print(d["id"])')
[ -n "$REQ" ] && ok "request created" || bad "request created"

echo "Only approved + online drivers receive it"
check "Driver A feed has it" "$(rpc $A get_driver_feed | grep -c "$REQ")" "1"
check "offline Driver D feed doesn't" "$(rpc $D get_driver_feed | grep -c "$REQ")" "0"
check "pending Driver E feed doesn't" "$(rpc $E get_driver_feed | grep -c "$REQ")" "0"
check "offline D cannot read the row" "$(get $D "ride_requests?id=eq.$REQ&select=id")" "[]"
check "offline D cannot offer" "$(rpc $D submit_offer "{\"p_request_id\":\"$REQ\",\"p_offer_type\":\"ACCEPT\"}" | py 'print(d.get("code"))')" "42501"
check "pending E cannot offer" "$(rpc $E submit_offer "{\"p_request_id\":\"$REQ\",\"p_offer_type\":\"ACCEPT\"}" | py 'print(d.get("code"))')" "42501"
check "offline D got no notification" "$(get $D "notifications?type=eq.NEW_REQUEST&select=id")" "[]"

echo "A accepts 1,100 · B counters 1,200 · C counters 1,300"
OA=$(rpc $A submit_offer "{\"p_request_id\":\"$REQ\",\"p_offer_type\":\"ACCEPT\",\"p_driver_lat\":30.77,\"p_driver_lng\":72.44}" | py 'print(d["id"])')
OB=$(rpc $B submit_offer "{\"p_request_id\":\"$REQ\",\"p_offer_type\":\"COUNTER\",\"p_fare\":1200}" | py 'print(d["id"])')
OC=$(rpc $C submit_offer "{\"p_request_id\":\"$REQ\",\"p_offer_type\":\"COUNTER\",\"p_fare\":1300}" | py 'print(d["id"])')
check "passenger sees 3 live offers" "$(rpc $P get_request_offers "{\"p_request_id\":\"$REQ\"}" | py 'print(sorted((o["offer_type"], int(o["fare"])) for o in d))')" "[('ACCEPT', 1100), ('COUNTER', 1200), ('COUNTER', 1300)]"
check "counter over guardrail rejected" "$(rpc $C submit_offer "{\"p_request_id\":\"$REQ\",\"p_offer_type\":\"COUNTER\",\"p_fare\":99999}" | py 'print(d.get("code"))')" "22023"

echo "Passenger selects B"
RIDE=$(rpc $P select_offer "{\"p_offer_id\":\"$OB\"}" | py 'print(d["id"])')
check "ride CONFIRMED at Rs. 1,200" "$(get $P "rides?id=eq.$RIDE&select=status,final_fare" | py 'print(d[0]["status"], int(d[0]["final_fare"]))')" "CONFIRMED 1200"
check "A and C offers unavailable" "$(rpc $P get_request_offers "{\"p_request_id\":\"$REQ\"}" | py 'print(sorted((int(o["fare"]), o["status"]) for o in d))')" "[(1100, 'UNAVAILABLE'), (1200, 'SELECTED'), (1300, 'UNAVAILABLE')]"
check "selecting C afterwards fails" "$(rpc $P select_offer "{\"p_offer_id\":\"$OC\"}" | py 'print(d.get("code"))')" "40001"

echo "Row lock: two simultaneous selections on Sana's request → exactly one wins"
SREQ=55555555-5555-4555-8555-000000000010
rpc $S select_offer '{"p_offer_id":"66666666-6666-4666-8666-000000000010"}' > /tmp/kg_sel1 &
rpc $S select_offer '{"p_offer_id":"66666666-6666-4666-8666-000000000011"}' > /tmp/kg_sel2 &
wait
check "one success, one refusal" "$(cat /tmp/kg_sel1 /tmp/kg_sel2 | grep -c '"offer_id"')" "1"
check "exactly one ride for that request" "$(get $S "rides?request_id=eq.$SREQ&select=id" | py 'print(len(d))')" "1"

echo "Driver B starts and completes"
check "passenger cannot start the ride" "$(rpc $P update_ride_status "{\"p_ride_id\":\"$RIDE\",\"p_new_status\":\"RIDE_STARTED\"}" | py 'print(d.get("code"))')" "22023"
check "cannot complete before starting" "$(rpc $B complete_ride "{\"p_ride_id\":\"$RIDE\"}" | py 'print(d.get("code"))')" "22023"
rpc $B update_ride_status "{\"p_ride_id\":\"$RIDE\",\"p_new_status\":\"DRIVER_ARRIVING\"}" >/dev/null
check "B starts ride" "$(rpc $B update_ride_status "{\"p_ride_id\":\"$RIDE\",\"p_new_status\":\"RIDE_STARTED\"}" | py 'print(d["status"])')" "RIDE_STARTED"
check "passenger cannot complete" "$(rpc $P complete_ride "{\"p_ride_id\":\"$RIDE\"}" | py 'print(d.get("code"))')" "P0002"
check "server commission 120 / driver 1,080" "$(rpc $B complete_ride "{\"p_ride_id\":\"$RIDE\"}" | py 'print(int(d["commission_amount"]), int(d["driver_earning"]))')" "120 1080"
check "ledger shows commission due" "$(get $B "driver_ledger?ride_id=eq.$RIDE&select=amount,entry_type" | py 'print(int(d[0]["amount"]), d[0]["entry_type"])')" "120 COMMISSION_DUE"

echo "Commission cannot be tampered with from the client"
check "insert commission denied" "$(post $B commissions "{\"ride_id\":\"$RIDE\",\"driver_id\":\"x\",\"final_fare\":1,\"commission_percent\":0,\"commission_amount\":0,\"driver_earning\":1}" | py 'print(d.get("code"))')" "42501"
check "update commission denied" "$(patch $B "commissions?ride_id=eq.$RIDE" '{"commission_amount":0}' | py 'print(d.get("code"))')" "42501"
check "update ride fare denied" "$(patch $P "rides?id=eq.$RIDE" '{"final_fare":1}' | py 'print(d.get("code"))')" "42501"
check "update ledger denied" "$(patch $B "driver_ledger?ride_id=eq.$RIDE" '{"amount":0}' | py 'print(d.get("code"))')" "42501"
check "passenger edits settings denied" "$(patch $P "settings?key=eq.commission_percent" '{"value":0}')" "[]"

echo "Passenger rates 5 stars; ride in history"
check "rating saved" "$(rpc $P rate_ride "{\"p_ride_id\":\"$RIDE\",\"p_stars\":5,\"p_comment\":\"Great\"}" | py 'print(d["stars"])')" "5"
check "ride in passenger history" "$(rpc $P get_my_rides | py "print(any(r['ride_id']=='$RIDE' and r['status']=='COMPLETED' and r['my_rating']==5 for r in d))")" "True"
check "ride in driver history with earning" "$(rpc $B get_my_rides | py "print([int(r['driver_earning']) for r in d if r['ride_id']=='$RIDE'])")" "[1080]"

echo "Return ride: B is now in Rajana and sees Rajana → Pir Mahal requests"
N=$(login +923000000098)
rpc $N complete_profile '{"p_full_name":"Rajana Rider","p_role":"PASSENGER"}' >/dev/null
RREQ=$(rpc $N create_ride_request "{\"p_route_id\":\"$R_RAJ_PM\",\"p_passenger_count\":1,\"p_offered_fare\":900}" | py 'print(d["id"])')
check "B's feed shows it as a return ride" "$(rpc $B get_driver_feed | py "print([r['is_return'] for r in d if r['request_id']=='$RREQ'])")" "[True]"
check "B got a return-ride notification" "$(get $B "notifications?type=eq.RETURN_RIDE&select=id" | py 'print(len(d)>0)')" "True"
check "A (still in Pir Mahal) doesn't see it" "$(rpc $A get_driver_feed | grep -c "$RREQ")" "0"

echo "Cancellation"
check "passenger cancels open request" "$(rpc $N cancel_request "{\"p_request_id\":\"$RREQ\"}" | py 'print(d["status"])')" "CANCELLED"

echo
echo "Passed: $PASS   Failed: $FAIL"
[ "$FAIL" = 0 ]
