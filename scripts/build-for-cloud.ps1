# Builds the admin console, and optionally both APKs, pointed at a cloud API.
#
#   .\build-for-cloud.ps1          # the console only
#   .\build-for-cloud.ps1 -Apks    # the console and both APKs
#
# The API address and the access key are compiled in, not read at runtime, so
# changing either means running this again and re-uploading. That is a property
# of a static bundle and a release APK, not a choice made here.
#
# See DEPLOY-AWS.md for where the two values come from.

param(
    [switch]$Apks,
    [string]$ApiUrl,
    [string]$AccessKey
)

$ErrorActionPreference = 'Stop'
. C:\sathiyaa-dev\env.ps1

$web = 'C:\Only Forward\Sathiyaa\sathiyaa-full-project - Flutter Web version'
$flutter = 'C:\Only Forward\Sathiyaa\Sathiyaa Flutter\Sathiyaa Flutter'
$out = $PSScriptRoot
$node = 'C:\sathiyaa-dev\node\node.exe'

function Ask($prompt, $current, $example) {
    if ($current) { return $current }
    Write-Host ""
    Write-Host "  $prompt" -ForegroundColor Cyan
    Write-Host "  e.g. $example" -ForegroundColor DarkGray
    $v = Read-Host '  >'
    if (-not $v) { throw 'Nothing entered. Stopping rather than building something that cannot work.' }
    return $v.Trim()
}

$ApiUrl = Ask 'API address, including /api/v1' $ApiUrl 'https://d-bbbb.cloudfront.net/api/v1'
$AccessKey = Ask 'API access key (from make-deploy-secrets.ps1)' $AccessKey 'kJ8...'

# A base URL without /api/v1 is the single most common way to spend an hour on
# a 404 that looks like a CORS problem.
if ($ApiUrl -notmatch '/api/v\d+/?$') {
    Write-Host ""
    Write-Host "  That address does not end in /api/v1." -ForegroundColor Yellow
    Write-Host "  Every route lives under it, so without it nothing resolves." -ForegroundColor Yellow
    $go = Read-Host '  Use it anyway? (y/N)'
    if ($go -ne 'y') { exit 1 }
}
$ApiUrl = $ApiUrl.TrimEnd('/')

Write-Host ""
Write-Host "== admin console" -ForegroundColor Cyan
Push-Location "$web\admin-portal"
try {
    $env:VITE_USE_MOCK = 'false'
    $env:VITE_API_BASE_URL = $ApiUrl
    $env:VITE_API_ACCESS_KEY = $AccessKey
    & $node node_modules\vite\bin\vite.js build --outDir dist-cloud --emptyOutDir | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The console build failed.' }
    Write-Host "   built -> $web\admin-portal\dist-cloud" -ForegroundColor Green
}
finally {
    $env:VITE_USE_MOCK = $null
    $env:VITE_API_BASE_URL = $null
    $env:VITE_API_ACCESS_KEY = $null
    Pop-Location
}

# Prove the address really is in the bundle. A mistyped env var name fails
# silently here: vite substitutes nothing, the fallback to localhost applies,
# and you find out after uploading.
$bundle = Get-ChildItem "$web\admin-portal\dist-cloud\assets" -Filter '*.js' |
    ForEach-Object { Get-Content $_.FullName -Raw }
if ($bundle -match [regex]::Escape($ApiUrl)) {
    Write-Host "   ok    API address is compiled into the bundle" -ForegroundColor Green
}
else {
    throw "The API address is NOT in the built bundle. Check VITE_API_BASE_URL."
}
if ($bundle -match [regex]::Escape($AccessKey)) {
    Write-Host "   ok    access key is compiled into the bundle" -ForegroundColor Green
}
else {
    throw "The access key is NOT in the built bundle. Check VITE_API_ACCESS_KEY."
}

if ($Apks) {
    & "$out\sync-design.ps1"
    & "$out\sync-to-build.ps1"

    foreach ($p in @(
            @{ d = 'customer_app'; n = 'sathiyaa-customer' },
            @{ d = 'provider_app'; n = 'sathiyaa-provider' })) {
        Write-Host ""
        Write-Host "== $($p.d) APK (cloud)" -ForegroundColor Cyan
        Set-Location "C:\sathiyaa-build\$($p.d)"
        # Both, not just the key. Compiling the key in and leaving the address
        # out made a "cloud" APK that still opened against 10.0.2.2 — the
        # emulator's name for the host machine, and nothing at all on a phone —
        # so everyone handed one had to type the address in by hand. Passing
        # the address also switches the build's default to live mode.
        flutter build apk --release `
            --dart-define=API_ACCESS_KEY=$AccessKey `
            --dart-define=API_BASE_URL=$ApiUrl
        $rel = 'build\app\outputs\flutter-apk\app-release.apk'
        if ($LASTEXITCODE -eq 0 -and (Test-Path $rel)) {
            Copy-Item $rel "$out\$($p.n)-cloud.apk" -Force
            $apk = "$out\$($p.n)-cloud.apk"
            $mb = [math]::Round((Get-Item $apk).Length / 1MB)
            Write-Host "   -> $apk  ($mb MB)" -ForegroundColor Green

            # Same reasoning as the console check above: a dart-define whose
            # name is wrong fails silently, the built-in default applies, and
            # you find out once it is on a phone. A release build stores
            # non-Latin-1 strings as UTF-16, so check both encodings.
            $bytes = [System.IO.File]::ReadAllBytes($apk)
            $ok = $true
            foreach ($needle in @($ApiUrl, $AccessKey)) {
                $one = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetBytes($needle)
                $two = [System.Text.Encoding]::Unicode.GetBytes($needle)
                $found = $false
                foreach ($pat in @($one, $two)) {
                    for ($i = 0; $i -le $bytes.Length - $pat.Length; $i++) {
                        if ($bytes[$i] -ne $pat[0]) { continue }
                        $match = $true
                        for ($j = 1; $j -lt $pat.Length; $j++) {
                            if ($bytes[$i + $j] -ne $pat[$j]) { $match = $false; break }
                        }
                        if ($match) { $found = $true; break }
                    }
                    if ($found) { break }
                }
                # The address is fine to print; the key is not. Terminal
                # scrollback gets copied into chats and bug reports, and the
                # whole point of the check is that it runs on every build --
                # so it must not be the thing that publishes the key.
                $shown = if ($needle -eq $AccessKey) {
                    "access key (" + $needle.Length + " chars, ends " + $needle.Substring($needle.Length - 4) + ")"
                }
                else { $needle }

                if ($found) {
                    Write-Host "   ok    compiled in: $shown" -ForegroundColor Green
                }
                else {
                    Write-Host "   MISSING from the APK: $shown" -ForegroundColor Red
                    $ok = $false
                }
            }
            if (-not $ok) { throw "$($p.d): the build did not pick up the dart-defines." }
        }
        else {
            Write-Host "   BUILD FAILED for $($p.d)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  These open against the cloud server on first run. The Server" -ForegroundColor DarkGray
    Write-Host "  screen still works, so one can be pointed back at your laptop." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Next, upload the console:" -ForegroundColor Cyan
Write-Host "    aws s3 sync `"$web\admin-portal\dist-cloud`" s3://<your-bucket>/ --delete"
Write-Host "    aws cloudfront create-invalidation --distribution-id <id> --paths `"/*`""
Write-Host ""
Write-Host "  Skip the invalidation and CloudFront serves the old bundle for up" -ForegroundColor DarkGray
Write-Host "  to a day, which looks exactly like the deploy not working." -ForegroundColor DarkGray
Write-Host ""
