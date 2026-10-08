#!/usr/bin/env bash
# KAM GO - acceptance test against the LOCAL Supabase stack, through the public API with real
# user sessions (exactly what the app does).
#
#   supabase db reset          # fresh seed (the seeded request expires after ~3 minutes: run right away)
#   tools/acceptance_test.sh
set -uo pipefail
SUPABASE=${SUPABASE:-supabase}
API=${API:-http://127.0.0.1:54321}
KEY=${KEY:-$($SUPABASE status -o env 2>/dev/null | sed -n 's/^PUBLISHABLE_KEY="\(.*\)"/\1/p')}
[ -z "$KEY" ] && { echo "Local Supabase is not running"; exit 1; }

PASS=0; FAIL=0
ok()   { echo "  [ok]   $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
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

TOBA=11111111-1111-4111-8111-000000000005
KAMALIA=11111111-1111-4111-8111-000000000001
PIRMAHAL=11111111-1111-4111-8111-000000000002

echo "Signing in demo users..."
P=$(login +923000000002)   # passenger Ali
S=$(login +923000000003)   # passenger Sana (has a seeded open request)
ADMIN=$(login +923000000001)
A=$(login +923000000011)   # Mini, Kamalia
B=$(login +923000000012)   # Mini, Toba Tek Singh
C=$(login +923000000013)   # Mini, Pir Mahal
D=$(login +923000000014)   # Comfort, Toba, OFFLINE
E=$(login +923000000015)   # PENDING
BK=$(login +923000000016)  # Bike, Toba
RK=$(login +923000000017)  # Rickshaw, Toba
LD=$(login +923000000018)  # Loader, Toba
F=$(login +923000000019)   # XL, Toba
N=$(login +923000000098)
rpc $N complete_profile '{"p_full_name":"Test Rider","p_role":"PASSENGER"}' >/dev/null
N2=$P   # Ali: a second passenger (one open request per passenger)

echo "Fare engine (database) - the worked examples"
fc() { rpc $N fare_calc "{\"p_distance\":$1,\"p_category\":\"$2\",\"p_night\":${3:-false},\"p_loading\":${4:-false},\"p_toll\":0}" | py 'print(int(d[0]["recommended"]))'; }
check "car_mini 5 km = 770" "$(fc 5 car_mini)" "770"
check "car_mini 20 km = 2310" "$(fc 20 car_mini)" "2310"
check "car_mini 40 km = 3360" "$(fc 40 car_mini)" "3360"
check "car_mini 95 km = 7470" "$(fc 95 car_mini)" "7470"
check "car_mini 20 km at night = 2770 (+20%)" "$(fc 20 car_mini true)" "2770"
check "loader loading charge adds Rs. 100" "$(( $(fc 10 loader false true) - $(fc 10 loader) ))" "100"
check "fare band: min 85% / max 200% of 2310" "$(rpc $N fare_calc '{"p_distance":20,"p_category":"car_mini","p_night":false,"p_loading":false,"p_toll":0}' | py 'print(int(d[0]["min_offer"]), int(d[0]["max_offer"]), int(d[0]["commission"]), int(d[0]["driver_gets"]))')" "1960 4620 231 2079"
check "six ride types in display order" "$(get $N 'ride_categories?select=code&order=sort_order' | py 'print([r["code"] for r in d])')" "['car_mini', 'car_comfort', 'car_xl', 'bike', 'rickshaw', 'loader']"

echo "Booking guards"
geo() { rpc ${WHO:-$N} create_ride_request_geo "{\"p_pickup_lat\":$1,\"p_pickup_lng\":$2,\"p_dropoff_lat\":$3,\"p_dropoff_lng\":$4,\"p_passenger_count\":${6:-1},\"p_offered_fare\":$5,\"p_category\":\"${7:-car_mini}\"}"; }
TOBA_P="30.9709 72.4826"; NEAR_TOBA="31.0500 72.5000"
check "pickup outside every service area: not available yet" "$(geo 31.52 74.35 30.9709 72.4826 2000 | py 'print(d.get("code"))')" "22023"
check "same place for both pins rejected" "$(geo 30.7258 72.6447 30.7258 72.6447 300 | py 'print(d.get("code"))')" "22023"
check "same pin but a typed distance of 4 km is accepted and used" "$(rpc $N create_ride_request_geo '{"p_pickup_lat":30.9709,"p_pickup_lng":72.4826,"p_dropoff_lat":30.9709,"p_dropoff_lng":72.4826,"p_passenger_count":1,"p_offered_fare":700,"p_category":"car_mini","p_distance_km":4}' | py 'print(float(d["distance_km"]))')" "4.0"
rpc $N cancel_request "{\"p_request_id\":\"$(get $N 'ride_requests?status=in.(SEARCHING,OFFER_RECEIVED)&select=id' | py 'print(d[0]["id"])')\"}" >/dev/null
check "a typed distance over 300 km is refused" "$(rpc $N create_ride_request_geo '{"p_pickup_lat":30.9709,"p_pickup_lng":72.4826,"p_dropoff_lat":30.9709,"p_dropoff_lng":72.4826,"p_passenger_count":1,"p_offered_fare":700,"p_category":"car_mini","p_distance_km":500}' | py 'print(d.get("code"))')" "22023"
check "a destination outside every city we serve (Lahore) is refused" "$(geo $TOBA_P 31.5204 74.3587 1500 | py 'print(d.get("code"))')" "22023"
check "a trip inside one city is a city trip; to another of our cities it is city to city" "$(X=$(geo $TOBA_P $NEAR_TOBA 1400 | py 'print(d["id"])'); a=$(get $N "ride_requests?id=eq.$X&select=trip_scope" | py 'print(d[0]["trip_scope"])'); rpc $N cancel_request "{\"p_request_id\":\"$X\"}" >/dev/null; Y=$(geo $TOBA_P 30.7258 72.6447 4000 | py 'print(d["id"])'); b=$(get $N "ride_requests?id=eq.$Y&select=trip_scope" | py 'print(d[0]["trip_scope"])'); rpc $N cancel_request "{\"p_request_id\":\"$Y\"}" >/dev/null; echo "$a $b")" "city intercity"
check "offer under 85% of recommended rejected" "$(geo $TOBA_P $NEAR_TOBA 300 | py 'print(d.get("code"))')" "22023"
check "offer over 200% of recommended rejected" "$(geo $TOBA_P $NEAR_TOBA 9000 | py 'print(d.get("code"))')" "22023"
check "Bike not offered for a ~69 km trip (max_km 40)" "$(geo 30.5301 72.6917 30.9709 72.4826 3000 1 bike | py 'print(d.get("code"))')" "22023"
check "Bike carries only 1 passenger" "$(geo $TOBA_P $NEAR_TOBA 600 2 bike | py 'print(d.get("code"))')" "22023"
check "unknown ride type rejected" "$(geo $TOBA_P $NEAR_TOBA 1200 1 jet | py 'print(d.get("code"))')" "22023"

echo "Dispatch: only drivers of the same city AND category"
REQ=$(geo $TOBA_P $NEAR_TOBA 1400 1 car_mini | py 'print(d["id"])')
check "request created, city = Toba Tek Singh" "$(get $N "ride_requests?id=eq.$REQ&select=city_id,category" | py 'print(d[0]["city_id"], d[0]["category"])')" "$TOBA car_mini"
check "Mini driver B (Toba) sees it" "$(rpc $B get_driver_feed | grep -c "$REQ")" "1"
check "Mini driver A (Kamalia) does not" "$(rpc $A get_driver_feed | grep -c "$REQ")" "0"
check "Mini driver C (Pir Mahal) does not" "$(rpc $C get_driver_feed | grep -c "$REQ")" "0"
check "XL driver F (Toba) does not" "$(rpc $F get_driver_feed | grep -c "$REQ")" "0"
check "Bike / Rickshaw / Loader drivers do not" "$(rpc $BK get_driver_feed | grep -c "$REQ")$(rpc $RK get_driver_feed | grep -c "$REQ")$(rpc $LD get_driver_feed | grep -c "$REQ")" "000"
check "offline Comfort driver D does not" "$(rpc $D get_driver_feed | grep -c "$REQ")" "0"
check "pending driver E does not" "$(rpc $E get_driver_feed | grep -c "$REQ")" "0"
check "driver A cannot read the row either" "$(get $A "ride_requests?id=eq.$REQ&select=id")" "[]"
check "driver A cannot offer on it" "$(rpc $A submit_offer "{\"p_request_id\":\"$REQ\",\"p_offer_type\":\"ACCEPT\"}" | py 'print(d.get("code"))')" "P0002"
check "driver card data: commission 10% and you-get" "$(rpc $B get_driver_feed | py "print([(int(r['commission']), int(r['driver_gets'])) for r in d if r['request_id']=='$REQ'])")" "[(140, 1260)]"
check "driver card has the recommended fare and the band" "$(rpc $B get_driver_feed | py "r=[r for r in d if r['request_id']=='$REQ'][0];print(r['recommended_fare'] is not None, r['min_offer'] is not None)")" "True True"
check "XL request in Toba reaches only the XL driver" "$(X=$(WHO=$N2 geo $TOBA_P $NEAR_TOBA 2200 1 car_xl | py 'print(d["id"])'); echo $(rpc $F get_driver_feed | grep -c "$X")$(rpc $B get_driver_feed | grep -c "$X"); rpc $N2 cancel_request "{\"p_request_id\":\"$X\"}" >/dev/null)" "10"
check "Mini request in Kamalia reaches only the Kamalia driver" "$(K=$(WHO=$N2 geo 30.7258 72.6447 30.7400 72.6600 700 1 car_mini | py 'print(d["id"])'); echo $(rpc $A get_driver_feed | grep -c "$K")$(rpc $B get_driver_feed | grep -c "$K"); rpc $N2 cancel_request "{\"p_request_id\":\"$K\"}" >/dev/null)" "10"

echo "Admin moves driver A to Toba: now two Mini drivers share the city"
check "non-admin cannot change a driver's city" "$(rpc $A admin_set_driver_city "{\"p_driver_id\":\"33333333-3333-4333-8333-000000000011\",\"p_city_id\":\"$TOBA\"}" | py 'print(d.get("code"))')" "42501"
rpc $ADMIN admin_set_driver_city "{\"p_driver_id\":\"33333333-3333-4333-8333-000000000011\",\"p_city_id\":\"$TOBA\"}" >/dev/null
check "driver A now sees the Toba Mini request" "$(rpc $A get_driver_feed | grep -c "$REQ")" "1"
check "price band enforced on a driver counter (too low)" "$(rpc $A submit_offer "{\"p_request_id\":\"$REQ\",\"p_offer_type\":\"COUNTER\",\"p_fare\":100}" | py 'print(d.get("code"))')" "22023"
OA=$(rpc $A submit_offer "{\"p_request_id\":\"$REQ\",\"p_offer_type\":\"COUNTER\",\"p_fare\":1450,\"p_eta_min\":6}" | py 'print(d["id"])')
OB=$(rpc $B submit_offer "{\"p_request_id\":\"$REQ\",\"p_offer_type\":\"COUNTER\",\"p_fare\":1500,\"p_eta_min\":4}" | py 'print(d["id"])')
check "passenger sees both offers" "$(rpc $N get_request_offers "{\"p_request_id\":\"$REQ\"}" | py 'print(sorted((o["offer_type"], int(o["fare"])) for o in d))')" "[('COUNTER', 1450), ('COUNTER', 1500)]"
check "passenger raises the offer to 1600" "$(rpc $N raise_request_fare "{\"p_request_id\":\"$REQ\",\"p_new_fare\":1600}" | py 'print(int(d["offered_fare"]))')" "1600"
check "raising below the allowed band is refused" "$(rpc $N raise_request_fare "{\"p_request_id\":\"$REQ\",\"p_new_fare\":100}" | py 'print(d.get("code"))')" "22023"

echo "A driver accepting the passenger's fare confirms the ride at once"
AREQ=$(WHO=$P geo $TOBA_P $NEAR_TOBA 1400 | py 'print(d["id"])')
check "ACCEPT returns the offer as SELECTED" "$(rpc $A submit_offer "{\"p_request_id\":\"$AREQ\",\"p_offer_type\":\"ACCEPT\",\"p_eta_min\":7}" | py 'print(d["status"])')" "SELECTED"
check "the ride is CONFIRMED with that driver, no passenger step" "$(get $P "rides?request_id=eq.$AREQ&select=status,driver_id" | py 'print(d[0]["status"], d[0]["driver_id"][-2:])')" "CONFIRMED 11"
check "the passenger was told (with the driver's arrival time)" "$(get $P 'notifications?type=eq.RIDE_CONFIRMED&select=body&order=created_at.desc&limit=1' | py 'print("arrives in 7 min" in d[0]["body"])')" "True"
rpc $P cancel_ride "{\"p_ride_id\":\"$(get $P "rides?request_id=eq.$AREQ&select=id" | py 'print(d[0]["id"])')\",\"p_reason\":\"PASSENGER_CANCELLED\"}" >/dev/null

echo "Passenger selects B; the request disappears for A"
RIDE=$(rpc $N select_offer "{\"p_offer_id\":\"$OB\"}" | py 'print(d["id"])')
check "ride CONFIRMED at Rs. 1,500" "$(get $N "rides?id=eq.$RIDE&select=status,final_fare" | py 'print(d[0]["status"], int(d[0]["final_fare"]))')" "CONFIRMED 1500"
check "A's feed no longer has the request" "$(rpc $A get_driver_feed | grep -c "$REQ")" "0"
check "A's offer is unavailable" "$(rpc $N get_request_offers "{\"p_request_id\":\"$REQ\"}" | py 'print(sorted((int(o["fare"]), o["status"]) for o in d))')" "[(1450, 'UNAVAILABLE'), (1500, 'SELECTED')]"
check "ride stores city, category, recommended and accepted fare" "$(get $N "rides?id=eq.$RIDE&select=city_id,category,recommended_fare,accepted_fare" | py 'r=d[0];print(r["city_id"], r["category"], r["recommended_fare"] is not None, int(r["accepted_fare"]))')" "$TOBA car_mini True 1500"
REQ2=$(WHO=$N2 geo $TOBA_P $NEAR_TOBA 1400 1 car_mini | py 'print(d["id"])')
check "driver B (busy on a ride) gets no new requests" "$(rpc $B get_driver_feed | grep -c "$REQ2")" "0"
check "free Mini driver A does" "$(rpc $A get_driver_feed | grep -c "$REQ2")" "1"
rpc $N2 cancel_request "{\"p_request_id\":\"$REQ2\"}" >/dev/null
rpc $ADMIN admin_set_driver_city "{\"p_driver_id\":\"33333333-3333-4333-8333-000000000011\",\"p_city_id\":\"$KAMALIA\"}" >/dev/null

echo "Row lock: two simultaneous selections on Sana's request -> exactly one wins"
SREQ=55555555-5555-4555-8555-000000000010
rpc $S select_offer '{"p_offer_id":"66666666-6666-4666-8666-000000000010"}' > /tmp/kg_sel1 &
rpc $S select_offer '{"p_offer_id":"66666666-6666-4666-8666-000000000011"}' > /tmp/kg_sel2 &
wait
check "one success, one refusal" "$(cat /tmp/kg_sel1 /tmp/kg_sel2 | grep -c '"offer_id"')" "1"
check "exactly one ride for that request" "$(get $S "rides?request_id=eq.$SREQ&select=id" | py 'print(len(d))')" "1"

echo "SOS during an active ride"
SOS1=$(rpc $N trigger_sos "{\"p_ride_id\":\"$RIDE\",\"p_lat\":32.1,\"p_lng\":73.6}" | tr -d '"')
check "passenger SOS creates an alert" "$([ ${#SOS1} = 36 ] && echo yes || echo no)" "yes"
check "pressing SOS twice reuses the alert" "$(rpc $N trigger_sos "{\"p_ride_id\":\"$RIDE\"}" | tr -d '"')" "$SOS1"
check "stranger (driver C) cannot raise SOS on it" "$(rpc $C trigger_sos "{\"p_ride_id\":\"$RIDE\"}" | py 'print(d.get("code"))')" "P0002"
check "admin got an SOS notification" "$(get $ADMIN 'notifications?type=eq.SOS&select=id' | py 'print(len(d)>=1)')" "True"

echo "Driver B: arrived, start, complete"
check "passenger cannot start the ride" "$(rpc $N update_ride_status "{\"p_ride_id\":\"$RIDE\",\"p_new_status\":\"RIDE_STARTED\"}" | py 'print(d.get("code"))')" "22023"
check "only the driver can tap arrived" "$(rpc $N driver_arrived "{\"p_ride_id\":\"$RIDE\"}" | py 'print(d.get("code"))')" "P0002"
check "driver taps arrived at the pickup" "$(rpc $B driver_arrived "{\"p_ride_id\":\"$RIDE\"}" | py 'print(d["arrived_at"] is not None)')" "True"
check "passenger was told the driver arrived" "$(get $N 'notifications?type=eq.DRIVER_ARRIVED&select=id' | py 'print(len(d)>=1)')" "True"
check "cannot complete before starting" "$(rpc $B complete_ride "{\"p_ride_id\":\"$RIDE\"}" | py 'print(d.get("code"))')" "22023"
check "B starts ride" "$(rpc $B update_ride_status "{\"p_ride_id\":\"$RIDE\",\"p_new_status\":\"RIDE_STARTED\"}" | py 'print(d["status"])')" "RIDE_STARTED"
check "driver cannot tap arrived once the ride started" "$(rpc $B driver_arrived "{\"p_ride_id\":\"$RIDE\"}" | py 'print(d.get("code"))')" "22023"
check "commission 150 / driver 1,350 (10% of 1,500, no waiting charge inside the free time)" "$(rpc $B complete_ride "{\"p_ride_id\":\"$RIDE\"}" | py 'print(int(d["commission_amount"]), int(d["driver_earning"]))')" "150 1350"
check "ledger shows commission due" "$(get $B "driver_ledger?ride_id=eq.$RIDE&select=amount,entry_type" | py 'print(int(d[0]["amount"]), d[0]["entry_type"])')" "150 COMMISSION_DUE"
check "ride details carry the money breakdown" "$(rpc $N get_ride_details "{\"p_ride_id\":\"$RIDE\"}" | py 'print(int(d["accepted_fare"]), int(d["waiting_charge"]), d["category"])')" "1500 0 car_mini"

echo "Commission cannot be tampered with from the client"
check "insert commission denied" "$(post $B commissions "{\"ride_id\":\"$RIDE\",\"driver_id\":\"x\",\"final_fare\":1,\"commission_percent\":0,\"commission_amount\":0,\"driver_earning\":1}" | py 'print(d.get("code"))')" "42501"
check "update ride fare denied" "$(patch $N "rides?id=eq.$RIDE" '{"final_fare":1}' | py 'print(d.get("code"))')" "42501"
check "update ledger denied" "$(patch $B "driver_ledger?ride_id=eq.$RIDE" '{"amount":0}' | py 'print(d.get("code"))')" "42501"
check "passenger edits settings denied" "$(patch $N "settings?key=eq.commission_percent" '{"value":0}')" "[]"

echo "Rating and history"
check "rating saved" "$(rpc $N rate_ride "{\"p_ride_id\":\"$RIDE\",\"p_stars\":5,\"p_comment\":\"Great\"}" | py 'print(d["stars"])')" "5"
check "ride in passenger history" "$(rpc $N get_my_rides | py "print(any(r['ride_id']=='$RIDE' and r['status']=='COMPLETED' and r['my_rating']==5 for r in d))")" "True"
check "ride in driver history with earning" "$(rpc $B get_my_rides | py "print([int(r['driver_earning']) for r in d if r['ride_id']=='$RIDE'])")" "[1350]"

echo "Admin: category change, fare report, settings"
check "non-admin cannot change a driver's ride type" "$(rpc $B admin_set_driver_category "{\"p_driver_id\":\"33333333-3333-4333-8333-000000000012\",\"p_category\":\"car_xl\"}" | py 'print(d.get("code"))')" "42501"
rpc $ADMIN admin_set_driver_category '{"p_driver_id":"33333333-3333-4333-8333-000000000011","p_category":"car_xl"}' >/dev/null
check "admin moved driver A to XL" "$(rpc $ADMIN admin_list_drivers | py 'print([r["category"] for r in d if r["driver_id"]=="33333333-3333-4333-8333-000000000011"])')" "['car_xl']"
rpc $ADMIN admin_set_driver_category '{"p_driver_id":"33333333-3333-4333-8333-000000000011","p_category":"car_mini"}' >/dev/null
check "fare report: Toba Tek Singh / Car Mini row exists" "$(rpc $ADMIN admin_fare_report '{}' | py 'print([(r["city_name"], r["category"], int(r["rides"]) >= 1) for r in d if r["category"]=="car_mini" and r["city_name"]=="Toba Tek Singh"])')" "[('Toba Tek Singh', 'car_mini', True)]"
check "a passenger cannot read the fare report" "$(rpc $N admin_fare_report '{}' | py 'print(d.get("code"))')" "42501"
check "a passenger cannot change a ride type's fares" "$(patch $N "ride_categories?code=eq.car_mini" '{"min_fare":1}' | py 'print(len(d) if isinstance(d,list) else d.get("code"))')" "0"
check "admin can change a ride type's minimum fare" "$(patch $ADMIN "ride_categories?code=eq.car_mini" '{"min_fare":460}' | py 'print(int(d[0]["min_fare"]))')" "460"
patch $ADMIN "ride_categories?code=eq.car_mini" '{"min_fare":450}' >/dev/null
check "admin can change the petrol price (setting)" "$(patch $ADMIN "settings?key=eq.petrol_price" '{"value":410}' | py 'print(d[0]["value"])')" "410"
check "...and the fare follows it (not hard-coded)" "$([ $(fc 20 car_mini) -gt 2310 ] && echo higher)" "higher"
patch $ADMIN "settings?key=eq.petrol_price" '{"value":400}' >/dev/null
check "fare is back to 2310" "$(fc 20 car_mini)" "2310"

echo "Passenger gets told when nobody answered"
check "the wait before the nudge is a setting (default 3 minutes)" "$(get $N 'settings?key=eq.no_driver_notify_minutes&select=value' | py 'print(d[0]["value"])')" "3"
check "the nudge job runs on the server only (not callable from the app)" "$(rpc $ADMIN nudge_unanswered_requests | py 'print(d.get("code"))')" "42501"

echo "Places (admin only to change)"
check "passengers can read the places list" "$(get $N 'places?select=id&limit=1000' | py 'print(len(d) > 100)')" "True"
check "a passenger cannot add a place" "$(post $N places '{"name":"Hacked Stop","kind":"stop","lat":30.7,"lng":72.6}' | py 'print(d.get("code") is not None)')" "True"

echo "Places exactly as the passenger wrote them (driver, ride screen, history)"
WREQ=$(rpc $N create_ride_request_geo '{"p_pickup_lat":30.9709,"p_pickup_lng":72.4826,"p_dropoff_lat":31.05,"p_dropoff_lng":72.5,"p_passenger_count":1,"p_offered_fare":1400,"p_pickup_label":"bilal town","p_dropoff_label":"ravi town kamalia","p_category":"car_mini"}' | py 'print(d["id"])')
check "the driver's request shows both places exactly as written" "$(rpc $B get_driver_feed | py "print([(r['pickup_label'], r['dropoff_label']) for r in d if r['request_id']=='$WREQ'])")" "[('bilal town', 'ravi town kamalia')]"
WO=$(rpc $B submit_offer "{\"p_request_id\":\"$WREQ\",\"p_offer_type\":\"ACCEPT\",\"p_eta_min\":5}" | py 'print(d["id"])')
WRIDE=$(get $N "rides?request_id=eq.$WREQ&select=id" | py 'print(d[0]["id"])')
check "ride details give both sides the ETA" "$(rpc $N get_ride_details "{\"p_ride_id\":\"$WRIDE\"}" | py 'print(d["eta_min"])') $(rpc $B get_ride_details "{\"p_ride_id\":\"$WRIDE\"}" | py 'print(d["eta_min"])')" "5 5"
check "the ride screen data keeps the written places" "$(rpc $B get_ride_details "{\"p_ride_id\":\"$WRIDE\"}" | py 'print(d["origin"]["label"], "|", d["destination"]["label"])')" "bilal town | ravi town kamalia"
check "the driver can start straight from CONFIRMED" "$(rpc $B update_ride_status "{\"p_ride_id\":\"$WRIDE\",\"p_new_status\":\"RIDE_STARTED\"}" | py 'print(d["status"])')" "RIDE_STARTED"
rpc $B complete_ride "{\"p_ride_id\":\"$WRIDE\"}" >/dev/null
check "ride history uses the written places" "$(rpc $N get_my_rides '{}' | py 'print(d[0]["origin_name"], "|", d[0]["destination_name"])')" "bilal town | ravi town kamalia"

echo "Booking types: hourly, round trip, scheduled"
check "package 4h prices: Mini 3940 / Comfort 4910 / XL 5560" "$(P4=$(get $N 'hourly_packages?hours=eq.4&select=id' | py 'print(d[0]["id"])'); for c in car_mini car_comfort car_xl; do rpc $N fare_calc_hourly "{\"p_category\":\"$c\",\"p_package_id\":\"$P4\"}" | py 'print(int(d[0]["recommended"]),end=" ")'; done)" "3940 4910 5560 "
check "round trip Mini: 20 km = 3530, 95 km = 10610, 20 km + 1h30 waiting = 3780" "$(rpc $N fare_calc_round_trip '{"p_distance":20,"p_category":"car_mini","p_expected_wait_min":0}' | py 'print(int(d[0]["recommended"]),end=" ")') $(rpc $N fare_calc_round_trip '{"p_distance":95,"p_category":"car_mini","p_expected_wait_min":0}' | py 'print(int(d[0]["recommended"]),end=" ")') $(rpc $N fare_calc_round_trip '{"p_distance":20,"p_category":"car_mini","p_expected_wait_min":90}' | py 'print(int(d[0]["recommended"]))')" "3530  10610  3780"
check "hourly packages are readable (2h/4h/8h/12h)" "$(get $N 'hourly_packages?select=hours,included_km&order=sort_order' | py 'print([(p["hours"], int(p["included_km"])) for p in d])')" "[(2, 20), (4, 40), (8, 80), (12, 120)]"
check "a passenger cannot edit packages" "$(patch $N 'hourly_packages?hours=eq.4' '{"included_km":1}' | py 'print(len(d) if isinstance(d,list) else d.get("code"))')" "0"
check "admin can edit a package" "$(patch $ADMIN 'hourly_packages?hours=eq.4' '{"included_km":41}' | py 'print(int(d[0]["included_km"]))')" "41"
patch $ADMIN 'hourly_packages?hours=eq.4' '{"included_km":40}' >/dev/null
P4=$(get $N 'hourly_packages?hours=eq.4&select=id' | py 'print(d[0]["id"])')
P2=$(get $N 'hourly_packages?hours=eq.2&select=id' | py 'print(d[0]["id"])')
bk() { rpc ${WHO:-$N} create_ride_request_geo "{\"p_pickup_lat\":30.9709,\"p_pickup_lng\":72.4826,\"p_dropoff_lat\":${3:-31.05},\"p_dropoff_lng\":${4:-72.5},\"p_passenger_count\":1,\"p_offered_fare\":$1,\"p_category\":\"${2:-car_mini}\",\"p_booking_type\":\"$5\",\"p_package_id\":${6:-null},\"p_expected_wait_min\":${7:-0},\"p_scheduled_at\":${8:-null}}"; }
check "Bike cannot be booked hourly" "$(bk 500 bike 31.05 72.5 hourly "\"$P4\"" | py 'print(d.get("code"))')" "22023"
check "Rickshaw cannot be booked as a round trip" "$(bk 800 rickshaw 31.05 72.5 round_trip null 0 | py 'print(d.get("code"))')" "22023"
check "hourly needs a package" "$(bk 3940 car_mini 31.05 72.5 hourly null | py 'print(d.get("code"))')" "22023"
check "hourly offer under 85% refused" "$(bk 3000 car_mini 31.05 72.5 hourly "\"$P4\"" | py 'print(d.get("code"))')" "22023"
HREQ=$(bk 3940 car_mini 31.05 72.5 hourly "\"$P4\"" | py 'print(d["id"])')
check "hourly 4h request: recommended 3940, package stored" "$(get $N "ride_requests?id=eq.$HREQ&select=booking_type,package_hours,package_km,recommended_fare" | py 'r=d[0];print(r["booking_type"], r["package_hours"], int(r["package_km"]), int(r["recommended_fare"]))')" "hourly 4 40 3940"
check "driver card: Hourly 4h data, commission 394 / you get 3546" "$(rpc $B get_driver_feed | py "print([(r['booking_type'], r['package_hours'], int(r['commission']), int(r['driver_gets'])) for r in d if r['request_id']=='$HREQ'])")" "[('hourly', 4, 394, 3546)]"
check "same dispatch rules: Kamalia driver A does not see it" "$(rpc $A get_driver_feed | grep -c "$HREQ")" "0"
HO=$(rpc $B submit_offer "{\"p_request_id\":\"$HREQ\",\"p_offer_type\":\"ACCEPT\",\"p_eta_min\":5}" | py 'print(d["id"])')
HRIDE=$(get $N "rides?request_id=eq.$HREQ&select=id" | py 'print(d[0]["id"])')
check "ride remembers booking type and package" "$(get $N "rides?id=eq.$HRIDE&select=booking_type,package_hours,package_km" | py 'r=d[0];print(r["booking_type"], r["package_hours"], int(r["package_km"]))')" "hourly 4 40"
check "destination buttons are for round trips only" "$(rpc $B driver_reached_destination "{\"p_ride_id\":\"$HRIDE\"}" | py 'print(d.get("code"))')" "22023"
check "km counter needs a started ride" "$(rpc $B update_ride_progress "{\"p_ride_id\":\"$HRIDE\",\"p_actual_km\":10}" | py 'print(d.get("code"))')" "22023"
rpc $B update_ride_status "{\"p_ride_id\":\"$HRIDE\",\"p_new_status\":\"RIDE_STARTED\"}" >/dev/null
check "driver app reports the km travelled (only grows)" "$(rpc $B update_ride_progress "{\"p_ride_id\":\"$HRIDE\",\"p_actual_km\":55.3}" | py 'print(float(d["actual_km"]))') $(rpc $B update_ride_progress "{\"p_ride_id\":\"$HRIDE\",\"p_actual_km\":20}" | py 'print(float(d["actual_km"]))')" "55.3 55.3"
check "passenger cannot report km" "$(rpc $N update_ride_progress "{\"p_ride_id\":\"$HRIDE\",\"p_actual_km\":1}" | py 'print(d.get("code"))')" "P0002"
check "the ride screen sees the live km and minutes" "$(rpc $N get_ride_details "{\"p_ride_id\":\"$HRIDE\"}" | py 'print(d["booking_type"], d["package_hours"], float(d["actual_km"]), d["actual_minutes"])')" "hourly 4 55.3 0"
rpc $B complete_ride "{\"p_ride_id\":\"$HRIDE\"}" >/dev/null
check "hourly end: 3940 + 15.3 extra km x 60 = 4858 (commission 485.80), no extra hour" "$(rpc $N get_ride_details "{\"p_ride_id\":\"$HRIDE\"}" | py 'print(int(d["final_fare"]), float(d["extra_km"]), int(d["extra_km_charge"]), d["extra_hours"], int(d["extra_hour_charge"]))')" "4858 15.3 918 0 0"
check "both sides get the breakdown; driver also sees commission and what he gets" "$(rpc $B get_ride_details "{\"p_ride_id\":\"$HRIDE\"}" | py 'print(int(d["commission_amount"]), int(d["driver_gets"]))') / $(rpc $N get_ride_details "{\"p_ride_id\":\"$HRIDE\"}" | py 'print(d["driver_gets"])')" "485 4372 / None"
check "ride stores actual_km, actual_minutes and commission" "$(get $ADMIN "rides?id=eq.$HRIDE&select=actual_km,actual_minutes,commission_amount,driver_gets" | py 'r=d[0];print(float(r["actual_km"]), r["actual_minutes"], int(r["commission_amount"]), int(r["driver_gets"]))')" "55.3 0 485 4372"

