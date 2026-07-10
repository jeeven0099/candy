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

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting pipeline..."
    & $python $pipeline `
        --ollama-model qwen2.5:14b --ollama-timeout 2700 `
        --parallel --groq-brands 25 --gemini-brands 30 `
        --clean-only
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Pipeline finished (exit $LASTEXITCODE)."
} finally {
    Remove-Item $lockFile -ErrorAction SilentlyContinue
}
