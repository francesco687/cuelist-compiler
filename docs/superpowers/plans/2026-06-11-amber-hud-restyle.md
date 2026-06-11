# Amber HUD Cyber-Tech Restyle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the Saetta iOS app app-wide into a "Balanced Amber HUD" cyber-tech look — adding HUD chrome (monospace readouts, uppercase tracked labels, corner brackets, faint tick-grid, sharper radii, contained glow) while preserving the existing amber-only hue and the red programmer/touched + destructive-delete semantics.

**Architecture:** All new visual primitives live in the theme layer (`Theme.swift` + a new `Theme+HUD.swift`) so the look propagates from one source. Per-tab work is a mechanical sweep that applies those primitives. No logic, transport, data-model, or SaettaKit changes — this is pure SwiftUI styling.

**Tech Stack:** SwiftUI, xcodegen-generated `Saetta.xcodeproj`, system monospaced font (no custom font files).

**Design spec:** `docs/superpowers/specs/2026-06-11-cyber-tech-hud-restyle-design.md`

---

## Conventions for this plan

**Verification model.** This is pure styling — there is no unit-testable surface in a `Color`/`Font`/`ViewModifier`. Each task's verification is therefore: **the app target compiles cleanly**, then a commit. The 208 SaettaKit tests are run once at the end (Task 8) to prove the shared module is untouched.

**Per-task build command (run from repo root `/Users/jordanbabev/cuelist-compiler-ios`):**

```bash
cd ios && xcodegen generate >/dev/null && cd .. && \
xcodebuild -project ios/Saetta.xcodeproj -scheme Saetta \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```

Expected output ends with: `** BUILD SUCCEEDED **`

(`xcodegen generate` is required before every build because the `.xcodeproj` is generated from `ios/project.yml`. The `generic/platform=iOS Simulator` destination compiles without booting a simulator — fast and deterministic for a styling check.)

**Guardrails (must hold after every task):**
- Amber is the only hue. No new accent color anywhere.
- Red (`Theme.danger`) stays reserved for the touched/programmer indicator and destructive delete. Do not add red elsewhere.
- The pale-amber `Theme.aqua` capture/voice tone is unchanged.
- No scanlines, no pulsing/animation, no ambient `//` `▸▸ ◂◂` glyphs. The only added glyph is one leading triangle on the primary CTA (Task 3).

---

## Task 1: Theme core primitives — `mono`, sharper radii, `hudLabel`

**Files:**
- Modify: `ios/Sources/App/Theme.swift` (radii at lines 47-49; add a static func + a `View` extension)

- [ ] **Step 1: Tighten the global radii**

In `ios/Sources/App/Theme.swift`, replace the three radius constants (currently lines 47-49):

```swift
    // Radii.
    static let radius: CGFloat = 11
    static let radiusSmall: CGFloat = 7
    static let radiusLarge: CGFloat = 16          // pill CTAs (bottom cluster, delete bar)
```

with the sharper HUD values:

```swift
    // Radii — tightened for the HUD look. Circular elements (CueBadge) are unaffected.
    static let radius: CGFloat = 7
    static let radiusSmall: CGFloat = 4
    static let radiusLarge: CGFloat = 11          // pill CTAs (bottom cluster, delete bar)
```

- [ ] **Step 2: Add the `Theme.mono` font helper**

Inside the `enum Theme { ... }` body, immediately after the radii constants you just edited, add:

```swift
    /// HUD monospace face — real SF Mono, for every numeric readout and HUD label.
    /// (The app previously used only `.monospacedDigit()` on a proportional face.)
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
```

- [ ] **Step 3: Add the `.hudLabel()` view modifier**

At the bottom of the existing `extension View { ... }` block (the one that already defines `cardSurface` and `accentGlow`), before its closing brace, add:

```swift
    /// HUD section/control label: uppercase + letter-spacing. Pairs with `Theme.mono`.
    func hudLabel() -> some View {
        self.textCase(.uppercase).tracking(1.2)
    }
```

- [ ] **Step 4: Build to verify it compiles**

