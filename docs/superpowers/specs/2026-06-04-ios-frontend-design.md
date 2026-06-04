# Cuelist Compiler — iOS frontend design

**Date:** 2026-06-04
**Status:** Approved (brainstorming → planning)
**Branch:** `feat/ios-shell` (off `v2`, PRs back into `v2`)
**Milestone:** M1 — Native authoring + Pi-hub send

## Goal

A native SwiftUI iPhone app that authors per-song grandMA3 cuelists and sends them
to the console **through a Raspberry Pi hub**. The phone is the authoring front-end;
the Pi runs the *actual* `web/js/compile.js` to build the MA3 command sequence and
relays it as OSC. This keeps **one compiler** (the existing JS) — no Swift port, no
contract duplication — and gives a centralized brain that also enables remote
programming from off-site.

The full authoring port ships in milestones. **This document specifies Milestone 1.**

## Decisions locked during brainstorming

| Question | Decision |
|----------|----------|
| App role | Native authoring front-end (full port, staged) |
| Send path | **Pi hub compiles + relays** (phone → Pi → MA3). Considered & rejected: on-device JavaScriptCore direct-to-MA3 (rejected: wanted centralized/remote-capable), native Swift compile + direct UDP (rejected: duplicates compiler) |
| Compiler | Reuse **`web/js/compile.js`** verbatim, run in Node on the Pi via a VM bridge. No Swift port. |
| Hub protocol | WebSocket, JSON messages. Stateless hub (full show sent per request). |
| `web/` changes | **None.** Hub is additive; existing web app + `proxy/` untouched. |
| Show storage (phone) | Local-only on phone (`show.json` schema); import/export later |
| Hub/console discovery | Manual IP config (Pi LAN IP or tailnet IP); no mDNS in M1 |
| Audio | Deferred |
| Min iOS | iOS 17+ (`@Observable`) |
| Phone persistence | Plain Codable JSON files (no SwiftData) |

### Why the Pi hub (and why it reuses compile.js)

A browser cannot open a UDP socket, which is the *only* reason the web app needs
`proxy/ws2osc.js`. The MA3 command sequence is defined once, in `web/js/compile.js`.
Rather than re-implement that contract in Swift (risk: two compilers drifting), the
**Pi runs the real `compile.js` in a Node VM** with browser shims — the same
technique the golden-fixture generator uses (`ios/tools/gen-golden.js`). The phone
sends a show; the Pi compiles + relays. The console setup (OSC input UDP, prefix
`gma3`) is unchanged. Remote programming works by pointing the phone at the Pi's
tunnel (Tailscale/WireGuard) address instead of its LAN IP.

Trade-off accepted: the Pi must be running and reachable to send anything, even in
the venue. Chosen deliberately for the centralized/remote benefits.

## Architecture

```
   iPhone (native SwiftUI)                 Raspberry Pi (Node hub)            grandMA3
  ┌────────────────────────┐   WebSocket  ┌──────────────────────────┐  OSC/UDP ┌──────┐
  │ authoring UI           │  compile-    │ ws server                │  /gma3/  │      │
  │ ProjectStore (show.json│  send ───────▶ compile-bridge           │  cmd ───▶│ MA3  │
  │ schema, local JSON)    │  ◀─ progress │  (runs web/js/compile.js │          │      │
  │ HubClient              │  ◀─ done/err │   in a Node VM)           │          └──────┘
  └────────────────────────┘             │ osc-send (port ws2osc.js) │
                                          └──────────────────────────┘
        web/ + proxy/  ── unchanged, additive ──┘ (may target the hub later)
```

### Component 1 — iOS app (native, this repo's `ios/`)

- **Authoring UI** (SwiftUI, `NavigationStack`): songs → cues → actions → group +
  6 preset pools (name/fade/delay), per-pool defaults, Overwrite/Merge.
- **Data model**: `Codable` structs serializing to the **exact `show.json` schema**
  (`Project { songs, activeSongId, storeMode }`, `Song`, `Cue`, `Action`,
  `Preset`, `Pool`, `Defaults`, `StoreMode`) + `Migration` (old→current). Unchanged
  from the prior design; reused.
