# ANAHITA

One-command deployment of a [slipstream-rust](https://github.com/Mygod/slipstream-rust) DNS tunnel with an optional [SOCKS5](https://github.com/nxdp/s5) proxy.

## Requirements

- Linux with systemd
- `curl`, `openssl`, `ssh-keygen` available
- Root access

## Usage

Set your domain, then run:
```bash
ANAHITA_DOMAIN=t.example.com bash <(curl -fsSL https://raw.githubusercontent.com/nxdp/anahita/main/install.sh)
```
Alternative:
```bash
export ANAHITA_DOMAIN=t.example.com
curl -fsSL https://raw.githubusercontent.com/nxdp/anahita/main/install.sh | bash
```

```
real    0m3.905s
user    0m1.388s
sys     0m0.142s
```

That's it. under 5 seconds.

## Configuration

All variables are optional except `ANAHITA_DOMAIN`.

| Variable | Default | Description |
|---|---|---|
| `ANAHITA_DOMAIN` | **required** | DNS tunnel domain |
| `ANAHITA_PROJECT_DIR` | `/opt/anahita` | project dir (keys stored here) |
| `ANAHITA_SLIP_BINARY_URL` | latest GitHub release | slipstream-server download URL |
| `ANAHITA_SLIP_BINARY` | `/usr/local/bin/slipstream-server` | slipstream-server binary install path |
| `ANAHITA_SLIP_BIND_HOST` | auto-detected primary IPv4 | slipstream bind address |
| `ANAHITA_SLIP_BIND_PORT` | `53` | slipstream bind port |
| `ANAHITA_SLIP_TARGET_ADDR` | `127.0.0.1` | tunnel target address |
| `ANAHITA_SLIP_TARGET_PORT` | `5201` | tunnel target port |
| `ANAHITA_SLIP_MAX_CONN` | `512` | max concurrent connections |
| `ANAHITA_SLIP_IDLE_TIMEOUT` | `3` | idle timeout in seconds |
| `ANAHITA_SOCKS5_PROXY` | `true` | deploy SOCKS5 proxy alongside |
| `ANAHITA_SOCKS5_ADDR` | `127.0.0.1` | SOCKS5 listen address |
| `ANAHITA_SOCKS5_PORT` | `$ANAHITA_SLIP_TARGET_PORT` | SOCKS5 listen port |
| `ANAHITA_SOCKS5_USER` | `$(openssl rand -hex 8)` | SOCKS5 proxy username |
| `ANAHITA_SOCKS5_PASSWORD` | `$(openssl rand -hex 8)` | SOCKS5 proxy password |
| `ANAHITA_FORCE_UPDATE` | `false` | set to `true` to re-download binary |

## Examples

**Minimal — DNS tunnel only:**
```bash
export ANAHITA_DOMAIN=t.example.com
export ANAHITA_SSH_PROXY=false

curl -fsSL https://raw.githubusercontent.com/nxdp/anahita/main/install.sh | bash
```

**Full setup:**
```bash
export ANAHITA_DOMAIN=t.example.com
export ANAHITA_SOCKS5_USER="username"
export ANAHITA_SOCKS5_PASSWORD="password"

curl -fsSL https://raw.githubusercontent.com/nxdp/anahita/main/install.sh | bash
```

**Force re-download binary and update services:**
```bash
export ANAHITA_DOMAIN=t.example.com
export ANAHITA_FORCE_UPDATE=true

curl -fsSL https://raw.githubusercontent.com/nxdp/anahita/main/install.sh | bash
```

## Services

```bash
# status
systemctl status anahita-slipstream-server
systemctl status anahita-proxy

# logs
journalctl -fu anahita-slipstream-server
journalctl -fu anahita-proxy
```

## Idempotent

Safe to run multiple times. Re-running updates service configs and restarts services. Keys are never regenerated once created.