```bash
cd ios && xcodegen generate >/dev/null && cd .. && \
xcodebuild -project ios/Saetta.xcodeproj -scheme Saetta \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/App/Theme.swift
git commit -m "feat(ios-ui): HUD theme primitives — mono font, sharper radii, hudLabel"
```

---

## Task 2: HUD chrome primitives — `TickGrid`, `CornerBrackets`, `.hudPanel()`

**Files:**
- Create: `ios/Sources/App/Theme+HUD.swift`

These live in a new file to keep `Theme.swift` focused. They are added by `project.yml`'s `sources: [path: Sources/App]` automatically (whole-directory source), so no `project.yml` edit is needed — but you MUST re-run `xcodegen generate` (the build command does this) so the new file is picked up.

- [ ] **Step 1: Create the file with both shapes and the panel modifier**

Create `ios/Sources/App/Theme+HUD.swift` with exactly:

```swift
import SwiftUI

/// Faint repeating horizontal hairlines — HUD "tick grid" texture behind fader
/// tracks and readout strips. Amber at low opacity so it reads as instrumentation,
/// not chrome. Non-interactive.
struct TickGrid: View {
    var spacing: CGFloat = 24
    var body: some View {
        GeometryReader { geo in
            Path { p in
                var y = spacing
                while y < geo.size.height {
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    y += spacing
                }
            }
            .stroke(Theme.accentStart.opacity(0.07), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Four L-shaped corner brackets framing a panel — the signature HUD element.
/// Drawn as an overlay; non-interactive.
struct CornerBrackets: View {
    var color: Color = Theme.accentSolid
    var length: CGFloat = 14
    var lineWidth: CGFloat = 2
    var inset: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                // top-left
                p.move(to: CGPoint(x: inset, y: inset + length))
                p.addLine(to: CGPoint(x: inset, y: inset))
                p.addLine(to: CGPoint(x: inset + length, y: inset))
                // top-right
                p.move(to: CGPoint(x: w - inset - length, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset + length))
                // bottom-left
                p.move(to: CGPoint(x: inset, y: h - inset - length))
                p.addLine(to: CGPoint(x: inset, y: h - inset))
                p.addLine(to: CGPoint(x: inset + length, y: h - inset))
                // bottom-right
                p.move(to: CGPoint(x: w - inset - length, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset - length))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Hero HUD panel: the existing frosted `cardSurface` + corner brackets.
    func hudPanel(_ fill: Color = Theme.surface1,
                  radius: CGFloat = Theme.radius,
                  glow: Bool = false) -> some View {
        self
            .cardSurface(fill, radius: radius, glow: glow)
            .overlay(CornerBrackets())
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
cd ios && xcodegen generate >/dev/null && cd .. && \
xcodebuild -project ios/Saetta.xcodeproj -scheme Saetta \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios/Sources/App/Theme+HUD.swift
git commit -m "feat(ios-ui): HUD chrome primitives — TickGrid, CornerBrackets, hudPanel"
```

---

## Task 3: Update `AmberCTAStyle` — leading glyph + contained glow

**Files:**
- Modify: `ios/Sources/App/Theme.swift` (the `AmberCTAStyle` struct, currently lines 92-107)

The radius already tightened automatically (it uses `Theme.radius`). This task adds the leading triangle glyph and tightens the glow so it reads "contained," not "bloomed."

- [ ] **Step 1: Replace the `makeBody` of `AmberCTAStyle`**

In `ios/Sources/App/Theme.swift`, replace the current `makeBody` body (lines 94-106) so the label is wrapped with a leading glyph and the shadow radius is reduced:

```swift
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowtriangle.right.fill").font(.system(size: 9, weight: .bold))
            configuration.label
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.aquaInk)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background {
            if dim { Theme.accentEnd.opacity(0.85) } else { Theme.accentGradient }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .shadow(color: Theme.accentSolid.opacity(dim ? 0.18 : 0.32), radius: dim ? 4 : 6, y: 1)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .opacity(configuration.isPressed ? 0.85 : 1)
    }
```

