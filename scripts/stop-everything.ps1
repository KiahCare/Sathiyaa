# Stops the API, the web app servers and MySQL.
Get-Process node -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "C:\sathiyaa-dev\node\*" } |
    ForEach-Object { $_ | Stop-Process -Force; Write-Host "stopped node $($_.Id)" }

$mysql = Get-Process mysqld -ErrorAction SilentlyContinue
if ($mysql) {
    # Ask it to close cleanly rather than killing it - an InnoDB kill means a
    # slow crash recovery on the next start.
    & "C:\sathiyaa-dev\mysql\bin\mysqladmin.exe" -u root -h 127.0.0.1 --protocol=TCP shutdown
    Write-Host "stopped MySQL"
}
Write-Host "all stopped"
