# Keeps the two apps on one design system -- but not one appearance.
#
# sathiyaa_theme.dart, sathiyaa_ui.dart and motion.dart are authored in
# customer_app and copied into provider_app, so spacing, radii, the type scale,
# shadows and every widget stay identical. Editing the provider copies directly
# is the one way those drift apart, so this script overwrites them every time.
#
# themepalette.dart is NOT copied. It is the one file each app owns, and it is
# what makes the customer app carry the website's teal while the provider app
# stays navy on warm cream. Copying it would undo that on the next build,
# silently.
#
# The same trap applies to anything provider-only: it must not live in one of
# the files listed below, or it is deleted the next time somebody builds an
# APK. approvalPresentation() was added to the provider's sathiyaa_ui.dart and
# would have vanished exactly that way; it lives in provider_app/lib/utils/
# approval.dart instead.
$src = "C:\Only Forward\Sathiyaa\Sathiyaa Flutter\Sathiyaa Flutter\customer_app\lib"
$dst = "C:\Only Forward\Sathiyaa\Sathiyaa Flutter\Sathiyaa Flutter\provider_app\lib"

# Written only when the contents actually differ.
#
# Copying unconditionally moved every shared file's timestamp on every run,
# including the sync that `redeploy.ps1 -Console` performs long after the
# APKs were built -- so verify-apks.mjs reported a current APK as STALE. A
# staleness check that cries wolf is one nobody reads.
function Sync-File($from, $to) {
    if ((Test-Path $to) -and
        ((Get-FileHash $from -Algorithm SHA256).Hash -eq (Get-FileHash $to -Algorithm SHA256).Hash)) {
        return
    }
    Copy-Item $from $to -Force
}

New-Item -ItemType Directory -Force "$dst\theme" | Out-Null
New-Item -ItemType Directory -Force "$dst\i18n"  | Out-Null
Sync-File "$src\theme\sathiyaa_theme.dart" "$dst\theme\sathiyaa_theme.dart"
Sync-File "$src\widgets\sathiyaa_ui.dart"  "$dst\widgets\sathiyaa_ui.dart"
Sync-File "$src\widgets\motion.dart"       "$dst\widgets\motion.dart"
# The languages a carer can claim and a family can filter for. One list, both
# apps: the customer's dropdown and the carer's picker have to offer the same
# words or the filter matches nothing.
Sync-File "$src\languages.dart"            "$dst\languages.dart"
# Where Sathiyaa operates, and the gate that turns everybody else away. One
# copy: the two apps must agree on what counts as inside, and the fallback
# city has to match migration 015 in both.
Sync-File "$src\service_area.dart"         "$dst\service_area.dart"
# The shape of a message from an admin. Shared so the two apps cannot drift
# on a field name the server only spells one way.
Sync-File "$src\broadcasts.dart"           "$dst\broadcasts.dart"
# The localisation machinery is shared; the translations are not. Each app has
# its own strings_hi.dart / strings_gu.dart, for the same reason each has its
# own palette: a carer reading "काम" and a family reading "बुकिंग" are not the
# same vocabulary, and copying one app's table over the other would replace a
# screen's worth of words with another screen's.
Sync-File "$src\i18n\l10n.dart"            "$dst\i18n\l10n.dart"
Sync-File "$src\i18n\language_screen.dart" "$dst\i18n\language_screen.dart"
# osm_map is shared too, but the tile user agent differs per app, so it is
# patched after the copy rather than copied blind.
#
# Read and write through .NET rather than Get-Content / Set-Content. In
# PowerShell 5.1 Get-Content reads a BOM-less UTF-8 file as the system
# codepage, so every byte of a multi-byte character becomes its own Latin-1
# character, and Set-Content -Encoding utf8 then re-encodes the damage and adds
# a BOM. That round trip is what turned the map's "(c) OpenStreetMap" into
# mojibake in provider_app, and every em dash in the file with it.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$map = [System.IO.File]::ReadAllText("$src\widgets\osm_map.dart", [System.Text.Encoding]::UTF8)
$map = $map.Replace("in.sathiyaa.customer", "in.sathiyaa.provider")
$osmDst = "$dst\widgets\osm_map.dart"
$osmOld = if (Test-Path $osmDst) { [System.IO.File]::ReadAllText($osmDst, [System.Text.Encoding]::UTF8) } else { $null }
if ($osmOld -ne $map) { [System.IO.File]::WriteAllText($osmDst, $map, $utf8NoBom) }
# Guard the split rather than trusting a comment to hold. Both palettes must
# declare exactly the same names: the shared theme aliases every one of them,
# so a name in one and not the other stops the other app compiling -- and it
# would do so in a Gradle build, ten minutes later, not here.
$names = @{}
foreach ($app in 'customer_app', 'provider_app') {
    $f = "C:\Only Forward\Sathiyaa\Sathiyaa Flutter\Sathiyaa Flutter\$app\lib\theme\palette.dart"
    if (-not (Test-Path $f)) { throw "$app has no theme\palette.dart" }
    $text = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
    $names[$app] = [regex]::Matches($text, 'static const (\w+) = Color\(') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object
}
$onlyCustomer = $names['customer_app'] | Where-Object { $_ -notin $names['provider_app'] }
$onlyProvider = $names['provider_app'] | Where-Object { $_ -notin $names['customer_app'] }
if ($onlyCustomer -or $onlyProvider) {
    if ($onlyCustomer) { Write-Host "  only in customer_app: $($onlyCustomer -join ', ')" -ForegroundColor Red }
    if ($onlyProvider) { Write-Host "  only in provider_app: $($onlyProvider -join ', ')" -ForegroundColor Red }
    throw 'The two palettes declare different colours. Add the missing name to both.'
}

Write-Host "design system synced to provider_app" -ForegroundColor Green
Write-Host "  palettes left alone; $($names['customer_app'].Count) colours declared in both" -ForegroundColor DarkGray
