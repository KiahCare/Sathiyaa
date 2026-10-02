# Runs the whole test suite against a database of its own.
#
# Why this exists
# ---------------
# Every script in this folder creates real accounts through the real API, and
# most of them take a booking. The delete endpoints refuse an account that has
# booking history — deliberately, because a booking is a record somebody may
# need — so the sweeper could only ever remove the accounts that never booked.
# A few hundred test rows had accumulated in the development database, and the
# only way back to a clean state was a reseed that wipes everything, including
# whatever you had created by hand on your phone that morning.
#
# So the suite gets its own database. This script builds `sathiyaa_test` from
# the migrations, seeds it, starts a second API on port 4010 pointed at it,
# runs everything, and then throws the database away. Your development data is
# never touched, and "the tests left rows behind" stops being a thing that can
# happen.
#
#   .\run-all.ps1                     build a test database, run everything
#   .\run-all.ps1 -Keep               leave the database up afterwards
#   .\run-all.ps1 -Only happy-path    one script (still on the test database)
#   .\run-all.ps1 -Api https://xxxx.cloudfront.net/api/v1 -Key <key> -AdminPassword <pw>
#                                     run against a deployment instead; builds
#                                     nothing, drops nothing
#
# The last form is the one to use after the AWS deploy: it is the same suite,
# aimed at the server that is actually live.

param(
    [string]$Api = '',
    [string]$Key = '',
    [string]$AdminPassword = 'Admin@123',
    [string]$Only = '',
    [int]$Port = 4010,
    [switch]$Keep,
    [switch]$Public,
    [switch]$Flutter
)

$ErrorActionPreference = 'Stop'

$here     = $PSScriptRoot
$root     = 'C:\Only Forward\Sathiyaa\sathiyaa-full-project - Flutter Web version'
$backend  = Join-Path $root 'backend'
$node     = 'C:\sathiyaa-dev\node\node.exe'
$mysql    = 'C:\sathiyaa-dev\mysql\bin\mysql.exe'
$mysqld   = 'C:\sathiyaa-dev\mysql\bin\mysqld.exe'
$testDb   = 'sathiyaa_test'
$flutterSrc = 'C:\Only Forward\Sathiyaa\Sathiyaa Flutter\Sathiyaa Flutter'
$workDir  = Join-Path $env:TEMP 'sathiyaa-test-run'
$logDir   = Join-Path $workDir 'logs'
# Relative, and every node call below runs with -WorkingDirectory $here.
# Start-Process joins -ArgumentList on spaces without quoting, and this folder
# lives under "C:\Only Forward\", so an absolute path arrives as two arguments
# and node reports that it cannot find a module called C:\Only.
$preamble = './lib/preamble.mjs'

# Order matters in two places and nowhere else:
#   - admin-actions writes global configuration (booking amount, revenue share),
#     so it runs after everything that prices a booking;
#   - cleanup-test-rows deletes accounts, so it runs last.
$suite = @(
    'osm',
    'shapes',
    'happy-path',
    'three-devices',
    'device-registry',
    'full-journey',
    'practical',
    'audit-everything',
    'partner-login',
    'contact-modes',
    'uploads-and-blocks',
    'uploads-url-shape',
    'broadcast-targeting',
    'settings-take-effect',
    'booking-for-dependent',
    'choose-carers',
    'organisation-registration',
    'admin-create-provider',
    'provider-languages',
    'service-area-and-fees',
    'sos',
    'messages',
    'admin-contract',
    'contract-drift',
    'admin-console-check',
    'console-routes',
    'admin-actions',
    'cleanup-test-rows'
)

function Say($text, $colour = 'Gray') { Write-Host $text -ForegroundColor $colour }
function Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }

if ($Flutter) {
    # The Flutter suites include a group that talks to a live server and
    # registers real customers on it — the same problem this script was written
    # to solve for the node scripts, in the other language. Two runs of
    # `flutter test` had quietly put six customers and six bookings into the
    # development database before anyone noticed.
    $suite = @('customer_app', 'provider_app')
    if ($Public) {
        Write-Host 'Use -Flutter or -Public, not both.' -ForegroundColor Red
        exit 2
    }
    . C:\sathiyaa-dev\env.ps1
    $flutterExe = (Get-Command flutter -ErrorAction SilentlyContinue).Source
    if (-not $flutterExe) { Write-Host 'flutter is not on PATH.' -ForegroundColor Red; exit 2 }
}

