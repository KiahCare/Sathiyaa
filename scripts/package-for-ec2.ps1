# Packs the backend into one file to copy to the server.
#
# The runbook used to say `scp -r backend/`, which works and does three things
# you do not want:
#
#   * it copies node_modules — 11 MB of packages built for Windows, which are
#     then deleted on the instance and reinstalled for ARM Linux anyway;
#   * it copies backend/.env, putting your laptop's database password and JWT
#     secret on a public instance for however long it takes you to overwrite
#     them;
#   * it copies backend/uploads, which is 2 MB of documents from test runs.
#
# This sends the ~1 MB that is actually the application, and nothing else.

$ErrorActionPreference = 'Stop'

$root = "C:\Only Forward\Sathiyaa\sathiyaa-full-project - Flutter Web version"
$backend = Join-Path $root 'backend'
$out = Join-Path $PSScriptRoot 'sathiyaa-backend.tar.gz'

if (-not (Test-Path $backend)) { throw "No backend at $backend" }

Write-Host ""
Write-Host "  Packing the backend" -ForegroundColor Cyan
Write-Host ""

if (Test-Path $out) { Remove-Item $out -Force }

# Windows ships bsdtar as tar.exe. Paths are relative to -C so the archive
# unpacks as backend/... rather than as a chain of directories with a space in
# the middle of them.
Push-Location $root
try {
    tar.exe -czf $out `
        --exclude='backend/node_modules' `
        --exclude='backend/.env' `
        --exclude='backend/uploads' `
        --exclude='backend/.git' `
        backend
}
finally { Pop-Location }

if (-not (Test-Path $out)) { throw 'tar produced nothing' }

$mb = [math]::Round((Get-Item $out).Length / 1MB, 2)
Write-Host "  -> $out  ($mb MB)" -ForegroundColor Green
Write-Host ""

# Worth saying out loud rather than trusting: the whole point is what is absent.
$listing = tar.exe -tzf $out
$bad = $listing | Where-Object { $_ -match 'node_modules|/\.env$|backend/uploads/' }
if ($bad) {
    Write-Host "  PROBLEM - these should not be in the archive:" -ForegroundColor Red
    $bad | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" }
    exit 1
}
Write-Host "  Checked: no node_modules, no .env, no uploads." -ForegroundColor DarkGray
Write-Host "  $($listing.Count) files." -ForegroundColor DarkGray
Write-Host ""

Write-Host "  Copy it up (replace the key and the address):" -ForegroundColor Cyan
Write-Host ""
Write-Host "    scp -i your-key.pem `"$out`" ec2-user@<instance-ip>:/tmp/" -ForegroundColor White
Write-Host ""
Write-Host "  Then on the instance:" -ForegroundColor Cyan
Write-Host ""
Write-Host "    sudo mkdir -p /opt/sathiyaa && sudo chown ec2-user:ec2-user /opt/sathiyaa" -ForegroundColor White
Write-Host "    tar -xzf /tmp/sathiyaa-backend.tar.gz -C /opt/sathiyaa" -ForegroundColor White
Write-Host "    cd /opt/sathiyaa/backend && npm ci --omit=dev" -ForegroundColor White
Write-Host ""
Write-Host "  Next: _builds\DEPLOY-AWS.md, the .env section of step 3." -ForegroundColor Cyan
Write-Host ""
