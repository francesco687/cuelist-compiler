# Cuelist Compiler — iOS frontend design

**Date:** 2026-06-04
**Status:** Approved (brainstorming → planning)
**Branch:** `feat/ios-shell` (off `v2`, PRs back into `v2`)
**Milestone:** M1 — Core authoring + send

## Goal

A native SwiftUI iPhone app that is, over time, a **full authoring port** of the
web Cuelist Compiler: author per-song grandMA3 cuelists and ship them as a `.lua`
plugin or live over OSC. It is the `ios/` frontend in the monorepo and implements
the same `shared/ma3-command-spec.md` contract the web app does.

The full port ships in milestones. **This document specifies Milestone 1: Core
authoring + send.** Everything else is on the roadmap (see Deferred).

## Decisions locked during brainstorming

| Question | Decision |
|----------|----------|
| App role | Full authoring port (staged into milestones) |
| OSC transport | **Pluggable**; ship Direct-UDP first, Relay (Pi/proxy) later |
| Show storage (v1) | **Local-only on phone**; add `show.json` import/export later |
| Audio | Deferred to a later milestone |
| M1 scope | Core authoring + send (no moods, pools-autocomplete, CSV, audio) |
| Min OS | iOS 17+ (for `@Observable`) |
| Persistence | Plain Codable JSON files (no SwiftData in M1) |

### Why no Pi in M1

The web app needs `proxy/ws2osc.js` only because **a browser cannot open a UDP
socket**. A native iOS app has no such restriction — it sends OSC UDP straight to
MA3's `host:8000` over the venue LAN, so it needs nothing in between. The Pi
becomes valuable for the **remote** case (programming the rig from off-site) and
for an optional shared show library — both deferred. When wanted, the existing
`proxy/ws2osc.js` *is* the relay: run it on the Pi bound to `0.0.0.0`, reach it
over a private tunnel (Tailscale/WireGuard), and the phone talks to it exactly
like the web app does today. The `OSCTransport` protocol (§4) is the seam for
that future `RelayTransport`.

## Architecture

```
ios/
  project.yml                       xcodegen project (iOS 17+, team UWJSLFQDGL)
  CuelistCompiler/
    App.swift                       @main, root NavigationStack
    Models/                         Codable structs == show.json schema
      Project.swift  Song.swift  Cue.swift  Action.swift  Preset.swift
      Pool.swift  Defaults.swift  StoreMode.swift  Migration.swift
    Compile/
      CommandBuilder.swift          PORT of web/js/compile.js (the contract)
    Store/
      ProjectStore.swift            @Observable; load/save/mutate; JSON persistence
    Transport/
      OSCTransport.swift            protocol + connection state
      DirectUDPTransport.swift      NWConnection UDP sender
      OSCEncoding.swift             port of ws2osc.js OSC encoder
    Views/
      SongsListView.swift  CueListView.swift  CueEditorView.swift
      ActionEditorView.swift  DefaultsView.swift  ConnectionView.swift
  CuelistCompilerTests/
    CommandBuilderTests.swift       golden-fixture parity vs the JS reference
  tools/
    gen-golden.js                   Node harness: emit .lua + .cmdlines goldens
```

### 1. Data model (faithful to `show.json`)

Pure `Codable` structs that serialize to the **exact** web schema, so a future
`show.json` import/export is byte-compatible even though M1 has no import UI.

- `Project { songs: [Song], activeSongId: String, storeMode: StoreMode }`
  — top-level matches `saveProject()`.
- `Song { id: String, name: String, sequence: Int, cues: [Cue], audioFileName: String }`
- `Cue { n: Double, name: String, fade: String, delay: String, position: String, collapsed: Bool, actions: [Action] }`
- `Action { group: String, presets: [Pool: Preset] }`
- `Preset { name: String, fade: String, delay: String }` — **fade/delay stay
  `String`**: the web treats them as form strings and the builder trims / checks
  emptiness, so string fidelity is required for byte-exact output.
- `enum Pool: color, dimmer, position, gobo, beam, focus` with `number`
  (dimmer=1, position=2, gobo=3, color=4, beam=5, focus=6) and canonical
  iteration order `[color, dimmer, position, gobo, beam, focus]`.
