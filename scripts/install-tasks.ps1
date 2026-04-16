# Register (or remove) Task Scheduler jobs for Windows host operation.
#
# Usage:
#   .\install-tasks.ps1              # register both tasks
#   .\install-tasks.ps1 -Remove      # remove both tasks
#
# Must run from an elevated (Administrator) PowerShell.

param(
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

# Repo root = parent of this scripts/ directory.
$RepoRoot       = Split-Path -Parent $PSScriptRoot
$UpdateScript   = Join-Path $RepoRoot 'update-tailscale.ps1'
$KeepaliveScript = Join-Path $RepoRoot 'keepalive.ps1'

$UpdateTask    = 'ts-subnet-update'
$KeepaliveTask = 'ts-subnet-keepalive'

function Assert-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Administrator PowerShell에서 실행해 주세요."
    }
}

function Remove-Tasks {
    foreach ($name in @($UpdateTask, $KeepaliveTask)) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            Write-Host "  removed: $name"
        } else {
            Write-Host "  skip (not found): $name"
        }
    }
}

function Register-Tasks {
    if (-not (Test-Path $UpdateScript))    { throw "Not found: $UpdateScript" }
    if (-not (Test-Path $KeepaliveScript)) { throw "Not found: $KeepaliveScript" }

    $user = "$env:USERDOMAIN\$env:USERNAME"

    $commonSettings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -DontStopIfGoingOnBatteries `
        -AllowStartIfOnBatteries `
        -MultipleInstances IgnoreNew

    # --- update task: daily 05:00 ---
    $updateAction = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$UpdateScript`""
    $updateTrigger = New-ScheduledTaskTrigger -Daily -At 5:00AM

    Register-ScheduledTask `
        -TaskName $UpdateTask `
        -Action   $updateAction `
        -Trigger  $updateTrigger `
        -Settings $commonSettings `
        -User     $user `
        -RunLevel Limited `
        -Description 'Tailscale image auto-update (daily 05:00)' `
        -Force | Out-Null
    Write-Host "  registered: $UpdateTask (daily 05:00)"

    # --- keepalive task: every 2 minutes, indefinitely ---
    $kaAction = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$KeepaliveScript`""

    $kaTrigger = New-ScheduledTaskTrigger `
        -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 2)
    # 무기한 반복: Duration을 빈 문자열로 설정
    $kaTrigger.Repetition.Duration = ''

    Register-ScheduledTask `
        -TaskName $KeepaliveTask `
        -Action   $kaAction `
        -Trigger  $kaTrigger `
        -Settings $commonSettings `
        -User     $user `
        -RunLevel Limited `
        -Description 'Tailscale keepalive ping (every 2 min)' `
        -Force | Out-Null
    Write-Host "  registered: $KeepaliveTask (every 2 min)"
}

Assert-Admin

if ($Remove) {
    Write-Host "==> Removing scheduled tasks..."
    Remove-Tasks
} else {
    Write-Host "==> Registering scheduled tasks..."
    Write-Host "    user = $env:USERDOMAIN\$env:USERNAME"
    Write-Host "    repo = $RepoRoot"
    Register-Tasks
}

Write-Host ""
Write-Host "==> Current state:"
Get-ScheduledTask -TaskName 'ts-subnet-*' -ErrorAction SilentlyContinue |
    Get-ScheduledTaskInfo |
    Format-Table TaskName, LastRunTime, LastTaskResult, NextRunTime -AutoSize
