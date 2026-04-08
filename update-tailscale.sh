#!/bin/bash
# Tailscale Docker image update checker & restarter
# Runs via cron — pulls latest image, recreates containers only if image changed.

COMPOSE_DIR="/Users/woohyeok/developments/ts-subnet-router"
LOG_FILE="$COMPOSE_DIR/update.log"

cd "$COMPOSE_DIR" || exit 1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking for tailscale image update..." >> "$LOG_FILE"

# Pull and capture output
PULL_OUTPUT=$(docker compose pull 2>&1)

if echo "$PULL_OUTPUT" | grep -q "Pulled"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] New image found. Recreating containers..." >> "$LOG_FILE"
    docker compose up -d >> "$LOG_FILE" 2>&1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Done. New version: $(docker exec ts-colleague-a tailscale version 2>/dev/null | head -1)" >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Already up to date." >> "$LOG_FILE"
fi
