# Internet Hub — control the laptop hub from a phone that isn't on the same WiFi

**Date:** 2026-06-06
**Branch:** `feat/internet-hub` (off `main`)
**Components:** new `relay/` (Fly app) + new `menubar-hub/` (Electron tray app); a small refactor in `hub/`; additive changes in `ios/`

## Purpose

Today the iPhone reaches the laptop hub only on the **same WiFi** (`ws://host:port`).
This adds a path for the phone to drive the desk **over the internet** — on
cellular or any other network — by pairing through a small relay the laptop and
phone both dial *out* to.

It ships as a **stripped-down, hub-only** menubar app: when all you need is "use
the laptop as a hub for the phone," you launch this instead of the full desktop
authoring app. It is kept **separate from `desktop/`** — no coupling to
`desktop/main.js` — while reusing the shared `hub/src/*` compiler/OSC libraries
exactly as `desktop/` already does.

## Topology

```
iPhone (anywhere) ──wss──► cuelist-relay (Fly) ◄──wss── Menubar Hub (laptop @ desk)
   relay mode,                 pairs by                     dials OUT, no public
   pairing code                pairing code                 listener │
                                                                     └─ OSC/UDP ─► grandMA3
```

Both ends dial **out** over `wss://…fly.dev` (port 443). The laptop never needs
port-forwarding or a public listener; the phone needs nothing installed. The
relay matches one laptop and one phone that present the same **pairing code** and
pipes JSON between them — it never touches OSC and never sees the LAN.

## Scope

In scope (v1):

- **`relay/`** — a new Fly app: a stateless WebSocket pairer (a "dumb pipe").
- **`menubar-hub/`** — a new Electron **tray app** with a click-down popover
  showing relay/phone status, the pairing code, MA3 settings, and a styled live
  log of what the phone has sent to the desk. No authoring UI.
- **`hub/` refactor** — extract the per-message logic from `server.js` into a
  transport-agnostic `handleMessage(...)` reused by both the LAN server and the
  new relay client.
- **`ios/`** — a new **relay** connection mode alongside the existing direct
  mode (a toggle in settings), so the phone can connect either way.
- **Relay-only** for this app: the phone always connects through Fly, even when
  next to the laptop.

Explicitly **out of scope** (YAGNI — may come later):

- **Hybrid LAN-direct-with-relay-fallback.** v1 is relay-only; same-WiFi local
  use stays the desktop app's job. (Noted as the most likely v2 follow-up.)
- Multi-operator / multiple phones per room. v1 is single hub + single phone.
- Any authoring UI in the menubar app.
- Accounts, a code registry, or per-user auth beyond the pairing code.
- Signed/notarized installer for the menubar app (run-from-source is fine for
  v1, matching where `desktop/` is today).

## Approach

### Shared core: extract `handleMessage` from `hub/src/server.js`

The compile/OSC/pull logic currently lives inline in `server.js`'s
`wss.on('connection') → ws.on('message')`. Extract it into a transport-agnostic
function so both the existing LAN server and the new relay client drive the same
core:

```js
// hub/src/handle.js (new)
// ctx = { api, sender, config }   reply = (obj) => void   (sends one JSON frame back to the phone)
async function handleMessage(ctx, msg, reply) { /* cmd | compile-send | pull-sequences | ping */ }
```

- `server.js` keeps its `WebSocketServer`, builds `ctx` once (one `api` + one
  `sender`, as today), and calls `handleMessage(ctx, msg, ws-reply)` per message.
  Its existing behavior and contract tests stay green.
- The relay client in `menubar-hub/` builds the same `ctx` and calls
  `handleMessage(ctx, msg, relay-reply)`, where the reply frame is wrapped for
  the relay (see protocol).

This keeps `hub/` the single source of truth for compiling and OSC. The menubar
app adds only a transport.

### The relay (`relay/`)

A single small WebSocket server. Opaque to payloads — it pairs and forwards.

**State:** `Map<roomCode, { hub?: socket, phone?: socket }>`.

**Join handshake** — first frame from any client:

```json
{ "type": "join", "room": "<pairingCode>", "role": "hub" | "phone" }
```

- A socket that does not send a valid `join` within ~5s is closed.
- If the room already holds a socket for that `role`, the new one is rejected
  (`{type:"join-error", message:"role taken"}`) — single hub + single phone.
- On successful join the relay replies `{type:"joined"}` and notifies the peer
  (if present) `{type:"peer", connected:true}`.

**Forwarding** — once joined, **every other frame** is relayed verbatim to the
room's opposite role. The existing protocol passes through unchanged:
`cmd`, `compile-send`, `progress`, `done`, `sent`, `pull-sequences`,
`sequences`, `pull-error`, `error`, `ping`, `pong`.