echo "Round trip: destination waiting, 30 minutes free"
RREQ=$(bk 3800 car_mini 31.05 72.5 round_trip null 90 | py 'print(d["id"])')
check "round trip request stores the expected waiting and its charge" "$(get $N "ride_requests?id=eq.$RREQ&select=booking_type,expected_wait_min,expected_wait_charge" | py 'r=d[0];print(r["booking_type"], r["expected_wait_min"], int(r["expected_wait_charge"]))')" "round_trip 90 250"
check "round trip quote = base round trip fare + waiting" "$(get $N "ride_requests?id=eq.$RREQ&select=recommended_fare,distance_km" | py 'print(int(d[0]["recommended_fare"]), float(d[0]["distance_km"]))' )" "$(DK=$(get $N "ride_requests?id=eq.$RREQ&select=distance_km" | py 'print(d[0]["distance_km"])'); echo "$(rpc $N fare_calc_round_trip "{\"p_distance\":$DK,\"p_category\":\"car_mini\",\"p_expected_wait_min\":90}" | py 'print(int(d[0]["recommended"]))') $DK")"
RO=$(rpc $B submit_offer "{\"p_request_id\":\"$RREQ\",\"p_offer_type\":\"ACCEPT\",\"p_eta_min\":5}" | py 'print(d["id"])')
RRIDE=$(get $N "rides?request_id=eq.$RREQ&select=id" | py 'print(d[0]["id"])')
check "return cannot start before arriving at the destination" "$(rpc $B driver_return_started "{\"p_ride_id\":\"$RRIDE\"}" | py 'print(d.get("code"))')" "22023"
rpc $B update_ride_status "{\"p_ride_id\":\"$RRIDE\",\"p_new_status\":\"RIDE_STARTED\"}" >/dev/null
check "driver taps Arrived at destination" "$(rpc $B driver_reached_destination "{\"p_ride_id\":\"$RRIDE\"}" | py 'print(d["dest_arrived_at"] is not None)')" "True"
check "passenger was told" "$(get $N 'notifications?type=eq.DESTINATION_REACHED&select=id' | py 'print(len(d)>=1)')" "True"
check "driver taps Return started" "$(rpc $B driver_return_started "{\"p_ride_id\":\"$RRIDE\"}" | py 'print(d["return_started_at"] is not None)')" "True"
rpc $B complete_ride "{\"p_ride_id\":\"$RRIDE\"}" >/dev/null
check "no waiting happened: final = agreed fare - expected waiting charge (250)" "$(rpc $N get_ride_details "{\"p_ride_id\":\"$RRIDE\"}" | py 'print(int(d["final_fare"]) + int(d["expected_wait_charge"]) - int(d["accepted_fare"]), int(d["dest_waiting_charge"]), d["dest_waiting_minutes"])')" "0 0 0"

