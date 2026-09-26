# One command to bring the whole Sathiyaa platform up locally:
# MySQL, the API, and the web apps. Nothing here costs anything - every
# third-party integration is stubbed until keys are configured.
. C:\sathiyaa-dev\env.ps1

$root = "C:\Only Forward\Sathiyaa\sathiyaa-full-project - Flutter Web version"
$node = "C:\sathiyaa-dev\node\node.exe"
$vite = "node_modules\vite\bin\vite.js"

function Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }

Step "MySQL"
if (Get-Process mysqld -ErrorAction SilentlyContinue) {
    Write-Host "   already running"
} else {
    Start-Process "C:\sathiyaa-dev\mysql\bin\mysqld.exe" `
        -ArgumentList "--datadir=C:\sathiyaa-dev\mysql-data","--basedir=C:\sathiyaa-dev\mysql","--port=3306","--bind-address=127.0.0.1" `
        -WindowStyle Hidden
    Start-Sleep -Seconds 6
    Write-Host "   started"
}

Step "API (port 4000)"
Get-Process node -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "C:\sathiyaa-dev\node\*" } | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process $node -ArgumentList "src\server.js" -WorkingDirectory "$root\backend" `
    -WindowStyle Hidden -RedirectStandardOutput "C:\sathiyaa-dev\backend.log" -RedirectStandardError "C:\sathiyaa-dev\backend.err.log"
Start-Sleep -Seconds 6

$health = curl.exe -s -o NUL -w "%{http_code}" http://localhost:4000/health
if ($health -eq "200") {
    Write-Host "   up" -ForegroundColor Green
    # Which integrations are real and which are stubbed - worth knowing at a glance.
    Get-Content "C:\sathiyaa-dev\backend.log" |
        Select-String "^\[integrations\]|^ +(stub|LIVE)" |
        ForEach-Object { Write-Host "   $_" }
} else {
    Write-Host "   FAILED - see C:\sathiyaa-dev\backend.err.log" -ForegroundColor Red
    Get-Content "C:\sathiyaa-dev\backend.err.log" -Tail 10
    Write-Host "`nStopping here; the web apps are not much use without the API." -ForegroundColor Red
    return
}

# The admin console can run two ways, and which one you are looking at matters:
# demo data is self-contained and proves nothing about your server, while the
# live build shows what your phones actually did. Build both, serve both, so
# there is never a doubt about which is on screen.
Step "Admin console - building both modes"

Push-Location "$root\admin-portal"

# Note: no `2>&1` on these. Redirecting a native command's stderr inside
# PowerShell 5.1 wraps each line in an error record and can stall the pipeline.
$env:VITE_USE_MOCK = "true"
$env:VITE_API_BASE_URL = $null
& $node $vite build --outDir dist-demo --emptyOutDir | Out-Null
Write-Host "   demo build -> dist-demo"

$env:VITE_USE_MOCK = "false"
$env:VITE_API_BASE_URL = "http://localhost:4000/api/v1"
& $node $vite build --outDir dist-live --emptyOutDir | Out-Null
Write-Host "   live build -> dist-live"

$env:VITE_USE_MOCK = $null
$env:VITE_API_BASE_URL = $null

# Their output goes to log files, not to this console -- otherwise they hold
# its handle open and this script never returns to the prompt.
Start-Process $node -ArgumentList $vite,"preview","--outDir","dist-demo","--port","4173","--strictPort" `
    -WorkingDirectory (Get-Location) -WindowStyle Hidden `
    -RedirectStandardOutput "C:\sathiyaa-dev\admin-demo.log" -RedirectStandardError "C:\sathiyaa-dev\admin-demo.err.log"
Start-Process $node -ArgumentList $vite,"preview","--outDir","dist-live","--port","4180","--strictPort" `
    -WorkingDirectory (Get-Location) -WindowStyle Hidden `
    -RedirectStandardOutput "C:\sathiyaa-dev\admin-live.log" -RedirectStandardError "C:\sathiyaa-dev\admin-live.err.log"
Pop-Location

# The real Flutter apps, compiled for the browser -- the same lib/ code the
# APKs are built from, so what is on screen here is what is on the phone.
# (The separate customer-app-web / provider-app-web folders are an older
# React rewrite and are deliberately NOT served: looking at those while
# changing the Flutter code is a good way to wonder why nothing you do has
# any effect.)
Step "Customer & provider apps in the browser"
$flutterSrc = "C:\Only Forward\Sathiyaa\Sathiyaa Flutter\Sathiyaa Flutter"
$webApps = [ordered]@{ "customer_app" = 4174; "provider_app" = 4175 }
foreach ($a in $webApps.Keys) {
    $dir = "$flutterSrc\$a\build\web"
    if (-not (Test-Path "$dir\index.html")) {
        Write-Host "   $a is not built for the browser yet - run rebuild-apks.ps1" -ForegroundColor Yellow
        continue
    }
    Start-Process $node -ArgumentList @("`"$PSScriptRoot\static-server.mjs`"", "$($webApps[$a])", "`"$dir`"") `
        -WindowStyle Hidden `
        -RedirectStandardOutput "C:\sathiyaa-dev\$a-web.log" -RedirectStandardError "C:\sathiyaa-dev\$a-web.err.log"
    Write-Host "   $a -> http://localhost:$($webApps[$a])"
}
Start-Sleep -Seconds 6

Write-Host "`n=== Everything is up ===" -ForegroundColor Green
Write-Host "  API                     http://localhost:4000/api/v1"
Write-Host ""
Write-Host "  Admin console - REAL DATA   http://localhost:4180   (what your phones actually did)" -ForegroundColor Yellow
Write-Host "  Admin console - demo data   http://localhost:4173"
Write-Host "  Sign in with admin@sathiyaa.com / Admin@123"
Write-Host ""
Write-Host "  Customer app in a browser   http://localhost:4174   (the real Flutter app)"
Write-Host "  Provider app in a browser   http://localhost:4175   (the real Flutter app)"
Write-Host ""
Write-Host "  Phone apps: install the APKs in this folder, then run"
Write-Host "  phone-connection-info.ps1 for the address to enter in the app."
Write-Host ""
Write-Host "Stop everything with: stop-everything.ps1"
