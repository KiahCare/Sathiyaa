# Prints the address to type into the "Server" screen of either Sathiyaa app,
# and checks the two things that usually stop a phone reaching the API.
. C:\sathiyaa-dev\env.ps1

Write-Host "=== Sathiyaa: connecting a phone to the local API ===" -ForegroundColor Cyan
Write-Host ""

# 1. Is the API actually up?
$code = curl.exe -s -o NUL -w "%{http_code}" "http://localhost:4000/api/v1/providers/search?service_type=companion"
if ($code -eq "000") {
    Write-Host "API:      NOT RUNNING - start it with start-backend.ps1" -ForegroundColor Red
} else {
    Write-Host "API:      running on port 4000 (HTTP $code)" -ForegroundColor Green
}

# 2. Which address should the phone use? Wi-Fi first; virtual adapters are not
#    reachable from a phone.
$candidates = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Sort-Object { if ($_.InterfaceAlias -like '*Wi-Fi*' -or $_.InterfaceAlias -like '*Ethernet*') { 0 } else { 1 } }

Write-Host ""
Write-Host "Type this into the app's Server screen:" -ForegroundColor Yellow
foreach ($ip in $candidates) {
    $note = if ($ip.InterfaceAlias -like '*VMware*' -or $ip.InterfaceAlias -like '*VirtualBox*' -or $ip.InterfaceAlias -like '*Hyper-V*') {
        "  (virtual adapter - a phone cannot reach this)"
    } else {
        "  <- use this one if the phone is on the same Wi-Fi"
    }
    Write-Host ("  {0}:4000{1}   [{2}]" -f $ip.IPAddress, $note, $ip.InterfaceAlias)
}
Write-Host ""
Write-Host "  On the Android emulator instead, use: 10.0.2.2:4000"

# 3. Windows Firewall almost always blocks this on a home (Private) network.
$rule = Get-NetFirewallRule -DisplayName "Sathiyaa API (port 4000)" -ErrorAction SilentlyContinue
Write-Host ""
if ($rule) {
    Write-Host "Firewall: rule 'Sathiyaa API (port 4000)' is present." -ForegroundColor Green
} else {
    Write-Host "Firewall: no rule for port 4000." -ForegroundColor Yellow
    Write-Host "          Windows blocks incoming connections by default, so the phone will"
    Write-Host "          time out until you allow the port. Open PowerShell AS ADMINISTRATOR"
    Write-Host "          and run:"
    Write-Host ""
    Write-Host '          New-NetFirewallRule -DisplayName "Sathiyaa API (port 4000)" -Direction Inbound -Protocol TCP -LocalPort 4000 -Action Allow -Profile Private' -ForegroundColor White
    Write-Host ""
    Write-Host "          Remove it later with:"
    Write-Host '          Remove-NetFirewallRule -DisplayName "Sathiyaa API (port 4000)"'
}
Write-Host ""
Write-Host "Then in the app: Welcome screen -> the chip at the top right -> Live Sathiyaa server"
Write-Host "-> enter the address -> Test connection -> Save."
