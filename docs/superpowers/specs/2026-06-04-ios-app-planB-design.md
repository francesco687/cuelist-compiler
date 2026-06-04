# Cuelist Compiler iOS — Plan B: Native app (M1)

**Date:** 2026-06-04
**Status:** Approved (brainstorming → planning)
**Branch:** `feat/ios-shell` (off `v2`, PRs back into `v2`)
**Milestone:** M1 — Native authoring + Pi-hub send
**Parent design:** `docs/superpowers/specs/2026-06-04-ios-frontend-design.md`
**Supersedes (mines for parts):** `docs/superpowers/plans/2026-06-04-ios-frontend-m1-engine.md`

## Goal

Build the native SwiftUI iPhone app that authors per-song grandMA3 cuelists and
sends them to the console **through the Pi hub** (already shipped + verified on a
real desk, 2026-06-04). The phone authors and persists a show locally and speaks
the hub's WebSocket protocol; it does **not** compile or speak OSC — the hub runs
the real `web/js/compile.js` and relays. This document specifies the iOS app
(Plan B). The hub (Plan A) is complete.

## Scope decisions (locked during brainstorming)

| Question | Decision |
|----------|----------|
| Navigation | **One scroll per song** (web parity): song switcher on top, cues as expand/collapse cards edited inline. Considered & rejected: 3-level drill-down; 2-level + cue sheet. |
| Preset editor | **All 6 pool rows visible** per group block (`name / fade / delay`), web-faithful. Rejected: name-first w/ timing-on-tap; only-filled-pools + add menu. |
| Connect/send | **Persistent connection + status pill**; Send current / Send all in the bottom bar; progress streams inline. Rejected: send-opens-sheet; pill+sheet hybrid. |
| Code structure | **`CuelistCompilerKit` framework** (Models/Store/HubClient, no UI) + thin `CuelistCompiler` app (SwiftUI). Tests target the Kit, no host app. |
| Show storage | **One working show**, autosaved to local JSON (`show.json` schema). No multi-file management, no import/export UI in M1. |
| M1 feature set | Full web-app authoring parity **minus** the deferred list below. Includes: per-pool Defaults editor, copy-actions-from-cue, action color tags, cue position label. |
| Compiler / OSC on phone | **None.** Hub owns both. No Swift `CommandBuilder`, no OSC encoding/transport on iOS. |
| Min iOS | iOS 17+ (`@Observable`). |
| Hub discovery | Manual host:port in Settings (default port `9000`). No mDNS. |

## Architecture

```
   iPhone (native SwiftUI)                         Pi hub (shipped)        grandMA3
  ┌──────────────────────────────┐   WebSocket   ┌──────────────────┐  OSC  ┌──────┐
  │ Views (App target)           │  compile-send │ ws server        │ /gma3 │      │
  │   ↕ @Observable              │ ────────────▶ │  compile-bridge  │ /cmd ▶│ MA3  │
  │ ProjectStore   HubClient     │  ◀ progress   │  (web/js/        │       └──────┘
  │ Models + Migration (Kit)     │  ◀ done/error │   compile.js,vm) │
  └──────────────────────────────┘               │  osc-send        │
   local JSON: show.json, defaults.json           └──────────────────┘
```

### Targets

- **`CuelistCompilerKit`** (framework): `Models/`, `Migration`, `ProjectStore`,
  `HubClient`, `HubConnection`. `ENABLE_TESTABILITY: YES`. No UIKit/SwiftUI views.
- **`CuelistCompiler`** (app): SwiftUI views only; depends on Kit. Portrait iPhone.
- **`CuelistCompilerKitTests`** (unit-test bundle): `@testable import
  CuelistCompilerKit`, no host app. Bundles `examples/SONG_1.json` as a resource.
- Built with **xcodegen** (`ios/project.yml`), iOS 17, Swift 5.9,
  `DEVELOPMENT_TEAM UWJSLFQDGL`, `CODE_SIGN_STYLE Automatic`. The scaffold
  (Task 1 of the superseded engine plan) carries over verbatim.

### Data model (Kit/Models) — carried from the superseded plan

`Codable` structs serializing to the **exact `show.json` schema**:

- `Pool` (enum: color, dimmer, position, gobo, beam, focus; `.number` = MA3 pool index).
- `StoreMode` (overwrite / merge).
- `Preset { name, fade, delay }` (Strings — fidelity matters to the hub compiler).
- `Action { group, color, presets: [Pool: Preset] }` — `presets` encodes as a
  6-key object; `color` is UI-only metadata (not used by the compiler).
- `Cue { n: Double, name, fade, delay, position, collapsed, actions: [Action] }` —
  `Cue.position` is a UI-only free-text label and is **distinct from** the
  `Pool.position` preset pool (the schema reuses the word for two unrelated things;
  do not conflate them in code).
- `Song { id, name, sequence: Int, cues, audioFileName }`.
- `Project { songs, activeSongId, storeMode }`.
- `Defaults { values: [Pool: Preset] }` (only fade/delay used), stored separately.
- `IDGen` (web `genId` analog) and `Migration` (old single-song / bare-string-preset
  → current shape; mirrors web `migrateState`). Migration is retained for forward
  compatibility (e.g. a future import path); it also tolerates loading an older
  locally-saved file.

