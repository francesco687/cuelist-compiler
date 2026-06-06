# Cuelist Compiler — Pi Hub

Receives a show from the iPhone over WebSocket, compiles it with the real
`web/js/compile.js`, and relays the MA3 command sequence as OSC/UDP.

## Run

Requires Node 20+. On Raspberry Pi OS, install via NodeSource so the binary
lands at `/usr/bin/node` (the path the systemd unit expects):

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

Then:

```bash
cd hub
npm install
npm start
```

## Deploy as a service (Pi)

```bash
sudo cp deploy/cuelist-hub.service /etc/systemd/system/
sudo systemctl enable --now cuelist-hub
```

If `node` is not at `/usr/bin/node` (e.g. installed via `nvm`), edit
`ExecStart` in `deploy/cuelist-hub.service` to point at `$(which node)`.

Configure via env:

| Var | Default | Meaning |
|-----|---------|---------|
| `HUB_HOST` | `0.0.0.0` | WS bind host |
| `HUB_PORT` | `9000` | WS port the phone connects to |
| `MA3_HOST` | `127.0.0.1` | grandMA3 IP |
| `MA3_PORT` | `8000` | MA3 OSC input UDP port |
| `MA3_PREFIX` | `gma3` | OSC prefix → address `/<prefix>/cmd` |
| `OSC_INTERVAL_MS` | `20` | throttle between lines |
| `WEB_JS_DIR` | `../web/js` | location of the web compiler modules |

grandMA3: **Menu > Network > MA Network Configuration > OSC** — input UDP `8000`,
prefix `gma3`, **Echo Input = Yes** (required for `/cmd` to dispatch).

> **Echo-loop caveat (same-box onPC):** with Echo Input on, keep that OSC entry's
> **Output destination off the input address** (`127.0.0.1:8000`). If the echo is
> sent back to the input, each received command runs **twice**. A desk on the
> network is unaffected; it only bites when onPC and the hub share `127.0.0.1`.

## Protocol

```
→ { type: "compile-send", project, defaults, selection: "current"|"all" }
← { type: "progress", sent, total } | { type: "done", total } | { type: "error", message }
```

Remote use: reach the Pi over a private tunnel (Tailscale/WireGuard) and point the
phone at the Pi's tunnel address instead of its LAN IP.
