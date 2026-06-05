# iOS UI Refresh — Design Spec

**Date:** 2026-06-05
**Branch:** `feat/ios-ui-refresh` off `main` (built in isolated worktree `~/cuelist-compiler-ios` — a parallel session holds `~/cuelist-compiler` on `feat/desktop-ui-vibrancy`)
**Scope:** Visual + interaction-model rework of the native iOS app (`ios/Sources/App/*`). Make it slick, minimal, Apple-grade, sharing the desktop "Tinted Vibrancy" redesign's exact design tokens.

## Goal

The iOS app is feature-complete but visually "developer prototype": stock SwiftUI, dense rows of `.roundedBorder` text fields, gray filled cards, system bars. Rework it into a refined, dark, native-feeling authoring tool that an operator at a grandMA3 in a dark venue enjoys using — and that reads as the *same product* as the redesigned desktop app, by adopting the desktop's committed token set.

## Hard scope boundary (load-bearing)

**This is a presentation-layer-only change.** It touches only the SwiftUI views in `ios/Sources/App/`. It must NOT change:

- Anything in `CuelistCompilerKit` (`ios/Sources/Kit/*`) — models, `ProjectStore`, mutations, hub client/codecs, voice pipeline. All 92 Kit tests stay green, untouched.
- The two **frozen shared contracts** with the desktop session: the hub WebSocket protocol (`compile-send {project,defaults,selection}` → `progress/done/error`, port 9000) and the project-JSON shape `compile.js` consumes. A pure visual restyle cannot reach either — confirmed.
- App behavior/features: nothing added or removed. Same songs/cues/groups/pools/presets, same voice authoring, same send-to-hub. Only *how it looks and how you touch it* changes.

The only logic-adjacent change is **decluttering empty pools** (render only set pools as rows; empty pools become add-affordances) — a view-state change, not a model change.

## Cross-app coherence (the anchor)

The desktop session committed a token set on `feat/desktop-ui-vibrancy` (`web/css/styles.css` `:root`). **iOS mirrors those exact values** so both apps are one product. Source of truth for the numbers:

| Token | Value | iOS use |
|---|---|---|
| accent (gradient) | `linear-gradient(135°, #7a5cff → #5e8bff)` | primary "tap": cue badges, Send → MA, add-group/cue |
| accent-solid | `#6f78ff` | single-color needs: stepper +/−, focus ring, fade numerics |
| accent-tint | `rgba(122,92,255,.12)` | group-card fill |
| bg | `radial-gradient(120% 120% at 0 0, #1b1e26 → #15171c → #111319)` | app canvas |
| surface-1/2/3 | `rgba(255,255,255,.045 / .06 / .09)` | cards / inputs / raised |
| border / border-strong | `rgba(255,255,255,.075 / .14)` | hairlines / dashed add-chips |
| text / dim / faint | `#e9eaf0 / #9a9eaa / #7c8090` | text hierarchy |
| ok / ok-bg / ok-border | `#5fe08a / rgba(48,209,88,.16) / .32` | **live = green** (MA online, "linked") |
| warn | `#f0b850` | delay numerics |
| danger | `#ff6b6b` | destructive (remove cue/group) |
| radius / sm / pill | `11 / 7 / 999` | corner radii |
| blur | `blur(12px)` | translucent materials |

**No aqua.** The earlier aqua-live idea is dropped per decision — live/ok is green, identical to desktop.

## Design decisions (validated via visual companion)

1. **Aesthetic:** Refined Dark, console-inspired, **dark-only for v1** (`.preferredColorScheme(.dark)`). Light mode deferred (desktop has none either).
2. **Accent = violet→blue gradient** (above) for everything interactive; rendered as a *filled shape* or glow. **Live/ok = green.**
3. **Pool colors stay faithful to web** (`PoolDisplay.accentHex`): COL `#c44d8f`, DIM `#d8d8d8`, POS `#5fb86a`, GOB `#e8a23a`, BEM `#56c2d6`, FOC `#a574d6`. **FOC** (lavender) is the one that hue-clashes with the violet accent — disambiguated **by treatment, not retune**: pool identity is always the 3-letter label + a small dot; chrome is always a filled gradient badge/button. A filled gradient badge never reads as lavender text. Optional micro-retune of FOC only if it reads muddy on-device.
4. **Cue interaction:** tapping a cue **expands it inline** in the list (no detail-screen push). One scroll, web-parity, consistent with inline pool editing.
5. **Preset editing:** **inline expand.** A group shows only its *set* pools as rows; tapping a pool row unfolds its editor (preset-name field + fade/delay steppers) in place. Empty pools collapse into a row of dashed `＋ POS GOB BEM FOC` add-chips. Fade numerics use accent-solid; delay numerics use warn.
6. **Song switcher:** native dropdown **Menu** on the nav title (`SONG_1 ⌄`) — songs list + New Song + Rename/Seq/Remove. No new screen.

## Architecture

A small **design-token layer** is the backbone; views become thin and consistent.

