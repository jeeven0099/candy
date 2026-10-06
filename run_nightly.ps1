$root     = "C:\Users\user\Desktop\promo-raw-scraper"
$ErrorActionPreference = "Stop"

$python      = "C:\Python314\python.exe"
$pipelineDir = "$root\promo-raw-scraper"
$pipeline    = "$pipelineDir\run_pipeline.py"
$lockFile    = "$pipelineDir\.pipeline.lock"
$logsDir     = "$pipelineDir\logs"
$wrapperLog  = "$logsDir\nightly_wrapper_$(Get-Date -Format 'yyyyMMdd').log"
$exitCode    = 0

New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
Start-Transcript -Path $wrapperLog -Append -ErrorAction SilentlyContinue | Out-Null

if (-not (Test-Path $python)) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ERROR: Python executable not found: $python"
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    exit 1
}
if (-not (Test-Path $pipeline)) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ERROR: Pipeline script not found: $pipeline"
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    exit 1
}

# Prevent concurrent runs - check lock file for a still-running Python process
if (Test-Path $lockFile) {
    $lockPid = (Get-Content $lockFile -ErrorAction SilentlyContinue) -replace '\D', ''
    $proc    = if ($lockPid) { Get-Process -Id ([int]$lockPid) -ErrorAction SilentlyContinue } else { $null }
    $running = $proc -and ($proc.Name -like "python*")
    if ($running) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Pipeline already running (PID $lockPid). Exiting."
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 0
    }
    Remove-Item $lockFile -Force
}
# Write a placeholder so the lock exists before Python starts
$PID | Out-File $lockFile -Force

try {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting pipeline (main pass - OpenRouter openai/gpt-oss-120b)..."
    $pipelineJob = Start-Process $python -ArgumentList @(
        $pipeline,
        "--model", "openrouter",
        "--openrouter-model", "openai/gpt-oss-120b",
        "--cloud-timeout", "60"
    ) -WorkingDirectory $pipelineDir -PassThru -NoNewWindow
    # Track the Python child PID in the lock file so concurrent-run check works
    # even if this PowerShell wrapper exits early
    $pipelineJob.Id | Out-File $lockFile -Force
    $pipelineJob.WaitForExit()
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Main pass finished (exit $($pipelineJob.ExitCode))."
    if ($pipelineJob.ExitCode -ne 0) {
        $exitCode = $pipelineJob.ExitCode
        throw "Main pipeline failed with exit code $exitCode."
    }

    # Retry pass runs every 3 days only
    $retryStampFile = "$pipelineDir\.last_retry_date"
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
        if ($LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
            throw "Retry pass failed with exit code $exitCode."
        }
        [datetime]::Today.ToString("yyyy-MM-dd") | Out-File $retryStampFile -Force
    } else {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Skipping retry pass (last ran $daysSinceRetry day(s) ago, runs every 3 days)."
    }

} catch {
    if ($exitCode -eq 0) {
        $exitCode = 1
    }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ERROR: $($_.Exception.Message)"
} finally {
    Remove-Item $lockFile -ErrorAction SilentlyContinue
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    exit $exitCode
}
