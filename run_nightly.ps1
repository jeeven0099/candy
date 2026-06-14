$ErrorActionPreference = "Stop"

$root     = "C:\Users\user\Downloads\promo-raw-scraper"
$python   = "C:\Python314\python.exe"
$pipeline = "$root\promo-raw-scraper\run_pipeline.py"
$assets   = "$root\promo_viewer\assets"

# Start Ollama if it isn't already running
$ollamaRunning = try { (Invoke-WebRequest -Uri "http://localhost:11434/api/version" -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200 } catch { $false }
if (-not $ollamaRunning) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting Ollama..."
    Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 10
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting pipeline..."
& $python $pipeline --ollama-model qwen2.5:14b --ollama-timeout 2700
if (-not $?) { Write-Host "[ERROR] Pipeline failed"; exit 1 }

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Running email pipeline..."
& $python "$root\promo-raw-scraper\email_pipeline\src\run_email_pipeline.py" --env-file "$root\promo-raw-scraper\.env.email" --ollama-model qwen2.5:14b --ollama-timeout 2700 --gmail-query "category:promotions newer_than:1d"
if (-not $?) { Write-Host "[WARN] Email pipeline failed - continuing" }

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Generating merged web promotions..."
& $python "$root\promo-raw-scraper\src\generate_merged_json.py"

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Merging web + email promotions..."
& $python "$root\promo-raw-scraper\src\merge_all_promotions.py"

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Adding fast redemption actions..."
& $python "$root\promo-raw-scraper\src\generate_fast_redemption.py"

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Computing rank scores..."
& $python "$root\promo-raw-scraper\src\generate_scores.py"

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Downloading brand logos..."
& $python "$root\promo-raw-scraper\src\download_logos.py"
if (-not $?) { Write-Host "[WARN] Logo download had failures - continuing" }

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Copying assets..."
Copy-Item "$root\promo-raw-scraper\all_promotions.json"     "$assets\all_promotions.json"     -Force
Copy-Item "$root\promo-raw-scraper\brand_locations.json"    "$assets\brand_locations.json"    -Force
if (Test-Path "$root\promo-raw-scraper\email_pipeline\logs\user_memberships.json") {
    Copy-Item "$root\promo-raw-scraper\email_pipeline\logs\user_memberships.json" "$assets\user_memberships.json" -Force
}
if (Test-Path "$root\promo-raw-scraper\email_pipeline\logs\brand_affinity.json") {
    Copy-Item "$root\promo-raw-scraper\email_pipeline\logs\brand_affinity.json" "$assets\brand_affinity.json" -Force
}

# Copy logos folder (only new/changed files)
New-Item -ItemType Directory -Force "$assets\logos" | Out-Null
Copy-Item "$root\promo-raw-scraper\logos\*" "$assets\logos\" -Force -ErrorAction SilentlyContinue

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Running quality report..."
& $python "$root\promo-raw-scraper\src\generate_quality_report.py"
if (-not $?) { Write-Host "[WARN] Quality report had errors - continuing" }

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Done."