(Note: glyph color is inherited `Theme.aquaInk` via `foregroundStyle`; the contained glow is the smaller `radius` + lower opacity vs the previous `radius: 8`.)

- [ ] **Step 2: Build to verify it compiles**

```bash
cd ios && xcodegen generate >/dev/null && cd .. && \
xcodebuild -project ios/Saetta.xcodeproj -scheme Saetta \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios/Sources/App/Theme.swift
git commit -m "feat(ios-ui): AmberCTAStyle — leading glyph + contained glow"
```

---

## Task 4: Fixtures tab sweep (showcase)

**Files:**
- Modify: `ios/Sources/App/Fixture/FixtureControlView.swift`
- Modify: `ios/Sources/App/Fixture/JogFader.swift`
- Modify: `ios/Sources/App/Fixture/StoreSheets.swift`

### FixtureControlView.swift

- [ ] **Step 1: Frame the control stack with a HUD panel**

In `body`, the inner `VStack(spacing: 14) { selectionChip; categoryPicker; controlArea...; clearButton; storeBar }` (lines 58-64) is the hero panel. Add padding + `.hudPanel()` to it. Replace:

```swift
                    VStack(spacing: 14) {
                        selectionChip
                        categoryPicker
                        controlArea.frame(maxHeight: .infinity)
                        clearButton
                        storeBar
                    }
                    .disabled(!hub.state.isOnline)
                    .opacity(hub.state.isOnline ? 1 : 0.5)
```

with:

```swift
                    VStack(spacing: 14) {
                        selectionChip
                        categoryPicker
                        controlArea.frame(maxHeight: .infinity)
                        clearButton
                        storeBar
                    }
                    .padding(14)
                    .hudPanel()
                    .disabled(!hub.state.isOnline)
                    .opacity(hub.state.isOnline ? 1 : 0.5)
```

- [ ] **Step 2: Make the category bar monospace + uppercase + sharper**

In `categoryPicker` (lines 287-311), change the segment label font to mono and add `.hudLabel()`, and tighten the two hardcoded `cornerRadius: 7` / `cornerRadius: 9` literals. Replace the `Text(cat.rawValue)` styling line:

```swift
                    Text(cat.rawValue)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
```

with:

```swift
                    Text(cat.rawValue)
                        .font(Theme.mono(size: 12, weight: selected ? .semibold : .medium))
                        .hudLabel()
```

Then in the same view, change the selected-pill background `RoundedRectangle(cornerRadius: 7)` (both occurrences, lines 300-302) to `cornerRadius: Theme.radiusSmall`, and the outer container `RoundedRectangle(cornerRadius: 9)` (line 310) to `cornerRadius: Theme.radius`.

- [ ] **Step 3: Monospace the selection chip text**

In `selectionChip` (line 272), replace:

```swift
                    .font(.system(size: 16, weight: .semibold))
```

with:

```swift
                    .font(Theme.mono(size: 15, weight: .semibold))
```

- [ ] **Step 4: Restyle the Store / Update / Clear buttons**

In `storeBar` (lines 322-338), monospace + uppercase both labels and sharpen them. Replace the `Text("Store to Cue")...` label content:

```swift
                Text("Store to Cue").font(.system(size: 15, weight: .bold))
```

with:

```swift
                Text("Store to Cue").font(Theme.mono(size: 14, weight: .bold)).hudLabel()
```

and replace the `Text("Update Preset")...` label content:

```swift
                Text("Update Preset").font(.system(size: 15, weight: .semibold))
```

with:

```swift
                Text("Update Preset").font(Theme.mono(size: 14, weight: .semibold)).hudLabel()
```

In `clearButton` (line 315), replace:

```swift
            Text("Clear").font(.system(size: 15, weight: .semibold))
```

with:

```swift
            Text("Clear").font(Theme.mono(size: 14, weight: .semibold)).hudLabel()
```

(The red touched indicator logic in `categoryPicker` via `isTouched(cat) ? Theme.danger` stays exactly as-is — do not change it.)

### JogFader.swift

- [ ] **Step 5: Tick-grid the track + monospace the readouts + sharpen the track**

