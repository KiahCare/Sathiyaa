# Generates the two secrets a public deployment needs.
#
# Prints them and writes nothing to disk. Copy them into backend/.env on the
# server and into the build script when it asks. If you lose them, run this
# again and change them in all three places — nothing here is recoverable by
# design.

$ErrorActionPreference = 'Stop'

function New-Secret([int]$bytes) {
    $buf = New-Object byte[] $bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
    # URL-safe: these end up in .env files, shell commands and a --dart-define,
    # and a stray + or / in any of those is an afternoon you do not get back.
    [Convert]::ToBase64String($buf).Replace('+', '-').Replace('/', '_').TrimEnd('=')
}

Write-Host ""
Write-Host "  Two secrets. Keep them somewhere you can find them." -ForegroundColor Cyan
Write-Host ""

Write-Host "  JWT_SECRET" -ForegroundColor Green
Write-Host "  ----------"
Write-Host "  $(New-Secret 48)"
Write-Host ""
Write-Host "  Anyone holding this can sign a token that says role=admin." -ForegroundColor DarkGray
Write-Host "  It goes in backend/.env on the server and NOWHERE else." -ForegroundColor DarkGray
Write-Host ""

Write-Host "  API_ACCESS_KEY" -ForegroundColor Green
Write-Host "  --------------"
Write-Host "  $(New-Secret 36)"
Write-Host ""
Write-Host "  Goes in three places: backend/.env, the console build, and the APK" -ForegroundColor DarkGray
Write-Host "  builds. It is baked into both, so anyone who unpacks an APK can read" -ForegroundColor DarkGray
Write-Host "  it. That is understood - it keeps scanners out, it is not a lock." -ForegroundColor DarkGray
Write-Host "  Do not put it in a public repository or a screenshot." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Next: _builds\DEPLOY-AWS.md, step 2." -ForegroundColor Cyan
Write-Host ""
