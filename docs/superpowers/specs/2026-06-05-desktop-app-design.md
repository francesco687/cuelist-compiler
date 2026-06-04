# Desktop App — Design

**Date:** 2026-06-05
**Branch:** `feat/desktop-app` (off `v2`)
**Status:** Approved design, pre-plan

## Problem

The web authoring app (`web/`) cannot send UDP OSC directly from a browser, so
live send today requires either:

- a separate Node `WebSocket→OSC` bridge (`proxy/`) running alongside the browser, or
- a Raspberry Pi hub (`hub/`) that the iPhone frontend connects to, which runs
  `web/js/compile.js` and relays OSC/UDP to the desk.

Operators need to run the tool on **their own personal laptops, which may be macOS
or Windows**. Maintaining a Pi per setup, plus a manual Node/proxy dance, is
friction we want to remove. We also do not want to build and maintain two native
apps.

## Goal

One **cross-platform desktop app** that operators install and double-click. It:

1. Hosts the full authoring UI (the existing `web/` app — author cues).
2. Sends OSC/UDP **directly** to the grandMA3 desk (no browser limitation, no
   separate proxy).
3. **Absorbs the Pi**: embeds the `hub/` WebSocket server so the iPhone connects
   to the laptop instead of a Pi. The Pi is deleted.

The iPhone becomes a **complementary companion** to the laptop "main hub."

## Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| Build tech | **Electron** | `hub/` and `compile.js` are already Node/JS; reuse ~100% of code. Tauri would force a Rust rewrite of the hub server. |
| Scope | **Author + send** | Operators build shows on their own machines. |
| Pi | **Deleted** | The Electron main process performs all three Pi roles itself. |
| iPhone | **Kept as companion** | Dials the laptop's LAN IP instead of the Pi. No iPhone code change. |
| v1 contents | **Includes the embedded hub server** | Full Pi replacement on day one. |
| iPhone↔Mac link | **Mac broadcasts its own WiFi hotspot** | Self-contained; no dependence on venue WiFi. |
| `proxy/` + browser mode | **Kept as dev/fallback path** | The transport abstraction makes it nearly free; keeps `web/` runnable in a plain browser. |

## Architecture

### Topology

```
┌─────────────────── Operator laptop (Windows / macOS) ──────────────────┐
│  Electron app                                                          │
│                                                                        │
│   Renderer (window)            Main process (Node)                     │
│   = existing web/ app  ─IPC→   • compile.js (required directly)        │
│                                • UDP sender (dgram)        ──UDP──►  grandMA3 desk
│                                • embedded hub WS server :9000 ◄──WS──  iPhone (companion)
└────────────────────────────────────────────────────────────────────────┘
        ▲ Ethernet (cat5 / USB adapter) → desk subnet 10.0.0.x
        ▲ WiFi (Mac-broadcast hotspot)  → iPhone control link 192.168.2.x
```

The Mac is **multi-homed**: Ethernet to the desk, WiFi hotspot to the iPhone. The
app is an **application-level relay** — the iPhone never receives an IP on the desk
network and no IP forwarding is enabled. The iPhone talks only to the hub server;
the hub holds the desk connection and emits OSC out the Ethernet interface
(automatic routing: UDP to `10.0.0.2` leaves via the matching subnet).

### Module layout — new `desktop/`

- `desktop/main.js` — Electron main process. Creates the window, starts the
  embedded hub server, owns the UDP socket, runs `compile.js`.
- `desktop/preload.js` — `contextBridge` exposing a minimal `cuelist` API to the
  page: `sendCurrent()`, `sendAll()`, `compileOnly()`, plus status/progress events.
- **Reused, not forked:**
  - `web/js/compile.js` — the compiler. `require`d directly in main (no `vm`
    sandbox needed — it is first-party code).
  - `hub/src/*` — the WebSocket server + OSC relay, imported as a **library**.
  - `dgram` UDP send logic from `proxy/ws2osc.js`.

### The one new abstraction: a send transport

The renderer's send path goes through `transport.send(...)` instead of a hard-wired
WebSocket. Two implementations selected at runtime:

- **Electron transport** → IPC → main → `compile.js` → UDP → desk. (normal path)
- **Browser transport** → existing WebSocket proxy. (dev/fallback when `web/` runs
  in a plain browser)

`compile.js` and the authoring UI are identical in both. This is the only
meaningful new renderer code.

## Data flows

