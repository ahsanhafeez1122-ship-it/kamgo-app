# KAM GO — final test script

Two parts: an automatic server test (2 minutes), then a hands-on run through
the app in Chrome that follows the Section 21 acceptance story.
OTP for every demo number is **123456**.

## 0. Setup

```bash
cd ~/Kamalia/kamgo_app
export PATH="$HOME/development/flutter/bin:$PATH"
alias supabase=~/development/supabase-cli/supabase
supabase start -x studio,imgproxy,edge-runtime,logflare,vector,supavisor,mailpit,postgres-meta
supabase db reset                      # fresh seed before each full run
```

## 1. Automatic acceptance test (server)

```bash
SUPABASE=~/development/supabase-cli/supabase tools/acceptance_test.sh
dart run tools/realtime_check.dart "$(supabase status -o env | sed -n 's/^PUBLISHABLE_KEY="\(.*\)"/\1/p')"
supabase db reset                      # reset again before the manual run
```

Expected: `Passed: 35   Failed: 0`. It signs in as the demo users through the
public API — exactly like the app — and checks: Rs. 10 / Rs. 50,000 rejected;
only approved + online drivers see/offer/get notified; A accepts 1,100, B
counters 1,200, C counters 1,300; selecting B makes A and C unavailable; two
simultaneous selections → exactly one wins (row lock); only B can start and
complete; server commission **Rs. 120 / driver Rs. 1,080** + ledger; every
client attempt to write commission, ledger, fare or settings is refused;
5-star rating; ride in both histories; B sees a Rajana → Pir Mahal request as a
**return ride**; cancellation works.

## 2. Hands-on (Chrome, three windows)

Open three windows side by side (use separate Chrome profiles or one normal +
two incognito, because each window keeps its own login):

```bash
flutter run -d chrome --dart-define-from-file=.env     # then open the printed URL in the other windows
```

| Window | Sign in as |
|---|---|
| P | 0300 0000002 — Ali Raza (passenger) |
| A | 0300 0000011 — Driver A |
| B | 0300 0000012 — Driver B |

1. **P — Home.** Pickup **Pir Mahal**, destination **Rajana**, passengers **2**.
   Your Offer: type `10` → "Minimum … Rs. 440" (button disabled); `50000` →
   "Maximum … Rs. 2,200"; set **1100**. Online Drivers shows **3** in Pir Mahal adda.
2. **P — Find a Ride.** Green check "Request sent", then the radar screen
   ("Finding drivers near you…", your offer Rs. 1,100 · 2 passengers).
3. **A and B — Dashboard.** They're online in the Pir Mahal adda; the request
   appears within a second or two (and an alert slides down from the top).
   - A: **Accept Rs. 1,100**.
   - B: **Counter Offer** → 1200 → Send offer.
4. **P — Driver Offers.** Moves automatically to "N drivers responded". Imran
   (green Rs. 1,100, "Accepted your offer", green border + solid Select) and
   Bilal (navy Rs. 1,200, amber "Counter Offer"). Have B change the counter to
   1250 and back to 1200 — the number animates on P's screen.
5. **P — Select Bilal.** Ride Confirmed screen with map, Bilal's car + plate,
   Call / Message / Share Trip / Cancel. On A's dashboard the request disappears
   and A gets "Passenger chose another driver".
6. **B — Ride screen opens** (passenger name, 2 passengers, Call). Tap
   **I'm on my way** → P sees "Driver is on the way". Tap **Start Ride** → P sees
   "Ride in progress" and the car moving along the route.
7. **B — Complete Ride.** Sheet shows Final fare Rs. 1,200 / KAM GO − Rs. 120 /
   Driver earning Rs. 1,080. Confirm → summary with the server's numbers.
8. **P — Ride completed** screen appears: tap 5 stars, comment, Submit. My Rides
   shows the ride with ★★★★★.
9. **B — Earnings tab:** today Rs. 1,080 (+ earlier seed ride), commission due
   includes Rs. 120.
10. **Return ride:** sign in a new window as `0300 0000098`, choose "I need
    rides", set pickup **Rajana** → **Pir Mahal**, Find a Ride. On B's dashboard
    it appears under **Return ride opportunities** (B is now in Rajana).
11. **Offline / unapproved drivers never receive requests:** sign in as
    `0300 0000014` (offline) or `0300 0000015` (pending) — no requests, and the
    pending driver sees "Finish your registration" / "Under review".

## 3. Driver registration + admin approval

1. Sign in as `0300 0000099` → "I drive" → Rajana → **Complete registration**:
   CNIC `33100-1234567-1`, vehicle, plate, routes, upload the 6 photos (any
   images), Submit → "Under review". Going online is impossible.
2. Admin panel: `flutter run -d chrome -t lib/main_admin.dart --dart-define-from-file=.env`,
   sign in `0300 0000001`. **Drivers → Pending** → *view* documents (signed
   URLs) → **Approve**.
3. Back in the driver window: pull to refresh → online toggle appears → go online.

## 4. Admin panel tour

Dashboard totals · Drivers (approve / reject with reason / suspend, record
cash payment of commission) · Passengers (suspend) · Cities (edit, disable) ·
Routes (edit distance, disable, add stops) · Rides (filter by status / city /
name; click a row for Final Fare / KAM GO / Driver breakdown; cancel an active
ride) · Complaints · Settings (try commission 80 → refused, 12 → saved; set it
back to 10).

## 5. Weak network & extras

- Turn Wi-Fi off (or Chrome DevTools → Network → Offline): an amber
  "Connection lost" strip appears; screens keep showing the last data; turn it
  back on and they refresh.
- Profile → Language → اردو: layout flips to RTL, navigation and main screens
  in Urdu.
- Profile → Help & Support: FAQ, WhatsApp / call, report a driver / ride.
- Ride screen → Share Trip: share sheet with route, driver, plate, fare.

## 6. Unit and screenshot tests

```bash
flutter test --exclude-tags golden   # 30 tests
flutter test test/goldens            # 5 screenshot tests (Home, Splash, Finding, Offers, Driver dashboard)
```