- **ProjectStore** (`@Observable`): in-memory show + defaults, persisted as JSON in
  the Documents dir (mirrors web `localStorage`). Reused.
- **HubClient**: connects to the hub over WebSocket; on "send current/all" sends a
  `compile-send` with the project + defaults + selection; surfaces streamed
  `progress`/`done`/`error`. Connection settings (hub host/port) in `UserDefaults`.
- The phone does **not** compile and does **not** speak OSC.

### Component 2 — Pi hub (`hub/`, new Node service)

- **WebSocket server** (binds `0.0.0.0:<port>`).
- **compile-bridge**: loads `web/js/{constants,util,state,compile}.js` once into a
  Node `vm` context with browser shims (`window`, `localStorage`, `document`, etc.),
  exposing `migrateState` + `buildCmdLines`. Given a project, returns the exact OSC
  command lines. **Reuses `web/js/compile.js` verbatim — zero `web/` changes.**
- **osc-send**: ports `proxy/ws2osc.js`'s OSC encoder + UDP socket; sends each line
  to MA3 `host:port` address `/<prefix>/cmd`, throttled (20 ms), streaming progress.
- **Config**: MA3 host/port/prefix + listen port via env/CLI. Runs as a service
  (systemd / pm2) on the Pi.

### Protocol (phone ↔ hub, JSON over WebSocket)

```
→ { type: "compile-send", project: { songs, activeSongId, storeMode },
    defaults, selection: "current" | "all" }
← { type: "progress", sent: <int>, total: <int> }
← { type: "done", total: <int> }
← { type: "error", message: <string> }
```

The legacy `{ type: "cmd", line }` message stays supported so the web app could use
the same hub later. `selection: "current"` compiles only the active song
(`activeSongId`); `"all"` compiles every song with cues.

## Contract integrity

`shared/ma3-command-spec.md` + `web/js/compile.js` remain the single source of truth.
The hub runs that exact file, so the sequence cannot diverge. The existing golden
fixture `examples/SONG_1.cmdlines.txt` (generated from the JS reference) now guards
the **hub**: a hub test feeds `SONG_1.json` via `compile-send` and asserts the OSC
datagrams it emits decode to the golden lines.

## Testing

- **Hub:** unit-test `compile-bridge` (project → expected lines vs golden); an
  integration test that runs the ws server, sends `compile-send` with `SONG_1.json`,
  captures datagrams on a fake UDP listener, and asserts they match
  `SONG_1.cmdlines.txt`; protocol error cases.
- **iOS:** model codec + migration tests (as before); `HubClient` against a stub
  WebSocket server (progress/done/error handling); manual device smoke (author on
  phone → hub on Pi → MA3 onPC stores cues).

## Milestones / plans

- **Plan A — Pi hub** (Node): compile-bridge + osc-send + ws protocol. Golden-guarded,
  no MA3 needed for tests. *Write and build first* (defines the protocol).
- **Plan B — iOS app** (native): models + migration + store (carried over from the
  superseded engine plan) + authoring UI + `HubClient`. Depends on Plan A's protocol.

## Superseded

`docs/superpowers/plans/2026-06-04-ios-frontend-m1-engine.md` (the native Swift
compiler + direct-UDP plan) is **superseded** by this revision. Carried forward into
Plan B: xcodegen scaffold, Codable models, migration, ProjectStore, the golden
fixture + `gen-golden.js`. Dropped: Swift `CommandBuilder`, Swift OSC
encoding/transport (the compiler now lives once, in JS, on the hub).

## Deferred (later milestones)

Moods library · pool-name autocomplete · CSV import · audio · `show.json`
import/export UI · web app pointing at the hub · mDNS hub discovery · auth/token on
the hub · iCloud sync · iPad layout.

## Out of scope (M1 non-goals)

No live MA3 feedback (send-only). No multi-user collaboration. No changes to `web/`
or `proxy/`. No on-phone compiling or OSC.
