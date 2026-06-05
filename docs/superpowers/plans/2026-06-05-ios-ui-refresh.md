# iOS UI Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the native iOS app into a slick, dark, Apple-grade authoring tool that mirrors the desktop "Tinted Vibrancy" design tokens (violet→blue gradient accent, green=live), with an inline-expand interaction model for cues and presets.

**Architecture:** Presentation-only. A new `Theme.swift` token layer + small reusable SwiftUI components (`Components/`) are added; every existing view in `ios/Sources/App/` is restyled to compose them. No file under `ios/Sources/Kit/` is touched — all 92 Kit tests stay green and the frozen hub-protocol / project-JSON contracts are untouched.

**Tech Stack:** SwiftUI (iOS 17+, `@Observable`), xcodegen project, xcodebuild for the iPhone 17 Pro simulator.

---

## Conventions used by every task

- **Worktree:** all work happens in `~/cuelist-compiler-ios` (branch `feat/ios-ui-refresh`). Do NOT touch `~/cuelist-compiler` (a parallel session holds it on `feat/desktop-ui-vibrancy`).
- **Build gate (run after every code change):**
  ```bash
  cd ~/cuelist-compiler-ios/ios && xcodegen generate >/dev/null && \
  xcodebuild -scheme CuelistCompiler \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -4
  ```
  Expected last line: `** BUILD SUCCEEDED **`
  (`xcodegen generate` is mandatory first — the app target globs the `Sources/App` folder, so new/deleted files only register after regeneration.)
- **Kit regression gate (run in Tasks 1 and 9):**
  ```bash
  cd ~/cuelist-compiler-ios/ios && xcodebuild -scheme CuelistCompilerKit \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -8
  ```
  Expected: `** TEST SUCCEEDED **` — 92 tests, 0 failures (1 expected skip: the Keychain round-trip).
- **No unit tests for SwiftUI views** — this project does not unit-test the App layer (confirmed: `ios/Tests/KitTests` only). The per-task gate is therefore *build succeeds + Kit tests stay green*; visual correctness is judged on-device in Task 10. This replaces the usual write-failing-test step for view work.
- **Kit APIs are fixed.** Reference only these (verified):
  - `ProjectStore`: `project`, `defaults`, `activeSong`, `addSong()`, `setActiveSong(_ id:String)`, `removeSong(id:String)`, `addCue()`, `removeCue(id:UUID)`, `addActionBlock(cueId:UUID)`, `removeActionBlock(cueId:UUID, at:Int)`, `copyActions(fromCueId:toCueId:)`, `apply(_:)`.
  - `Cue`: `id:UUID, n:Double, name, fade, delay, position, collapsed:Bool, actions:[Action]`.
  - `Action`: `id:UUID, group:String, color:String, presets:[Pool:Preset]` (always all 6 pools present).
  - `Preset`: `name, fade, delay` (all `String`).
  - `Pool`: `.allCases`, `.abbreviation` (`"COL"`…), `.accentHex` (`"#c44d8f"`…), `.rawValue`.
  - `Defaults`: `fade(_ pool:Pool)->String`, `delay(_ pool:Pool)->String`, `values[Pool]`.
  - `HubClient`: `state:ConnectionState (.offline/.connecting/.online/.error(String))`, `state.isOnline`, `progress:SendProgress?(.sent,.total)`, `lastResult:SendResult?(.done(total:)/.failed(String))`, `host`, `port`, `connect()`, `send(project:defaults:selection:)` with `selection: .current`/`.all`.
  - `VoiceCaptureController`: `phase:Phase (.idle/.recording/.transcribing/.interpreting/.preview/.error(String))`, `pending:Pending?`, `startRecording()`, `stopAndProcess(project:defaults:)`, `cancel()`. `Pending` has `transcript, summary:[String], warnings:[String], clarification:String?, result, canApply`.
  - `Color(hex:)` from `Color+Hex.swift` returns `Color?` (force-unwrap on the literal token hexes below is safe — they are all valid 6-digit).

---

## File Structure

