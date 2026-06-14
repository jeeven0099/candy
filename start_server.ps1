$ErrorActionPreference = "Stop"

$root   = "C:\Users\user\Downloads\promo-raw-scraper"
$python = "C:\Python314\python.exe"

# ── 1. Start asset server ────────────────────────────────────────────────────

$existing = Get-Process -Name python -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*serve_assets*" }

if ($existing) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Asset server already running (PID $($existing.Id))"
} else {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting asset server on port 8080..."
    Start-Process $python -ArgumentList "$root\serve_assets.py" -WindowStyle Hidden
    Start-Sleep -Seconds 2
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Asset server started."
}

# ── 2. ngrok instructions ────────────────────────────────────────────────────

Write-Host ""
Write-Host "Asset server is running at http://localhost:8080"
Write-Host ""
Write-Host "If ngrok is not already running, start it in a new terminal:"
Write-Host "  ngrok http 8080 --domain=YOUR-DOMAIN.ngrok-free.app"
Write-Host ""
Write-Host "Your testers will fetch data from:"
Write-Host "  https://YOUR-DOMAIN.ngrok-free.app/all_promotions.json"
Write-Host ""
Write-Host "Make sure lib/config.dart in the Flutter app has the correct URL before building."
