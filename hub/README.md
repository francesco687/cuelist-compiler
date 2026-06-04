# Cuelist Compiler — Pi Hub

Receives a show from the iPhone over WebSocket, compiles it with the real
`web/js/compile.js`, and relays the MA3 command sequence as OSC/UDP.

## Run

```bash
cd hub
npm install
npm start
```

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

## Protocol

```
→ { type: "compile-send", project, defaults, selection: "current"|"all" }
← { type: "progress", sent, total } | { type: "done", total } | { type: "error", message }
```

Remote use: reach the Pi over a private tunnel (Tailscale/WireGuard) and point the
phone at the Pi's tunnel address instead of its LAN IP.