| File | Responsibility |
|---|---|
| `ios/Sources/App/Theme.swift` | **new** — all design tokens (colors, gradient, radii) + canvas background + shared text styles |
| `ios/Sources/App/Components/CueBadge.swift` | **new** — gradient cue-number badge |
| `ios/Sources/App/Components/Chip.swift` | **new** — summary pill |
| `ios/Sources/App/Components/LiveIndicator.swift` | **new** — hub-state dot+label (green=online) |
| `ios/Sources/App/Components/StepperField.swift` | **new** — −/value/+ numeric field bound to a `String` |
| `ios/Sources/App/Components/AddChips.swift` | **new** — dashed `＋POOL` chips for empty pools |
| `ios/Sources/App/App.swift` | dark scheme + accent tint |
| `ios/Sources/App/RootView.swift` | dark scaffold; nav-title song **Menu** + rename alert; slim subbar; restyled mic |
| `ios/Sources/App/SongBarView.swift` | **deleted** — folded into RootView |
| `ios/Sources/App/SendBarView.swift` | `LiveIndicator` + segmented store + gradient Send/All + restyled progress/result |
| `ios/Sources/App/PoolRowView.swift` | tappable pool row + inline `PoolEditor` |
| `ios/Sources/App/ActionBlockView.swift` | group card: accent bar, name, color swatch, set-pool rows + `AddChips` |
| `ios/Sources/App/CueCardView.swift` | inline-expand cue card; collapsed chip summary |
| `ios/Sources/App/CueListView.swift` | dark scroll, empty state, add-cue |
| `ios/Sources/App/SettingsView.swift` | dark restyle (no logic change) |
| `ios/Sources/App/DefaultsView.swift` | dark restyle (no logic change) |
| `ios/Sources/App/ColorPickerPopover.swift` | dark restyle |
| `ios/Sources/App/CopyFromBar.swift` | restyle label |
| `ios/Sources/App/VoicePreviewSheet.swift` | dark restyle |

---

### Task 1: Design tokens (`Theme.swift`)

**Files:**
- Create: `ios/Sources/App/Theme.swift`

- [ ] **Step 1: Establish the green baseline** — run the Kit regression gate (above) and confirm `** TEST SUCCEEDED **`, 92 tests. This proves the starting tree is healthy before any view change.

- [ ] **Step 2: Create `Theme.swift`** with the desktop-mirrored tokens:

```swift
import SwiftUI

/// Single source of truth for the dark "Tinted Vibrancy" look.
/// Values mirror the desktop's committed `web/css/styles.css :root` tokens
/// so iOS and desktop read as one product. If the desktop retunes, re-sync here.
enum Theme {
    // Accent — violet→blue gradient (#7a5cff → #5e8bff), solid fallback #6f78ff.
    static let accentStart = Color(hex: "#7a5cff")!
    static let accentEnd   = Color(hex: "#5e8bff")!
    static let accentSolid = Color(hex: "#6f78ff")!
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let accentTint = Color(hex: "#7a5cff")!.opacity(0.12)   // group-card fill

    // Surfaces / borders (white over the dark canvas).
    static let surface1 = Color.white.opacity(0.045)
    static let surface2 = Color.white.opacity(0.06)
    static let surface3 = Color.white.opacity(0.09)
    static let border = Color.white.opacity(0.075)
    static let borderStrong = Color.white.opacity(0.14)

    // Text hierarchy.
    static let text = Color(hex: "#e9eaf0")!
    static let textDim = Color(hex: "#9a9eaa")!
    static let textFaint = Color(hex: "#7c8090")!

    // Semantic signals.
    static let ok = Color(hex: "#5fe08a")!            // live / online
    static let warn = Color(hex: "#f0b850")!          // delay numerics / connecting
    static let danger = Color(hex: "#ff6b6b")!        // destructive / error

    // Radii.
    static let radius: CGFloat = 11
    static let radiusSmall: CGFloat = 7

    /// Full-screen app canvas (radial dark gradient). Use as a background.
    static var canvas: some View {
        LinearGradient(colors: [Color(hex: "#1b1e26")!, Color(hex: "#15171c")!, Color(hex: "#111319")!],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

extension View {
    /// Standard translucent card: surface fill + hairline border + radius.
    func cardSurface(_ fill: Color = Theme.surface1, radius: CGFloat = Theme.radius) -> some View {
        self.background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.border, lineWidth: 0.5))
    }
}
```

- [ ] **Step 3: Build** — run the build gate. Expected `** BUILD SUCCEEDED **` (the file compiles even though nothing uses it yet).

- [ ] **Step 4: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/Theme.swift && \
git commit -m "feat(ios-ui): add Theme design tokens mirroring desktop vibrancy"
```

---

### Task 2: Atom components

**Files:**
- Create: `ios/Sources/App/Components/CueBadge.swift`, `Chip.swift`, `LiveIndicator.swift`, `StepperField.swift`, `AddChips.swift`

- [ ] **Step 1: `CueBadge.swift`**

```swift
import SwiftUI