- **`Theme.swift`** (new, App layer) — single source of truth mirroring the desktop tokens above: a `LinearGradient` accent, `accentSolid`, surfaces, borders, text colors, ok/warn/danger, radii, plus shared text styles (title, cue-name, label, mono-numeric). All views read from this; no scattered literals. Keeping the values in one file makes a future "shared token" sync with desktop trivial.
- **Reusable components** (new, small, App layer):
  - `CueBadge` — gradient rounded number badge with glow.
  - `GroupCard` — accent-tint card, left accent bar (group color), group-name field, color swatch, remove.
  - `PoolRow` — dot + abbr + value + fade/delay (accent/warn) + chevron; expands into…
  - `PoolEditor` — preset-name field + two `StepperField`s (fade, delay).
  - `StepperField` — bordered −/value/+, accent-solid controls, decimal entry, default-as-placeholder.
  - `AddChips` — wrap of dashed `＋POOL` chips for empty pools.
  - `Chip` — summary chip for collapsed-cue rows.
  - `LiveIndicator` — green dot + label reflecting `HubClient.state` (green online / warn connecting / danger error / faint offline).
- Existing views are restyled to compose these; data flow (`@Environment(ProjectStore)`, `@Bindable`, bindings into `project.songs[i].cues`) is unchanged.

### File-by-file

| File | Change |
|---|---|
| `Theme.swift` | **new** — tokens (mirror desktop) + text styles |
| `Components/` | **new** — `CueBadge`, `GroupCard`, `PoolRow`, `PoolEditor`, `StepperField`, `AddChips`, `Chip`, `LiveIndicator` |
| `App.swift` | `.preferredColorScheme(.dark)` + accent tint |
| `RootView.swift` | restyle nav (tappable song Menu in title, mic, green MA status, `⋯` overflow); dark gradient scaffold |
| `SongBarView.swift` | collapse into the nav-title **Menu** + a slim seq/cue-count subbar (drop the inline name field + stepper bar) |
| `CueListView.swift` | dark scroll, styled empty state, styled `＋ Add Cue` |
| `CueCardView.swift` | inline-expand card: `CueBadge` + name; collapsed → `Chip` summary; expanded → `GroupCard`s + `＋ Add group` + cue fade/delay |
| `ActionBlockView.swift` | becomes `GroupCard`: accent bar, name, color swatch; renders set `PoolRow`s + `AddChips`; owns tap-to-expand pool state |
| `PoolRowView.swift` | `PoolRow` + inline `PoolEditor` (replaces always-on triple text fields) |
| `SendBarView.swift` | `LiveIndicator` + segmented store mode + gradient `Send → MA` / `All`; restyle progress + result states |
| `SettingsView.swift` | dark restyle (host/port, API keys) |
| `DefaultsView.swift` | dark restyle (per-pool default fade/delay) |
| `ColorPickerPopover.swift` | dark restyle of the action-color swatch grid (`PoolDisplay.actionColors`) |
| `CopyFromBar.swift` | restyle as a subtle menu/chip within the expanded cue |
| `VoicePreviewSheet.swift` | dark restyle; gradient Apply / plain Discard; legible warnings |

## Component states to cover

- **Cue:** collapsed (chip summary) / expanded; empty-name placeholder; destructive remove (danger).
- **Pool row:** empty (add-chip) / set-collapsed / set-expanded(editing); fade/delay show the per-pool **default** as placeholder when blank (preserve current `store.defaults.fade/delay` placeholder behavior).
- **Hub link (`LiveIndicator`):** offline (faint) / connecting (warn) / online (green) / error (danger); tap to connect (unchanged).
- **Send:** idle / sending (progress + `sending n/total…`) / done (green "Sent N lines") / failed (danger). Same logic, restyled.
- **Voice mic:** idle / recording (red stop) / transcribing+interpreting (spinner) / preview (sheet). Same state machine, restyled.
- **Empty states:** no cues ("Add your first cue"), single-song (no Remove).

## Out of scope (explicit)

- No Kit/model/store/hub/voice logic changes.
- No new features (no multi-show, no new authoring ops, no light mode, no aqua).
- No protocol or project-JSON changes.
- Not editing the parallel desktop branch; we *mirror its committed tokens* only. If that session later extracts a truly shared token artifact, fold it in as a follow-up.

## Testing & verification

- **Automated:** `xcodebuild build -scheme CuelistCompiler` must SUCCEED; all 92 Kit tests stay green (they don't touch views — confirm untouched). No new unit tests (pure presentation; SwiftUI views aren't unit-tested in this project).
- **Manual (the real gate):** on-device eyeball on jPhone (2) — every state above, plus a quick voice run and a real `Send → MA` to confirm nothing behavioral regressed. UI quality judged by eye, per project norm.

## Risks

- **FOC/violet hue proximity** — mitigated by treatment (filled gradient chrome vs label+dot data); retune is opt-in only.
- **Inline-expand state** (which cue / which pool is open) — keep local `@State` per card/row, mirroring today's `cue.collapsed`; never leak into the model.
- **Token drift from desktop** — values are duplicated by hand in `Theme.swift`; if desktop retunes, re-sync. Documented as a known maintenance point.
- **Dark-only** may surprise a daytime user — acceptable for v1; documented.