**Peer lifecycle** — when a socket closes, the relay clears its slot and sends
the peer `{type:"peer", connected:false}`; the room is deleted when empty.

**Security & limits:**

- The **pairing code is the only auth** — it must be high-entropy enough that
  guessing it to reach the desk is impractical (≥ 8 random url-safe chars,
  generated on the laptop).
- Max frame size cap (reject/close on oversize).
- Cap on total concurrent rooms.
- TLS (`wss`) is provided by Fly automatically → satisfies iOS ATS.

**Fly:** single machine, its own app (`cuelist-relay`), independent of Karpatian.
Standard `Dockerfile` + `fly.toml`; one internal port; health check on a plain
HTTP route. (Honors the "one machine per app, never two deploys at once" rule.)

### The menubar hub app (`menubar-hub/`)

Electron, **tray icon + click-down popover** (a small frameless `BrowserWindow`
anchored under the tray icon — native menus can't render a styled scrollable
log). No authoring window.

**Main process:**

1. Load settings (MA3 host/port/prefix, relay URL, pairing code). Generate and
   persist a pairing code on first launch if absent.
2. Build `ctx` (`createCompiler` + `OscSender` from `hub/src/*`).
3. Open an outbound `wss` to the relay; send `join` as `role:"hub"`.
4. On each relayed phone message → `handleMessage(ctx, msg, reply)`, where
   `reply` sends the response frame back over the relay socket. Emit a **log
   event** per relayed command to the renderer via IPC.
5. Reconnect to the relay with capped backoff on drop, re-`join`ing the same room.

**Popover renderer:**

- **Status:** relay (connecting / online / error) + phone-paired (✓ / "waiting
  for phone"), both driven by the socket state and `peer` frames.
- **Pairing code:** shown large, with **Copy** and **Regenerate** buttons.
  Regenerate writes a new code, persists it, and re-`join`s a fresh room (the
  phone must be updated to match).
- **MA3 settings:** host / port / prefix (same fields/semantics as
  `desktop/settings.js`) + relay URL. Saving rebuilds `ctx`/sender and re-joins.
- **Live activity log:** a stylish, scrollable, capped (~200) ring buffer. Each
  phone→desk action is one timestamped, type-colored row, e.g.:
  - `19:42:07  GO+    Exec 101`
  - `19:42:11  PAUSE`
  - `19:42:30  SEND   all → 47 lines ✓`
  - `19:43:02  PULL   12 sequences`
  Errors render in a warning color. The log is derived from the same messages
  `handleMessage` processes, so it reflects exactly what reached the desk.

**Persistence:** settings + pairing code to the app's `userData` dir, mirroring
`desktop/settings.js`.

### iOS changes (`ios/`) — additive

The same phone app is used both with the desktop app on LAN and with this relay
hub, so relay is a **new mode beside** the existing direct mode, not a
replacement.

- **`HubClient`** gains a connection mode:
  - `.direct(host, port)` — today's `ws://host:port`, unchanged.
  - `.relay(url, pairingCode)` — opens `wss://<relay>`, and on open sends
    `{type:"join", room:code, role:"phone"}` **before** anything else.
- After the join handshake, **everything downstream is unchanged** — the relay
  forwards hub replies verbatim, so `HubClient.handle()`, the Live tab, Send, and
  Pull all work as-is.
- Sends are gated on `{type:"peer", connected:true}` (or `joined` + peer
  present): until the laptop is paired the UI shows "waiting for laptop" rather
  than firing commands into a void.
- **Settings UI** (`SettingsView` / `SettingsTabView`): a mode toggle
  (Direct / Relay) revealing either host+port or relay-URL + pairing-code.
- New persisted defaults: `connectionMode`, `relayURL`, `pairingCode`.

## Data flow (relay mode, a live GO+)

1. Phone (Live tab) → `HubClient.sendCommand("Go+")` → `{type:"cmd", line:"Go+"}`
   over `wss` to the relay.
2. Relay forwards the frame verbatim to the room's `hub` socket.
3. Menubar main process → `handleMessage(ctx, {type:"cmd",line:"Go+"}, reply)`
   → `sender.send("Go+")` → OSC `/gma3/cmd` UDP → grandMA3. Emits a log row.
4. `reply({type:"sent", line:"Go+"})` → relay → phone. `HubClient` updates state.

## Error handling

- **Both ends auto-reconnect** to the relay with capped backoff and re-`join`.
  A mid-show relay drop → phone sees `peer:false` ("laptop reconnecting…") then
  recovers.
- **OSC stays fire-and-forget UDP** (unchanged): a wrong MA3 host fails silently
  exactly as today. Relay and OSC are independent layers.
- **Relay restart / Fly deploy:** both ends reconnect; at most the one in-flight
  message is lost — consistent with the existing single-operator, non-serialized
  model.
- **Wrong/typo pairing code:** the two never pair → phone shows "waiting for
  laptop" indefinitely. No silent wrong-room delivery (both must share the exact
  code).