/// Gradient rounded badge showing a cue number.
struct CueBadge: View {
    let n: Double
    var body: some View {
        Text(n, format: .number)
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .shadow(color: Theme.accentSolid.opacity(0.45), radius: 8, y: 2)
    }
}
```

- [ ] **Step 2: `Chip.swift`**

```swift
import SwiftUI

/// Small pill used in collapsed-cue summaries.
struct Chip: View {
    let text: String
    var tint: Color = Theme.text
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}
```

- [ ] **Step 3: `LiveIndicator.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

/// Hub connection signal: green dot = online ("linked"), amber = connecting,
/// red = error, faint = offline. Mirrors desktop's --ok green.
struct LiveIndicator: View {
    let state: ConnectionState
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.9), radius: 5)
            Text(label).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(color)
    }
    private var color: Color {
        switch state {
        case .offline: return Theme.textFaint
        case .connecting: return Theme.warn
        case .online: return Theme.ok
        case .error: return Theme.danger
        }
    }
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

- [ ] **Step 4: `StepperField.swift`**

```swift
import SwiftUI

/// A −/value/+ control bound to a String (fade/delay are Strings in the model).
/// Buttons bump by 0.5 and clamp at 0; the field also accepts direct decimal entry.
struct StepperField: View {
    let label: String
    @Binding var value: String
    var placeholder: String = ""
    var tint: Color = Theme.accentSolid

    private func bump(_ delta: Double) {
        let base = Double(value) ?? Double(placeholder) ?? 0
        let next = max(0, base + delta)
        value = next == next.rounded() ? String(Int(next)) : String(next)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textDim)
            HStack(spacing: 0) {
                Button { bump(-0.5) } label: {
                    Image(systemName: "minus").frame(width: 30, height: 30)
                }.buttonStyle(.plain).foregroundStyle(Theme.accentSolid)
                TextField(placeholder, text: $value)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(tint)
                    .frame(width: 46)
                Button { bump(0.5) } label: {
                    Image(systemName: "plus").frame(width: 30, height: 30)
                }.buttonStyle(.plain).foregroundStyle(Theme.accentSolid)
            }
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.borderStrong, lineWidth: 1))
        }
    }
}
```

- [ ] **Step 5: `AddChips.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

/// Dashed "＋POOL" chips for pools that are not yet shown. Tapping one reveals it.
struct AddChips: View {
    let pools: [Pool]
    let onAdd: (Pool) -> Void
    var body: some View {
        if !pools.isEmpty {
            HStack(spacing: 6) {
                ForEach(pools, id: \.self) { pool in
                    Button { onAdd(pool) } label: {
                        Text("＋ \(pool.abbreviation)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                    .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [3]))
                            )
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
```

- [ ] **Step 6: Build** — run the build gate. Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/Components && \
git commit -m "feat(ios-ui): add atom components (badge, chip, live, stepper, add-chips)"
```

---

### Task 3: App scheme + RootView scaffold (folds in SongBar)

**Files:**
- Modify: `ios/Sources/App/App.swift`
- Modify: `ios/Sources/App/RootView.swift`
- Delete: `ios/Sources/App/SongBarView.swift`

- [ ] **Step 1: Force dark + accent tint in `App.swift`** — change only the `RootView()` modifiers; leave the `@State` setup and `onChange` untouched:

Replace the `WindowGroup { ... }` body's `RootView()` chain with:

```swift
            RootView()
                .environment(store)
                .environment(hub)
                .environment(voice)
                .tint(Theme.accentSolid)
                .preferredColorScheme(.dark)
                .onAppear { if !hub.host.isEmpty { hub.connect() } }
```

- [ ] **Step 2: Delete `SongBarView.swift`**

```bash
rm ~/cuelist-compiler-ios/ios/Sources/App/SongBarView.swift
```

- [ ] **Step 3: Rewrite `RootView.swift`** — dark canvas, nav-title song Menu + rename alert, slim subbar (seq stepper + cue count), restyled mic. Full file:

```swift
import SwiftUI
import CuelistCompilerKit