In `JogFader.body`, the track `ZStack` background (lines 34-35) is a `RoundedRectangle(cornerRadius: 14)`. Replace:

```swift
                    RoundedRectangle(cornerRadius: 14).fill(Theme.surface2)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 0.5))
```

with (sharper radius + tick-grid overlay clipped to the track shape):

```swift
                    RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface2)
                        .overlay(TickGrid().clipShape(RoundedRectangle(cornerRadius: Theme.radius)))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border, lineWidth: 0.5))
```

Then the moving grip `RoundedRectangle(cornerRadius: 11)` (line 40) → `RoundedRectangle(cornerRadius: Theme.radiusSmall)`.

Then the label + value readouts (lines 78-80). Replace:

```swift
            Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textDim)
            Text(valueText).font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.text)
```

with:

```swift
            Text(label).font(Theme.mono(size: 13, weight: .semibold)).hudLabel().foregroundStyle(Theme.textDim)
            Text(valueText).font(Theme.mono(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
```

### StoreSheets.swift

- [ ] **Step 6: Monospace the "Will store" preview values + group labels**

Open `ios/Sources/App/Fixture/StoreSheets.swift`. In the `StorePreview` view (and the `StoreGroup`/`StoredValue` rendering it contains), apply these two substitutions wherever they occur:

1. The numeric/value text (the `StoredValue.value` strings like `+12`) — change its `.font(...)` to `Theme.mono(size: 13, weight: .semibold)`.
2. The per-fixture group header (the `StoreGroup.selection` string, e.g. `101 thru 105`) — add `.font(Theme.mono(size: 13, weight: .bold))` and `.hudLabel()`.

If the file already uses `.monospacedDigit()` on those, replace the whole `.font(...)` modifier with the `Theme.mono(...)` form above. Leave the descriptive prose labels (sheet titles, "Will store" caption) in the existing proportional font — only the data readouts and the fixture-group headers go mono.

- [ ] **Step 7: Build to verify it compiles**

```bash
cd ios && xcodegen generate >/dev/null && cd .. && \
xcodebuild -project ios/Saetta.xcodeproj -scheme Saetta \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add ios/Sources/App/Fixture/FixtureControlView.swift ios/Sources/App/Fixture/JogFader.swift ios/Sources/App/Fixture/StoreSheets.swift
git commit -m "feat(ios-ui): Fixtures tab — HUD panel, mono readouts, tick-grid faders"
```

---

## Task 5: Live tab sweep

**Files:**
- Modify: `ios/Sources/App/LiveView.swift`

- [ ] **Step 1: Monospace the transport titles**

In the private `TransportButton` struct (lines 122-127), replace:

```swift
                Text(title).font(.system(size: 24, weight: .heavy))
```

with:

```swift
                Text(title).font(Theme.mono(size: 24, weight: .heavy)).hudLabel()
```

- [ ] **Step 2: Turn `connectionRow` into a bracketed HUD status readout**

In `LiveView.connectionRow` (lines 98-111), monospace the status text and frame the row with `.hudPanel()`. Replace:

```swift
                Text(hub.state.isOnline ? "Connected" : "Tap to connect")
                    .font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
            .contentShape(Rectangle())
```

with:

```swift
                Text(hub.state.isOnline ? "CONNECTED" : "TAP TO CONNECT")
                    .font(Theme.mono(size: 11, weight: .medium)).hudLabel().foregroundStyle(Theme.textDim)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .hudPanel()
            .contentShape(Rectangle())
```

- [ ] **Step 3: Bracket-frame the message field**

In `controlSection` (lines 56-77), the `TextField("Message to console…", ...)` uses `.background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))` (line 64). Replace that single `.background(...)` modifier with `.hudPanel()`:

```swift
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .hudPanel()
```

(Leave the `MacroPadView` call as-is — it is styled in its own file and out of scope for this task to avoid touching macro logic.)

- [ ] **Step 4: Build to verify it compiles**

```bash
cd ios && xcodegen generate >/dev/null && cd .. && \
xcodebuild -project ios/Saetta.xcodeproj -scheme Saetta \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/App/LiveView.swift
git commit -m "feat(ios-ui): Live tab — mono transport, HUD status readout + message field"
```