if ($Public) {
    if ($Api -ne '') {
        Write-Host 'Use -Public or -Api, not both: -Public starts a server of its own.' -ForegroundColor Red
        exit 2
    }
    # Everything else in the suite runs against a laptop backend and so says
    # nothing about the configuration the deployed one will use. This runs one
    # script against a backend started the way AWS will start it.
    $suite = @('public-config')
    $publicKey = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
    $publicJwt = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
    $publicOrigin = 'https://d111111abcdef8.cloudfront.net'
    if ($AdminPassword -eq 'Admin@123') {
        # Rotated, so the run also proves that rotating it takes effect and that
        # the password printed in the repository stops working.
        $AdminPassword = 'Rotated-' + [guid]::NewGuid().ToString('N').Substring(0, 12) + '!aA1'
    }
}

if ($Only -ne '') {
    $Only = $Only -replace '\.mjs$', ''
    if ($suite -notcontains $Only) {
        Say "No script called '$Only'. The suite is:" Red
        foreach ($s in $suite) { Say "  $s" }
        exit 2
    }
    $suite = @($Only)
}

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Get-ChildItem $logDir -Filter *.log -ErrorAction SilentlyContinue | Remove-Item -Force

# Run from your own prompt, this script would otherwise leave DB_NAME pointing
# at a database it has just dropped, and the next `npm start` in that window
# would fail with something that looks nothing like the cause. Put them back.
$touched = @('DB_NAME', 'PORT', 'UPLOAD_DIR', 'ADMIN_PASSWORD', 'PUBLIC_DEPLOYMENT',
             'API_ACCESS_KEY', 'SATHIYAA_API', 'API_BASE', 'JWT_SECRET', 'CORS_ORIGINS',
             'TRUST_PROXY_HOPS', 'SATHIYAA_PUBLIC_KEY', 'SATHIYAA_CORS_ORIGIN')
$saved = @{}
foreach ($v in $touched) { $saved[$v] = [Environment]::GetEnvironmentVariable($v) }

$server = $null
$builtDb = $false
$target = $Api

