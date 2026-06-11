# Saetta Amber Aurora-Glass Restyle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reskin the Saetta iOS app to a dark, monochrome **amber** aurora-glass aesthetic, driven from `Theme.swift`, with status signalled by brightness/glyph (delete stays red) and a matching amber app icon.

**Architecture:** A thin presentation-layer change. `Theme.swift` is the single token+modifier hub every view consumes; reworking it propagates the palette. Leaf components (`CueBadge`, `Chip`, `LiveIndicator`, `StepperField`) and `SendBarView` get individual reskins. No Kit/model/logic changes. The app icon is recolored via the committed SVG generator.

**Tech Stack:** SwiftUI, xcodegen (`project.yml` → `CuelistCompiler.xcodeproj`), Python + headless Chrome for the icon.

**Working dir:** `~/cuelist-compiler-ios` on branch `feat/ios-ui-refresh`. **Do NOT touch `~/cuelist-compiler`** (the hub session lives there).

---

## Conventions used by every task

**App build (visual gate):**
```bash
cd ~/cuelist-compiler-ios/ios && xcodegen generate && \
xcodebuild build -project CuelistCompiler.xcodeproj -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: `** BUILD SUCCEEDED **`. If the named simulator is absent, run `xcrun simctl list devices available | grep iPhone` and substitute one.

**Kit tests (must stay green — logic is untouched, this guards against accidents):**
```bash
cd ~/cuelist-compiler-ios/ios && xcodebuild test -project CuelistCompiler.xcodeproj \
  -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: `** TEST SUCCEEDED **`.

There are no UI unit tests; visual correctness is verified by build success + eyeball in the simulator/device. "Eyeball" steps say exactly what to look for.

---

## File Structure

| File | Responsibility after this plan |
|---|---|
| `ios/Sources/App/Theme.swift` | Amber tokens, aurora canvas, frosted `cardSurface(glow:)`, `accentGlow()`, retuned status tokens |
| `ios/Sources/App/Components/CueBadge.swift` | Amber ring badge with glow |
| `ios/Sources/App/Components/Chip.swift` | Frosted amber-bordered pill |
| `ios/Sources/App/Components/LiveIndicator.swift` | Monochrome brightness-based connection signal |
| `ios/Sources/App/Components/StepperField.swift` | Amber tints (no change to logic) |
| `ios/Sources/App/SendBarView.swift` | Amber send button (dark text) + glass bar + monochrome result row |
| `ios/Sources/App/CueCardView.swift` | Glass card; trash stays red |
| `ios/Sources/App/RootView.swift` | Voice "stop" indicator → amber (not destructive) |
| `ios/Sources/App/{Settings,Defaults,PoolRow,CopyFromBar,ColorPickerPopover,VoicePreviewSheet}.swift` | Inherit via tokens; spot-checked |
| `ios/icon-design/AppIcon-1024.svg`, `final.py` | Amber-recolored icon source + generator |
| `ios/Sources/App/Assets.xcassets/AppIcon.appiconset/` | Regenerated amber 1024 asset |
| `ios/project.yml` | Adds `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` |

---

## Task 1: Theme foundation — amber tokens, aurora canvas, frosted surface

**Files:**
- Modify: `ios/Sources/App/Theme.swift` (whole file)

- [ ] **Step 1: Replace `Theme.swift` with the amber version**