---

## Task 6: Program tab sweep

**Files:**
- Modify: `ios/Sources/App/RootView.swift`
- Modify: `ios/Sources/App/SeqField.swift`
- Modify: `ios/Sources/App/CueCardView.swift`

### RootView.swift

- [ ] **Step 1: Monospace the song title + cue count**

In `songMenu` (line 133), replace:

```swift
                Text(name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
```

with:

```swift
                Text(name).font(Theme.mono(size: 16, weight: .semibold)).hudLabel().foregroundStyle(Theme.text)
```

In `subbar` (lines 161-162), replace:

```swift
                Text("\(store.project.songs[i].cues.count) cue\(store.project.songs[i].cues.count == 1 ? "" : "s")")
                    .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
```

with:

```swift
                Text("\(store.project.songs[i].cues.count) cue\(store.project.songs[i].cues.count == 1 ? "" : "s")")
                    .font(Theme.mono(size: 11)).hudLabel().foregroundStyle(Theme.textFaint)
```

### SeqField.swift

- [ ] **Step 2: Monospace the Seq label + field, sharpen field corners**

In `SeqField.body` (lines 13-24), replace the "Seq" label line:

```swift
            Text("Seq").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
```

with:

```swift
            Text("Seq").font(Theme.mono(size: 13, weight: .semibold)).hudLabel().foregroundStyle(Theme.text)
```

and the `TextField` font (line 17):

```swift
                .font(.system(size: 18, weight: .bold).monospacedDigit())
```

with:

```swift
                .font(Theme.mono(size: 18, weight: .bold))
```

(The field's `cornerRadius: Theme.radiusSmall` already tightened via Task 1 — no change needed there.)

### CueCardView.swift

- [ ] **Step 3: Subtle corner brackets on the cue card + mono numerics**

Open `ios/Sources/App/CueCardView.swift`. Apply these substitutions:

1. **Card frame:** locate the card's outer container background — it will use either `.cardSurface(...)` or a `.background(..., in: RoundedRectangle(...))`. Add lightweight brackets by appending `.overlay(CornerBrackets(length: 10, lineWidth: 1.5))` to that outer container (lighter than the hero `length: 14, lineWidth: 2` default so cards in a list don't shout). If the card uses `.cardSurface(...)`, append the overlay right after it; do NOT swap it to `.hudPanel()` (that would use the heavy default brackets).
2. **Numeric readouts:** any cue-number / time / delay numeric `Text` using `.font(.system(...).monospacedDigit())` or a plain `.font(.system(size: N, ...))` on a number → change to `Theme.mono(size: N, weight: <same weight>)`.
3. **Field labels** (e.g. "Delay", "Fade", section captions): add `.hudLabel()` and switch their font to `Theme.mono(size: <same size>, weight: <same weight>)`.

Leave free-text content (cue names/notes the user typed) in the proportional font — only labels and numerics go mono. Do not touch `CueBadge` (it is intentionally circular and already mono-digit).

- [ ] **Step 4: Build to verify it compiles**

```bash
cd ios && xcodegen generate >/dev/null && cd .. && \
xcodebuild -project ios/Saetta.xcodeproj -scheme Saetta \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/App/RootView.swift ios/Sources/App/SeqField.swift ios/Sources/App/CueCardView.swift
git commit -m "feat(ios-ui): Program tab — mono song title/counts, cue-card brackets"
```

---

## Task 7: Send + Settings light touch

**Files:**
- Modify: `ios/Sources/App/SendView.swift`
- Modify: `ios/Sources/App/SettingsTabView.swift`
- Modify: `ios/Sources/App/SettingsView.swift`
- Modify: `ios/Sources/App/DefaultsView.swift`

These are dense/form screens — **no corner brackets**. Only: monospace numerics, uppercase tracked section labels, and the shared sharper radii (already global). The CTA restyle is already inherited via `AmberCTAStyle`.

- [ ] **Step 1: Sweep numerics + section labels in all four files**

For each of the four files, apply the same two substitution rules (read the file first, then apply):

