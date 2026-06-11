# Saetta — Amber Aurora-Glass restyle

**Date:** 2026-06-11
**Branch:** `feat/ios-ui-refresh` (worktree `~/cuelist-compiler-ios`)
**Status:** Design approved, awaiting plan

## Goal

Restyle the Saetta iOS app to a **dark, monochrome amber, aurora-glass** aesthetic.
Single hue (amber) throughout — no second accent colour — over a deep aurora-lit
near-black canvas, with frosted-glass panels. Inspired by glassmorphism references
but kept **venue-legible**: the app is operated during live shows in dark rooms, so
the dark base and high-contrast accents are deliberate.

This is a **reskin**, not a feature change. Cue/send/voice logic is untouched. Work is
confined to `Theme.swift`, a small set of component views, and the app icon. All work
stays in the `~/cuelist-compiler-ios` worktree — the hub session on `~/cuelist-compiler`
is **not** touched.

## Locked decisions

| Decision | Choice |
|---|---|
| Hue | **Amber** — gradient `#f0b860 → #e0913f`, solid `#eaa64f` |
| Aesthetic | Dark aurora canvas + frosted glass panels + soft amber glow |
| Status signalling | **Brightness + glyph**, not hue (one exception below) |
| Destructive delete | **Stays red** — single deliberate safety exception |
| App icon | **Re-render in amber** — in scope |
| Decorative meter bars | **Not shipped** — no fake progress data (see Non-goals) |
| Segmented store picker | Native `.segmented`, amber-tinted only (no custom chrome) |

## Design tokens — `ios/Sources/App/Theme.swift`

Rework the single source of truth. New/changed values:

```
// Accent — single amber.
accentStart = #f0b860
accentEnd   = #e0913f
accentSolid = #eaa64f
accentGradient = LinearGradient([accentStart, accentEnd], topLeading → bottomTrailing)
accentTint  = amber.opacity(0.12)
accentBorder = amber.opacity(0.22)   // NEW — glass border tint

// Canvas — amber dark aurora (replaces neutral dark gradient).
// Radial blooms over near-black base:
//   radial #7a4f1e @ top-left, radial #5c3a16 @ bottom-right,
//   over linear #1d160e → #15110a → #0f0c07
// Implemented as a ZStack of RadialGradients over a base LinearGradient.

// Text — warm off-whites (replace cool greys).
text     = #f6ead6
textDim  = #c2a079
textFaint= #94795e

// Semantic status — collapse to amber brightness; keep danger red.
ok      → amber bright  (#f0c074)   // success glyph carries meaning
warn    → amber mid     (#d49a4a)   // delay numerics
danger  = #ff6b6b  (UNCHANGED — destructive delete only)

// Radii unchanged (11 / 7).
```

### New view modifiers

```swift
// Frosted glass card: material + translucent highlight + amber-tinted hairline + soft glow.
func glassSurface(radius: CGFloat = Theme.radius, glow: Bool = false) -> some View
//   .background(.ultraThinMaterial, in: RoundedRectangle)
//   .overlay(white .10→.035 linear highlight)
//   .overlay(RoundedRectangle.strokeBorder(Theme.accentBorder, lineWidth: 1))
//   .shadow(amber.opacity(glow ? 0.35 : 0.18), radius: 16, y: 8)

// Amber glow for hero elements (send button, live dot).
func accentGlow(_ strength: Double = 0.5) -> some View
```

`cardSurface()` is retained but re-pointed to `glassSurface()` internally (or callers
migrated) so existing call-sites get the new look with minimal churn.

## Component changes

