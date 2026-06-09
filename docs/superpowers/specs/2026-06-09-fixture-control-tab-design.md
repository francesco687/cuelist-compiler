# Fixture Control Tab — Design

**Date:** 2026-06-09
**App:** Saetta (iOS, `ios/`)
**Branch:** `feat/fixture-control-tab`

## Problem

Saetta authors cue *structure* (songs → cues → actions referencing named presets) and
sends it to a grandMA3 desk, plus runs transport (Go+/Go-/Pause) from the Live tab. It
has no surface for **live, direct control of individual fixtures or groups** — selecting
a fixture, adjusting its attributes (intensity, pan/tilt, …) on the fly, and capturing the
result into a cue or preset. This adds that surface as a new bottom tab.

## Concept & Architecture

A new 4th bottom tab — **"Fixtures"** (order: Live · Program · Send · **Fixtures** ·
Settings) — that is a **direct remote control of the desk's programmer**.

It holds **no fixture-value state in the project model**. Every interaction emits one or
more grandMA3 command-line strings over the existing transport
(`HubClient.sendCommand` / `sendLines`, the same optimistic fire-and-forget path the Live
tab uses). The **desk's programmer is the source of truth**; the app only pushes deltas,
recalls, and store commands at it.

This keeps the feature consistent with the rest of the app:

- No new desk→app read-back channel.
- No new persisted project data (aside from optional, local-only preset-slot labels).
- Reuses `HubClient`, `StoreMode`, `Pool`, and the existing sheet/Theme idioms.

### Readout caveat (stated honestly in UI)

Because there is no value read-back, the numbers shown next to faders (e.g. "Pan +12°")
are a **local running offset** accumulated from the nudges sent *this session* — not a
true value read from the desk. They reset to zero on **Clear** and whenever the selection
changes. They answer "how much have I pushed since I grabbed this", nothing more. The UI
must not imply these are the desk's absolute values.

## Decisions (from brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Value model | **Relative nudge** (send deltas) | No read-back needed; matches encoder feel; robust |
| Selection | **Console-style keypad** | grandMA3 muscle memory; single fixtures + ranges + groups |
| Parameter control | **Hybrid** — encoders for continuous attrs, recall for Color/Gobo | Nudging hue/gobo on a phone is clumsy; recall is faster |
| Store target | **Keypad target + Overwrite/Merge toggle** | Explicit, console-accurate; reuses `StoreMode` |
| Screen layout | **A · Programmer Page** | Selection as a chip→sheet; control area dominates; store via sheets |
| Encoder widget | **B · Jog faders** + coarse/fine toggle | One attribute per finger; familiar; precise when slow |
| Color/Gobo recall | **Recall by number** | Zero read-back; consistent with fire-and-forget; ships now |

## Screen (Layout A · jog faders)

```
┌─────────────────────────────┐
│ ● Connected · Hub            │   reused connection row
│ Selection                    │
│ [ Fixture 101        ⌨ edit ]│   tap chip → keypad sheet
│ Parameter                    │
│ [Int][Pos][Color][Gobo][Beam][Focus]   segmented picker
│ ┌─────────────────────────┐  │
│ │   ▲        ▲             │  │
│ │  Pan      Tilt   (jog    │  │   control area, varies by category
│ │ +12°      −4°    faders) │  │
│ │   ▼        ▼  [coarse|fine] │
│ └─────────────────────────┘  │
│ [ Clear ]                    │   release programmer (ClearAll)
│ [ Store to Cue… ][ Update Preset… ]
└─────────────────────────────┘
```

- **Selection chip** → opens a **keypad sheet**: digits + `Fixture` / `Group` / `Thru`
  / `+` / `Clear`, with a live preview of the command and a "Select" button that fires it.
- **Parameter segmented control** swaps the control area.
- **Coarse/Fine toggle** scales nudge-per-drag-distance.
- **Clear** sends `ClearAll` to drop the programmer.

### Attribute map per category (v1)

Easily extended — these are just attribute names fed to the command builder.

| Category | Control | Attributes / behavior |
|---|---|---|
| Int | jog fader | Dimmer (`At`) |
| Pos | jog faders | Pan, Tilt |
| Beam | jog faders (scrollable) | Zoom, Focus, Iris |
| Focus | jog fader | Focus |
| Color | recall grid | `At Preset 4.<n>` |
| Gobo | recall grid | `At Preset 3.<n>` |

