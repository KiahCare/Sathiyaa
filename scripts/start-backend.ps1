# Starts MySQL (portable) + the Sathiyaa API. Leave this window open.
. C:\sathiyaa-dev\env.ps1
$root = "C:\Only Forward\Sathiyaa\sathiyaa-full-project - Flutter Web version"

if (-not (Get-Process mysqld -ErrorAction SilentlyContinue)) {
    Write-Host "starting MySQL..."
    Start-Process "C:\sathiyaa-dev\mysql\bin\mysqld.exe" `
        -ArgumentList "--datadir=C:\sathiyaa-dev\mysql-data","--basedir=C:\sathiyaa-dev\mysql","--port=3306","--bind-address=127.0.0.1" `
        -WindowStyle Hidden
    Start-Sleep -Seconds 6
}
Write-Host "MySQL: $(& 'C:\sathiyaa-dev\mysql\bin\mysqladmin.exe' -u root -h 127.0.0.1 --protocol=TCP ping)"

Set-Location "$root\backend"
Write-Host "API -> http://localhost:4000/api/v1"
npm start