| File | Change |
|---|---|
| `Theme.swift` | Token rework + `canvas` aurora + `glassSurface`/`accentGlow` modifiers |
| `Components/CueBadge.swift` | Ring-style: amber gradient circle, inner translucent stroke (`inset 4px white .06`), soft amber glow |
| `Components/Chip.swift` | Frosted pill: translucent fill + amber-tinted border, warm text |
| `Components/LiveIndicator.swift` | Brightness states — offline = dim hollow dot; connecting = mid pulse; live = full bright glowing dot. No green. |
| `Components/StepperField.swift` | Amber tints (Fade = accentSolid, Delay = warn amber) |
| `SendBarView.swift` | Send button = amber gradient, **dark text `#0c0c14`**, `accentGlow`; send bar gains amber tint + border over existing `.ultraThinMaterial`; result row uses bright glyphs (✓ / ⚠) not green/red |
| `CueCardView.swift` | Uses `glassSurface()`; destructive trash keeps `Theme.danger` red |
| `CueListView.swift`, `RootView.swift`, `SettingsView.swift`, `DefaultsView.swift`, `PoolRowView.swift`, `CopyFromBar.swift`, `ColorPickerPopover.swift`, `VoicePreviewSheet.swift` | Inherit via tokens/modifiers; spot-check each for hardcoded violet refs and migrate to amber |

### Status mapping (monochrome with one exception)

- **Live / connection**: `LiveIndicator` brightness + dot glow.
- **Send success**: bright `checkmark.circle.fill` in amber.
- **Send failure**: bright `exclamationmark.triangle.fill` in amber + dimmer text.
- **Sending progress**: `ProgressView` tinted `accentSolid`.
- **Destructive delete only**: `Theme.danger` red — unchanged.

## App icon — `ios/icon-design/`

Re-render the existing bolt icon in amber to match. The generator (`final.py`,
SVG → PNG via headless Chrome) is committed and reproducible. Swap the violet→blue
gradient bolt for the amber gradient (`#f0b860 → #e0913f`) on the dark canvas, keep the
blade-slice composition (the approved "C1" direction). Regenerate the 1024 universal
asset into `Assets.xcassets/AppIcon.appiconset/`. Scratch renders stay gitignored;
committed source (`final.py` + SVGs) updated for reproducibility.

## Non-goals (YAGNI)

- **No fake progress/meter bars.** The glowing meters in the brainstorm mockups were
  decorative; cue cards have no progress value. The glass + glow treatment carries the
  aesthetic; cards keep real content only (badge · name · chips · steppers).
- **No custom segmented control.** Native `.segmented` Picker, amber-tinted.
- **No layout/IA changes.** Same navigation, same screens, same interactions.
- **No desktop/web changes.** This intentionally diverges iOS from the desktop's dark
  violet tokens; desktop is out of scope.

## Architecture / isolation

The restyle is a thin presentation layer over unchanged logic:

- **Theme** is the single dependency hub — tokens + modifiers. Every other view consumes
  it; changing it propagates the look.
- **Components** are leaf views with one visual job each, individually verifiable.
- **No Kit changes** — models, store, hub, voice are untouched.

This keeps each unit small and the blast radius contained: a reviewer can read
`Theme.swift` and know the whole palette; each component file is self-contained.

## Verification

Visual reskin — verified by build + eyeball, not unit tests:

1. `cd ios && xcodegen generate && xcodebuild` build green.
2. Install on **jPhone (2)** via `xcrun devicectl` (per `reference_ios_signing`).
3. Eyeball each screen against this spec: aurora canvas, glass cards, amber badges/send
   button, brightness-based live/result status, red delete, amber icon on springboard.
4. Confirm legibility with screen at low brightness (venue check).

Existing Kit tests must still pass (they're logic-only, unaffected).

## Risks

- **Glassmorphism contrast in a dark room** — frosted panels over a dark aurora can lose
  edge definition. Mitigation: amber-tinted 1px borders on every glass surface; verify at
  low brightness (step 4).
- **SwiftUI `.segmented` tint limits** — native control may not fully honour amber on all
  states; acceptable per scope, revisit only if it reads wrong.
- **Hardcoded violet leftovers** — prior `feat/ios-ui-refresh` commits may have inlined
  `#7a5cff`/`#5e8bff` outside Theme. Plan must grep for stray hex literals and migrate.