echo "Scheduled bookings: no overlapping offers for a driver with an accepted booking"
in_hours() { date -u -d "@$(( $(date +%s) + $1 * 3600 ))" +%Y-%m-%dT%H:%M:%SZ; }
SREQ1=$(bk 2400 car_mini 31.05 72.5 hourly "\"$P2\"" 0 "\"$(in_hours 3)\"" | py 'print(d["id"])')
check "scheduled request is sent to drivers immediately and carries its time" "$(rpc $B get_driver_feed | py "print([r['scheduled_at'] is not None for r in d if r['request_id']=='$SREQ1'])")" "[True]"
SO=$(rpc $B submit_offer "{\"p_request_id\":\"$SREQ1\",\"p_offer_type\":\"ACCEPT\",\"p_eta_min\":5}" | py 'print(d["id"])')
SRIDE=$(get $N "rides?request_id=eq.$SREQ1&select=id" | py 'print(d[0]["id"])')
check "ride keeps the scheduled time" "$(get $N "rides?id=eq.$SRIDE&select=scheduled_at,status" | py 'print(d[0]["scheduled_at"] is not None, d[0]["status"])')" "True CONFIRMED"
check "a far-off scheduled ride does not make the driver busy: immediate request still reaches B" "$(WHO=$P; I=$(WHO=$P bk 1400 car_mini 31.05 72.5 one_way null 0 | py 'print(d["id"])'); echo $(rpc $B get_driver_feed | grep -c "$I"); rpc $P cancel_request "{\"p_request_id\":\"$I\"}" >/dev/null)" "1"
OV=$(WHO=$P bk 1400 car_mini 31.05 72.5 one_way null 0 "\"$(in_hours 3)\"" | py 'print(d["id"])')
check "a request overlapping the accepted booking is NOT shown to B" "$(rpc $B get_driver_feed | grep -c "$OV")" "0"
rpc $ADMIN admin_set_driver_city "{\"p_driver_id\":\"33333333-3333-4333-8333-000000000011\",\"p_city_id\":\"$TOBA\"}" >/dev/null
check "...but a free Mini driver sees it" "$(rpc $A get_driver_feed | grep -c "$OV")" "1"
check "...and B cannot offer on it" "$(rpc $B submit_offer "{\"p_request_id\":\"$OV\",\"p_offer_type\":\"ACCEPT\"}" | py 'print(d.get("code"))')" "P0002"
rpc $P cancel_request "{\"p_request_id\":\"$OV\"}" >/dev/null
LATER=$(WHO=$P bk 1400 car_mini 31.05 72.5 one_way null 0 "\"$(in_hours 8)\"" | py 'print(d["id"])')
check "a request well after the booking is shown to B" "$(rpc $B get_driver_feed | grep -c "$LATER")" "1"
rpc $P cancel_request "{\"p_request_id\":\"$LATER\"}" >/dev/null
rpc $ADMIN admin_set_driver_city "{\"p_driver_id\":\"33333333-3333-4333-8333-000000000011\",\"p_city_id\":\"$KAMALIA\"}" >/dev/null
check "reminder job: nothing is due yet for a booking 3 hours away" "$(rpc $B remind_scheduled_rides | tr -d '"')" "0"
rpc $N cancel_ride "{\"p_ride_id\":\"$SRIDE\",\"p_reason\":\"PASSENGER_CANCELLED\"}" >/dev/null
check "fare report can be filtered by booking type" "$(rpc $ADMIN admin_fare_report '{"p_booking_type":"hourly"}' | py 'print(sorted(set(r["booking_type"] for r in d)))') $(rpc $ADMIN admin_fare_report '{"p_booking_type":"round_trip"}' | py 'print(sorted(set(r["booking_type"] for r in d)))')" "['hourly'] ['round_trip']"
echo "Earnings and cancellation"
check "driver B's dashboard shows today's earnings after completing rides" "$(rpc $B get_driver_dashboard | py 'print(float(d["earnings"]["today"]) >= 1350, int(d["earnings"]["rides_today"]) >= 1)')" "True True"
CREQ2=$(WHO=$P geo $TOBA_P $NEAR_TOBA 1400 | py 'print(d["id"])')
CO=$(rpc $B submit_offer "{\"p_request_id\":\"$CREQ2\",\"p_offer_type\":\"ACCEPT\",\"p_eta_min\":5}" | py 'print(d["id"])')
CRIDE=$(get $P "rides?request_id=eq.$CREQ2&select=id" | py 'print(d[0]["id"])')
check "driver B has the confirmed ride as active" "$(rpc $B get_my_active | py 'print(d.get("ride_id") == "'$CRIDE'")')" "True"
rpc $P cancel_ride "{\"p_ride_id\":\"$CRIDE\",\"p_reason\":\"PASSENGER_CANCELLED\"}" >/dev/null
check "after the passenger cancels, the ride is gone for driver B" "$(rpc $B get_my_active | py 'print(d.get("ride_id"))')" "None"
check "and the cancelled request is not in anyone's feed" "$(rpc $B get_driver_feed | grep -c "$CREQ2")" "0"
echo "KAM GO learns addresses from drivers' GPS"
LREQ=$(rpc $P create_ride_request_geo '{"p_pickup_lat":30.9709,"p_pickup_lng":72.4826,"p_dropoff_lat":31.05,"p_dropoff_lng":72.5,"p_passenger_count":1,"p_offered_fare":1400,"p_category":"car_mini","p_pickup_label":"Gulshan Iqbal Toba — near masjid"}' | py 'print(d["id"])')
LO=$(rpc $B submit_offer "{\"p_request_id\":\"$LREQ\",\"p_offer_type\":\"ACCEPT\",\"p_eta_min\":5}" | py 'print(d["id"])')
LRIDE=$(get $P "rides?request_id=eq.$LREQ&select=id" | py 'print(d[0]["id"])')
rpc $B driver_arrived "{\"p_ride_id\":\"$LRIDE\",\"p_lat\":30.9801,\"p_lng\":72.4903}" >/dev/null
check "the typed pickup became a saved place at the driver's GPS spot" "$(get $N 'places?name=eq.Gulshan%20Iqbal%20Toba&select=source,confirmations,lat' | py 'print([(p["source"], p["confirmations"], round(p["lat"],4)) for p in d])')" "[('learned', 1, 30.9801)]"
rpc $P cancel_ride "{\"p_ride_id\":\"$LRIDE\",\"p_reason\":\"PASSENGER_CANCELLED\"}" >/dev/null
check "words like 'Map pin' are never learned" "$(get $N 'places?source=eq.learned&name=ilike.map%20pin&select=id' | py 'print(len(d))')" "0"
check "a user cannot send fake notifications (notify is internal)" "$(rpc $N notify '{"p_user_id":"33333333-3333-4333-8333-000000000012","p_type":"X","p_title":"fake","p_body":"fake"}' | py 'print(d.get("code") is not None)')" "True"
check "a user cannot trigger dispatch_request" "$(rpc $N dispatch_request '{"p_request_id":"55555555-5555-4555-8555-000000000010","p_title":"x","p_body":"x"}' | py 'print(d.get("code") is not None)')" "True"
check "a user cannot read a driver's position through driver_position_now" "$(rpc $N driver_position_now '{"p_ride_id":"77777777-7777-4777-8777-000000000001","p_driver":"33333333-3333-4333-8333-000000000014"}' | py 'print(d.get("code") is not None if isinstance(d,dict) else False)')" "True"
check "a passenger cannot call learn_place directly" "$(rpc $N learn_place '{"p_label":"fake","p_lat":30.97,"p_lng":72.48}' | py 'print(d.get("code") is not None)')" "True"
echo "Driver registration: city + vehicle model decides the category"
M=$(login +923000000099)
rpc $M complete_profile '{"p_full_name":"Mode Tester","p_role":"PASSENGER"}' >/dev/null
check "become_driver starts a PENDING application" "$(rpc $M become_driver | py 'print(d["status"])')" "PENDING"
check "a pending driver cannot go online" "$(rpc $M set_driver_online '{"p_online":true}' | py 'print(d.get("code") is not None)')" "True"
reg() { rpc $M save_driver_application "{\"p_cnic\":\"3310012345671\",\"p_city_id\":\"${5:-$TOBA}\",\"p_vehicle_make\":\"$1\",\"p_vehicle_model\":\"$2\",\"p_vehicle_color\":\"White\",\"p_plate_number\":\"$3\",\"p_seats\":4,\"p_vehicle_year\":2020,\"p_ac_available\":${4:-false}}"; }
check "a Toyota Fortuner is not on the model list" "$(reg Toyota Fortuner TTM-001 | py 'print(d.get("code"))')" "22023"
check "a Suzuki Alto is accepted" "$(reg Suzuki Alto TTM-002 | py 'print(d["status"])')" "PENDING"
check "...and becomes Car Mini in Toba Tek Singh" "$(get $M 'vehicles?select=category,ac_available' | py 'print(d[0]["category"], d[0]["ac_available"])') $(get $M 'drivers?select=city_id' | py 'print(d[0]["city_id"])')" "car_mini False $TOBA"
check "a Honda Civic with AC becomes Car Comfort" "$(reg Honda Civic TTM-004 true | py 'print(d["status"])') $(get $M 'vehicles?select=category,ac_available' | py 'print(d[0]["category"], d[0]["ac_available"])')" "PENDING car_comfort True"
check "a Honda CD 70 becomes a Bike (AC ignored for non-cars)" "$(reg Honda 'CD 70' TTM-005 true | py 'print(d["status"])') $(get $M 'vehicles?select=category,ac_available' | py 'print(d[0]["category"], d[0]["ac_available"])')" "PENDING bike False"
check "the city is required" "$(rpc $M save_driver_application '{"p_cnic":"3310012345671","p_vehicle_make":"Suzuki","p_vehicle_model":"Alto","p_vehicle_color":"White","p_plate_number":"TTM-006","p_seats":4,"p_vehicle_year":2020}' | py 'print(d.get("code") is not None)')" "True"
check "model list is readable by every signed-in user" "$(get $N 'vehicle_models?select=category,model&order=category,model' | py 'print([m["model"] for m in d if m["category"]=="car_mini"])')" "['Alto', 'Cultus', 'Mehran', 'Swift', 'Wagon R']"
check "a passenger cannot add a model" "$(post $N vehicle_models '{"category":"car_mini","make":"X","model":"Y"}' | py 'print(d.get("code") is not None)')" "True"
check "admins cannot use become_driver" "$(rpc $ADMIN become_driver | py 'print(d.get("code"))')" "42501"
check "the same account can still book as a passenger" "$(rpc $M create_ride_request_geo '{"p_pickup_lat":30.9709,"p_pickup_lng":72.4826,"p_dropoff_lat":31.05,"p_dropoff_lng":72.5,"p_passenger_count":1,"p_offered_fare":1400}' | py 'print(len(d["id"]))')" "36"

echo
echo "Passed: $PASS   Failed: $FAIL"
[ "$FAIL" = 0 ]