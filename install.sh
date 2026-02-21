#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${ANAHITA_DOMAIN:?'domain is required: export ANAHITA_DOMAIN=t.domain.tld'}"

PROJECT="anahita"
PROJECT_DIR="${ANAHITA_PROJECT_DIR:-/opt/${PROJECT}}"
SLIP_BINARY="${ANAHITA_SLIP_BINARY:-/usr/local/bin/slipstream-server}"
SLIP_BINARY_URL="${ANAHITA_BINARY_URL:-https://github.com/net2share/slipstream-rust-build/releases/download/v2026.02.05/slipstream-server-linux-amd64}"
S5_BINARY="${ANAHITA_S5_BINARY:-/usr/local/bin/s5}"
S5_BINARY_URL="${ANAHITA_S5_BINARY_URL:-https://github.com/nxdp/s5/releases/download/v0.0.2/s5-linux-amd64}"

PRIMARY_IP="$(ip route get 8.8.8.8 | awk '{print $7}')"
SLIP_BIND_HOST="${ANAHITA_SLIP_BIND_HOST:-$PRIMARY_IP}"
SLIP_BIND_PORT="${ANAHITA_SLIP_BIND_PORT:-53}"
SLIP_TARGET_ADDR="${ANAHITA_SLIP_TARGET_ADDR:-127.0.0.1}"
SLIP_TARGET_PORT="${ANAHITA_SLIP_TARGET_PORT:-5201}"
SLIP_MAX_CONN="${ANAHITA_SLIP_MAX_CONN:-512}"
SLIP_IDLE_TIMEOUT="${ANAHITA_SLIP_IDLE_TIMEOUT:-3}"

SOCKS5_PROXY="${ANAHITA_SOCKS5_PROXY:-true}"
SOCKS5_ADDR="${ANAHITA_SOCKS5_ADDR:-127.0.0.1}"
SOCKS5_PORT="${ANAHITA_SOCKS5_PORT:-$SLIP_TARGET_PORT}"
SOCKS5_USER="${ANAHITA_SOCKS5_USER:-$(openssl rand -hex 8)}"
SOCKS5_PASSWORD="${ANAHITA_SOCKS5_PASSWORD:-$(openssl rand -hex 8)}"

SVC_SLIP="${PROJECT}-slipstream-server"
SVC_PROXY="${PROJECT}-proxy"

mkdir -p "$PROJECT_DIR"

[[ ! -f "${PROJECT_DIR}/slipstream.key" ]] && {
  echo "→ Generating slipstream keys..."
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${PROJECT_DIR}/slipstream.key" \
    -out "${PROJECT_DIR}/slipstream.pub" \
    -days 365 -subj "/CN=slipstream" 2>/dev/null
}

[[ ! -x "$SLIP_BINARY" || "${ANAHITA_FORCE_UPDATE:-}" == "true" ]] && {
  echo "→ Downloading slipstream-server..."
  curl -fsSL "$SLIP_BINARY_URL" -o "$SLIP_BINARY"
  chmod +x "$SLIP_BINARY"
}

[[ "$SOCKS5_PROXY" == "true" && ! -x "$S5_BINARY" || "${ANAHITA_FORCE_UPDATE:-}" == "true" ]] && {
  echo "→ Downloading s5..."
  curl -fsSL "$S5_BINARY_URL" -o "$S5_BINARY"
  chmod +x "$S5_BINARY"
}

cat > "/etc/systemd/system/${SVC_SLIP}.service" <<EOF
[Unit]
Description=Anahita Slipstream DNS Tunnel
After=network-online.target
Requires=network-online.target
StartLimitIntervalSec=0
StartLimitBurst=0

[Service]
Type=simple
TimeoutStartSec=3s
TimeoutStopSec=3s
Restart=always
RestartSec=1s
ExecStart=${SLIP_BINARY} \
  --dns-listen-host ${SLIP_BIND_HOST} \
  --dns-listen-port ${SLIP_BIND_PORT} \
  --target-address ${SLIP_TARGET_ADDR}:${SLIP_TARGET_PORT} \
  --domain ${DOMAIN} \
  --cert ${PROJECT_DIR}/slipstream.pub \
  --key ${PROJECT_DIR}/slipstream.key \
  --max-connections ${SLIP_MAX_CONN} \
  --idle-timeout-seconds ${SLIP_IDLE_TIMEOUT}

[Install]
WantedBy=multi-user.target
EOF

[[ "$SOCKS5_PROXY" == "true" ]] && {
  cat > "/etc/systemd/system/${SVC_PROXY}.service" <<EOF
[Unit]
Description=Anahita SOCKS5 Proxy
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0
StartLimitBurst=0

[Service]
Type=simple
TimeoutStartSec=3
TimeoutStopSec=3
Restart=always
RestartSec=1
ExecStart=${S5_BINARY} \
  -l ${SOCKS5_ADDR}:${SOCKS5_PORT} \
  -u ${SOCKS5_USER} \
  -p ${SOCKS5_PASSWORD}

[Install]
WantedBy=multi-user.target
EOF
}

systemctl daemon-reload
systemctl enable --now "${SVC_SLIP}.service" 2>/dev/null
systemctl restart "${SVC_SLIP}.service"

[[ "$SOCKS5_PROXY" == "true" ]] && {
  systemctl enable --now "${SVC_PROXY}.service" 2>/dev/null
  systemctl restart "${SVC_PROXY}.service"
}

echo "✓ ${SVC_SLIP} → ${SLIP_BIND_HOST}:${SLIP_BIND_PORT} (domain: ${DOMAIN})"
[[ "$SOCKS5_PROXY" == "true" ]] && echo -e "✓ ${SVC_PROXY} → socks5://${SOCKS5_ADDR}:${SOCKS5_PORT}\n✓ socks5 username: ${SOCKS5_USER}\n✓ socks5 password: ${SOCKS5_PASSWORD}"
