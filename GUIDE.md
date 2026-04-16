# Tailscale Subnet Router for Colleagues

ddps-mini Mac mini 위에서 동료별 독립 Tailscale 계정에 연구실 LAN(`166.104.75.0/24`) 접근을 제공하는 설정입니다.

## 구조

```
동료 노트북 (자기 tailnet)
  -> [ts-colleague-X 컨테이너 (ddps-mini)]
    -> 166.104.75.0/24 (연구실 LAN)
```

Mac mini가 `TS_USERSPACE=true` 모드로 패킷을 포워딩합니다.
`network_mode: host`는 macOS Docker 환경에서 동작하지 않으므로 사용하지 않습니다.

---

## 동료 추가 절차

### 1. 동료가 Auth Key 발급

동료가 자기 Tailscale Admin Console에서:

1. `https://login.tailscale.com/admin/settings/keys`
2. **Generate auth key**
3. Reusable: **OFF**, Ephemeral: **OFF**, Expiry: 90일
4. 발급된 키(`tskey-auth-...`)를 관리자(나)에게 전달

### 2. .env에 키 추가

```bash
# .env 파일에 추가
TS_AUTHKEY_B=tskey-auth-xxxxx
```

### 3. docker-compose.yml에 서비스 추가

주석 처리된 `ts-colleague-b` 블록을 복사해서 추가:

```yaml
ts-colleague-b:
  image: tailscale/tailscale:latest
  container_name: ts-colleague-b
  hostname: ddps-subnet-b
  environment:
    - TS_AUTHKEY=${TS_AUTHKEY_B}
    - TS_ROUTES=166.104.75.0/24
    - TS_STATE_DIR=/var/lib/tailscale
    - TS_USERSPACE=true
    - TS_ACCEPT_DNS=false
  volumes:
    - ts-b-state:/var/lib/tailscale
  restart: unless-stopped

volumes:
  ts-b-state:
```

hostname은 동료 tailnet에서 보이는 노드 이름이므로 겹치지 않게 설정합니다.

### 4. 컨테이너 시작

```bash
cd ~/developments/ts-subnet-router
docker compose up -d ts-colleague-b
docker logs ts-colleague-b --follow  # Running 상태 확인
```

### 5. 동료가 Route 승인

동료가 자기 Admin Console에서:

1. `https://login.tailscale.com/admin/machines`
2. **`ddps-subnet-b`** 노드 확인
3. `...` 메뉴 → **Edit route settings**
4. `166.104.75.0/24` → **Approve**

### 6. 동료 PC에서 접속 확인

```bash
ping 166.104.75.1   # 연구실 게이트웨이 등 임의의 호스트로 테스트
```

---

## 운영

### 상태 확인

```bash
docker compose ps
docker logs ts-colleague-a
```

### 재시작

```bash
docker compose restart ts-colleague-a
```

### 동료 제거

```bash
docker compose stop ts-colleague-a
docker compose rm ts-colleague-a
docker volume rm ts-subnet-router_ts-a-state
```

`.env`에서 해당 키도 삭제하고, 동료가 자기 Admin Console에서 노드를 제거하면 완전히 정리됩니다.

### 전체 중단 / 재시작

```bash
docker compose down
docker compose up -d
```

### Mac mini 재부팅 시 자동 시작

macOS LaunchAgent로 Colima가 로그인 시 자동 시작되도록 등록되어 있습니다.

```
~/Library/LaunchAgents/com.colima.default.plist
```

Colima가 뜨면 `restart: unless-stopped` 설정에 의해 컨테이너도 자동으로 올라옵니다.

```bash
# LaunchAgent 상태 확인
launchctl list | grep colima

# 자동 시작 해제
launchctl unload ~/Library/LaunchAgents/com.colima.default.plist

# 자동 시작 재등록
launchctl load ~/Library/LaunchAgents/com.colima.default.plist

# 시작 로그 확인
cat /tmp/colima.stdout.log
cat /tmp/colima.stderr.log
```

### 자동 이미지 업데이트 (cron)

매일 새벽 5시에 `update-tailscale.sh`가 실행되어 최신 이미지가 있으면 pull & 컨테이너 재생성합니다.

```bash
# crontab -l 로 확인
0 5 * * * /Users/woohyeok/developments/ts-subnet-router/update-tailscale.sh
```

- 새 이미지가 없으면 아무것도 하지 않음
- 로그: `update.log`에 기록
- Tailscale 버전 불일치(client != server)가 연결 실패를 유발할 수 있으므로 자동 업데이트 권장

### Keepalive (idle peer 방지)

#### 문제 상황

Tailscale은 5분간 트래픽이 없는 peer의 WireGuard 설정을 해제합니다 (lazy peer trimming).
`TS_USERSPACE=true` + 양쪽 NAT 환경에서는 이후 DERP relay 연결도 stale해져서
재연결 자체가 실패할 수 있습니다.

실제로 2026-04-08에 ts-colleague-a에서 macbook-pro-dev로 `tailscale ping`이 완전히 타임아웃되는 현상이 발생했습니다:

```
$ docker exec ts-colleague-a tailscale ping -c 3 100.85.139.40
ping "100.85.139.40" timed out
ping "100.85.139.40" timed out
ping "100.85.139.40" timed out

# peer 상태: Online이지만 handshake가 한 번도 성공하지 않음
CurAddr:        (빈 값 — direct 연결 없음)
LastHandshake:  0001-01-01T00:00:00Z (한 번도 성공 안 함)
Relay:          kr (DERP relay만 시도)
```

컨테이너를 재시작하면 DERP에 fresh connection을 맺으면서 즉시 복구되었습니다.

#### 해결: 2분마다 keepalive ping

이를 방지하기 위해 2분마다 `keepalive.sh`가 컨테이너별 peer 하나에 ping을 보냅니다.

```bash
# crontab -l 로 확인
*/2 * * * * /Users/woohyeok/developments/ts-subnet-router/keepalive.sh
```

스크립트는 `ts-colleague-*` 컨테이너를 자동 탐색하므로 동료 추가/제거 시 수정할 필요 없습니다.

#### ping 실패해도 keepalive는 동작하는가?

네. peer가 오프라인이어도 ping 시도 과정에서 DERP 서버에 접속하고 STUN 갱신이 발생합니다:

```
# 오프라인 peer에 ping 시도 후 로그
localapi: [POST] /localapi/v0/ping
ping(100.108.143.97): sending disco ping to [sSuQY] kmkims-macbook-air ...
magicsock: derp-7 does not know about peer [sSuQY], removing route
magicsock: endpoints changed: 166.104.75.140:56991 (stun), ...
```

- `sending disco ping` → DERP 서버에 접속하여 ping 전송 시도
- `endpoints changed` → STUN 체크 수행, NAT 매핑 갱신

따라서 peer 온/오프라인 여부와 관계없이 DERP 연결이 유지됩니다.

#### 연결 문제 발생 시 확인 방법

```bash
# 1. tailscale ping으로 연결 확인
docker exec ts-colleague-a tailscale ping --c 1 --timeout 5s <peer-ip>

# 2. peer 상태 상세 확인 (LastHandshake가 0001-01-01이면 문제)
docker exec ts-colleague-a tailscale status --json | python3 -c "
import json,sys; d=json.load(sys.stdin)
for k,p in d.get('Peer',{}).items():
    print(p.get('HostName'), '| Online:', p.get('Online'),
          '| CurAddr:', p.get('CurAddr'),
          '| LastHandshake:', p.get('LastHandshake'))
"

# 3. 문제 시 컨테이너 재시작으로 즉시 복구
docker compose restart ts-colleague-a
```