```swift
import SwiftUI

/// Single source of truth for the dark "Amber Aurora-Glass" look.
/// Monochrome: one hue (amber) throughout. Status signals by brightness + glyph,
/// NOT by hue — the one exception is `danger` (red), reserved for destructive delete.
enum Theme {
    // Accent — single amber (gradient #f0b860 → #e0913f), solid fallback #eaa64f.
    static let accentStart = Color(hex: "#f0b860")!
    static let accentEnd   = Color(hex: "#e0913f")!
    static let accentSolid = Color(hex: "#eaa64f")!
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let accentTint = Color(hex: "#f0b860")!.opacity(0.12)   // group-card fill
    static let accentBorder = Color(hex: "#f0b860")!.opacity(0.22) // glass hairline

    // Surfaces / borders (white over the dark canvas).
    static let surface1 = Color.white.opacity(0.05)
    static let surface2 = Color.white.opacity(0.07)
    static let surface3 = Color.white.opacity(0.10)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.14)

    // Text hierarchy — warm off-whites.
    static let text = Color(hex: "#f6ead6")!
    static let textDim = Color(hex: "#c2a079")!
    static let textFaint = Color(hex: "#94795e")!

    // Status — monochrome amber by brightness; glyphs carry meaning.
    static let ok = Color(hex: "#f0c074")!     // bright amber — success / live
    static let warn = Color(hex: "#d49a4a")!   // mid amber — delay numerics / connecting
    static let danger = Color(hex: "#ff6b6b")! // RED — destructive delete ONLY

    // Radii.
    static let radius: CGFloat = 11
    static let radiusSmall: CGFloat = 7

    /// Full-screen amber aurora canvas. Radial blooms over a near-black base.
    static var canvas: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#1d160e")!, Color(hex: "#15110a")!, Color(hex: "#0f0c07")!],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: "#7a4f1e")!.opacity(0.55), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(hex: "#5c3a16")!.opacity(0.5), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Frosted glass card: material + warm highlight + amber-tinted hairline + soft glow.
    func cardSurface(_ fill: Color = Theme.surface1, radius: CGFloat = Theme.radius,
                     glow: Bool = false) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                    .blendMode(.plusLighter).opacity(0.4)
            )
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.accentBorder, lineWidth: 1))
            .shadow(color: Theme.accentSolid.opacity(glow ? 0.35 : 0.16), radius: glow ? 18 : 12, y: 8)
    }

    /// Soft amber bloom for hero elements (send button, live dot).
    func accentGlow(_ strength: Double = 0.5) -> some View {
        self.shadow(color: Theme.accentSolid.opacity(strength), radius: 14, y: 3)
            .shadow(color: Theme.accentEnd.opacity(strength * 0.6), radius: 30, y: 0)
    }
}
```

- [ ] **Step 2: Build (visual gate)**

Run the **App build** command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Eyeball in the simulator**

Launch the app (Xcode ▸ Run, or `xcodebuild ... -destination ... ` then open in Simulator). Expected: dark near-black canvas with warm amber glow in the top-left & bottom-right corners; all previously-violet chrome (send button, cue badges) now reads amber; text is warm off-white, not cool grey.

- [ ] **Step 4: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/Theme.swift && \
git commit -m "feat(ios-ui): amber aurora canvas + frosted glass tokens"
```

---

## Task 2: CueBadge — amber ring badge

**Files:**
- Modify: `ios/Sources/App/Components/CueBadge.swift` (whole file)

- [ ] **Step 1: Replace with the ring badge**

```swift
import SwiftUI

/// Circular amber ring badge showing a cue number.
struct CueBadge: View {
    let n: Double
    var body: some View {
        Text(n, format: .number)
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                Circle().fill(
                    AngularGradient(colors: [Theme.accentStart, Theme.accentEnd, Theme.accentStart],
                                    center: .center, angle: .degrees(220)))
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 4))
            .shadow(color: Theme.accentSolid.opacity(0.5), radius: 10, y: 2)
    }
}
```

- [ ] **Step 2: Build** — run the **App build** command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Eyeball** — a cue card's number badge is now a round amber ring with an inner translucent rim and soft glow.

- [ ] **Step 4: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/Components/CueBadge.swift && \
git commit -m "feat(ios-ui): amber ring cue badge"
```

---

## Task 3: Chip — frosted amber pill

**Files:**
- Modify: `ios/Sources/App/Components/Chip.swift` (whole file)

- [ ] **Step 1: Replace with the frosted pill**

