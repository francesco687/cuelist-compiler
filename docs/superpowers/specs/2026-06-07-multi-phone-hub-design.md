# Multiple iPhones → one Hub (relay)

**Date:** 2026-06-07
**Status:** Design approved
**Scope:** Fly relay transport only (`cuelist-relay.fly.dev` + `menubar-hub` + iOS `HubClient`). The LAN hub (`hub/src/server.js`, ws://0.0.0.0:9000) is out of scope.

## Problem

Today the relay pairing is **one room = one hub + one phone**. `relay/src/rooms.js` keys each room as `{ hub, phone }`; a second phone joining the same code is rejected with `role taken`, and `forward()` simply sends to the opposite role. Multiple operators (Matteo, Francesco, …) cannot drive the same desk through one hub.

Two secondary problems surfaced during design:

1. **No attribution.** The hub log shows *what* was sent, never *who* sent it, and there is no view of who is currently connected.
2. **Pairing friction / lock-out.** If the Fly relay resets (in-memory rooms are lost) or a phone drops, the **phone does not auto-reconnect** (`HubClient` goes `.offline` and waits for a manual tap), so an operator away from the desk can get stuck out. Worse, the hub **regenerates its pairing code on every launch until a setting is first saved** (`main.js` calls `settings.load()` on first run but never persists the generated code), silently locking out previously-paired phones.

## Decisions (locked)

- **Transport:** Relay only.
- **Room model:** All phones share one pairing code = one room; hub fans out to all phones.
- **Concurrency:** Free-for-all in arrival order (matches the hub processing one frame at a time). No locking, no command echo between phones. Exception: `compile-send` is serialized so a whole-show push stays atomic (see §6).
- **Awareness:** Both sides see a roster. The hub lists connected operators; each phone sees the other operators. Each log entry is attributed to its operator.
- **Identity:** Zero-config — phones send `UIDevice.current.name` ("Matteo's iPhone") as the join `name`. No settings field.
- **Pairing UX:** Editable, memorable, persistent code (no QR). Phone auto-reconnects with backoff.

## Approach (chosen: relay envelopes with a connection-id)

Every hub reply is a **request/response** bound to one phone: `pong` (per-phone latency), `progress`/`done` (the phone that hit compile), `sequences` (the phone that pulled), `sent` (the cmd's originator). These must **not** be broadcast — a stray `pong` corrupts another phone's latency calc and a stray `sequences` payload could clobber another phone's state. So the relay routes each reply back to its originating phone via a connection-id envelope. App-level frames stay opaque inside the envelope, so iOS keeps sending/receiving plain frames.

Rejected alternatives: (B) broadcast every reply and dedupe on the phone via a request token — pushes routing into every client, wastes bandwidth, heavier iOS; (C) per-phone rooms with the hub opening N relay sockets — more moving parts on the hub, awkward roster.

## Components

### 1. Relay — `relay/src/rooms.js`, `relay/src/server.js`

- **Room shape:** `{ hub: socket|null, phones: Map<cid, {socket, name}> }`.
- **cid:** monotonic per-relay-process counter rendered as `p1`, `p2`, … Unique across the process; only used for routing and roster identity within a room.
- **Phone join** `{type:'join', room, role:'phone', name}`:
  - Assign a cid, store `{socket, name}` (missing/blank `name` → `"iPhone"`).
  - Reply `{type:'joined', cid}` to the joining phone.
  - Reject with `{type:'join-error', message:'room full'}` (then close) if `phones.size >= maxPhones` (default **8**).
  - Broadcast roster (see below).
- **Hub join** `{type:'join', room, role:'hub'}`: unchanged single-hub rule — a second hub gets `join-error: role taken`. On join, broadcast roster. Reply `{type:'joined'}` (no cid).
- **Forward phone → hub:** wrap as `{type:'from-phone', cid, name, frame:<rawText>}` and send to `room.hub` (drop if no hub yet).
- **Forward hub → phone:** the hub sends `{type:'to-phone', cid, frame:<jsonString>}`. The relay looks up `cid`, and sends the **inner `frame` only** (plain) to that phone's socket. Drop silently if the cid is gone.
  - **Legacy fallback:** if the hub sends an un-enveloped frame (old hub with no `to-phone` wrapper), broadcast it to all phones (graceful degradation during rollout).
- **Roster broadcast** on every join/leave:
  - to the hub: `{type:'roster', phones:[{cid,name}]}`
  - to each phone: `{type:'roster', hub:<bool>, phones:[{cid,name}]}` — `hub` is the phone's online signal; `phones` is the full operator list (recipient finds itself by its own cid from `joined`).
- **Leave:** remove the socket from `phones` (or clear `hub`); rebroadcast roster; delete the room when both `hub` is null and `phones` is empty.
- Existing limits unchanged: `maxRooms` 200, `MAX_FRAME` 256 KB, heartbeat 25 s, join timeout 5 s.

### 2. menubar-hub — `menubar-hub/src/relay-client.js`

- **On `from-phone`:** extract `cid`, `name`, parse `frame`; build a per-frame reply closure that wraps each outgoing object as `{type:'to-phone', cid, frame: JSON.stringify(obj)}` over the single relay socket; call `core.handleMessage(ctx, frame, reply)`.
- **Attribution:** the resulting log entry includes the operator `name`, i.e. `onLog({ ...out, name, at })`, so the UI can show "Matteo → Go+".
- **On `roster`:** new hook `hooks.onRoster(phones)`; the menubar UI renders the connected-operators list.
- The single shared `ctx` (one VM compiler + one `OscSender` UDP socket) continues to serve all phones — sharing the UDP-to-desk sender is correct.
- `onPeer` is superseded by roster; the hub's "phone connected" status text is derived from `phones.length > 0`.

### 3. menubar-hub UI — `menubar-hub/main.js` + renderer

- Surface the roster (connected operators) and per-line attribution in the popover/log.
- Wire the new `onRoster` hook through to the renderer alongside the existing state/log channels.

### 4. iOS — `ios/Sources/Kit/Hub/HubMessages.swift`, `HubClient.swift`

- **`OutgoingMessage.join`** gains a `name` field; the app passes `UIDevice.current.name` (UIKit import in the app layer; `HubClient` takes the name as a parameter to keep Kit UI-framework-free where practical).
- **`IncomingMessage`:** add
  - `roster(hub: Bool, phones: [Operator])`
  - `joined(cid: String?)` (cid optional; hub-side `joined` has none)
  - where `Operator` is `{ cid: String, name: String }`.
  - Legacy `peer` decoding may be retained as a harmless no-op; the relay no longer emits it.
- **`HubClient`:**
  - Store own `cid` from `joined` to mark "self" in the roster.
  - `state` is `.online` iff the latest `roster.hub == true` (relay mode); `.connecting` while joined but hub absent.
  - New observable `roster: [Operator]` for the UI.
  - **Auto-reconnect:** on `.closed` in relay mode, schedule a reconnect with exponential backoff (1 s → 15 s, mirroring `relay-client.js`). Cancel the pending reconnect on an explicit user disconnect or a `join-error` (bad/full code) so we don't hammer a rejected room.

### 5. iOS UI — roster view

- A small "Connected: Matteo, Francesco" element on the Live/Settings surface, bound to `HubClient.roster`, self distinguished.

### 6. Concurrency safety — `hub/src/handle.js`

- Add a per-context async lock (a promise chain on `ctx`) around the `compile-send` send loop so two simultaneous whole-show pushes serialize instead of interleaving OSC lines on the shared sender. Single `cmd`/GO frames remain free-for-all (unlocked).

### 7. Pairing — easy to set + persistent

- **Hub (`settings.js`, `main.js`):**
  - Allow an **editable custom code**: lowercase letters + digits, min length 6. Keep `generatePairingCode()` as the default. Relax `validate()` (currently requires length ≥ 8) to accept custom codes ≥ 6 of `[a-z0-9]`.
  - **Fix first-run regeneration:** on `app.whenReady`, if no `settings.json` exists, immediately `save()` the defaults so the generated code is persisted once and never silently changes across launches.
  - Show the code prominently in the popover; keep the existing `hub:regenCode` action for deliberate rotation.
- **iOS:** code already persists in UserDefaults (`hubPairingCode`); auto-reconnect (§4) reuses it so a relay reset recovers hands-free. Removing the `role taken` rejection for phones eliminates another lock-out path.

## Data flow (relay mode, two phones)

1. Matteo's phone joins `{join, room:CODE, role:'phone', name:"Matteo's iPhone"}` → relay assigns `p1`, replies `{joined, cid:'p1'}`, broadcasts roster.
2. Francesco's phone joins → `p2`, roster rebroadcast to hub + p1 + p2.
3. Matteo hits Go+ → phone sends `{cmd, line:"Go+"}` → relay wraps `{from-phone, cid:'p1', name:"Matteo's iPhone", frame:'{"cmd"…}'}` → hub.
4. Hub fires OSC, replies `{sent, line:"Go+"}` via closure → `{to-phone, cid:'p1', frame:'{"sent"…}'}` → relay → unwraps → only p1's socket gets `{sent…}`. Hub log: "Matteo's iPhone → Go+".
5. Francesco pulls sequences → routed `p2`-only; Matteo sees nothing.
6. Fly relay restarts → both phones' sockets close → hub auto-reconnects (existing) and both phones auto-reconnect with backoff using the persisted code → room re-forms, roster rebuilt. No manual action.

## Error handling

- Reply to a vanished cid: dropped silently (phone will have reconnected with a new cid).
- `room full` (> maxPhones): phone gets `join-error`, surfaces the reason, does **not** auto-retry.
- Old hub (no `to-phone`): relay broadcast fallback keeps a single-phone path working mid-rollout.
- Old phone (no `name`): roster shows `"iPhone"`.

## Rollout

Flag-day across three artifacts deployed together: **relay** (Fly deploy), **Saetta Hub** (signed/notarized DMG), **iOS** (device install). Tolerant fallbacks (legacy broadcast, default name) soften the transition. After rollout, rotate the exposed notary app-specific password (separate housekeeping item).

## Testing

- **Relay `rooms`:** multi-phone join assigns distinct cids; `room full` past cap; roster contents + hub flag on join/leave; `from-phone` wrapping; `to-phone` routing to the right cid only; legacy un-enveloped broadcast; room GC when empty.
- **relay-client:** `from-phone` unwrap → core called with inner frame; reply wrapped as `to-phone` with cid; log entry carries `name`; `onRoster` fires.
- **Kit (`HubClient`/messages):** `join` encodes `name`; `roster`/`joined(cid)` decode; `state` derived from `roster.hub`; self-identification by cid; auto-reconnect backoff schedule (and cancel on manual disconnect / join-error).
- **hub `handle`:** concurrent `compile-send` serialized (no interleaved lines); single `cmd` unaffected.
- **settings:** custom code validation (accept `[a-z0-9]{6,}`, reject shorter/invalid); first-run save persists the generated code (stable across reloads).

## Out of scope (YAGNI)

- LAN hub multi-phone.
- QR pairing / camera.
- Command echo / "X fired GO" awareness between phones.
- Per-operator command locking, queueing, or driver hand-off.
- Custom operator names beyond the device name.
