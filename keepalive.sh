#!/bin/bash
# Keep Tailscale peer connections alive by sending periodic pings
# Prevents idle timeout on WireGuard sessions (lazy peer trimming after 5min)
#
# Pings one peer per container to keep the DERP connection alive.
# Ping failure (offline peer) is fine — the attempt itself is the keepalive.

for container in $(docker ps --format '{{.Names}}' | grep '^ts-colleague-'); do
  peer=$(docker exec "$container" tailscale status --json 2>/dev/null \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
for k,p in d.get('Peer',{}).items():
    for ip in p.get('TailscaleIPs',[]):
        if ':' not in ip:
            print(ip)
            sys.exit()
" 2>/dev/null)

  [ -n "$peer" ] && docker exec "$container" tailscale ping --c 1 --timeout 5s "$peer" >/dev/null 2>&1 || true
done
