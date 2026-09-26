# Mirrors the Flutter source into the space-free build copy under
# C:\sathiyaa-build. Gradle and the Android SDK both dislike spaces in paths,
# so builds happen there rather than in the project folder.
#
# Anything pubspec.yaml or the manifest REFERS to has to be mirrored as well.
# That is the whole trap of this script: the source tree looks correct, the
# build copy is missing a file, and the failure arrives ten minutes later in
# a Gradle log -- or, worse, does not arrive at all and simply ships an APK
# without the thing. It has happened twice now:
#
#   android/app/src   the network-security config was silently absent from
#                     every APK while the source said otherwise
#   assets/           declared in pubspec.yaml, so leaving it out fails the
#                     build outright with "No file or variants found for
#                     asset: assets/logo.png"
$src = "C:\Only Forward\Sathiyaa\Sathiyaa Flutter\Sathiyaa Flutter"
$dst = "C:\sathiyaa-build"

foreach ($app in @("customer_app", "provider_app")) {
    robocopy "$src\$app\lib"  "$dst\$app\lib"  /MIR /NJH /NJS /NDL /NP | Out-Null
    robocopy "$src\$app\test" "$dst\$app\test" /MIR /NJH /NJS /NDL /NP | Out-Null

    # android/app/src is mirrored too: the manifest, res/ and res/xml live
    # there. build/ and .gradle/ are excluded so the mirror keeps its own
    # build cache.
    robocopy "$src\$app\android\app\src" "$dst\$app\android\app\src" /MIR /NJH /NJS /NDL /NP | Out-Null

    # Declared assets -- the brand mark, today. A missing one is a hard build
    # failure, which is the good case; the bad case is a file that is present
    # but stale, which /MIR prevents.
    if (Test-Path "$src\$app\assets") {
        robocopy "$src\$app\assets" "$dst\$app\assets" /MIR /NJH /NJS /NDL /NP | Out-Null
    }

    Copy-Item "$src\$app\pubspec.yaml" "$dst\$app\pubspec.yaml" -Force

    # Check rather than trust: every asset pubspec.yaml declares has to exist
    # in the mirror, or the build fails ten minutes from now in a Gradle log
    # instead of here in one line.
    $declared = Select-String -Path "$dst\$app\pubspec.yaml" -Pattern '^\s+-\s+(assets/\S+)$' |
        ForEach-Object { $_.Matches[0].Groups[1].Value }
    foreach ($asset in $declared) {
        $path = Join-Path "$dst\$app" ($asset -replace '/', '\')
        if (-not (Test-Path $path)) {
            throw "$app declares $asset in pubspec.yaml but it is not in the build mirror at $path"
        }
    }

    # robocopy exit codes below 8 are success (0 = no change, 1 = files copied)
    Write-Host "$app synced$(if ($declared) { " ($($declared.Count) asset(s) checked)" })"
}
