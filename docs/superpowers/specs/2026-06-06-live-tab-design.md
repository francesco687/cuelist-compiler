# Live tab — running cues from the phone

**Date:** 2026-06-06
**Branch:** `feat/live-tab` (worktree `~/cuelist-compiler-live`, off `main`)
**Component:** iOS app (`ios/`)

## Purpose

Give the operator a dedicated, leftmost tab for *running* the show live —
distinct from authoring (Author tab) and uploading (Send tab). v1 is three
big transport buttons that drive the grandMA3's currently-selected executor:

- **GO+** — advance to the next cue
- **GO-** — step back a cue
- **PAUSE** — pause/resume the running cue

This is a live-performance surface: taps must fire instantly with no
confirmation dialog.

## Scope

In scope (v1):

- A new `Live` tab, positioned first (leftmost) in the bottom tab bar.
- Three large transport buttons (GO+, GO-, PAUSE).
- Bare command-line semantics — commands act on whatever executor is
  selected **on the console**. No executor-targeting UI in the app.
- Instant firing with haptic feedback and a brief visual pulse on each tap.
- Buttons disabled when the hub is not connected.
- A connection row (status + tap-to-connect) reusing the Send tab's pattern.

Explicitly **out of scope** (YAGNI — may come later):

- In-app executor selection / targeting (`Go+ Executor 201`).
- Live cue/state feedback from the desk (what cue is running, fade progress).
- Arm/lockout toggle, multi-executor banks, fader control.

## Approach

The hub **already** supports a generic command passthrough:
`{ "type": "cmd", "line": "<string>" }` → OSC `/<prefix>/cmd` with the line as
its argument → executed on the grandMA3 command line (see
`hub/src/server.js`, `hub/src/osc.js`). Therefore **the hub requires no
changes** — all work is on the iOS side, reusing this path.

A dedicated new "run" message type was considered and rejected: it would
duplicate the existing `cmd` plumbing without adding capability.

## Command mapping

grandMA3 command-line keywords, acting on the console-selected executor:

| Button | Line sent |
|--------|-----------|
| GO+    | `Go+`     |
| GO-    | `Go-`     |
| PAUSE  | `Pause`   |

(To be confirmed against the desk during the manual smoke test.)

## Components

### Kit — `OutgoingMessage` (`ios/Sources/Kit/Hub/HubMessages.swift`)

Add a case for the command passthrough:

```swift
case cmd(line: String)
```

Encodes to `{"type":"cmd","line":"Go+"}` (mirrors the existing
`CompileSend` / `PullSequences` private Encodable structs).

### Kit — `HubClient` (`ios/Sources/Kit/Hub/HubClient.swift`)

Add:

```swift
public func sendCommand(_ line: String)
```

Behaviour mirrors `pullSequences()`: connect if not online, encode
`OutgoingMessage.cmd(line:)`, push over the connection. Feedback is
**optimistic** (the view flashes on tap), so the hub's `sent` ack is not
required and `IncomingMessage` is left unchanged (it already maps `sent`
to `.other`).

### App — `LiveView.swift` (new, `ios/Sources/App/`)

- `NavigationStack` + `Theme.canvas`, title "Live".
- Top: a connection row — `LiveIndicator(state: hub.state)` + tap-to-connect,
  same pattern as `SendView`.
- Body: three large buttons filling the vertical space:
  - **GO+** — primary / green (`Theme.ok` family).
  - **PAUSE** — amber / warn.
  - **GO-** — dimmer secondary.
- Each tap: trigger `UIImpactFeedbackGenerator(style: .medium)`, a brief
  visual pulse (scale/opacity), and `hub.sendCommand(<line>)`.
- Whole button cluster is `.disabled(!hub.state.isOnline)` and visually
  dimmed when offline.

### App — `RootView.swift`

Insert `LiveView()` as the **first** child of the `TabView`, before the
Author tab:

```swift
LiveView()
    .tabItem { Label("Live", systemImage: "play.circle.fill") }
```

Keep this change to a single localized insertion to minimise conflict with
the parallel `feat/ios-ui-refresh` work.

## Data flow

```
LiveView button tap
  → haptic + visual pulse
  → HubClient.sendCommand("Go+")
  → OutgoingMessage.cmd(line:"Go+").jsonString()
  → WebSocket → hub
  → OscSender.send("Go+") → OSC /<prefix>/cmd "Go+" (UDP)
  → grandMA3 executes on selected executor
```

## Error handling

- **Offline:** buttons disabled; tapping the connection row attempts connect.
- **Encode failure:** extremely unlikely for a fixed string; `sendCommand`
  fails silently (no `lastResult` mutation) since there is no compile flow
  to report against. Acceptable for v1 fixed commands.
- **No desk ack:** by design — optimistic UI. A dropped datagram simply means
  the cue doesn't move; the operator taps again.

## Testing

- **Kit unit test** (extend `ios/Tests/KitTests/HubClientTests.swift` /
  `HubMessagesTests.swift`):
  - `OutgoingMessage.cmd(line:"Go+")` encodes to exactly
    `{"type":"cmd","line":"Go+"}`.
  - `HubClient.sendCommand("Go+")` pushes that text through the stub
    connection used by existing tests.
- **Hub:** unchanged; the existing `cmd` path is covered by current hub tests.
- **Manual desk smoke:** select an executor on the grandMA3, tap GO+ / GO- /
  PAUSE, confirm the cue advances / steps back / pauses. Confirms the
  command-keyword mapping end-to-end.

## Coordination / isolation

Adding the tab edits `RootView.swift`, which the parallel session on
`feat/ios-ui-refresh` (worktree `~/cuelist-compiler-ios`) may also touch.
This work lives on its own branch `feat/live-tab` in worktree
`~/cuelist-compiler-live`, branched from `main`, and keeps the RootView edit
to one localized tab insertion to minimise merge conflict.