- `Defaults` — per-pool `{ fade: String, delay: String }`. Stored separately from
  the project blob (mirrors the web's separate `localStorage` key). `storeMode`
  lives on `Project`.
- `Migration.migrate(...)` ports `migrateState` / `migrateActions` / `migrateCues`:
  upgrades the old single-song format (`{songName, sequence, cues}`, presets as
  bare strings) to the current shape. Needed for the parity test (the anchor is
  old-format) and for later import.

### 2. CommandBuilder — the shared-contract port

A single `CommandBuilder` porting `web/js/compile.js` **byte-for-byte**:

- `buildCmdLines(songs:defaults:storeMode:) -> [String]` — the OSC path.
- `buildLua(songs:headerTitle:defaults:storeMode:date:) -> String` — the `.lua`
  export. `date` is injectable so output is deterministic in tests (the JS uses
  `new Date().toISOString()` in the header).

Must replicate exactly: `"`→`\"` escaping, trimming, the 3-step fade/delay
resolution (preset value → per-pool default → omit), pool iteration order, the
`/Overwrite|/Merge` flag + `/NoConfirmation`, `Store`/`Set Sequence` lines, and
the trailing `ClearAll`.

**Parity is enforced by test, not by hope.** `tools/gen-golden.js` loads
`examples/SONG_1.json`, runs the same migration the web does, and emits two golden
fixtures: the `.lua` (already committed as `examples/SONG_1.lua`) and a new
`examples/SONG_1.cmdlines.txt`. `CommandBuilderTests` asserts the Swift builder
reproduces both exactly, normalizing only the `-- Generated:` timestamp line.
**Rule (from the contract):** any change to the sequence updates
`shared/ma3-command-spec.md`, `web/js/compile.js`, and `CommandBuilder.swift` in
the same PR; the goldens catch drift.

### 3. OSC transport — pluggable, Direct-UDP first

```swift
protocol OSCTransport {
    var state: TransportState { get }        // offline | connecting | online | sending
    func send(_ lines: [String],
              progress: (Int, Int) -> Void) async throws
}
```

- `DirectUDPTransport` — `Network.framework` `NWConnection(.udp)` to MA3
  `host:port`. Each line is encoded as an OSC message to `/<prefix>/cmd` by
  `OSCEncoding` (port of `ws2osc.js`: null-terminated, 4-byte-padded OSC strings,
  `,s` typetag, one string arg). Sends are throttled at `OSC_SEND_INTERVAL_MS`
  (20 ms) with `sending… N/total` progress, mirroring `web/js/osc.js`.
- Connection settings — MA3 host IP, OSC port (default `8000`), prefix (default
  `gma3`) → address `/<prefix>/cmd`. Persisted in `UserDefaults`. The Connection
  screen surfaces the MA3 requirement **OSC Echo Input = Yes** (without it `/cmd`
  will not dispatch).
- `send current song` / `send all` build lines via `CommandBuilder.buildCmdLines`
  and stream them through the transport.
- The protocol is the seam for a future `RelayTransport` (WebSocket → Pi running
  `proxy/ws2osc.js`). **Not built in M1.**

### 4. UI (SwiftUI, `NavigationStack`)

- **SongsListView** — songs with add / delete / reorder, set sequence, pick active.
- **CueListView** (per song) — cues (n, name) with add / delete / reorder.
- **CueEditorView** — n, name, fade, delay, position; a list of actions.
- **ActionEditorView** — group field + 6 pool sections (name / fade / delay),
  color-accented per `POOL_ACCENT`.
- **DefaultsView** — per-pool default fade/delay + Overwrite/Merge toggle.
- **ConnectionView** — MA3 host/port/prefix, status pill, `send current` /
  `send all` with progress; `.lua` export via the iOS share sheet.

### 5. Persistence

`ProjectStore` (`@Observable`) holds the in-memory `Project` + `Defaults` and
writes Codable JSON to the app's Documents dir (one project file + a defaults
file), debounced on change — mirrors the web's `localStorage` save and keeps the
`show.json` bytes authoritative. No SwiftData in M1.

## Testing

- `CommandBuilderTests` — golden parity (`.lua` and `.cmdlines`) against the JS
  reference, plus targeted cases: empty cue name (no quotes branch), preset vs
  default fade/delay resolution, `"` escaping, Merge vs Overwrite, multi-song.
- `MigrationTests` — old-format `SONG_1.json` upgrades to the expected new shape.
- Manual device smoke: author a small show on the iPhone, send to grandMA3 onPC
  on the same LAN, confirm cues store; export `.lua`, run it in MA3, confirm
  identical result.

## Deferred (later milestones)

Moods library · pool-name autocomplete (paste from `export_pools.lua`) · CSV
import · audio file + waveform/playback · `show.json` import/export UI · Relay
(Pi) transport + tunnel · iCloud sync · iPad-optimized layout.

## Out of scope (M1 non-goals)

No backend server. No live MA3 *feedback* (the app sends; it does not read MA3
state). No multi-user / collaboration.
