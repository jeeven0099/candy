$root     = "C:\Users\user\Downloads\promo-raw-scraper"
$python   = "C:\Python314\python.exe"
$pipeline = "$root\promo-raw-scraper\run_pipeline.py"
$lockFile = "$root\promo-raw-scraper\.pipeline.lock"

# Prevent concurrent runs
if (Test-Path $lockFile) {
    $lockPid = Get-Content $lockFile -ErrorAction SilentlyContinue
    $running = $lockPid -and (Get-Process -Id $lockPid -ErrorAction SilentlyContinue)
    if ($running) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Pipeline already running (PID $lockPid). Exiting."
        exit 0
    }
    Remove-Item $lockFile -Force
}
$PID | Out-File $lockFile -Force

try {
    # Start Ollama if not already running
    $ollamaRunning = try {
        (Invoke-WebRequest -Uri "http://localhost:11434/api/version" -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200
    } catch { $false }

    if (-not $ollamaRunning) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting Ollama..."
        Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 10
    }

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting pipeline (main pass)..."
    & $python $pipeline `
        --ollama-model qwen2.5:14b --ollama-timeout 3200 `
        --parallel --groq-brands 50 `
        --clean-only
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Main pass finished (exit $LASTEXITCODE)."

    # Retry pass runs every 3 days only
    $retryStampFile = "$root\promo-raw-scraper\.last_retry_date"
    $daysSinceRetry = 999
    if (Test-Path $retryStampFile) {
        $lastRetry = [datetime]::Parse((Get-Content $retryStampFile))
        $daysSinceRetry = ([datetime]::Today - $lastRetry.Date).Days
    }

    if ($daysSinceRetry -ge 3) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting failed-brand retry pass (last ran $daysSinceRetry day(s) ago)..."
        & $python $pipeline `
            --skip-scrape --from-step 4 `
            --ollama-model qwen2.5:14b --ollama-timeout 3200
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Retry pass finished (exit $LASTEXITCODE)."
        [datetime]::Today.ToString("yyyy-MM-dd") | Out-File $retryStampFile -Force
    } else {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Skipping retry pass (last ran $daysSinceRetry day(s) ago, runs every 3 days)."
    }

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Applying keyword store patches..."
    & $python "$root\promo-raw-scraper\src\apply_keyword_store.py"
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Keyword store applied (exit $LASTEXITCODE)."
} finally {
    Remove-Item $lockFile -ErrorAction SilentlyContinue
}
