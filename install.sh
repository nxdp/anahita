#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:?'domain is required: export DOMAIN=t.domain.tld'}"

PROJECT="anahita"
PROJECT_DIR="${PROJECT_DIR:-/opt/${PROJECT}}"
TUNNEL_ENGINE="${TUNNEL_ENGINE:-dnstt}"
FORCE_UPDATE="${FORCE_UPDATE:-false}"

SLIP_BINARY="${SLIP_BINARY:-/usr/local/bin/slipstream-server}"
SLIP_BINARY_URL="${SLIP_BINARY_URL:-https://github.com/net2share/slipstream-rust-build/releases/download/v2026.02.22.1/slipstream-server-linux-amd64}"
DNSTT_BINARY="${DNSTT_BINARY:-/usr/local/bin/dnstt-server}"
DNSTT_BINARY_URL="${DNSTT_BINARY_URL:-https://github.com/net2share/dnstt/releases/download/latest/dnstt-server-linux-amd64}"
XRAY_BINARY="${XRAY_BINARY:-/usr/local/bin/xray}"
XRAY_ARCHIVE_URL="${XRAY_ARCHIVE_URL:-https://github.com/XTLS/Xray-core/releases/download/v26.2.6/Xray-linux-64.zip}"
XRAY_CONFIG="${XRAY_CONFIG:-${PROJECT_DIR}/config.json}"

PRIMARY_IP="$(ip route get 8.8.8.8 | awk '{print $7}')"
BIND_HOST="${BIND_HOST:-$PRIMARY_IP}"
BIND_PORT="${BIND_PORT:-53}"
TARGET_ADDR="${TARGET_ADDR:-127.0.0.1}"
TARGET_PORT="${TARGET_PORT:-5201}"
MTU="${MTU:-1232}"
MAX_CONN="${MAX_CONN:-512}"
IDLE_TIMEOUT="${IDLE_TIMEOUT:-60}"

SOCKS5_PROXY="${SOCKS5_PROXY:-true}"
SOCKS5_ADDR="${SOCKS5_ADDR:-127.0.0.1}"
SOCKS5_PORT="${SOCKS5_PORT:-$TARGET_PORT}"
SOCKS5_USER="${SOCKS5_USER:-$(openssl rand -hex 4)}"
SOCKS5_PASSWORD="${SOCKS5_PASSWORD:-$(openssl rand -hex 4)}"

SVC_TUNNEL="${PROJECT}-dns-tunnel"
SVC_PROXY="${PROJECT}-proxy"
SVC_OLD_SLIP="${PROJECT}-slipstream-server"

wait_or_fail() {
  local pid
  for pid in "$@"; do
    wait "$pid" || exit 1
  done
}

download_binary() {
  local url="$1"
  local dest="$2"
  local tmp

  tmp="$(mktemp)" || exit 1

  trap 'rm -f "$tmp"' EXIT

  echo "→ Downloading $(basename "$dest")..."
  curl -fsSL "$url" -o "$tmp" || exit 1

  chmod +x "$tmp" || exit 1
  mv -f "$tmp" "$dest" || exit 1

  trap - EXIT
}

download_archive_binary() {
  local url="$1"
  local dest="$2"
  local binary="$3"
  local tmpdir
  local archive

  tmpdir="$(mktemp -d)" || exit 1
  archive="${tmpdir}/archive.zip"

  trap 'rm -rf "$tmpdir"' EXIT

  echo "→ Downloading $(basename "$dest")..."
  curl -fsSL "$url" -o "$archive" || exit 1

  if command -v unzip >/dev/null 2>&1; then
    unzip -qo "$archive" -d "$tmpdir" || exit 1
  else
    echo "error: unzip is required to extract Xray archive" >&2
    exit 1
  fi

  chmod +x "${tmpdir}/${binary}" || exit 1
  mv -f "${tmpdir}/${binary}" "$dest" || exit 1

  trap - EXIT
}

mkdir -p "$PROJECT_DIR"

case "$TUNNEL_ENGINE" in
  dnstt|slipstream) ;;
  *)
    echo "error: TUNNEL_ENGINE must be one of: dnstt, slipstream" >&2
    exit 1
    ;;
esac

if [[ "$TUNNEL_ENGINE" == "dnstt" ]]; then
  TUNNEL_EXEC="${DNSTT_BINARY} -udp ${BIND_HOST}:${BIND_PORT} -privkey-file ${PROJECT_DIR}/dnstt.key -mtu ${MTU} ${DOMAIN} ${TARGET_ADDR}:${TARGET_PORT}"