try {
    # ------------------------------------------------------------------ set up
    if ($Api -ne '') {
        Step "Running against $Api"
        Say "   nothing is built and nothing is dropped; this is somebody else's server"
    }
    else {
        # --- the .env we borrow the credentials from -------------------------
        $envFile = Join-Path $backend '.env'
        if (-not (Test-Path $envFile)) { throw "No .env at $envFile" }
        $cfg = @{}
        foreach ($line in Get-Content $envFile) {
            if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)$') {
                $cfg[$matches[1]] = $matches[2].Trim()
            }
        }
        $dbUser = $cfg['DB_USER']
        if (-not $dbUser) { $dbUser = 'sathiyaa_app' }

        # --- MySQL ------------------------------------------------------------
        Step 'MySQL'
        if (Get-Process mysqld -ErrorAction SilentlyContinue) {
            Say '   already running'
        }
        else {
            Start-Process $mysqld -ArgumentList `
                '--datadir=C:\sathiyaa-dev\mysql-data', '--basedir=C:\sathiyaa-dev\mysql', `
                '--port=3306', '--bind-address=127.0.0.1' -WindowStyle Hidden
            Start-Sleep -Seconds 6
            Say '   started'
        }

        # --- a database of its own -------------------------------------------
        Step "Building $testDb from the migrations"
        # Dropped first as well as last: an aborted run must not leave a
        # half-migrated database for the next one to trip over.
        $ddl = "DROP DATABASE IF EXISTS $testDb; CREATE DATABASE $testDb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        $ddl | & $mysql --host=127.0.0.1 --protocol=TCP -u root
        if ($LASTEXITCODE -ne 0) { throw "Could not create $testDb (is MySQL up?)" }
        $builtDb = $true

        # The app user, not root, so this also proves the account the API runs
        # as has the privileges the migrations need. MySQL 8 will not grant to a
        # user that does not exist, and the host part varies by install, so ask
        # for the grants that apply rather than guessing 'localhost'.
        $genGrants = "SELECT CONCAT('GRANT ALL PRIVILEGES ON $testDb.* TO ''', user, '''@''', host, ''';') FROM mysql.user WHERE user = '$dbUser';"
        $grants = $genGrants | & $mysql --host=127.0.0.1 --protocol=TCP -u root -N -B
        if (-not $grants) { throw "No MySQL account called '$dbUser' to grant $testDb to" }
        (($grants -join "`n") + "`nFLUSH PRIVILEGES;") | & $mysql --host=127.0.0.1 --protocol=TCP -u root
        if ($LASTEXITCODE -ne 0) { throw "Could not grant $testDb to $dbUser" }
        Say "   created, granted to $dbUser"

        # --- migrate and seed it ---------------------------------------------
        # dotenv does not overwrite a variable that is already set, so these win
        # over backend\.env for this process and everything it starts.
        $env:DB_NAME = $testDb
        $env:PORT = "$Port"
        $env:UPLOAD_DIR = (Join-Path $workDir 'uploads')
        $env:ADMIN_PASSWORD = $AdminPassword
        $env:PUBLIC_DEPLOYMENT = 'false'
        $env:API_ACCESS_KEY = $Key
        New-Item -ItemType Directory -Force -Path $env:UPLOAD_DIR | Out-Null

        if ($Public) {
            # The same shape of configuration DEPLOY-AWS.md asks you to put in
            # .env on the instance, with throwaway values.
            if (-not $cfg['DB_PASSWORD']) {
                throw 'DB_PASSWORD is empty in backend\.env, and preflight refuses a public deployment without one. Set it before deploying.'
            }
            $env:PUBLIC_DEPLOYMENT = 'true'
            $env:API_ACCESS_KEY = $publicKey
            $env:JWT_SECRET = $publicJwt
            $env:CORS_ORIGINS = $publicOrigin
            $env:TRUST_PROXY_HOPS = '1'
            $env:SATHIYAA_PUBLIC_KEY = $publicKey
            $env:SATHIYAA_CORS_ORIGIN = $publicOrigin
            $Key = $publicKey
            Say '   configured as a public deployment (key, JWT secret, CORS list, 1 proxy hop)'
        }

        Push-Location $backend
        try {
            & $node 'src\db\migrate.js' | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'migrate failed' }
            Say '   migrated'
            & $node 'src\db\seed.js' | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'seed failed' }
            Say '   seeded'
        }
        finally { Pop-Location }

        # --- a second API, on its own port, pointed at it ---------------------
        Step "API on port $Port"
        $outLog = Join-Path $workDir 'server.log'
        $errLog = Join-Path $workDir 'server.err.log'
        $server = Start-Process $node -ArgumentList 'src\server.js' -WorkingDirectory $backend `
            -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog

        $up = $false
        for ($i = 0; $i -lt 40; $i++) {
            try {
                $h = Invoke-WebRequest "http://localhost:$Port/health" -UseBasicParsing -TimeoutSec 2
                if ($h.StatusCode -eq 200) { $up = $true; break }
            }
            catch { Start-Sleep -Milliseconds 500 }
        }
        if (-not $up) {
            Say '   FAILED to come up' Red
            if (Test-Path $errLog) { Get-Content $errLog -Tail 20 }
            throw "API did not answer on port $Port"
        }
        Say "   up, on $testDb" Green
        $target = "http://localhost:$Port/api/v1"
    }

    # ------------------------------------------------------------------- run it
    if ($Flutter) { Step "Running $($suite.Count) Flutter suite(s)" }
    else { Step "Running $($suite.Count) script(s)" }
    $env:SATHIYAA_API = $target
    $env:API_BASE = $target
    $env:ADMIN_PASSWORD = $AdminPassword
    $env:API_ACCESS_KEY = $Key

    $results = @()
    foreach ($name in $suite) {
        $o = Join-Path $logDir "$name.log"
        $e = Join-Path $logDir "$name.err.log"
        $started = Get-Date

        if ($Flutter) {
            # api_backend_test.dart reads SATHIYAA_API through String.fromEnvironment,
            # which is compiled in rather than read at run time, so it has to be a
            # --dart-define and not the environment variable set above.
            $p = Start-Process $flutterExe `
                -ArgumentList @('test', '--no-pub', "--dart-define=SATHIYAA_API=$target") `
                -WorkingDirectory (Join-Path $flutterSrc $name) -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $o -RedirectStandardError $e
        }
        else {
            # public-config is the one script that must see the raw fetch: half of
            # what it checks is what the server does when the key is missing or
            # wrong, and the preamble would helpfully put a correct one on.
            $nodeArgs = @('--import', $preamble, "$name.mjs")
            if ($name -eq 'public-config') { $nodeArgs = @("$name.mjs") }

            $p = Start-Process $node -ArgumentList $nodeArgs `
                -WorkingDirectory $here -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $o -RedirectStandardError $e
        }
        $secs = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)

        # Two verdicts, because they disagree in a way worth knowing about. The
        # exit code is what a runner normally trusts; the printed FAIL lines are
        # what a person reads. A script that prints FAIL and exits 0 is a script
        # that has been lying to whoever ran it.
        $text = ''
        if (Test-Path $o) { $text = (Get-Content $o -Raw) }
        $printed = 0
        if ($text) {
            $printed = ([regex]::Matches($text, '(?m)^\s*(FAIL|DRIFT)\b')).Count
        }
        $errText = ''
        if (Test-Path $e) { $errText = (Get-Content $e -Raw) }

        $ok = ($p.ExitCode -eq 0) -and ($printed -eq 0)
        $results += [pscustomobject]@{
            Name = $name; Exit = $p.ExitCode; Printed = $printed; Seconds = $secs; Ok = $ok
        }

        if ($ok) {
            Say ("  PASS  {0,-22} {1,5}s" -f $name, $secs) Green
        }
        else {
            Say ("  FAIL  {0,-22} {1,5}s   exit {2}, {3} FAIL line(s)" -f $name, $secs, $p.ExitCode, $printed) Red
            if ($printed -gt 0) {
                foreach ($m in [regex]::Matches($text, '(?m)^.*\b(FAIL|DRIFT)\b.*$') | Select-Object -First 6) {
                    Say ("          " + $m.Value.Trim())
                }
            }
            if ($errText) { Say ("          stderr: " + ($errText -split "`n")[0]) }
            Say ("          full output: $o")
        }
    }

    # ------------------------------------------------------------------ summary
    $failed = @($results | Where-Object { -not $_.Ok })
    $lying = @($results | Where-Object { $_.Exit -eq 0 -and $_.Printed -gt 0 })

    Write-Host ''
    Write-Host ('=' * 68)
    if ($failed.Count -eq 0) {
        Say ("  {0}/{0} passed" -f $results.Count) Green
    }
    else {
        Say ("  {0}/{1} passed" -f ($results.Count - $failed.Count), $results.Count) Red
        foreach ($f in $failed) { Say ("    - " + $f.Name) Red }
    }
    if ($lying.Count -gt 0) {
        Write-Host ''
        Say '  These printed a failure but exited 0, which means their exit code' Yellow
        Say '  cannot be trusted by anything automated:' Yellow
        foreach ($l in $lying) { Say ("    - " + $l.Name) Yellow }
    }
    Write-Host ('=' * 68)
    Say "  logs: $logDir"

    if ($failed.Count -gt 0) { exit 1 }
}
finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
    }
    foreach ($v in $touched) {
        if ($null -eq $saved[$v]) { Remove-Item "Env:\$v" -ErrorAction SilentlyContinue }
        else { Set-Item "Env:\$v" $saved[$v] -ErrorAction SilentlyContinue }
    }
    if ($builtDb) {
        if ($Keep) {
            Write-Host ''
            Say "  $testDb left in place. To look at it:" Yellow
            Say "    C:\sathiyaa-dev\mysql\bin\mysql.exe --host=127.0.0.1 --protocol=TCP -u root $testDb" Yellow
        }
        else {
            "DROP DATABASE IF EXISTS $testDb;" | & $mysql --host=127.0.0.1 --protocol=TCP -u root
            Say "  $testDb dropped; the development database was never touched"
        }
    }
}
