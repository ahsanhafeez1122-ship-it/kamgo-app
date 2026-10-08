# Opens the KAM GO test windows already signed in (no OTP typing).
#   powershell -ExecutionPolicy Bypass -File tools\open_test_windows.ps1
# Needs: local Supabase running, the web app served on http://127.0.0.1:8080.
# Each window has its own Chrome profile (%USERPROFILE%\kamgo_profiles\<name>); a fresh login
# session is written into it every time, so it also works after `supabase db reset`.
$ErrorActionPreference = 'Stop'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$app = 'http://127.0.0.1:8080'
# The web build is made from .env.lan when it exists (so phones on the Wi-Fi can use it too), else .env.
$envFile = Join-Path $PSScriptRoot '..\.env.lan'
if (-not (Test-Path $envFile)) { $envFile = Join-Path $PSScriptRoot '..\.env' }
$envLines = Get-Content $envFile
$key = ($envLines | Where-Object { $_ -like 'SUPABASE_PUBLISHABLE_KEY=*' }) -replace '^SUPABASE_PUBLISHABLE_KEY=', ''
$api = ($envLines | Where-Object { $_ -like 'SUPABASE_URL=*' }) -replace '^SUPABASE_URL=', ''
# supabase_flutter keeps the session under sb-<first part of the API host>-auth-token
$storageKey = 'sb-' + ([Uri]$api).Host.Split('.')[0] + '-auth-token'
$windows = @(
  @{ name = 'passenger'; phone = '+923000000002'; x = 20 },    # Ali Raza (passenger)
  @{ name = 'driver1';   phone = '+923000000012'; x = 450 },   # Bilal, Mini, Toba
  @{ name = 'driver2';   phone = '+923000000019'; x = 880 }    # Faisal, XL, Toba
)

function Get-Session($phone) {
  $h = @{ apikey = $key; 'Content-Type' = 'application/json' }
  Invoke-RestMethod -Method Post -Uri "$api/auth/v1/otp" -Headers $h -Body (@{ phone = $phone } | ConvertTo-Json) | Out-Null
  Invoke-RestMethod -Method Post -Uri "$api/auth/v1/verify" -Headers $h `
    -Body (@{ phone = $phone; token = '123456'; type = 'sms' } | ConvertTo-Json) | ConvertTo-Json -Depth 10 -Compress
}

function Invoke-Cdp($wsUrl, $expression) {
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ws.ConnectAsync([Uri]$wsUrl, [Threading.CancellationToken]::None).Wait()
  $msg = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $expression } } | ConvertTo-Json -Depth 5 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
  $ws.SendAsync([ArraySegment[byte]]$bytes, 'Text', $true, [Threading.CancellationToken]::None).Wait()
  $buf = New-Object byte[] 65536
  $ws.ReceiveAsync([ArraySegment[byte]]$buf, [Threading.CancellationToken]::None).Wait()
  $ws.CloseAsync('NormalClosure', '', [Threading.CancellationToken]::None).Wait()
}

$port = 9322
foreach ($w in $windows) {
  $dir = Join-Path $env:USERPROFILE "kamgo_profiles\$($w.name)"
  New-Item -ItemType Directory -Force $dir | Out-Null
  $session = Get-Session $w.phone
  # open the app with a debugging port, write the session into its storage, reload
  $p = Start-Process $chrome -PassThru -ArgumentList "--user-data-dir=$dir", "--remote-debugging-port=$port", '--no-first-run', '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding', '--disable-background-timer-throttling', "--app=$app", '--window-size=420,860', "--window-position=$($w.x),20"
  $target = $null
  for ($i = 0; $i -lt 30 -and -not $target; $i++) {
    Start-Sleep -Milliseconds 500
    try { $target = @(Invoke-RestMethod "http://127.0.0.1:$port/json") | ForEach-Object { $_ } | Where-Object { $_.type -eq 'page' -and $_.url -like "$app*" } | Select-Object -First 1 } catch {}
  }
  if (-not $target) { Write-Warning "Could not reach Chrome for $($w.name)"; continue }
  $js = "localStorage.setItem('$storageKey', " + (ConvertTo-Json $session -Compress) + "); location.reload();"
  Invoke-Cdp $target.webSocketDebuggerUrl $js
  Start-Sleep -Seconds 2   # the window stays open, signed in
  $port++
}
Write-Host 'Opened: passenger (Ali Raza), driver1 (Bilal, Mini), driver2 (Faisal, XL). Already signed in.'