else
  TUNNEL_EXEC="${SLIP_BINARY} --dns-listen-host ${BIND_HOST} --dns-listen-port ${BIND_PORT} --target-address ${TARGET_ADDR}:${TARGET_PORT} --domain ${DOMAIN} --cert ${PROJECT_DIR}/slipstream.pub --key ${PROJECT_DIR}/slipstream.key --max-connections ${MAX_CONN} --idle-timeout-seconds ${IDLE_TIMEOUT}"
fi

prepare_tunnel_assets() {
  if [[ "$TUNNEL_ENGINE" == "dnstt" ]]; then
    [[ ! -x "$DNSTT_BINARY" || "$FORCE_UPDATE" == "true" ]] &&
      download_binary "$DNSTT_BINARY_URL" "$DNSTT_BINARY"

    [[ ! -f "${PROJECT_DIR}/dnstt.key" || ! -f "${PROJECT_DIR}/dnstt.pub" ]] && {
      echo "→ Generating dnstt keys..."
      "$DNSTT_BINARY" -gen-key \
        -privkey-file "${PROJECT_DIR}/dnstt.key" \
        -pubkey-file "${PROJECT_DIR}/dnstt.pub" >/dev/null
    }
    return
  fi

  local pids=()

  [[ ! -f "${PROJECT_DIR}/slipstream.key" ]] && {
    {
      echo "→ Generating slipstream keys..."
      openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "${PROJECT_DIR}/slipstream.key" \
        -out "${PROJECT_DIR}/slipstream.pub" \
        -days 365 -subj "/CN=slipstream" 2>/dev/null
    } &
    pids+=("$!")
  }

  [[ ! -x "$SLIP_BINARY" || "$FORCE_UPDATE" == "true" ]] && {
    download_binary "$SLIP_BINARY_URL" "$SLIP_BINARY" &
    pids+=("$!")
  }

  [[ "${#pids[@]}" -gt 0 ]] && wait_or_fail "${pids[@]}"
}

pids=()
prepare_tunnel_assets &
pids+=("$!")

[[ "$SOCKS5_PROXY" == "true" ]] &&
[[ ! -x "$XRAY_BINARY" || "$FORCE_UPDATE" == "true" ]] && {
  download_archive_binary "$XRAY_ARCHIVE_URL" "$XRAY_BINARY" "xray" &
  pids+=("$!")
}

cat > "/etc/systemd/system/${SVC_TUNNEL}.service" <<EOF
[Unit]
Description=Anahita DNS Tunnel (${TUNNEL_ENGINE})
After=network.target nss-lookup.target
StartLimitIntervalSec=0
StartLimitBurst=0

[Service]
Type=simple
TimeoutStartSec=3s
TimeoutStopSec=3s
Restart=always
RestartSec=1s
ExecStart=${TUNNEL_EXEC}

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

systemctl --no-block stop "${SVC_OLD_SLIP}.service" >/dev/null 2>&1 || true
systemctl --no-block disable "${SVC_OLD_SLIP}.service" >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/${SVC_OLD_SLIP}.service"

wait_or_fail "${pids[@]}"

systemctl daemon-reload

systemctl --no-block enable -q "${SVC_TUNNEL}.service"
systemctl --no-block restart "${SVC_TUNNEL}.service"

[[ "$SOCKS5_PROXY" == "true" ]] && {
  systemctl --no-block enable -q "${SVC_PROXY}.service"
  systemctl --no-block restart "${SVC_PROXY}.service"
} || {
  systemctl --no-block stop "${SVC_PROXY}.service" >/dev/null 2>&1 || true
  systemctl --no-block disable "${SVC_PROXY}.service" >/dev/null 2>&1 || true
}

DNSTT_PUBKEY=""
[[ "$TUNNEL_ENGINE" == "dnstt" ]] && DNSTT_PUBKEY="$(tr -d '\n' < "${PROJECT_DIR}/dnstt.pub")"

echo ""
echo "  engine      →  ${TUNNEL_ENGINE}"
echo "  dns tunnel  →  ${BIND_HOST}:${BIND_PORT}  (${DOMAIN})"
echo "  target      →  ${TARGET_ADDR}:${TARGET_PORT}"
[[ "$TUNNEL_ENGINE" == "dnstt" ]] && echo "  pubkey      →  ${DNSTT_PUBKEY}"
[[ "$SOCKS5_PROXY" == "true" ]] && cat <<EOF
  socks5      →  ${SOCKS5_ADDR}:${SOCKS5_PORT}
  user        →  ${SOCKS5_USER}
  pass        →  ${SOCKS5_PASSWORD}
EOF
echo ""