**Dropped from the superseded plan:** `CommandBuilder`, `JSNumber`, `OSCEncoding`,
`OSCTransport`/`DirectUDPTransport`. The compiler lives once, in JS, on the hub.

### `ProjectStore` (`@Observable`, Kit)

Holds the in-memory `Project` + `Defaults`. Responsibilities:

- **Persistence:** load on init from `Documents/show.json` + `Documents/defaults.json`;
  autosave (debounced) on any change. Malformed/missing file → fresh empty project
  (one empty song) / empty defaults. A loaded file of an older shape is upgraded via
  `Migration`.
- **Mutations (mirror web `state.js`):** add/remove song, set active song, add cue,
  remove cue, reorder/sort cues by `n`, toggle collapsed, add/remove group block
  (never drop to zero blocks — re-seed an empty one, as web does), edit any field,
  **copy a cue's actions into another cue** in the same song.
- `activeSong` accessor; cue summary helper for collapsed rows.

### `HubClient` (`@Observable`, Kit) + `HubConnection` (protocol)

- `HubConnection` protocol abstracts the socket (connect / send text / receive
  stream / close). Production conformer wraps `URLSessionWebSocketTask`. Tests use a
  mock that emits canned frames.
- **Settings:** `host`, `port` (default `9000`) in `UserDefaults`.
- **State:** `enum ConnectionState { offline, connecting, online, error(String) }`
  drives the pill. Auto-connect to the saved hub on launch; tapping the pill
  (re)connects. Connection failures surface as `.error`, never crash.
- **Send:** `send(selection: .current | .all)` serializes
  `{ type:"compile-send", project, defaults, selection }` and streams the hub's
  `progress {sent,total}` / `done {total}` / `error {message}` into observable
  published fields (`progress`, `lastResult`) for inline UI. Matches the protocol
  verified end-to-end on the desk 2026-06-04.

### UI (App target, SwiftUI)

- **Root** `NavigationStack` → song-editor screen.
- **Top bar:** song switcher `Menu` (list songs + "Manage songs…" → add/remove),
  song name + sequence fields, **hub status pill** (color-coded; tap → reconnect),
  ⚙ Settings, Defaults button.
- **Cue list:** collapsible cue cards sorted by `n`.
  - *Collapsed:* number · name · summary (`position · N groups · fade · delay`).
  - *Expanded:* copy-from-cue control → one or more **group blocks**, each = group
    name field + **color swatch** (popover) + **6 pool rows** (`name / fade / delay`,
    placeholder = Defaults) → "+ Add Group block" → cue fade/delay row.
  - "+ Add Cue" at the bottom.
- **Bottom bar:** store-mode picker (Overwrite/Merge), **Send current → MA**,
  **Send all → MA** (disabled when offline), inline progress (`12/17 → ✅` / error).
- **Settings sheet:** hub host + port.
- **Defaults screen:** per-pool fade/delay (the values used when a preset's own
  fade/delay is blank — they change what the desk receives).
- **Color popover:** swatch palette for a group block.

## Protocol (phone → hub) — already verified

```
→ { type:"compile-send", project:{songs,activeSongId,storeMode}, defaults,
    selection:"current"|"all" }
← { type:"progress", sent:int, total:int }
← { type:"done", total:int }
← { type:"error", message:string }
```

`selection:"current"` = active song only; `"all"` = every song with cues. The
hub also accepts legacy `{type:"cmd",line}` / `{type:"ping"}`, which the app does
not need.

## Error handling

- Hub offline → red pill; Send shows "hub offline — tap to connect", buttons disabled.
- Send error → inline red line carrying the hub's `message`.
- Persistence write failure → non-fatal banner; in-memory state preserved.
- Corrupt/old saved file on launch → `Migration` upgrade if recognizable, else fresh
  empty project. Never crash on bad input.

## Testing

- **Kit unit tests:**
  - Model codec — presets encode as a 6-key object; new-format round-trip.
  - Migration — `examples/SONG_1.json` (old format, bare-string presets) → 1 song,
    2 cues, correct scalars and preset upgrades.
  - `ProjectStore` — mutations (add/remove/copy/reorder, never-zero-blocks invariant)
    and autosave→reload round-trip via a temp Documents dir.
  - `HubClient` — state machine + message encoding/decoding against a **mock
    `HubConnection`** feeding canned `progress`/`done`/`error` frames; verifies the
    emitted `compile-send` JSON and the observable progress/result transitions.
- **No on-iOS compile-parity tests** — the hub is the single compiler; its golden
  fixture (`examples/SONG_1.cmdlines.txt`) already guards the command contract.
- **Manual device smoke:** author on the phone → hub (Pi or Mac) → grandMA3 stores
  the cues (the loop proven by hand on the real desk, 2026-06-04).

## Out of scope (M1 non-goals)

On-phone compiling or OSC · moods library · pool picker / name autocomplete · audio
waveform · CSV (CuePoints) import · `show.json` import/export UI · multi-show file
management · mDNS hub discovery · hub auth/token · iCloud sync · iPad layout · live
MA3 feedback (send-only).

## Plan dependency

Depends on Plan A (hub) — **done and hardware-verified**. No `web/` or `proxy/`
changes. The implementation plan (next step) carries the superseded engine plan's
scaffold + models + migration + store tasks, drops its compiler/OSC tasks, and adds
`HubClient` + the SwiftUI authoring UI.