1. **Numeric readouts** (counts, sequence numbers, ports, durations, version strings) — any `Text` rendering a number with `.font(.system(size: N, weight: W))` or `.monospacedDigit()` → `Theme.mono(size: N, weight: W)`.
2. **Section/row labels** that read as field captions or headers (short, non-sentence) — append `.hudLabel()` and switch to `Theme.mono(size: <same>, weight: <same>)`.

Do NOT change: sentence-case helper/description prose, navigation titles set via `.navigationTitle(...)`, button *actions*, or any `Toggle`/`Picker` *logic*. If a file has no numerics and no caption-style labels (pure prose form), it is acceptable to leave it unchanged — note that in the commit body.

- [ ] **Step 2: Build to verify it compiles**

```bash
cd ios && xcodegen generate >/dev/null && cd .. && \
xcodebuild -project ios/Saetta.xcodeproj -scheme Saetta \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios/Sources/App/SendView.swift ios/Sources/App/SettingsTabView.swift ios/Sources/App/SettingsView.swift ios/Sources/App/DefaultsView.swift
git commit -m "feat(ios-ui): Send + Settings — mono numerics & HUD labels (light touch)"
```

---

## Task 8: Final verification — regression tests, device build, eyeball

**Files:** none (verification only)

- [ ] **Step 1: Prove SaettaKit is untouched — run the 208 Kit tests**

```bash
cd ios && xcodegen generate >/dev/null && cd .. && \
xcodebuild -project ios/Saetta.xcodeproj -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -15
```

Expected: `** TEST SUCCEEDED **` with 208 tests passing (1 skip). If the named simulator doesn't exist, list available ones with `xcrun simctl list devices available | grep iPhone` and substitute the name.

- [ ] **Step 2: Device build (real-target compile + sign)**

```bash
xcodebuild -project ios/Saetta.xcodeproj -scheme Saetta \
  -destination 'platform=iOS,name=jPhone (2)' \
  -allowProvisioningUpdates build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. (If the device isn't connected, a `generic/platform=iOS` destination still proves the device-target compiles/signs.)

- [ ] **Step 3: Manual on-device eyeball (human)**

Install on jPhone (2) and walk all five tabs. Confirm each guardrail visually:
  - Numeric readouts are legible in the dark (mono face not too thin).
  - The red touched/programmer signal on the Fixtures category bar still reads as red.
  - Corner brackets render on Fixtures hero panel + Live status/message + cue cards (subtle), and are absent on Send/Settings forms.
  - Tighter radii didn't clip or break any layout; bottom Store/Clear bar still sits above the tab bar.
  - No accidental second hue anywhere; pale-amber capture/voice surfaces unchanged.

- [ ] **Step 4: Final summary commit (if any eyeball-driven tweaks were made)**

If Step 3 surfaced small tweaks, fix them and commit:

```bash
git add -A
git commit -m "fix(ios-ui): HUD restyle on-device polish"
```

If no tweaks were needed, skip this step — the work is already committed task-by-task.

---

## Self-review notes (author)

- **Spec coverage:** every spec primitive maps to a task — `Theme.mono`/radii/`hudLabel` → T1; `tickGridFill`(`TickGrid`)/`CornerBrackets`/`hudPanel` → T2; `AmberCTAStyle` → T3; per-tab application (Fixtures/Live/Program/Send/Settings) → T4–T7; testing + guardrail verification → T8.
- **Naming consistency:** spec's prose name `Theme.tickGridFill` is implemented as the `TickGrid` view (a view is the right SwiftUI primitive for a clipped overlay); `hudPanel`/`hudLabel`/`mono` names are identical across plan tasks and call sites.
- **Guardrails** restated at the top and verified in T8 Step 3. Red and pale-amber semantics are explicitly "do not change" in T4/elsewhere.
- **Placeholder check:** sweep tasks (T4 St6, T6 St3, T7 St1) describe substitutions over files not quoted line-for-line, but each gives the exact target font/modifier code and the precise rule — concrete, not "style appropriately." The executor reads the file then applies the named substitution.
