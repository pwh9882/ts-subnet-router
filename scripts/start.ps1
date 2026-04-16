# Start all ts-subnet-router containers on Windows.
# Docker Desktop manages the VM; no colima equivalent needed.

$ErrorActionPreference = 'Stop'

$ComposeFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'docker-compose.yml'

Write-Host "==> Docker 상태 확인..."
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker Desktop이 실행 중이 아닙니다. 먼저 Docker Desktop을 시작하세요."
    exit 1
}

Write-Host "==> 컨테이너 시작..."
docker compose -f $ComposeFile up -d

Write-Host "==> 상태 확인..."
docker compose -f $ComposeFile ps