struct RootView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(VoiceCaptureController.self) private var voice
    @State private var showSettings = false
    @State private var showDefaults = false
    @State private var showRename = false
    @State private var renameText = ""

    private var activeIndex: Int? {
        store.project.songs.firstIndex(where: { $0.id == store.project.activeSongId })
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 0) {
                    subbar
                    CueListView()
                    SendBarView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { micButton }
                ToolbarItem(placement: .principal) { songMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Defaults…") { showDefaults = true }
                        Button("Settings…") { showSettings = true }
                    } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showDefaults) { DefaultsView() }
            .sheet(isPresented: previewBinding) {
                if let pending = voice.pending {
                    VoicePreviewSheet(
                        pending: pending,
                        onApply: { store.apply(pending.result); voice.cancel() },
                        onDiscard: { voice.cancel() }
                    )
                }
            }
            .alert("Voice", isPresented: errorBinding) {
                Button("OK") { voice.cancel() }
            } message: { Text(errorText) }
            .alert("Rename song", isPresented: $showRename) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let i = activeIndex { store.project.songs[i].name = renameText }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: Song menu (in nav title)

    @ViewBuilder private var songMenu: some View {
        let name = store.activeSong.name.isEmpty ? "(untitled)" : store.activeSong.name
        Menu {
            ForEach(store.project.songs) { song in
                Button {
                    store.setActiveSong(song.id)
                } label: {
                    Label(song.name.isEmpty ? "(untitled)" : song.name,
                          systemImage: song.id == store.project.activeSongId ? "checkmark" : "music.note")
                }
            }
            Divider()
            Button("New Song") { store.addSong() }
            Button("Rename…") {
                renameText = store.activeSong.name; showRename = true
            }
            if store.project.songs.count > 1 {
                Button("Remove \u{201C}\(name)\u{201D}", role: .destructive) {
                    store.removeSong(id: store.project.activeSongId)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Theme.accentSolid)
            }
        }
    }

    // MARK: Slim subbar (seq + cue count)

    @ViewBuilder private var subbar: some View {
        @Bindable var store = store
        if let i = activeIndex {
            HStack(spacing: 10) {
                Stepper(value: $store.project.songs[i].sequence, in: 1...9999) {
                    Text("Seq \(store.project.songs[i].sequence)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textDim)
                }
                .fixedSize()
                Spacer()
                Text("\(store.project.songs[i].cues.count) cue\(store.project.songs[i].cues.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }

    // MARK: Mic

    @ViewBuilder private var micButton: some View {
        switch voice.phase {
        case .idle, .error:
            Button { Task { await voice.startRecording() } } label: { Image(systemName: "mic") }
        case .recording:
            Button {
                Task { await voice.stopAndProcess(project: store.project, defaults: store.defaults) }
            } label: { Image(systemName: "stop.circle.fill").foregroundStyle(Theme.danger) }
        case .transcribing, .interpreting:
            ProgressView()
        case .preview:
            Image(systemName: "mic").foregroundStyle(Theme.textFaint)
        }
    }

    private var previewBinding: Binding<Bool> {
        Binding(get: { if case .preview = voice.phase { return true } else { return false } },
                set: { if !$0 { voice.cancel() } })
    }
    private var errorBinding: Binding<Bool> {
        Binding(get: { if case .error = voice.phase { return true } else { return false } },
                set: { if !$0 { voice.cancel() } })
    }
    private var errorText: String {
        if case let .error(m) = voice.phase { return m } else { return "" }
    }
}
```

- [ ] **Step 4: Build** — run the build gate. Expected `** BUILD SUCCEEDED **`. (`xcodegen generate` drops the deleted `SongBarView` and registers nothing new; CueListView/SendBarView are still their old selves and compile.)

- [ ] **Step 5: Commit**

```bash
cd ~/cuelist-compiler-ios && git add -A ios/Sources/App && \
git commit -m "feat(ios-ui): dark scaffold + nav-title song menu, fold out SongBarView"
```

---

### Task 4: SendBarView restyle

**Files:**
- Modify: `ios/Sources/App/SendBarView.swift` (full rewrite)

- [ ] **Step 1: Rewrite `SendBarView.swift`** — `LiveIndicator`, segmented store mode, gradient Send/All, restyled progress/result. Full file:

```swift
import SwiftUI
import CuelistCompilerKit

struct SendBarView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(HubClient.self) private var hub

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 8) {
            HStack {
                Button { hub.connect() } label: { LiveIndicator(state: hub.state) }
                    .buttonStyle(.plain)
                Spacer()
                Picker("Store", selection: $store.project.storeMode) {
                    ForEach(StoreMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            HStack(spacing: 10) {
                Button {
                    hub.send(project: store.project, defaults: store.defaults, selection: .current)
                } label: {
                    Label("Send → MA", systemImage: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .foregroundStyle(.white)
                        .shadow(color: Theme.accentSolid.opacity(0.4), radius: 12, y: 3)
                }
                Button {
                    hub.send(project: store.project, defaults: store.defaults, selection: .all)
                } label: {
                    Text("All")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.vertical, 11).padding(.horizontal, 18)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .foregroundStyle(Theme.text)
                }
            }
            .buttonStyle(.plain)
            .disabled(!hub.state.isOnline)
            .opacity(hub.state.isOnline ? 1 : 0.5)

            resultRow
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.border), alignment: .top)
    }

    @ViewBuilder private var resultRow: some View {
        if let p = hub.progress {
            VStack(spacing: 4) {
                ProgressView(value: Double(p.sent), total: Double(max(1, p.total))).tint(Theme.accentSolid)
                Text("sending \(p.sent)/\(p.total)…").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
        } else if let result = hub.lastResult {
            switch result {
            case let .done(total):
                Label("Sent \(total) lines", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.ok)
            case let .failed(msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.danger)
            }
        }
    }
}
```

- [ ] **Step 2: Build** — run the build gate. Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/SendBarView.swift && \
git commit -m "feat(ios-ui): restyle send bar — live indicator + gradient send"
```

---

### Task 5: PoolRow + inline PoolEditor

**Files:**
- Modify: `ios/Sources/App/PoolRowView.swift` (full rewrite — keeps init signature `(pool:Pool, action:Binding<Action>)` so `ActionBlockView` still compiles)

- [ ] **Step 1: Rewrite `PoolRowView.swift`** — tappable row that expands an inline editor. Full file:

```swift
import SwiftUI
import CuelistCompilerKit

struct PoolRowView: View {
    @Environment(ProjectStore.self) private var store
    let pool: Pool
    @Binding var action: Action
    @State private var expanded = false

    private var preset: Binding<Preset> {
        Binding(get: { action.presets[pool] ?? Preset() },
                set: { action.presets[pool] = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(Color(hex: pool.accentHex) ?? .gray).frame(width: 8, height: 8)
                    Text(pool.abbreviation)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.text).frame(width: 32, alignment: .leading)
                    Text(preset.wrappedValue.name.isEmpty ? "—" : preset.wrappedValue.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(preset.wrappedValue.name.isEmpty ? Theme.textFaint : Theme.text)
                        .lineLimit(1)
                    Spacer()
                    fadeDelayLabel
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(Theme.textFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                editor.padding(.top, 8)
            }
        }
        .padding(.vertical, 9)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Theme.border), alignment: .top)
    }

    // Compact fade/delay readout: fade in accent, delay in warn. Falls back to the
    // per-pool default (shown dimmed) when the preset's own value is blank.
    @ViewBuilder private var fadeDelayLabel: some View {
        let f = preset.wrappedValue.fade
        let d = preset.wrappedValue.delay
        let fShown = f.isEmpty ? store.defaults.fade(pool) : f
        let dShown = d.isEmpty ? store.defaults.delay(pool) : d
        if !fShown.isEmpty || !dShown.isEmpty {
            HStack(spacing: 3) {
                Text(fShown.isEmpty ? "–" : fShown)
                    .foregroundStyle(f.isEmpty ? Theme.accentSolid.opacity(0.45) : Theme.accentSolid)
                Text("/").foregroundStyle(Theme.textFaint)
                Text(dShown.isEmpty ? "–" : dShown)
                    .foregroundStyle(d.isEmpty ? Theme.warn.opacity(0.45) : Theme.warn)
            }
            .font(.system(size: 11).monospacedDigit())
        }
    }

    private var editor: some View {
        VStack(spacing: 8) {
            TextField("preset name", text: preset.name)
                .font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.border, lineWidth: 0.5))
                .autocorrectionDisabled()
            HStack(spacing: 14) {
                StepperField(label: "Fade", value: preset.fade,
                             placeholder: store.defaults.fade(pool), tint: Theme.accentSolid)
                StepperField(label: "Delay", value: preset.delay,
                             placeholder: store.defaults.delay(pool), tint: Theme.warn)
                Spacer()
            }
        }
    }
}
```

- [ ] **Step 2: Build** — run the build gate. Expected `** BUILD SUCCEEDED **`. (Old `ActionBlockView` still calls `PoolRowView(pool:action:)` for all 6 pools — compiles and renders the new row style.)

- [ ] **Step 3: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/PoolRowView.swift && \
git commit -m "feat(ios-ui): tappable pool row with inline preset editor"
```

---

### Task 6: GroupCard (ActionBlockView) — set pools + add-chips

**Files:**
- Modify: `ios/Sources/App/ActionBlockView.swift` (full rewrite — keeps init signature `(cue:Binding<Cue>, action:Binding<Action>)`)

- [ ] **Step 1: Rewrite `ActionBlockView.swift`** — accent-bar card; show only set pools as rows; empty pools become `AddChips`; tracks which empties were revealed this session in local `@State`. Full file:

```swift
import SwiftUI
import CuelistCompilerKit

struct ActionBlockView: View {
    @Environment(ProjectStore.self) private var store
    @Binding var cue: Cue
    @Binding var action: Action
    @State private var showColors = false
    @State private var revealed: Set<Pool> = []

    private var blockIndex: Int? { cue.actions.firstIndex(where: { $0.id == action.id }) }

    private func isEmpty(_ pool: Pool) -> Bool {
        let p = action.presets[pool] ?? Preset()
        return p.name.trimmingCharacters(in: .whitespaces).isEmpty
            && p.fade.trimmingCharacters(in: .whitespaces).isEmpty
            && p.delay.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Shown rows = pools with content OR explicitly revealed this session, in canonical order.
    private var shownPools: [Pool] { Pool.allCases.filter { !isEmpty($0) || revealed.contains($0) } }
    private var emptyPools: [Pool] { Pool.allCases.filter { isEmpty($0) && !revealed.contains($0) } }

    private var accent: Color { Color(hex: action.color) ?? Theme.accentSolid }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button { showColors = true } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: action.color) ?? Theme.surface3)
                        .frame(width: 14, height: 14)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border, lineWidth: 1))
                }
                .popover(isPresented: $showColors) { ColorPickerPopover(selection: $action.color) }

                TextField("Group name", text: $action.group)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .autocorrectionDisabled()

                Button {
                    if let i = blockIndex { store.removeActionBlock(cueId: cue.id, at: i) }
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textFaint) }
                .buttonStyle(.plain)
            }

            ForEach(shownPools, id: \.self) { pool in
                PoolRowView(pool: pool, action: $action)
            }

            AddChips(pools: emptyPools) { pool in
                withAnimation(.snappy(duration: 0.18)) { revealed.insert(pool) }
            }
            .padding(.top, 8)
        }
        .padding(11)
        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(
            HStack { Rectangle().fill(accent).frame(width: 3); Spacer() }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}
