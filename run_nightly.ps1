$root     = "C:\Users\user\Downloads\promo-raw-scraper"
$python   = "C:\Python314\python.exe"
$pipeline = "$root\promo-raw-scraper\run_pipeline.py"
$lockFile = "$root\promo-raw-scraper\.pipeline.lock"

# Prevent concurrent runs — check lock file for a still-running Python process
if (Test-Path $lockFile) {
    $lockPid = (Get-Content $lockFile -ErrorAction SilentlyContinue) -replace '\D', ''
    $proc    = if ($lockPid) { Get-Process -Id ([int]$lockPid) -ErrorAction SilentlyContinue } else { $null }
    $running = $proc -and ($proc.Name -like "python*")
    if ($running) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Pipeline already running (PID $lockPid). Exiting."
        exit 0
    }
    Remove-Item $lockFile -Force
}
# Write a placeholder so the lock exists before Python starts
$PID | Out-File $lockFile -Force

try {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting pipeline (main pass — OpenRouter openai/gpt-oss-120b)..."
    $pipelineJob = Start-Process $python -ArgumentList @(
        $pipeline,
        "--model", "openrouter",
        "--openrouter-model", "openai/gpt-oss-120b",
        "--cloud-timeout", "60"
    ) -PassThru -NoNewWindow
    # Track the Python child PID in the lock file so concurrent-run check works
    # even if this PowerShell wrapper exits early
    $pipelineJob.Id | Out-File $lockFile -Force
    $pipelineJob.WaitForExit()
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Main pass finished (exit $($pipelineJob.ExitCode))."

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
            --model openrouter --openrouter-model openai/gpt-oss-120b --cloud-timeout 60
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Retry pass finished (exit $LASTEXITCODE)."
        [datetime]::Today.ToString("yyyy-MM-dd") | Out-File $retryStampFile -Force
    } else {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Skipping retry pass (last ran $daysSinceRetry day(s) ago, runs every 3 days)."
    }

} finally {
    Remove-Item $lockFile -ErrorAction SilentlyContinue
}
