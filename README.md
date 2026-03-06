# ANAHITA

One-command deployment of a DNS tunnel (`dnstt` or `slipstream`) with an optional [SOCKS5](https://github.com/XTLS/Xray-core) proxy.

## Requirements

- Linux with systemd
- `curl`, `openssl`, `unzip` available
- Root access

## Usage

Set your domain, then run:
```bash
DOMAIN=t.example.com bash <(curl -fsSL https://raw.githubusercontent.com/nxdp/anahita/main/install.sh)
```
Alternative:
```bash
export DOMAIN=t.example.com
curl -fsSL https://raw.githubusercontent.com/nxdp/anahita/main/install.sh | bash
```

```
→ Generating dnstt keys...
→ Downloading xray...

  engine      →  dnstt
  dns tunnel  →  203.0.113.2:53  (t.example.com)
  target      →  127.0.0.1:5201
  pubkey      →  939700acff5ba1c0...
  socks5      →  127.0.0.1:5201
  user        →  86612f10
  pass        →  e4749ec8


real    0m1.350s
user    0m0.258s
sys     0m0.083s
```

That's it. under 2 seconds.

## Configuration

All variables are optional except `DOMAIN`.

| Variable | Default | Description |
|---|---|---|
| `DOMAIN` | **required** | DNS tunnel domain |
| `TUNNEL_ENGINE` | `dnstt` | `dnstt` or `slipstream` |
| `PROJECT_DIR` | `/opt/anahita` | project dir (keys stored here) |
| `DNSTT_BINARY` | `/usr/local/bin/dnstt-server` | dnstt-server binary install path |
| `DNSTT_BINARY_URL` | `https://github.com/net2share/dnstt/releases/download/latest/dnstt-server-linux-amd64` | dnstt-server download URL |
| `SLIP_BINARY_URL` | latest GitHub release (amd64) | slipstream-server download URL |
| `SLIP_BINARY` | `/usr/local/bin/slipstream-server` | slipstream-server binary install path |
| `XRAY_ARCHIVE_URL` | `https://github.com/XTLS/Xray-core/releases/download/v26.2.6/Xray-linux-64.zip` | Xray archive download URL |
| `XRAY_BINARY` | `/usr/local/bin/xray` | Xray binary install path |
| `XRAY_CONFIG` | `$PROJECT_DIR/config.json` | Xray config file path |
| `BIND_HOST` | auto-detected primary IPv4 | DNS tunnel bind address |
| `BIND_PORT` | `53` | DNS tunnel bind port |
| `TARGET_ADDR` | `127.0.0.1` | tunnel target address |
| `TARGET_PORT` | `5201` | tunnel target port |
| `MTU` | `1232` | dnstt MTU |
| `MAX_CONN` | `512` | max concurrent connections (slipstream only) |
| `IDLE_TIMEOUT` | `60` | idle timeout in seconds (slipstream only) |
| `SOCKS5_PROXY` | `true` | deploy SOCKS5 proxy alongside |
| `SOCKS5_ADDR` | `127.0.0.1` | SOCKS5 listen address |
| `SOCKS5_PORT` | `$TARGET_PORT` | SOCKS5 listen port |
| `SOCKS5_USER` | `$(openssl rand -hex 4)` | SOCKS5 proxy username |
| `SOCKS5_PASSWORD` | `$(openssl rand -hex 4)` | SOCKS5 proxy password |
| `FORCE_UPDATE` | `false` | set to `true` to re-download binary |

## Examples

**Minimal (DNS tunnel only):**
```bash
export DOMAIN=t.example.com
export SOCKS5_PROXY=false
export TARGET_PORT=8080 # your custom proxy

curl -fsSL https://raw.githubusercontent.com/nxdp/anahita/main/install.sh | bash
```

**Use slipstream engine:**
```bash
export DOMAIN=t.example.com
export TUNNEL_ENGINE=slipstream

curl -fsSL https://raw.githubusercontent.com/nxdp/anahita/main/install.sh | bash
```

**Full setup (with SOCKS5):**
```bash
export DOMAIN=t.example.com
export SOCKS5_USER="username"
export SOCKS5_PASSWORD="password"

curl -fsSL https://raw.githubusercontent.com/nxdp/anahita/main/install.sh | bash
```

**Force re-download binary and update services:**
```bash
export DOMAIN=t.example.com
export FORCE_UPDATE=true

curl -fsSL https://raw.githubusercontent.com/nxdp/anahita/main/install.sh | bash
```

## Services

```bash
# status
systemctl status anahita-dns-tunnel
systemctl status anahita-proxy

# logs
journalctl -fu anahita-dns-tunnel
journalctl -fu anahita-proxy
```

If you used older versions with `anahita-slipstream-server`, clean it manually:
```bash
systemctl disable --now anahita-slipstream-server
rm -f /etc/systemd/system/anahita-slipstream-server.service
systemctl daemon-reload
```

## Idempotent

Safe to run multiple times. Re-running updates service configs and restarts services. Tunnel keys are generated once, while SOCKS5 user/pass are regenerated each run unless explicitly set.