```

- [ ] **Step 2: Build** — run the build gate. Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/ActionBlockView.swift && \
git commit -m "feat(ios-ui): group card — set-pool rows + dashed add-chips"
```

---

### Task 7: CueCardView — inline expand + collapsed chip summary

**Files:**
- Modify: `ios/Sources/App/CueCardView.swift` (full rewrite — keeps init signature `(cue:Binding<Cue>)`)

- [ ] **Step 1: Rewrite `CueCardView.swift`** — `CueBadge` + name; collapsed → group-name `Chip`s + muted preset count; expanded → `CopyFromBar` + `ActionBlockView`s + Add group + cue fade/delay. Full file:

```swift
import SwiftUI
import CuelistCompilerKit

struct CueCardView: View {
    @Environment(ProjectStore.self) private var store
    @Binding var cue: Cue

    private var groupChips: [String] {
        cue.actions.map { $0.group.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var presetCount: Int {
        cue.actions.reduce(0) { acc, a in
            acc + Pool.allCases.filter { pool in
                let p = a.presets[pool] ?? Preset()
                return !p.name.trimmingCharacters(in: .whitespaces).isEmpty
            }.count
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { cue.collapsed.toggle() }
            } label: {
                HStack(spacing: 11) {
                    CueBadge(n: cue.n)
                    TextField("Cue name", text: $cue.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .autocorrectionDisabled()
                        .disabled(cue.collapsed)            // tap toggles when collapsed
                    Spacer(minLength: 4)
                    Button(role: .destructive) {
                        store.removeCue(id: cue.id)
                    } label: { Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Theme.danger) }
                    .buttonStyle(.plain)
                    Image(systemName: cue.collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption).foregroundStyle(Theme.textFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if cue.collapsed {
                if !groupChips.isEmpty || presetCount > 0 {
                    HStack(spacing: 7) {
                        ForEach(Array(groupChips.prefix(3).enumerated()), id: \.offset) { _, g in Chip(text: g) }
                        if presetCount > 0 {
                            Text("\(presetCount) preset\(presetCount == 1 ? "" : "s")")
                                .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                        }
                    }
                }
            } else {
                CopyFromBar(cue: $cue)
                ForEach($cue.actions) { $action in
                    ActionBlockView(cue: $cue, action: $action)
                }
                Button { store.addActionBlock(cueId: cue.id) } label: {
                    Label("Add group", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accentSolid)
                }
                .buttonStyle(.plain)

                HStack(spacing: 14) {
                    StepperField(label: "Fade", value: $cue.fade, tint: Theme.accentSolid)
                    StepperField(label: "Delay", value: $cue.delay, tint: Theme.warn)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(13)
        .cardSurface()
    }
}
```