```swift
import SwiftUI

/// Small frosted pill used in collapsed-cue summaries.
struct Chip: View {
    let text: String
    var tint: Color = Theme.textDim
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.accentBorder, lineWidth: 1))
    }
}
```

- [ ] **Step 2: Build** — run the **App build** command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Eyeball** — collapse a cue with groups; the summary chips are now frosted capsules with a faint amber border.

- [ ] **Step 4: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/Components/Chip.swift && \
git commit -m "feat(ios-ui): frosted amber chip"
```

---

## Task 4: LiveIndicator — monochrome brightness signal

**Files:**
- Modify: `ios/Sources/App/Components/LiveIndicator.swift` (whole file)

- [ ] **Step 1: Replace with brightness-based states (no green/red)**

```swift
import SwiftUI
import CuelistCompilerKit

/// Hub connection signal, monochrome amber by BRIGHTNESS (not hue):
/// offline = dim hollow dot, connecting = mid amber, online = full bright glowing dot.
/// Error reuses the dim treatment with the message text — no red here (red is delete-only).
struct LiveIndicator: View {
    let state: ConnectionState
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isOnline ? Theme.ok : dotColor.opacity(0.0))
                .overlay(Circle().strokeBorder(dotColor, lineWidth: state.isOnline ? 0 : 1.5))
                .frame(width: 8, height: 8)
                .shadow(color: Theme.ok.opacity(state.isOnline ? 0.9 : 0), radius: 5)
            Text(label).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(textColor)
    }
    private var dotColor: Color {
        switch state {
        case .offline: return Theme.textFaint
        case .connecting: return Theme.warn
        case .online: return Theme.ok
        case .error: return Theme.textDim
        }
    }
    private var textColor: Color { state.isOnline ? Theme.ok : Theme.textDim }
    private var label: String {
        switch state {
        case .offline: return "offline"
        case .connecting: return "connecting…"
        case .online: return "linked"
        case let .error(m): return m
        }
    }
}
```

> Note: relies on the existing `ConnectionState.isOnline`. If it does not exist, add a computed `var isOnline: Bool { if case .online = self { true } else { false } }` — but `SendBarView.swift` already uses `hub.state.isOnline`, so it exists on the hub client; confirm whether it's on `ConnectionState` or `HubClient`. If only on `HubClient`, replace `state.isOnline` here with an inline `if case .online = state`.

- [ ] **Step 2: Build** — run the **App build** command. Expected: `** BUILD SUCCEEDED **`. If it fails on `isOnline`, apply the note above and rebuild.

- [ ] **Step 3: Eyeball** — tap the live indicator to connect: offline shows a dim hollow ring + grey text; linked shows a solid glowing amber dot + amber "linked". No green anywhere.

- [ ] **Step 4: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/Components/LiveIndicator.swift && \
git commit -m "feat(ios-ui): monochrome brightness-based live indicator"
```

---

## Task 5: SendBarView — amber send button, glass bar, monochrome result

**Files:**
- Modify: `ios/Sources/App/SendBarView.swift` (3 edits)

- [ ] **Step 1: Send button — dark text on amber gradient + glow**

Replace the `Label("Send → MA", …)` modifier chain (currently `.foregroundStyle(.white)` + `.shadow(color: Theme.accentSolid.opacity(0.4), …)`):

```swift
                    Label("Send → MA", systemImage: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .foregroundStyle(Color(hex: "#0c0c14")!)
                        .accentGlow(0.55)
```

- [ ] **Step 2: Glass send bar — add amber tint + hairline over the existing material**

Replace the bar's bottom modifiers (currently `.background(.ultraThinMaterial)` + the top-edge `.overlay(Rectangle()…Theme.border…)`):

```swift
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .background(Theme.accentTint)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.accentBorder), alignment: .top)
```

- [ ] **Step 3: Monochrome result row — amber glyphs, no green/red**

In `resultRow`, replace the `.done` and `.failed` cases:

