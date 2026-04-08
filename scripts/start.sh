#!/bin/bash
# Colima 시작 후 모든 컨테이너 올리기

set -e

echo "==> Colima 상태 확인..."
if ! colima status &>/dev/null; then
  echo "==> Colima 시작 중..."
  colima start --cpu 2 --memory 4 --disk 60 --arch aarch64
else
  echo "    Colima 이미 실행 중"
fi

echo "==> 컨테이너 시작..."
docker compose -f "$(dirname "$0")/../docker-compose.yml" up -d

echo "==> 상태 확인..."
docker compose -f "$(dirname "$0")/../docker-compose.yml" ps