- [ ] **Step 2: Build** — run the build gate. Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/CueCardView.swift && \
git commit -m "feat(ios-ui): inline-expand cue card with collapsed chip summary"
```

---

### Task 8: CueListView — dark scroll, empty state, add cue

**Files:**
- Modify: `ios/Sources/App/CueListView.swift` (full rewrite)

- [ ] **Step 1: Rewrite `CueListView.swift`**. Full file:

```swift
import SwiftUI
import CuelistCompilerKit

struct CueListView: View {
    @Environment(ProjectStore.self) private var store

    private var activeIndex: Int? {
        store.project.songs.firstIndex(where: { $0.id == store.project.activeSongId })
    }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            if let i = activeIndex {
                if store.project.songs[i].cues.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.largeTitle).foregroundStyle(Theme.textFaint)
                        Text("No cues yet")
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textDim)
                        Text("Tap “Add Cue” to start.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    LazyVStack(spacing: 11) {
                        ForEach($store.project.songs[i].cues) { $cue in
                            CueCardView(cue: $cue)
                        }
                    }
                    .padding(.horizontal, 14).padding(.top, 6)
                }

                Button { store.addCue() } label: {
                    Label("Add Cue", systemImage: "plus")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accentSolid)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14).padding(.bottom, 8)
            }
        }
        .scrollContentBackground(.hidden)
    }
}
```

- [ ] **Step 2: Build** — run the build gate. Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App/CueListView.swift && \
git commit -m "feat(ios-ui): dark cue list with styled empty state"
```

