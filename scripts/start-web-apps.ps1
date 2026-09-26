# Serves the three built React apps. Leave this window open; Ctrl+C stops them.
. C:\sathiyaa-dev\env.ps1
$root = "C:\Only Forward\Sathiyaa\sathiyaa-full-project - Flutter Web version"
$apps = [ordered]@{ "admin-portal" = 4173; "customer-app-web" = 4174; "provider-app-web" = 4175 }

foreach ($a in $apps.Keys) {
    Start-Process "C:\sathiyaa-dev\node\node.exe" `
        -ArgumentList "node_modules\vite\bin\vite.js","preview","--port","$($apps[$a])","--strictPort" `
        -WorkingDirectory "$root\$a" -WindowStyle Hidden
    Write-Host "$a -> http://localhost:$($apps[$a])"
}
Write-Host "`nAdmin portal      http://localhost:4173   admin@sathiyaa.com / Admin@123"
Write-Host "Customer app      http://localhost:4174"
Write-Host "Provider app      http://localhost:4175"
Write-Host "`nPress Enter to stop them all."
Read-Host
Get-Process node -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "C:\sathiyaa-dev\node\*" } | Stop-Process -Force
