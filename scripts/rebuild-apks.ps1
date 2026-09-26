# Rebuilds both apps from source: the Android APKs, and the browser builds
# used to try the apps on a computer without a phone.
. C:\sathiyaa-dev\env.ps1
$out = "C:\Only Forward\Sathiyaa\_builds"
$src = "C:\Only Forward\Sathiyaa\Sathiyaa Flutter\Sathiyaa Flutter"

# Mirror the latest source into the space-free build copy first: Gradle and
# the Android SDK both dislike spaces in paths.
& "$out\sync-to-build.ps1"

foreach ($p in @(@{d = "customer_app"; n = "sathiyaa-customer" }, @{d = "provider_app"; n = "sathiyaa-provider" })) {
    Write-Host "=== building $($p.d) APK ===" -ForegroundColor Cyan
    Set-Location "C:\sathiyaa-build\$($p.d)"

    # A release build needs gen_snapshot.exe, and icon tree-shaking needs
    # font-subset.exe. Windows Smart App Control blocked both while it was on,
    # which is why this used to fall back to a debug APK. Both are available
    # again; the fallback stays in case the policy comes back.
    flutter build apk --release
    $release = "build\app\outputs\flutter-apk\app-release.apk"

    if ($LASTEXITCODE -eq 0 -and (Test-Path $release)) {
        Copy-Item $release "$out\$($p.n).apk" -Force
        $mb = [math]::Round((Get-Item "$out\$($p.n).apk").Length / 1MB)
        Write-Host "-> $out\$($p.n).apk  (release, $mb MB)" -ForegroundColor Green
    }
    else {
        Write-Host "   release build unavailable - falling back to a debug APK" -ForegroundColor Yellow
        flutter build apk --debug --no-tree-shake-icons
        $debug = "build\app\outputs\flutter-apk\app-debug.apk"
        if ($LASTEXITCODE -eq 0 -and (Test-Path $debug)) {
            Copy-Item $debug "$out\$($p.n).apk" -Force
            $mb = [math]::Round((Get-Item "$out\$($p.n).apk").Length / 1MB)
            Write-Host "-> $out\$($p.n).apk  (debug, $mb MB - installs and runs, just larger)" -ForegroundColor Yellow
        }
        else {
            Write-Host "   BOTH builds failed for $($p.d) - the APK in _builds is unchanged and now stale" -ForegroundColor Red
        }
    }
}

# The browser builds are made in the source tree rather than the mirror, so
# start-everything.ps1 always serves whatever the source currently says.
foreach ($d in @("customer_app", "provider_app")) {
    Write-Host "=== building $d for the browser ===" -ForegroundColor Cyan
    Set-Location "$src\$d"
    flutter build web --release --no-wasm-dry-run
    if ($LASTEXITCODE -eq 0) {
        Write-Host "-> $src\$d\build\web" -ForegroundColor Green
    }
    else {
        Write-Host "   web build FAILED for $d" -ForegroundColor Red
    }
}