---

### Task 9: Secondary surfaces — sheets, popover, copy bar, voice preview

**Files:**
- Modify: `ios/Sources/App/SettingsView.swift`, `DefaultsView.swift`, `ColorPickerPopover.swift`, `CopyFromBar.swift`, `VoicePreviewSheet.swift`

These keep ALL their logic; only presentation changes. `Form`/`List` sheets get a dark scroll background and accent tint.

- [ ] **Step 1: `CopyFromBar.swift`** — restyle the label only (logic unchanged). Replace the `label:` of the `Menu` with:

```swift
            } label: {
                Label("Copy from cue…", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accentSolid)
            }
```

(Leave the `sources` computed property and `Menu { ForEach… }` body exactly as-is.)

- [ ] **Step 2: `ColorPickerPopover.swift`** — give the popover a dark background. Change the `.padding()` line of `body` to:

```swift
        .padding()
        .background(Theme.surface3)
        .presentationCompactAdaptation(.popover)
```

And in `swatch(hex:isNone:)`, change the none-swatch fill `Color(.systemGray4)` → `Theme.surface3` and the selected stroke `.primary` → `Theme.accentSolid`.

- [ ] **Step 3: `DefaultsView.swift`** — dark Form. After the `Form { … }` closing brace's `.navigationTitle("Defaults")` line, add:

```swift
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .tint(Theme.accentSolid)
```

(Logic and bindings unchanged.)

- [ ] **Step 4: `SettingsView.swift`** — same dark Form treatment. After `.navigationTitle("Settings")` add:

```swift
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .tint(Theme.accentSolid)
```

(Hub/key logic unchanged.)

- [ ] **Step 5: `VoicePreviewSheet.swift`** — dark List + tinted/semantic labels. After `.navigationBarTitleDisplayMode(.inline)` add:

```swift
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .tint(Theme.accentSolid)
```

And recolor the clarification/warning labels: change `.foregroundStyle(.orange)` → `.foregroundStyle(Theme.warn)` on the clarification `Label`, and the warnings `Label`'s `.foregroundStyle(.secondary)` → `.foregroundStyle(Theme.textDim)`. (Apply/Discard and `pending` logic unchanged.)

- [ ] **Step 6: Build** — run the build gate. Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Kit regression** — run the Kit regression gate. Expected `** TEST SUCCEEDED **`, 92 tests, 0 failures (1 skip). This proves no Kit file was disturbed across the whole refresh.

- [ ] **Step 8: Commit**