Recall grid slots carry an optional **local-only label** the operator can set in-app
(e.g. label slot 3 "Red"); labels never come from the desk.

## What gets sent (command lines)

| Action | Emitted line(s) |
|---|---|
| Select fixture | `Fixture 101` |
| Select range | `Fixture 101 Thru 105` |
| Select group | `Group 2` |
| Intensity nudge | `At + 5` / `At - 5` |
| Pan nudge | `Attribute "Pan" At + 5` ⚠️ |
| Tilt nudge | `Attribute "Tilt" At - 5` ⚠️ |
| Color/Gobo recall | `At Preset 4.3` |
| Clear programmer | `ClearAll` |
| Store to cue | `Store Sequence 5 Cue 2 /Merge /NoConfirmation` |
| Update preset | `Store Preset 4.3 /Overwrite /NoConfirmation` |

Nudges are **throttled/coalesced**: a continuous drag emits at most ~1 line per ~50 ms,
summing the accumulated delta between emissions, so a drag never floods the desk.

### ⚠️ Phase 0 — relative-attribute syntax spike (do FIRST)

Dimmer relative `At + 5` is well-established. The exact form for a **per-attribute
relative nudge** over the `/cmd` OSC channel — `Attribute "Pan" At + 5` — must be
**verified against the real desk before** the fader logic is built on it. ~15-minute
spike. If that form is not accepted, fallbacks (in order): MAtricks/feature-encoder
syntax, or absolute-with-local-tracking. The spike result determines the builder's nudge
output and is a hard prerequisite for the Position/Beam/Focus/Int fader work.

## Store & Update (Layout A sheets)

- **Store to Cue sheet:** Sequence field (prefilled from active song's `sequence`,
  editable) · Cue number field · Overwrite/Merge toggle (`StoreMode`) · "Store" button.
  Displays the exact command before firing.
- **Update Preset sheet:** Pool picker (6 pools) · preset-number field · Overwrite/Merge
  toggle · "Update" button. Displays the exact command before firing.
- Both are confirm-by-construction (open sheet → press action) and show the composed
  command line so there is no ambiguity about what reaches the desk.

## Components & boundaries

### Kit (pure, unit-tested — no SwiftUI)

- **`FixtureControlBuilder`** — mirrors `MA3CommandBuilder`'s style. Pure functions:
  intents → command strings. Covers: selection lines, intensity/attribute nudge lines
  (per Phase-0 syntax), preset-recall lines, `ClearAll`, store-cue line, update-preset
  line. Quoting/format helpers mirror the existing builder.
- **`NudgeAccumulator`** (or similar) — coalesces a stream of drag deltas into throttled
  emissions (sum-between-emits, ~50 ms cadence) and tracks the per-attribute session
  offset shown in the UI. Pure/testable (inject the clock, as `HubClient` injects
  `scheduleAfter`).

### App (SwiftUI)

- **`FixtureControlView`** — the tab root; owns selection state, current category, the
  accumulator, and wires intents to `HubClient`.
- **`SelectionKeypadSheet`** — keypad → selection command, live preview, Select.
- **`JogFader`** — reusable vertical drag widget emitting relative deltas; recenters on
  release; coarse/fine aware.
- **`PresetRecallGrid`** — numbered recall buttons with optional local labels.
- **`StoreCueSheet`**, **`UpdatePresetSheet`** — the two store flows.
- `RootView` gains a 4th `tabItem` ("Fixtures").

## Testing

- Unit-test `FixtureControlBuilder` output for every row in the command-line table
  (selection variants, nudge ±, recall, store, update, overwrite vs merge, quoting).
- Unit-test `NudgeAccumulator` coalescing/throttling and offset tracking with an injected
  clock.
- App views follow existing manual-on-device verification (install on jPhone (2),
  hardware smoke against the desk) — consistent with how the app has been validated.

## Open / deferred (not in v1)

- Pulling named presets from the desk (deferred; recall-by-number ships instead).
- Reading true absolute attribute values (no read-back channel by design).
- Additional Beam attributes (Frost/Strobe/etc.) — trivial to add to the attribute map.

## Non-goals

- No change to the existing Program/Send/Live authoring or transport behavior.
- No new persisted project model fields (preset-slot labels are local-only UI state).
