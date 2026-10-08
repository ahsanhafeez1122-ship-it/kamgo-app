# KAM GO — testing guide

OTP for every demo number is **123456**.

## 1. Start everything (Windows)

```powershell
cd d:\kamgo-app-main
D:\supabase-cli\supabase.exe start        # local database, if it is not running
D:\supabase-cli\supabase.exe db reset     # fresh data (run again before every full test)
$env:Path = "D:\flutter\bin;$env:Path"
flutter run -d web-server --release --web-port 8080 --web-hostname 127.0.0.1 --dart-define-from-file=.env
```

Then double-click **KAMGO Test Windows.bat** on the Desktop (or run `tools\open_test_windows.ps1`).
It opens three windows, already signed in:

| Window | Account | Role |
|---|---|---|
| Passenger | 923000000002 Ali Raza | passenger |
| Driver 1 | 923000000012 Bilal | Car Mini, Toba Tek Singh |
| Driver 2 | 923000000019 Faisal | Car XL, Toba Tek Singh |

Other demo drivers: 923000000011 Mini (Kamalia), 923000000013 Mini (Pir Mahal), 923000000014 Comfort (Toba, offline),
923000000016 Bike, 923000000017 Rickshaw, 923000000018 Loader (all Toba). Admin: 923000000001.
The **Passenger | Driver** switch at the top of every home screen flips the same account between the two sides.

## 2. Automatic checks

```powershell
flutter analyze
flutter test --exclude-tags golden                      # unit + widget tests (fares, booking, place picker...)
```

Server test (139 checks, run right after `db reset`; the seeded request expires after ~3 minutes):

```powershell
Copy-Item tools\acceptance_test.sh $env:TEMP\acc\acc.sh -Force
docker run --rm -v "$env:TEMP\acc:/w" -e SUPABASE=/w/fake.sh -e API=http://host.docker.internal:54321 kg-acc bash /w/acc.sh
```

Trips that need hours to pass (hourly 4h20m = Rs. 5400, round trip waiting = Rs. 3780 / 4030, reminders):

```powershell
Get-Content tools\test_booking_scenarios.sql | docker exec -i supabase_db_kamgo_app psql -U postgres
```

## 3. Hands-on story

1. **Driver 1, Driver 2:** switch the green toggle to Online.
2. **Passenger — City Ride:** pickup (write it, e.g. "bilal town"), destination in the same city. If the
   two places cannot be told apart the app counts ≈ 3 km (admin setting) and you can correct the Distance.
   Pick **Car Mini**, press **Find a Ride**. Only Driver 1 gets it (Driver 2 is XL).
3. **Driver 1:** Accept or Counter. **Passenger:** pick the offer → ride confirmed.
4. **Driver 1:** I'm on my way → I have arrived (waiting is free for 5 minutes) → Start → Complete.
   The Earnings tab shows the ride; the commission is 10 %.
5. **Passenger — City to City:** pick a city card (e.g. Rajana), a ride type and send it. Drivers of the
   pickup city see a "City to City" badge. **Round Trip** adds the waiting-at-destination field.
6. **Cancel tests:** cancel from the passenger side at each step; the request/ride must disappear on the driver
   side within ~10 seconds.
7. **Admin** (separate build: `flutter build web -t lib/main_admin.dart --dart-define-from-file=.env --output build/admin`):
   cities and service radius, ride types and all fare numbers, vehicle models, drivers (change city / type),
   fare report, settings.

Fares come entirely from the database (settings + ride types); nothing is hard-coded in the apps.
