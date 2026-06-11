# Saetta — "Amber HUD" cyber-tech restyle

**Date:** 2026-06-11
**Status:** Approved design, ready for implementation plan
**Scope:** App-wide visual restyle of the Saetta iOS app (all five tabs + shared chrome). Pure styling — no behavior, data, or transport changes.

## Goal

The app's current "Amber Aurora-Glass" look reads as generic SwiftUI. Push it toward a
**cyber-tech HUD** feel — evolving the existing amber design language, not replacing it.
Chosen direction and intensity were validated via visual mockups during brainstorming:

- **Direction:** Amber HUD (keep amber hue + the red programmer/touched convention; add HUD chrome).
- **Intensity:** Balanced — distinctly HUD, but calm and fast to read under stage conditions.
  Explicitly *not* the "Full HUD" maximal variant (no scanlines, pulsing, or decorative
  slash/arrow glyphs as ambient noise).
- **Scope:** Whole app, driven from the theme layer so the look stays consistent.

## Non-negotiable guardrails

These existing design rules are preserved exactly — the restyle must not violate them:

1. **Amber is the only hue.** No new accent color is introduced anywhere.
2. **Red is reserved.** Red = "in programmer" / "touched" indicator (Fixtures category bar,
   store log) AND destructive delete (`Theme.danger`). Nothing else becomes red.
3. **Pale-amber capture/voice tone** (`Theme.aqua` family) stays as the second lightness for
   capture/voice surfaces — distinguished by lightness, not a second hue.
4. **No Full-HUD ornamentation:** no scanline texture, no pulsing/animated glow, no decorative
   `▸▸ ◂◂` / `//` ambient glyphs. A single leading `▸` on the primary CTA is the only added glyph.

## Theme primitives (the engine)

All added in `ios/Sources/App/Theme.swift` (and its `View`/`ButtonStyle` extensions) so the
look propagates from one source. These are the building blocks every tab reuses.

| Primitive | Definition | Purpose |
|---|---|---|
| `Theme.mono(size:weight:)` | Returns `Font.system(size:weight:design:.monospaced)` | Real SF Mono for **all numeric readouts** and HUD labels (today the app uses only `.monospacedDigit()` on a proportional face). |
| `.hudLabel()` View modifier | Uppercases text + applies `.tracking(1.2)` (letter-spacing) | Section titles and control labels (PAN, COLOR, SEQ, etc.). |
| `.hudPanel(glow:)` View modifier | Wraps existing `cardSurface(...)` and overlays four small L-shaped **corner brackets** in `Theme.accentSolid` | The signature HUD element for hero panels. |
| `Theme.tickGridFill` | A faint repeating horizontal hairline (`accentStart` @ ~0.07 opacity every ~24pt) as a `ShapeStyle`/overlay | Background texture for fader tracks and readout strips. |
| Sharper radii | `radius 11 → 7`, `radiusSmall 7 → 4`, `radiusLarge 16 → 11` | Tighter, more technical edges globally. Circular elements (`CueBadge`) are unaffected. |

### `AmberCTAStyle` update
The existing "commit to MA" button style gets: the sharper corner radius, a **contained** glow
(tighter radius, no spread increase), and a single leading `▸` glyph before the label.
Dark warm ink on the amber gradient is retained.

## Per-tab application

The theme primitives are applied consistently. Density-sensitive screens (forms) get a lighter
touch — no bracket clutter.

- **Fixtures** (`Fixture/FixtureControlView.swift`, `JogFader.swift`, `StoreSheets.swift`) — the showcase:
  - Category bar: `.hudLabel()` + mono, sharper radii. The red "touched" dot keeps its glow.
  - `JogFader` track: apply `tickGridFill`, sharper corner radius; value/label readouts use `Theme.mono` + `.hudLabel()`.
  - Panel framed with `.hudPanel()`.
  - Store/Update CTAs use the updated `AmberCTAStyle`; "Will store" preview labels `.hudLabel()`.
- **Live** (`LiveView.swift`):
  - Transport titles (GO+/PAUSE/GO−) → `Theme.mono`.
  - `connectionRow` → bracketed HUD status readout.
  - Macro pad + message field → bracket framing via `.hudPanel()`.
- **Program** (`RootView.swift` author tab, `CueListView.swift`, `CueCardView.swift`, `SeqField.swift`):
  - Song title → mono/uppercase; subbar cue-count → `Theme.mono`.
  - Cue cards → subtle corner brackets (lighter than hero panels).
  - `SeqField` numeric → `Theme.mono`.
- **Send** (`SendView.swift`) & **Settings** (`SettingsTabView.swift`, `SettingsView.swift`, `DefaultsView.swift`):
  - Lighter touch: mono numerics, sharper radii via the global constants, updated shared CTA.
  - No bracket framing on dense forms.

## Architecture / isolation

- Single source of truth stays `Theme.swift`. New primitives are small, independently
  understandable modifiers/helpers with clear inputs (size, weight, glow flag) and no hidden
  state. Consumers call them; internals can change without breaking call sites.
- No new files strictly required, but `.hudPanel` + corner-bracket overlay may live in a small
  `Theme+HUD.swift` extension file to keep `Theme.swift` focused if it grows large.
- Per-tab edits are mechanical substitutions (swap `.font(...)` → `Theme.mono(...)`, wrap panels
  in `.hudPanel()`), each reviewable in isolation.

## Error handling

N/A — no logic, networking, or data paths are touched. Risk surface is purely visual regression.

## Testing & verification

This is pure styling; there is nothing unit-testable in a `Color`/`Font`/`ViewModifier`.

- **Build:** `swift build` (and the app target build) stays green, sim + device.
- **Regression:** the existing **208 SaettaKit tests stay green (1 skip)** — they must be
  unaffected since no Kit code changes.
- **Manual:** on-device eyeball pass on jPhone (2) across all five tabs, confirming:
  legibility of mono readouts in the dark, the red touched/programmer signal still reads,
  corner brackets render correctly, no layout breakage from tighter radii.

No new automated tests are added (no testable surface).

## Out of scope

- Any behavior, transport, hub-protocol, or data-model change.
- The Full-HUD maximal variant (scanlines, pulsing, ambient ornament glyphs).
- New accent hues or changes to the red/pale-amber semantics.
- Custom font files (uses the system monospaced face).