- **Relay hardening:** un-`join`ed sockets dropped after a timeout; oversized
  frames rejected; room count capped.

## Testing

- **`relay/`** — unit tests for the pairing state machine with injected fake
  sockets (no network): matching codes get bridged; mismatched don't; `peer`
  connect/disconnect notifications fire; un-joined socket is dropped; a second
  hub or phone in a full room is rejected; oversized frame rejected.
- **`hub/`** — direct tests for the extracted `handleMessage` (feed
  `cmd`/`compile-send`/`pull-sequences` + a capturing `reply`, assert OSC sends
  and reply frames). Existing `server.js` contract tests stay green (it now
  delegates).
- **`menubar-hub/`** — settings-module unit tests (mirror `desktop/test`); a
  light integration test driving `handleMessage` through a fake relay socket and
  asserting the emitted log events.
- **Manual smoke (acceptance bar):** menubar app on the laptop + the real relay
  deployed to Fly + phone on **cellular** (true off-WiFi) → onPC/desk. Verify
  `Go+`, `PAUSE`, `Send all`, and `Pull`; confirm the popover log shows each.

## Repo layout

```
cuelist-compiler/
├─ hub/                  # existing — gains hub/src/handle.js; server.js delegates
│   └─ src/handle.js     #   NEW transport-agnostic handleMessage
├─ relay/                # NEW — Fly WebSocket pairer (Dockerfile, fly.toml, src, test)
├─ menubar-hub/          # NEW — Electron tray app (main, popover renderer, settings, test)
├─ desktop/              # unchanged — full authoring app (not coupled to the above)
└─ ios/                  # additive — relay connection mode + settings toggle
```

## Open / deferred

- **Folder name** `menubar-hub/` is a working name (alternatives: `relay-hub/`).
- **Pairing code is regenerable** from the popover (assumed yes).
- **Hybrid LAN-direct + relay-fallback** is the most likely v2 follow-up.
- **Signed installer** for the menubar app deferred (run-from-source for v1).

## Smoke results — Phase E PASSED (2026-06-06)

Cellular acceptance smoke run end-to-end and **passed**.

- **Relay deployed:** Fly app `cuelist-relay` (region `ams`, single machine via
  `fly apps create` + `fly deploy --ha=false`; `shared-cpu-1x`/256mb, always-on).
  `GET https://cuelist-relay.fly.dev/healthz` → `ok`. New-hostname DNS took ~30s to
  resolve globally after first deploy.
- **Hub:** menubar app run-from-source on the Mac; **iOS app** built + installed on
  jPhone (2) (`xcrun devicectl`). Phone on **cellular (WiFi off)**.
- **Chain proven:** jPhone → Fly relay (ams) → menubar hub (Mac) → OSC `/gma3/cmd`
  :8000 → grandMA3 onPC. A local UDP capture on `8000` caught valid `/gma3/cmd`
  packets for **GO+ / GO- / PAUSE** and a full **Send-all** (`Store Sequence 165
  Cue 1..4 /Merge /NoConfirmation`). One tap = exactly one frame at the hub.

Two issues surfaced, **neither a transport bug** — both addressed on this branch:

1. **Pairing failed first try** because the 12-char mixed-case base64url code
   (`d4jQVvOab_ZY`, adjacent `QVv`, `_`) is too error-prone to hand-type. Fixed:
   `generatePairingCode` now uses a 9-char unambiguous lowercase alphabet
   (`23456789abcdefghjkmnpqrstuvwxyz`, no `0/1/i/l/o`, no case).
2. **"GO fires twice per tap" was a grandMA3 OSC echo loop**, reproduced with a
   single direct OSC packet (zero phone involvement): `Echo Input = Yes` + the OSC
   row's Output destination pointing back at `127.0.0.1:8000` re-injects the echoed
   command. Fixed at the desk by moving the Output destination off-loopback;
   documented in `hub/README.md` and `menubar-hub/README.md`.

Also tightened the iOS relay-mode error wording (`"set the relay URL"` /
`"enter the pairing code"` instead of the misleading `"set relay URL + pairing
code"`, which actually only fires when the URL is empty).
