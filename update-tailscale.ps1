# Tailscale Docker image update checker & restarter
# Runs via Task Scheduler - pulls latest image, recreates containers only if image changed.

$ErrorActionPreference = 'Continue'

# Script sits at repo root alongside docker-compose.yml.
$ComposeDir = $PSScriptRoot
$LogFile = Join-Path $ComposeDir 'update.log'

Set-Location $ComposeDir

function Write-Log([string]$msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$ts] $msg" | Add-Content -Path $LogFile -Encoding UTF8
}

Write-Log "Checking for tailscale image update..."

$pullOutput = (docker compose pull 2>&1 | Out-String)

if ($pullOutput -match 'Pulled') {
    Write-Log "New image found. Recreating containers..."
    (docker compose up -d 2>&1 | Out-String) | Add-Content -Path $LogFile -Encoding UTF8
    $version = docker exec ts-colleague-a tailscale version 2>$null | Select-Object -First 1
    Write-Log "Done. New version: $version"
} else {
    Write-Log "Already up to date."
}
