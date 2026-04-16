# Keep Tailscale peer connections alive by sending periodic pings
# Prevents idle timeout on WireGuard sessions (lazy peer trimming after 5min)
#
# Pings one peer per container to keep the DERP connection alive.
# Ping failure (offline peer) is fine - the attempt itself is the keepalive.

$ErrorActionPreference = 'Continue'

$containers = docker ps --format '{{.Names}}' | Where-Object { $_ -match '^ts-colleague-' }

foreach ($container in $containers) {
    $raw = docker exec $container tailscale status --json 2>$null
    if (-not $raw) { continue }

    try {
        $status = $raw | ConvertFrom-Json
    } catch {
        continue
    }

    $peerIp = $null
    foreach ($peer in $status.Peer.PSObject.Properties.Value) {
        foreach ($ip in $peer.TailscaleIPs) {
            if ($ip -notmatch ':') {
                $peerIp = $ip
                break
            }
        }
        if ($peerIp) { break }
    }

    if ($peerIp) {
        docker exec $container tailscale ping --c 1 --timeout 5s $peerIp *> $null
    }
}