```bash
cd ~/cuelist-compiler-ios && git add ios/Sources/App && \
git commit -m "feat(ios-ui): dark restyle of settings, defaults, color picker, copy bar, voice preview"
```

---

### Task 10: On-device verification (manual — the real visual gate)

No code. This is the acceptance checklist, run by the human partner on **jPhone (2)** (iPhone 17 Pro). SwiftUI views aren't unit-tested in this project, so the eye is the gate.

- [ ] **Step 1: Build, sign, install to device** (team `UWJSLFQDGL`, bundle `com.blearred.cuelistcompiler`):

```bash
cd ~/cuelist-compiler-ios/ios && xcodegen generate >/dev/null && \
xcodebuild -scheme CuelistCompiler -configuration Debug \
  -destination 'generation=any,platform=iOS' \
  -derivedDataPath build build 2>&1 | tail -4
# then install the .app from build/Build/Products/Debug-iphoneos via:
xcrun devicectl device install app --device <jPhone2-id> \
  build/Build/Products/Debug-iphoneos/CuelistCompiler.app
```
Expected: `** BUILD SUCCEEDED **` then a successful install.

- [ ] **Step 2: Visual acceptance** — confirm by eye, in a dimmed room:
  - Dark canvas + violet→blue gradient cue badges + gradient Send button read as the desktop's sibling.
  - Tapping a cue **expands inline**; collapsed cues show group-name chips + preset count.
  - A group shows only **set** pools as rows; empty pools are dashed `＋POOL` chips; tapping a chip reveals the pool; tapping a pool row opens the inline editor (name + fade/delay steppers).
  - Fade numerics render in accent (violet), delay in amber; blank values show the dimmed per-pool default.
  - Song-name **Menu** in the title switches/creates/renames/removes songs; seq stepper + cue count in the subbar.
  - `LiveIndicator` is **green** when linked, amber connecting, red on error, faint offline.
  - **FOC** (lavender) and **BEM** (cyan) pool dots remain readable and don't read as the chrome — note if a micro-retune is wanted.

- [ ] **Step 3: Behavioral non-regression** — confirm the restyle didn't break function:
  - Author a cue + group + a couple presets; relaunch the app → data persisted.
  - Connect to the hub, `Send → MA` → "Sent N lines" in green; the cue stores on the desk.
  - Run one voice command → preview sheet renders (dark) → Apply works.

- [ ] **Step 4: Finish the branch** — when the human partner signs off, use `superpowers:finishing-a-development-branch` to open a PR for `feat/ios-ui-refresh` into `main` (coordinate with the desktop session, which will also land on `main`).

---

## Self-Review

**Spec coverage:**
- Dark-only + accent tint → Task 3 Step 1. ✓
- Desktop-mirrored tokens → Task 1 (`Theme.swift`). ✓
- Gradient primary / green live / amber delay → Tasks 1, 4, 5. ✓
- Inline-expand cues → Task 7. ✓
- Inline pool editing + set-rows + add-chips → Tasks 5, 6. ✓
- Song-switcher Menu → Task 3. ✓
- Reusable components (CueBadge, GroupCard via ActionBlockView, PoolRow, PoolEditor inline, StepperField, AddChips, Chip, LiveIndicator) → Tasks 2, 5, 6. ✓
- FOC/violet clash by treatment (label+dot vs filled chrome) → Tasks 5, 6 (dots are small circles; chrome is filled gradient). ✓
- Secondary sheets restyle → Task 9. ✓
- No Kit/contract change; 92 tests green → Tasks 1 & 9 gates. ✓
- On-device manual verification → Task 10. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases". Every code step shows complete file or complete replacement block. ✓

**Type consistency:**
- `PoolRowView(pool:action:)` signature preserved across Tasks 5/6. ✓
- `ActionBlockView(cue:action:)` and `CueCardView(cue:)` signatures preserved. ✓
- `CopyFromBar(cue:)`, `ColorPickerPopover(selection:)`, `VoicePreviewSheet(pending:onApply:onDiscard:)` unchanged. ✓
- `hub.send(project:defaults:selection:)` with `.current`/`.all`; `StoreMode.allCases`; `ConnectionState` cases — all match Kit. ✓
- `cue.n` is `Double` → `CueBadge(n: Double)` and `Text(n, format: .number)`. ✓
- `StepperField(label:value:placeholder:tint:)` call sites in Tasks 5 & 7 match its definition in Task 2 (`placeholder` defaults to `""`). ✓
- `Theme.canvas` returns a `View` used as `.background(...)` and as a ZStack layer — both valid. ✓

No gaps found.