Both flows funnel through the **same `compile.js`** and the **same UDP socket**, so
a cue fired from the laptop and a cue fired from the phone behave identically.

1. **Local author → send:** renderer → IPC → `compile.js` → UDP → desk.
2. **iPhone companion:** phone → WS `compile-send` → embedded hub → `compile.js` →
   UDP → desk; `progress`/`done`/`error` stream back to the phone, and a small
   "📱 phone connected / sending…" indicator surfaces in the desktop window.

## Shared contracts (frozen — coordinate with the iOS session)

These already exist today (the Pi relies on them); the desktop app preserves them
byte-for-byte. **Neither the desktop work nor the iOS work may change them without
syncing the other session.**

1. **Hub WebSocket protocol** — `{type:"compile-send", project, defaults, selection}`
   → `progress` / `done` / `error`, on port **9000**. (See `hub/README.md`,
   `ios/Sources/Kit/Hub/HubMessages.swift`.)
2. **Project-JSON shape** — the iPhone's Swift `Project` is `Encodable`; the
   embedded `compile.js` parses it exactly as the Pi does now.

The iPhone needs **no code change**: `HubClient.swift` already builds
`ws://<host>:<port>` from a user-configurable host/port (default 9000) stored in
UserDefaults. Switching from Pi to laptop is an operator typing the laptop's WiFi
IP into the existing host field.

## Networking (v1 assumption: Mac-broadcast hotspot)

- The Mac runs **macOS Internet Sharing** (Windows: **Mobile Hotspot**), sharing
  *from the Ethernet interface to WiFi*. No internet on the desk link is required;
  macOS still brings up the AP and assigns the iPhone a `192.168.2.x` address.
- The iPhone reaches the hub at the Mac's AP IP (`~192.168.2.1`).
- The hub server binds `0.0.0.0`, so it is reachable on the WiFi-side IP.
- **On-site check (one-time):** confirm the WiFi AP and the static
  Ethernet-to-desk link coexist (different subnets — normally fine).

## Settings & status

In-app settings panel (replaces the README's manual MA3 setup steps): MA3 host /
UDP port / prefix, throttle interval (`OSC_INTERVAL_MS`), embedded-hub on/off +
port (default 9000). Status row: **desk reachable?** and **phone connected?**.

First launch triggers an OS firewall prompt (macOS + Windows) because the app now
*listens* for the phone — documented as expected.

## Error handling

Reuse the hub's existing error contract:

- UDP send failure → surfaced in UI + `error` message to the phone.
- Hub port already in use → clear message; let the user pick another port.
- Malformed project from phone → existing hub validation message.
- Desk unreachable → status goes red; send blocked with a hint.

## Testing

- `hub/`'s existing **12 tests stay green** (it is now a library, not a Pi daemon).
- New: unit tests for the transport abstraction (Electron vs browser selection)
  and the preload bridge surface.
- `compile.js` unchanged → its `examples/` regression anchor still applies.
- Smoke: MA3 onPC first, then the real desk (same loop already used for the Pi
  hardware smoke).

## What gets deleted / kept

- **Deleted:** Pi deployment — `hub/deploy/cuelist-hub.service`, Pi-specific README
  run steps.
- **Kept as library:** `hub/src/*` (now imported by `desktop/`).
- **Kept as dev/fallback:** `proxy/` + `web/` browser mode (via the browser
  transport).

## Distribution

- `electron-builder` → macOS `.dmg`/`.app` and Windows `.exe` (NSIS).
- **macOS:** signed + notarized via the existing Apple team (`UWJSLFQDGL`).
- **Windows:** **v1 ships unsigned-with-instructions.** Without a code-signing
  cert, operators see a SmartScreen "unknown publisher" warning (clickable
  through). A Windows cert is a post-v1 purchase decision.

## v1 scope (YAGNI line)

**In:** Electron app (author + send), embedded hub server, cross-platform
installers (macOS `.dmg`, Windows `.exe`), settings panel, status indicators.

**Deferred:** auto-update; **Bonjour/mDNS** hub discovery (so the iPhone
auto-finds the Mac and skips typing the IP); in-app phone↔laptop project sync;
multi-desk profiles; Windows code-signing cert.

## Open items for spec review

- Confirm: keep `proxy/` as the dev fallback (current plan) vs. delete it and make
  the desktop app the only live-send path.
- Confirm: Windows unsigned-for-v1 is acceptable.