```swift
            case let .done(total):
                Label("Sent \(total) lines", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.ok)
            case let .failed(msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textDim)
```

(Success = bright amber `ok`; failure = the warning glyph + dimmed text. The glyph distinguishes them, not colour.)

- [ ] **Step 4: Build** — run the **App build** command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Eyeball** — the Send button is amber with near-black text and a soft bloom; the send bar has a faint warm tint + amber top hairline. (Send a cue if a hub is reachable to confirm the result row reads amber ✓ / dimmed ⚠.)

- [ ] **Step 6: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/SendBarView.swift && \
git commit -m "feat(ios-ui): amber glass send bar + monochrome result"
```

---

## Task 6: Status & stray-colour sweep

Migrate the remaining non-destructive status colours to the monochrome rule and confirm no stray violet literals remain. **Delete stays red.**

**Files:**
- Modify: `ios/Sources/App/RootView.swift:123` (voice stop indicator)
- Inspect (likely no change): `CueCardView.swift`, `PoolRowView.swift`, `VoicePreviewSheet.swift`, `StepperField.swift`

- [ ] **Step 1: RootView voice "stop" → amber (not destructive)**

At `ios/Sources/App/RootView.swift:123`, change the recording-stop glyph from red to bright amber:

```swift
            } label: { Image(systemName: "stop.circle.fill").foregroundStyle(Theme.ok) }
```

(Stopping a recording isn't destructive; red is reserved for delete.)

- [ ] **Step 2: Confirm delete stays red**

Verify `ios/Sources/App/CueCardView.swift:35` still uses `Theme.danger` for the trash icon. No change — this is the deliberate red exception.

- [ ] **Step 3: Grep for stray violet literals & old token assumptions**

```bash
cd ~/cuelist-compiler-ios/ios && grep -rn -iE '#7a5cff|#5e8bff|#6f78ff|\.green|\.red|Color\.blue|systemPurple' Sources/App/
```
Expected: **no matches**. Any hit that isn't inside a comment must be migrated to a `Theme.*` token. (`Theme.warn`/`Theme.ok`/`Theme.danger` references are fine — those are now amber/red tokens.)

- [ ] **Step 4: Build + Kit tests**

Run the **App build** command (expect `** BUILD SUCCEEDED **`), then the **Kit tests** command (expect `** TEST SUCCEEDED **`).

- [ ] **Step 5: Eyeball the remaining screens**

In the simulator, open: a cue's group block (PoolRow delay numerics read amber), Settings sheet, Defaults sheet, the color-picker popover, and the voice preview sheet. Expected: every surface is dark amber-glass, warm text, no leftover blue/violet/green; only the cue trash icon is red.

- [ ] **Step 6: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/RootView.swift && \
git commit -m "feat(ios-ui): monochrome status sweep (delete stays red)"
```

---

## Task 7: Amber app icon

