#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${ANAHITA_DOMAIN:?'domain is required: export ANAHITA_DOMAIN=t.domain.tld'}"

PROJECT="anahita"
PROJECT_DIR="${ANAHITA_PROJECT_DIR:-/opt/${PROJECT}}"
SLIP_BINARY="${ANAHITA_SLIP_BINARY:-/usr/local/bin/slipstream-server}"
SLIP_BINARY_URL="${ANAHITA_BINARY_URL:-https://github.com/net2share/slipstream-rust-build/releases/download/v2026.02.22.1/slipstream-server-linux-amd64}"
XRAY_BINARY="${ANAHITA_XRAY_BINARY:-/usr/local/bin/xray}"
XRAY_ARCHIVE_URL="${ANAHITA_XRAY_ARCHIVE_URL:-https://github.com/XTLS/Xray-core/releases/download/v26.2.6/Xray-linux-64.zip}"
XRAY_CONFIG="${ANAHITA_XRAY_CONFIG:-${PROJECT_DIR}/config.json}"

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
SOCKS5_USER="${ANAHITA_SOCKS5_USER:-$(openssl rand -hex 4)}"
SOCKS5_PASSWORD="${ANAHITA_SOCKS5_PASSWORD:-$(openssl rand -hex 4)}"

SVC_SLIP="${PROJECT}-slipstream-server"
SVC_PROXY="${PROJECT}-proxy"

download_binary() {
  local url="$1"
  local dest="$2"

  tmp="$(mktemp)" || exit 1

  trap 'rm -f "$tmp"' EXIT

  echo "→ Downloading $(basename "$dest")..."
  curl -fsSL "$url" -o "$tmp" || exit 1

  chmod +x "$tmp" || exit 1
  mv -f "$tmp" "$dest" || exit 1

  trap - EXIT
}

download_xray_binary() {
  local url="$1"
  local dest="$2"
  local tmpdir
  local archive

  tmpdir="$(mktemp -d)" || exit 1
  archive="${tmpdir}/xray.zip"

  trap 'rm -rf "$tmpdir"' EXIT

  echo "→ Downloading xray..."
  curl -fsSL "$url" -o "$archive" || exit 1

  if command -v unzip >/dev/null 2>&1; then
    unzip -qo "$archive" -d "$tmpdir" || exit 1
  else
    echo "error: unzip is required to extract Xray archive" >&2
    exit 1
  fi

  chmod +x "${tmpdir}/xray" || exit 1
  mv -f "${tmpdir}/xray" "$dest" || exit 1

  trap - EXIT
}

mkdir -p "$PROJECT_DIR"

[[ ! -f "${PROJECT_DIR}/slipstream.key" ]] && {
  echo "→ Generating slipstream keys..."
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${PROJECT_DIR}/slipstream.key" \
    -out "${PROJECT_DIR}/slipstream.pub" \
    -days 365 -subj "/CN=slipstream" 2>/dev/null
} &

[[ ! -x "$SLIP_BINARY" || "${ANAHITA_FORCE_UPDATE:-}" == "true" ]] &&
  download_binary "$SLIP_BINARY_URL" "$SLIP_BINARY" &

[[ "$SOCKS5_PROXY" == "true" ]] &&
[[ ! -x "$XRAY_BINARY" || "${ANAHITA_FORCE_UPDATE:-}" == "true" ]] &&
  download_xray_binary "$XRAY_ARCHIVE_URL" "$XRAY_BINARY" &

cat > "/etc/systemd/system/${SVC_SLIP}.service" <<EOF
[Unit]
Description=Anahita Slipstream DNS Tunnel
After=network.target nss-lookup.target
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
  mkdir -p "$(dirname "$XRAY_CONFIG")"
  cat > "${XRAY_CONFIG}" <<EOF
{
  "log": {
    "access": "none",
    "dnsLog": false,
    "error": "",
    "loglevel": "warning",
    "maskAddress": ""
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "outboundTag": "blocked",
        "protocol": [
          "bittorrent"
        ]
      }
    ]
  },
  "inbounds": [
    {
      "listen": "${SOCKS5_ADDR}",
      "port": ${SOCKS5_PORT},
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "${SOCKS5_USER}",
            "pass": "${SOCKS5_PASSWORD}"
          }
        ],
        "udp": true,
        "ip": "${SOCKS5_ADDR}"
      },
      "streamSettings": {
        "network": "raw",
        "security": "none",
        "sockopt": {
          "tcpFastOpen": true,
          "tcpCongestion": "bbr",
          "tcpMptcp": true,
          "tcpNoDelay": true
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "AsIs"
      }
    },
    {
      "tag": "blocked",
      "protocol": "blackhole"
    }
  ]
}
EOF

  cat > "/etc/systemd/system/${SVC_PROXY}.service" <<EOF
[Unit]
Description=Anahita SOCKS5 Proxy
After=network.target nss-lookup.target
StartLimitIntervalSec=0
StartLimitBurst=0

[Service]
Type=simple
LimitNPROC=10000
LimitNOFILE=1000000
RestartSec=1
Restart=always
ExecStart=${XRAY_BINARY} run -c ${XRAY_CONFIG}

[Install]
WantedBy=multi-user.target
EOF
}

systemctl daemon-reload

wait

systemctl --no-block enable -q "${SVC_SLIP}.service"
systemctl --no-block restart "${SVC_SLIP}.service"

[[ "$SOCKS5_PROXY" == "true" ]] && {
  systemctl --no-block enable -q "${SVC_PROXY}.service"
  systemctl --no-block restart "${SVC_PROXY}.service"
}

echo ""
echo "  slipstream  →  ${SLIP_BIND_HOST}:${SLIP_BIND_PORT}  (${DOMAIN})"
[[ "$SOCKS5_PROXY" == "true" ]] && cat <<EOF
  socks5      →  ${SOCKS5_ADDR}:${SOCKS5_PORT}
  user        →  ${SOCKS5_USER}
  pass        →  ${SOCKS5_PASSWORD}
EOF
echo ""