Pull the committed icon source from `main` (this branch doesn't have it), recolor amber, regenerate, and wire it into the target.

**Files:**
- Add (from main): `ios/icon-design/*`, `ios/Sources/App/Assets.xcassets/AppIcon.appiconset/*`
- Modify: `ios/icon-design/final.py`
- Modify: `ios/project.yml`

- [ ] **Step 1: Bring the icon files onto this branch (paths only, no full merge)**

```bash
cd ~/cuelist-compiler-ios && \
git checkout main -- ios/icon-design ios/Sources/App/Assets.xcassets/AppIcon.appiconset && \
ls ios/icon-design && ls ios/Sources/App/Assets.xcassets/AppIcon.appiconset
```
Expected: lists `final.py`, `AppIcon-1024.svg`, `c1.svg`, … and `AppIcon-1024.png`, `Contents.json`.

- [ ] **Step 2: Recolor the generator to amber**

In `ios/icon-design/final.py`, change the three colour spots:
- `bg` gradient stops `#1b1e26 / #15171c / #111319` → `#1d160e / #15110a / #0f0c07`
- `acc` gradient stops `#7a5cff` / `#5e8bff` → `#f0b860` / `#e0913f`
- the bright glint line `stroke="#d7c9ff"` → `stroke="#ffe6c0"`

(Keep the bolt path and the blade-slice composition exactly — that's the approved C1 direction.)

- [ ] **Step 3: Regenerate the icon**

```bash
cd ~/cuelist-compiler-ios/ios/icon-design && python3 final.py
```
Expected: prints `AppIcon-1024 True` and `final-preview True`. Open `AppIcon-1024.png` — an **amber** glowing bolt on a warm-dark canvas, cut by the slice.

- [ ] **Step 4: Copy the regenerated 1024 into the asset catalog**

```bash
cd ~/cuelist-compiler-ios/ios && \
cp icon-design/AppIcon-1024.png Sources/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

- [ ] **Step 5: Wire the icon into the app target**

In `ios/project.yml`, under the `CuelistCompiler` application target's `settings:` (next to `DEVELOPMENT_TEAM`/`CODE_SIGN_STYLE`), add:

```yaml
    ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

If the application target has no `settings:` block of its own (only the top-level one), add one under the `CuelistCompiler:` application target.

- [ ] **Step 6: Build**

Run the **App build** command. Expected: `** BUILD SUCCEEDED **` with no "missing app icon" warning.

- [ ] **Step 7: Commit**

```bash
cd ~/cuelist-compiler-ios && \
git add ios/icon-design ios/Sources/App/Assets.xcassets/AppIcon.appiconset ios/project.yml && \
git commit -m "feat(ios-ui): amber app icon"
```

---

## Task 8: Device smoke + venue legibility + wrap

**Files:** none (verification only)

- [ ] **Step 1: Install on jPhone (2)**

Build for the device and install per `reference_ios_signing`:
```bash
cd ~/cuelist-compiler-ios/ios && xcodegen generate && \
xcodebuild -project CuelistCompiler.xcodeproj -scheme CuelistCompiler \
  -destination 'generic/platform=iOS' -derivedDataPath build-device build
# then locate the .app under build-device/Build/Products/Debug-iphoneos/ and:
xcrun devicectl device install app --device <jPhone-2-udid> \
  build-device/Build/Products/Debug-iphoneos/CuelistCompiler.app
```
Expected: app installs; amber bolt icon appears on the home screen (springboard refresh may lag).

- [ ] **Step 2: Eyeball on device**

Open each screen: cue list, expanded cue, send bar, settings, defaults, voice preview. Confirm amber-glass throughout, red only on delete, brightness-based live dot.

- [ ] **Step 3: Venue legibility check**

Drop the phone to ~20% brightness. Confirm cue names, badges, and the live/send state are still clearly readable — the glass borders should keep panel edges defined. If anything washes out, note it (a follow-up may bump `Theme.accentBorder` opacity or panel fill); do not block the commit.

- [ ] **Step 4: Final Kit-test confirmation**

Run the **Kit tests** command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Done**

No new commit (verification only). The restyle is complete on `feat/ios-ui-refresh`. Hand back for PR decision (the user will choose merge/PR; the hub session is unaffected).

---

## Self-review notes

- **Spec coverage:** amber tokens (T1), aurora canvas (T1), frosted glass (T1), ring badge (T2), frosted chip (T3), monochrome live status (T4), amber send button + glass bar + monochrome result (T5), delete-stays-red + stray-colour sweep (T6), amber icon (T7), device + venue verification (T8). Non-goals (no fake meters, native segmented picker, no desktop change) are respected — no task adds them.
- **Status exception:** `Theme.danger` red is referenced only at `CueCardView.swift:35` (delete) after T6; `RootView` stop becomes amber.
- **Branch isolation:** every command targets `~/cuelist-compiler-ios`; `git checkout main -- <paths>` in T7 reads from main without merging or touching `~/cuelist-compiler`.
- **Risk flagged in spec (legibility):** verified explicitly in T8 Step 3.
