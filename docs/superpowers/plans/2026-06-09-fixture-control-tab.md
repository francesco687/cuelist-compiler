# Fixture Control Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Fixtures" bottom tab that directly controls the grandMA3 desk's programmer — select a fixture/group, nudge attributes with jog faders, recall color/gobo presets by number, and store the result to a cue or update a preset.

**Architecture:** The tab is a stateless remote control. Every interaction emits grandMA3 command-line strings over the existing `HubClient.sendCommand` fire-and-forget transport; the desk's programmer is the source of truth. A pure Kit layer (`FixtureControlBuilder`, `SelectionEntry`, `NudgeAccumulator`) turns intents into command strings and coalesces drag deltas; the App layer is SwiftUI views wired to `HubClient`. No new project-model state, no desk→app read-back.

**Tech Stack:** Swift 5.9, SwiftUI, `@Observable`, XCTest. Project is generated with `xcodegen` from `ios/project.yml`. New files under `Sources/Kit/**` and `Sources/App/**` are auto-included on regeneration.

**Reference spec:** `docs/superpowers/specs/2026-06-09-fixture-control-tab-design.md`

---

## Conventions for every task

- **Working dir:** `ios/` (i.e. `/Users/jordanbabev/cuelist-compiler/ios`).
- **Regenerate after adding files:** `xcodegen generate` (run from `ios/`).
- **Run Kit tests:**
  ```bash
  xcodebuild test -scheme SaettaKit \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
  ```
  If "iPhone 17 Pro" is unavailable, run `xcrun simctl list devices available` and substitute any available iPhone simulator name.
- **Build the app (App-layer tasks):**
  ```bash
  xcodebuild build -scheme Saetta \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
  ```
- Commit after each task with the message shown in its final step.

---

## Task 0: Phase-0 spike — verify per-attribute relative nudge syntax (MANUAL, do FIRST)

**This is a manual hardware checkpoint, not code. It gates Task 2.** It decides the exact string `FixtureControlBuilder.attributeNudge` produces.

- [ ] **Step 1: Connect the app to the desk.** Launch Saetta on jPhone (2) (or the web/hub harness), confirm the Live tab shows "Connected". Make sure a moving-light fixture (e.g. Fixture 101) is patched and its Pan/Tilt are visible on the desk's encoders.

- [ ] **Step 2: Send candidate selection + nudge lines via the Live tab's message field (or hub console), one at a time, and watch the desk programmer.** Try, in order, until one moves Pan by ~5° relative:
  1. `Fixture 101` then `Attribute "Pan" At + 5`
  2. `Fixture 101` then `Attribute "Pan" At +5`
  3. `Fixture 101` then `MAtricks ...` / feature-encoder form (consult the desk's command reference if 1–2 fail)

- [ ] **Step 3: Record the verified forms.** In `docs/superpowers/specs/2026-06-09-fixture-control-tab-design.md`, under the "Phase 0" section, append a short "VERIFIED" note with:
  - The exact dimmer relative form that worked (expected `At + 5`).
  - The exact attribute relative form that worked (expected `Attribute "Pan" At + 5`).
  - Whether negative uses `At - 5` (space-separated sign).

- [ ] **Step 4: Commit the verification note.**

```bash
git add docs/superpowers/specs/2026-06-09-fixture-control-tab-design.md
git commit -m "docs: record verified MA3 relative-nudge syntax (Phase 0 spike)"
```

> **If the verified attribute form differs from `Attribute "Pan" At + 5`,** update the literal strings/asserts in Task 2 to match before implementing it. Everything else in the plan is independent of this result.

---

## Task 1: `SelectionEntry` — keypad → selection command string

**Files:**
- Create: `Sources/Kit/Fixture/SelectionEntry.swift`
- Test: `Tests/KitTests/SelectionEntryTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/KitTests/SelectionEntryTests.swift
import XCTest
@testable import SaettaKit

final class SelectionEntryTests: XCTestCase {

    func test_single_fixture() {
        var e = SelectionEntry()
        e.tapKeyword(.fixture); e.tapDigit(1); e.tapDigit(0); e.tapDigit(1)
        XCTAssertEqual(e.command, "Fixture 101")
        XCTAssertFalse(e.isEmpty)
    }

    func test_fixture_range_with_thru() {
        var e = SelectionEntry()
        e.tapKeyword(.fixture); e.tapDigit(1); e.tapDigit(0); e.tapDigit(1)
        e.tapKeyword(.thru); e.tapDigit(1); e.tapDigit(0); e.tapDigit(5)
        XCTAssertEqual(e.command, "Fixture 101 Thru 105")
    }

    func test_group_then_plus_fixture() {
        var e = SelectionEntry()
        e.tapKeyword(.group); e.tapDigit(2)
        e.tapKeyword(.plus); e.tapKeyword(.fixture); e.tapDigit(7)
        XCTAssertEqual(e.command, "Group 2 + Fixture 7")
    }

    func test_backspace_removes_trailing_digit_then_token() {
        var e = SelectionEntry()
        e.tapKeyword(.fixture); e.tapDigit(1); e.tapDigit(2)
        e.backspace()                       // "Fixture 1"
        XCTAssertEqual(e.command, "Fixture 1")
        e.backspace()                       // "Fixture"
        XCTAssertEqual(e.command, "Fixture")
        e.backspace()                       // ""
        XCTAssertEqual(e.command, "")
        XCTAssertTrue(e.isEmpty)
    }

    func test_reset_clears_everything() {
        var e = SelectionEntry()
        e.tapKeyword(.fixture); e.tapDigit(9)
        e.reset()
        XCTAssertTrue(e.isEmpty)
        XCTAssertEqual(e.command, "")
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: FAIL — `cannot find 'SelectionEntry' in scope`.

- [ ] **Step 3: Implement `SelectionEntry`**

```swift
// Sources/Kit/Fixture/SelectionEntry.swift
import Foundation

/// Accumulates numeric-keypad taps into a grandMA3 selection command string
/// (e.g. "Fixture 101 Thru 105", "Group 2 + Fixture 7"). Purely a string
/// assembler — the result is sent verbatim over the cmd transport.
public struct SelectionEntry: Equatable {
    public enum Keyword: String {
        case fixture = "Fixture"
        case group = "Group"
        case thru = "Thru"
        case plus = "+"
    }

    /// Each part is either a multi-digit number run or a keyword token.
    private var parts: [String] = []
    /// True when the last part is an open number run that digits should extend.
    private var inNumber = false

    public init() {}

    public mutating func tapDigit(_ d: Int) {
        let digit = String(max(0, min(9, d)))
        if inNumber, let last = parts.last {
            parts[parts.count - 1] = last + digit
        } else {
            parts.append(digit)
            inNumber = true
        }
    }

    public mutating func tapKeyword(_ k: Keyword) {
        parts.append(k.rawValue)
        inNumber = false
    }

    /// Remove one trailing digit; if the trailing number run empties or the
    /// trailing part is a keyword, drop the whole part.
    public mutating func backspace() {
        guard var last = parts.last else { return }
        if inNumber, last.count > 1 {
            last.removeLast()
            parts[parts.count - 1] = last
        } else {
            parts.removeLast()
            inNumber = parts.last.map { Int($0) != nil } ?? false
        }
    }

    public mutating func reset() {
        parts.removeAll()
        inNumber = false
    }

    public var command: String { parts.joined(separator: " ") }
    public var isEmpty: Bool { parts.isEmpty }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Kit/Fixture/SelectionEntry.swift Tests/KitTests/SelectionEntryTests.swift
git commit -m "feat: SelectionEntry keypad-to-command assembler"
```

---

## Task 2: `FixtureControlBuilder` — nudge & recall lines

**Files:**
- Create: `Sources/Kit/Fixture/FixtureControlBuilder.swift`
- Test: `Tests/KitTests/FixtureControlBuilderTests.swift`

> If Task 0 verified an attribute form other than `Attribute "Pan" At + 5`, change the literals below to match.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/KitTests/FixtureControlBuilderTests.swift
import XCTest
@testable import SaettaKit

final class FixtureControlBuilderTests: XCTestCase {

    func test_intensity_nudge_positive_and_negative() {
        XCTAssertEqual(FixtureControlBuilder.intensityNudge(5), "At + 5")
        XCTAssertEqual(FixtureControlBuilder.intensityNudge(-5), "At - 5")
        XCTAssertNil(FixtureControlBuilder.intensityNudge(0), "zero delta emits nothing")
    }

    func test_attribute_nudge() {
        XCTAssertEqual(FixtureControlBuilder.attributeNudge("Pan", 5), "Attribute \"Pan\" At + 5")
        XCTAssertEqual(FixtureControlBuilder.attributeNudge("Tilt", -3), "Attribute \"Tilt\" At - 3")
        XCTAssertNil(FixtureControlBuilder.attributeNudge("Pan", 0))
    }

    func test_recall_preset_uses_pool_number() {
        XCTAssertEqual(FixtureControlBuilder.recallPreset(pool: .color, number: 3), "At Preset 4.3")
        XCTAssertEqual(FixtureControlBuilder.recallPreset(pool: .gobo, number: 1), "At Preset 3.1")
    }

    func test_clear_constant() {
        XCTAssertEqual(FixtureControlBuilder.clear, "ClearAll")
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: FAIL — `cannot find 'FixtureControlBuilder' in scope`.

- [ ] **Step 3: Implement the nudge/recall half**

```swift
// Sources/Kit/Fixture/FixtureControlBuilder.swift
import Foundation

/// Turns live fixture-control intents into grandMA3 command-line strings.
/// Mirrors the style of `MA3CommandBuilder`. All output is sent over the
/// optimistic `cmd` transport; relative forms verified in the Phase-0 spike.
public enum FixtureControlBuilder {

    /// "At + 5" / "At - 5" for relative intensity. Returns nil for a zero delta.
    public static func intensityNudge(_ delta: Int) -> String? {
        guard delta != 0 else { return nil }
        return "At \(sign(delta)) \(abs(delta))"
    }

    /// "Attribute \"Pan\" At + 5" for a relative attribute nudge. Nil for zero.
    public static func attributeNudge(_ attribute: String, _ delta: Int) -> String? {
        guard delta != 0 else { return nil }
        return "Attribute \"\(attribute)\" At \(sign(delta)) \(abs(delta))"
    }

    /// "At Preset 4.3" — recall preset `number` from `pool` onto the selection.
    public static func recallPreset(pool: Pool, number: Int) -> String {
        "At Preset \(pool.number).\(number)"
    }

    /// Drop the programmer.
    public static let clear = "ClearAll"

    private static func sign(_ n: Int) -> String { n < 0 ? "-" : "+" }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Kit/Fixture/FixtureControlBuilder.swift Tests/KitTests/FixtureControlBuilderTests.swift
git commit -m "feat: FixtureControlBuilder nudge and preset-recall lines"
```

---

## Task 3: `FixtureControlBuilder` — store-to-cue & update-preset lines

**Files:**
- Modify: `Sources/Kit/Fixture/FixtureControlBuilder.swift`
- Modify: `Tests/KitTests/FixtureControlBuilderTests.swift`

- [ ] **Step 1: Add failing tests** (append inside the existing test class)

```swift
    func test_store_cue_overwrite_and_merge() {
        XCTAssertEqual(FixtureControlBuilder.storeCue(sequence: 5, cue: 2, mode: .overwrite),
                       "Store Sequence 5 Cue 2 /Overwrite /NoConfirmation")
        XCTAssertEqual(FixtureControlBuilder.storeCue(sequence: 5, cue: 2, mode: .merge),
                       "Store Sequence 5 Cue 2 /Merge /NoConfirmation")
    }

    func test_update_preset() {
        XCTAssertEqual(FixtureControlBuilder.updatePreset(pool: .color, number: 3, mode: .overwrite),
                       "Store Preset 4.3 /Overwrite /NoConfirmation")
        XCTAssertEqual(FixtureControlBuilder.updatePreset(pool: .position, number: 1, mode: .merge),
                       "Store Preset 2.1 /Merge /NoConfirmation")
    }
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: FAIL — `storeCue` / `updatePreset` not found.

- [ ] **Step 3: Add the store/update functions** (inside `FixtureControlBuilder`, before the private `sign`)

```swift
    /// "Store Sequence 5 Cue 2 /Merge /NoConfirmation".
    public static func storeCue(sequence: Int, cue: Int, mode: StoreMode) -> String {
        "Store Sequence \(sequence) Cue \(cue) \(mode.flag) /NoConfirmation"
    }

    /// "Store Preset 4.3 /Overwrite /NoConfirmation".
    public static func updatePreset(pool: Pool, number: Int, mode: StoreMode) -> String {
        "Store Preset \(pool.number).\(number) \(mode.flag) /NoConfirmation"
    }
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Kit/Fixture/FixtureControlBuilder.swift Tests/KitTests/FixtureControlBuilderTests.swift
git commit -m "feat: FixtureControlBuilder store-cue and update-preset lines"
```

---

## Task 4: `NudgeAccumulator` — coalesce/throttle drag deltas

**Files:**
- Create: `Sources/Kit/Fixture/NudgeAccumulator.swift`
- Test: `Tests/KitTests/NudgeAccumulatorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/KitTests/NudgeAccumulatorTests.swift
import XCTest
@testable import SaettaKit

final class NudgeAccumulatorTests: XCTestCase {

    func test_first_accept_emits_immediately() {
        let acc = NudgeAccumulator(intervalMs: 50)
        XCTAssertEqual(acc.accept(delta: 3, atMs: 0), 3)
        XCTAssertEqual(acc.offset, 3)
    }

    func test_within_window_coalesces_and_returns_nil() {
        let acc = NudgeAccumulator(intervalMs: 50)
        _ = acc.accept(delta: 3, atMs: 0)          // emits 3
        XCTAssertNil(acc.accept(delta: 2, atMs: 10)) // coalesced
        XCTAssertNil(acc.accept(delta: 1, atMs: 20)) // coalesced
        XCTAssertEqual(acc.offset, 6, "offset tracks the true running sum")
    }

    func test_emits_accumulated_after_window_elapses() {
        let acc = NudgeAccumulator(intervalMs: 50)
        _ = acc.accept(delta: 3, atMs: 0)          // emits 3
        XCTAssertNil(acc.accept(delta: 2, atMs: 10))
        XCTAssertEqual(acc.accept(delta: 1, atMs: 60), 3, "pending 2 + new 1 emitted")
        XCTAssertEqual(acc.offset, 6)
    }

    func test_flush_emits_pending() {
        let acc = NudgeAccumulator(intervalMs: 50)
        _ = acc.accept(delta: 3, atMs: 0)
        XCTAssertNil(acc.accept(delta: 4, atMs: 10))
        XCTAssertEqual(acc.flush(atMs: 20), 4)
        XCTAssertNil(acc.flush(atMs: 30), "nothing pending after flush")
        XCTAssertEqual(acc.offset, 7)
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: FAIL — `cannot find 'NudgeAccumulator' in scope`.

- [ ] **Step 3: Implement `NudgeAccumulator`**

```swift
// Sources/Kit/Fixture/NudgeAccumulator.swift
import Foundation

/// Coalesces a stream of relative nudge deltas (from a finger drag) into
/// throttled emissions so a drag never floods the desk. Leading-edge emit, then
/// sum within `intervalMs`, then emit on the next accept past the window or on
/// `flush` (drag end). `offset` always tracks the true running sum for display.
public final class NudgeAccumulator {
    private let intervalMs: Int
    private var pending = 0
    private var lastEmitMs: Int?            // nil → first accept emits immediately
    public private(set) var offset = 0

    public init(intervalMs: Int = 50) {
        self.intervalMs = intervalMs
    }

    /// Feed a delta sampled at monotonic `now` (ms). Returns the delta to send,
    /// or nil if it was coalesced into the pending window.
    public func accept(delta: Int, atMs now: Int) -> Int? {
        offset += delta
        pending += delta
        if let last = lastEmitMs, now - last < intervalMs {
            return nil
        }
        return emit(now)
    }

    /// Emit any pending delta now (call on drag end). Returns it, or nil.
    public func flush(atMs now: Int) -> Int? {
        guard pending != 0 else { return nil }
        return emit(now)
    }

    private func emit(_ now: Int) -> Int? {
        guard pending != 0 else { return nil }
        let out = pending
        pending = 0
        lastEmitMs = now
        return out
    }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Kit/Fixture/NudgeAccumulator.swift Tests/KitTests/NudgeAccumulatorTests.swift
git commit -m "feat: NudgeAccumulator drag-delta coalescer"
```

---

## Task 5: `JogFader` view

**Files:**
- Create: `Sources/App/Fixture/JogFader.swift`

No unit test (SwiftUI view); verified via app build + on-device feel.

- [ ] **Step 1: Implement `JogFader`**

```swift
// Sources/App/Fixture/JogFader.swift
import SwiftUI

/// A vertical jog strip that emits RELATIVE integer deltas as you drag up/down.
/// The grip springs back to center on release. Drag distance maps to deltas via
/// a points-per-unit factor (coarse vs fine). Accumulates a fractional residual
/// so slow drags still register whole-unit steps.
struct JogFader: View {
    let label: String
    let valueText: String          // running session offset, e.g. "+12°"
    let fine: Bool
    let onNudge: (Int) -> Void     // incremental delta during drag
    let onEnd: () -> Void          // drag ended → flush

    @State private var lastY: CGFloat = 0
    @State private var residual: CGFloat = 0
    @State private var gripOffset: CGFloat = 0

    private var pointsPerUnit: CGFloat { fine ? 24 : 8 }
    private let trackHeight: CGFloat = 170
    private let gripHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.surface2)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border, lineWidth: 0.5))
                Image(systemName: "chevron.up").font(.caption).foregroundStyle(Theme.textFaint)
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(Theme.textFaint)
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 8)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.accentGradient)
                    .frame(height: gripHeight)
                    .shadow(color: Theme.accentSolid.opacity(0.5), radius: 8)
                    .offset(y: gripOffset)
            }
            .frame(width: 52, height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let dy = v.translation.height - lastY
                        lastY = v.translation.height
                        // Up (negative dy) = increase.
                        residual += -dy / pointsPerUnit
                        let whole = Int(residual.rounded(.towardZero))
                        if whole != 0 {
                            residual -= CGFloat(whole)
                            onNudge(whole)
                        }
                        gripOffset = max(-trackHeight/2 + gripHeight/2,
                                         min(trackHeight/2 - gripHeight/2, v.translation.height))
                    }
                    .onEnded { _ in
                        lastY = 0; residual = 0
                        withAnimation(.snappy(duration: 0.18)) { gripOffset = 0 }
                        onEnd()
                    }
            )

            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
            Text(valueText).font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.text)
        }
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
xcodebuild build -scheme Saetta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A Sources/App/Fixture Saetta.xcodeproj
git commit -m "feat: JogFader relative-nudge drag widget"
```

---

## Task 6: `SelectionKeypadSheet` view

**Files:**
- Create: `Sources/App/Fixture/SelectionKeypadSheet.swift`

- [ ] **Step 1: Implement the sheet**

```swift
// Sources/App/Fixture/SelectionKeypadSheet.swift
import SwiftUI
import SaettaKit

/// Builds a grandMA3 selection command on a numeric keypad and fires it on Select.
struct SelectionKeypadSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Called with the assembled command (e.g. "Fixture 101 Thru 105").
    let onSelect: (String) -> Void

    @State private var entry = SelectionEntry()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 16) {
                    Text(entry.isEmpty ? "—" : entry.command)
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(entry.isEmpty ? Theme.textFaint : Theme.accentSolid)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))

                    HStack(spacing: 8) {
                        keyword(.fixture, "Fixture")
                        keyword(.group, "Group")
                        keyword(.thru, "Thru")
                        keyword(.plus, "+")
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(1...9, id: \.self) { d in digit(d) }
                        Button { entry.backspace() } label: { keyLabel("⌫", tint: Theme.surface3) }
                        digit(0)
                        Button { entry.reset() } label: { keyLabel("Clr", tint: Theme.surface3) }
                    }

                    Button {
                        let cmd = entry.command
                        guard !cmd.isEmpty else { return }
                        onSelect(cmd); dismiss()
                    } label: {
                        Text("Select").font(.system(size: 17, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(entry.isEmpty ? Theme.surface2 : Theme.accentSolid,
                                        in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                            .foregroundStyle(entry.isEmpty ? Theme.textDim : .white)
                    }
                    .buttonStyle(.plain).disabled(entry.isEmpty)
                }
                .padding(20)
            }
            .navigationTitle("Select").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
    }

    private func digit(_ d: Int) -> some View {
        Button { entry.tapDigit(d) } label: { keyLabel(String(d), tint: Theme.surface2) }
    }
    private func keyword(_ k: SelectionEntry.Keyword, _ title: String) -> some View {
        Button { entry.tapKeyword(k) } label: {
            Text(title).font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Theme.surface3, in: RoundedRectangle(cornerRadius: Theme.radius))
                .foregroundStyle(Theme.accentSolid)
        }.buttonStyle(.plain)
    }
    private func keyLabel(_ s: String, tint: Color) -> some View {
        Text(s).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
xcodebuild build -scheme Saetta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A Sources/App/Fixture Saetta.xcodeproj
git commit -m "feat: SelectionKeypadSheet console-style selection entry"
```

---

## Task 7: `PresetRecallGrid` view

**Files:**
- Create: `Sources/App/Fixture/PresetRecallGrid.swift`

- [ ] **Step 1: Implement the grid**

```swift
// Sources/App/Fixture/PresetRecallGrid.swift
import SwiftUI
import SaettaKit

/// A grid of numbered preset-recall buttons for a pool. Tapping slot N fires
/// "At Preset <pool>.N". Slot count is fixed; labels are not read from the desk.
struct PresetRecallGrid: View {
    let pool: Pool
    let slots: Int                 // how many numbered buttons to show
    let onRecall: (Int) -> Void    // preset number tapped

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(1...slots, id: \.self) { n in
                    Button { onRecall(n) } label: {
                        VStack(spacing: 2) {
                            Text("\(pool.number).\(n)")
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundStyle(Theme.text)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border, lineWidth: 0.5))
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .padding(.vertical, 4)
        }
    }
}
```

> `PressScaleStyle` already exists in `Sources/App/LiveView.swift` and is internal to the App target, so it is reusable here without import.

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
xcodebuild build -scheme Saetta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A Sources/App/Fixture Saetta.xcodeproj
git commit -m "feat: PresetRecallGrid recall-by-number buttons"
```

---

## Task 8: `StoreCueSheet` and `UpdatePresetSheet`

**Files:**
- Create: `Sources/App/Fixture/StoreSheets.swift`

- [ ] **Step 1: Implement both sheets**

```swift
// Sources/App/Fixture/StoreSheets.swift
import SwiftUI
import SaettaKit

/// Store the desk's current programmer into a cue. Sequence prefilled from the
/// active song. Shows the exact command before firing.
struct StoreCueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var sequence: Int
    @State var cue: Int
    @State var mode: StoreMode
    let onStore: (String) -> Void

    var body: some View {
        StoreSheetScaffold(
            title: "Store to Cue",
            command: FixtureControlBuilder.storeCue(sequence: sequence, cue: cue, mode: mode),
            mode: $mode,
            actionTitle: "Store",
            onConfirm: { onStore(FixtureControlBuilder.storeCue(sequence: sequence, cue: cue, mode: mode)); dismiss() },
            onCancel: { dismiss() }
        ) {
            numField("Sequence", value: $sequence)
            numField("Cue", value: $cue)
        }
    }

    @ViewBuilder private func numField(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textDim)
            Spacer()
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.text).frame(width: 90)
                .padding(.vertical, 8).padding(.horizontal, 10)
                .background(Theme.surface3, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
    }
}

/// Overwrite/merge an existing preset from the current programmer.
struct UpdatePresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var pool: Pool = .color
    @State var number: Int = 1
    @State var mode: StoreMode
    let onUpdate: (String) -> Void

    var body: some View {
        StoreSheetScaffold(
            title: "Update Preset",
            command: FixtureControlBuilder.updatePreset(pool: pool, number: number, mode: mode),
            mode: $mode,
            actionTitle: "Update",
            onConfirm: { onUpdate(FixtureControlBuilder.updatePreset(pool: pool, number: number, mode: mode)); dismiss() },
            onCancel: { dismiss() }
        ) {
            HStack {
                Text("Pool").foregroundStyle(Theme.textDim)
                Spacer()
                Picker("Pool", selection: $pool) {
                    ForEach(Pool.allCases, id: \.self) { Text("\($0.rawValue.capitalized) (\($0.number))").tag($0) }
                }.tint(Theme.accentSolid)
            }
            HStack {
                Text("Preset #").foregroundStyle(Theme.textDim)
                Spacer()
                TextField("", value: $number, format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.text).frame(width: 90)
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .background(Theme.surface3, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
        }
    }
}

/// Shared chrome: title, fields slot, overwrite/merge toggle, command preview, actions.
private struct StoreSheetScaffold<Fields: View>: View {
    let title: String
    let command: String
    @Binding var mode: StoreMode
    let actionTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let fields: () -> Fields

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(alignment: .leading, spacing: 16) {
                    fields()
                    Picker("Mode", selection: $mode) {
                        ForEach(StoreMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(command).font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
                    Button(action: onConfirm) {
                        Text(actionTitle).font(.system(size: 17, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.accentSolid, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                            .foregroundStyle(.white)
                    }.buttonStyle(.plain)
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel", action: onCancel) } }
        }
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
xcodebuild build -scheme Saetta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A Sources/App/Fixture Saetta.xcodeproj
git commit -m "feat: StoreCueSheet and UpdatePresetSheet with command preview"
```

---

## Task 9: `FixtureControlView` — assemble the tab

**Files:**
- Create: `Sources/App/Fixture/FixtureControlView.swift`

- [ ] **Step 1: Implement the tab root**

```swift
// Sources/App/Fixture/FixtureControlView.swift
import SwiftUI
import SaettaKit

/// The Fixtures tab: select → pick parameter → nudge/recall → store/update.
/// Stateless remote control — every action fires a command line at the desk.
struct FixtureControlView: View {
    @Environment(HubClient.self) private var hub
    @Environment(ProjectStore.self) private var store

    enum Category: String, CaseIterable, Identifiable {
        case intensity = "Int", position = "Pos", color = "Color"
        case gobo = "Gobo", beam = "Beam", focus = "Focus"
        var id: String { rawValue }
    }

    @State private var selection = ""          // last sent selection command, for display
    @State private var category: Category = .position
    @State private var fine = false
    @State private var showKeypad = false
    @State private var showStoreCue = false
    @State private var showUpdatePreset = false
    @State private var fireCount = 0

    // One accumulator per attribute key; reset on Clear / new selection.
    @State private var accumulators: [String: NudgeAccumulator] = [:]
    @State private var version = 0             // bump to force fader value-text refresh

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 14) {
                    connectionRow
                    selectionChip
                    categoryPicker
                    controlArea.frame(maxHeight: .infinity)
                    clearButton
                    storeBar
                }
                .padding(20)
                .disabled(!hub.state.isOnline)
                .opacity(hub.state.isOnline ? 1 : 0.5)
            }
            .navigationTitle("Fixtures").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sensoryFeedback(.impact(weight: .light), trigger: fireCount)
            .sheet(isPresented: $showKeypad) {
                SelectionKeypadSheet { cmd in selection = cmd; resetAccumulators(); send(cmd) }
            }
            .sheet(isPresented: $showStoreCue) {
                StoreCueSheet(sequence: store.activeSong.sequence, cue: 1, mode: store.project.storeMode) { send($0) }
            }
            .sheet(isPresented: $showUpdatePreset) {
                UpdatePresetSheet(mode: store.project.storeMode) { send($0) }
            }
        }
    }

    // MARK: control area per category

    @ViewBuilder private var controlArea: some View {
        switch category {
        case .intensity:
            faderRow([("Dimmer", nil)])
        case .position:
            faderRow([("Pan", "Pan"), ("Tilt", "Tilt")])
        case .beam:
            faderRow([("Zoom", "Zoom"), ("Focus", "Focus"), ("Iris", "Iris")])
        case .focus:
            faderRow([("Focus", "Focus")])
        case .color:
            PresetRecallGrid(pool: .color, slots: 24) { recall(pool: .color, $0) }
        case .gobo:
            PresetRecallGrid(pool: .gobo, slots: 24) { recall(pool: .gobo, $0) }
        }
    }

    /// Each item: (display label, attribute name or nil for bare-intensity).
    private func faderRow(_ items: [(String, String?)]) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                ForEach(items, id: \.0) { item in
                    let key = item.1 ?? "Dimmer"
                    JogFader(
                        label: item.0,
                        valueText: offsetText(key),
                        fine: fine,
                        onNudge: { nudge(key: key, attribute: item.1, delta: $0) },
                        onEnd: { flush(key: key, attribute: item.1) }
                    )
                    .id(version)   // refresh value text after resets
                }
            }
            Picker("", selection: $fine) {
                Text("Coarse").tag(false); Text("Fine").tag(true)
            }.pickerStyle(.segmented).frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: intent → command

    private func nudge(key: String, attribute: String?, delta: Int) {
        let acc = accumulator(key)
        guard let emit = acc.accept(delta: delta, atMs: nowMs()) else { return }
        sendNudge(attribute: attribute, delta: emit)
    }
    private func flush(key: String, attribute: String?) {
        let acc = accumulator(key)
        if let emit = acc.flush(atMs: nowMs()) { sendNudge(attribute: attribute, delta: emit) }
        version += 1   // refresh displayed offset
    }
    private func sendNudge(attribute: String?, delta: Int) {
        let line = attribute == nil
            ? FixtureControlBuilder.intensityNudge(delta)
            : FixtureControlBuilder.attributeNudge(attribute!, delta)
        if let line { send(line, haptic: false) }
        version += 1
    }
    private func recall(pool: Pool, _ n: Int) {
        send(FixtureControlBuilder.recallPreset(pool: pool, number: n))
    }

    private func accumulator(_ key: String) -> NudgeAccumulator {
        if let a = accumulators[key] { return a }
        let a = NudgeAccumulator(); accumulators[key] = a; return a
    }
    private func offsetText(_ key: String) -> String {
        let o = accumulators[key]?.offset ?? 0
        return o > 0 ? "+\(o)" : "\(o)"
    }
    private func resetAccumulators() { accumulators.removeAll(); version += 1 }
    private func nowMs() -> Int { Int(ProcessInfo.processInfo.systemUptime * 1000) }

    private func send(_ line: String, haptic: Bool = true) {
        hub.sendCommand(line)
        if haptic { fireCount += 1 }
    }

    // MARK: chrome

    private var connectionRow: some View {
        Button { hub.connect() } label: {
            HStack(spacing: 10) {
                LiveIndicator(state: hub.state)
                Spacer()
                Text(hub.state.isOnline ? "Connected" : "Tap to connect")
                    .font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var selectionChip: some View {
        Button { showKeypad = true } label: {
            HStack {
                Text(selection.isEmpty ? "No selection" : selection)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selection.isEmpty ? Theme.textFaint : Theme.accentSolid)
                Spacer()
                Image(systemName: "keyboard").foregroundStyle(Theme.textDim)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border, lineWidth: 0.5))
        }.buttonStyle(.plain)
    }

    private var categoryPicker: some View {
        Picker("", selection: $category) {
            ForEach(Category.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented)
    }

    private var clearButton: some View {
        Button { send(FixtureControlBuilder.clear); resetAccumulators() } label: {
            Text("Clear").font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Theme.surface3, in: RoundedRectangle(cornerRadius: Theme.radius))
                .foregroundStyle(Theme.textDim)
        }.buttonStyle(.plain)
    }

    private var storeBar: some View {
        HStack(spacing: 10) {
            Button { showStoreCue = true } label: {
                Text("Store to Cue").font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.accentSolid, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    .foregroundStyle(.white)
            }.buttonStyle(.plain)
            Button { showUpdatePreset = true } label: {
                Text("Update Preset").font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(Theme.border, lineWidth: 0.5))
                    .foregroundStyle(Theme.accentSolid)
            }.buttonStyle(.plain)
        }
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
xcodebuild build -scheme Saetta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A Sources/App/Fixture Saetta.xcodeproj
git commit -m "feat: FixtureControlView assembling the live fixture-control tab"
```

---

## Task 10: Add the tab to `RootView`

**Files:**
- Modify: `Sources/App/RootView.swift:20-29`

- [ ] **Step 1: Insert the Fixtures tab** between Send and Settings in the `TabView`

Change:
```swift
            SendView()
                .tabItem { Label("Send", systemImage: "paperplane") }
            SettingsTabView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
```
to:
```swift
            SendView()
                .tabItem { Label("Send", systemImage: "paperplane") }
            FixtureControlView()
                .tabItem { Label("Fixtures", systemImage: "slider.horizontal.3") }
            SettingsTabView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
```

- [ ] **Step 2: Regenerate, build, and run the Kit test suite to confirm nothing regressed**

```bash
xcodegen generate
xcodebuild build -scheme Saetta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: BUILD SUCCEEDED and all tests PASS (existing + new SelectionEntry/FixtureControlBuilder/NudgeAccumulator tests).

- [ ] **Step 3: Commit**

```bash
git add Sources/App/RootView.swift
git commit -m "feat: add Fixtures tab to RootView"
```

---

## Task 11: On-device hardware smoke (MANUAL)

**Files:** none (verification only).

- [ ] **Step 1: Install on jPhone (2)** and connect to the hub/desk (see prior session install command in the project memory / handoffs).

- [ ] **Step 2: Run the full flow against the desk:**
  1. Fixtures tab → tap selection chip → keypad → `Fixture 101` → Select. Confirm the desk selects it.
  2. Position category → drag the Pan fader. Confirm the desk's Pan moves and the offset readout climbs; toggle Fine and confirm finer steps.
  3. Color category → tap a preset slot that exists (e.g. `4.1`). Confirm the color applies.
  4. Store to Cue → confirm sequence prefilled from active song, set a safe cue number, pick Merge, Store. Confirm the cue stores on the desk.
  5. Update Preset → pick a safe preset slot, Overwrite, Update. Confirm.
  6. Clear → confirm the programmer releases and offsets reset to 0.

- [ ] **Step 3: Note results** (what worked / any syntax that the desk rejected) in a brief comment on the eventual PR. No commit required for this task.

---

## Self-Review (completed during planning)

- **Spec coverage:** value model (relative nudge → `NudgeAccumulator` + builder ±), selection (keypad → `SelectionEntry`/`SelectionKeypadSheet`), hybrid control (faders + `PresetRecallGrid`), store target (`StoreCueSheet`/`UpdatePresetSheet` + `storeCue`/`updatePreset`), layout A (`FixtureControlView` chip→sheet, control area, store bar), jog faders (`JogFader` + coarse/fine), recall-by-number (`PresetRecallGrid`), Phase-0 spike (Task 0), new tab (Task 10) — all covered.
- **Placeholder scan:** no TBD/TODO; every code step shows full code; every command shows expected output.
- **Type consistency:** `SelectionEntry.Keyword` (.fixture/.group/.thru/.plus), `FixtureControlBuilder.{intensityNudge,attributeNudge,recallPreset,clear,storeCue,updatePreset}`, `NudgeAccumulator.{accept,flush,offset}`, `JogFader(label:valueText:fine:onNudge:onEnd:)` — all referenced consistently across tasks. `Pool.number`, `StoreMode.flag/allCases`, `store.activeSong.sequence`, `store.project.storeMode`, `hub.sendCommand`, `LiveIndicator`, `PressScaleStyle` verified against current source.

## Deferred / notes

- Per-attribute "+" multi-selection works via the keypad `+` token (`Group 2 + Fixture 7`); no further plumbing needed.
- Beam attribute set is Zoom/Focus/Iris in v1 — add Frost/Strobe by extending the `faderRow` list in `FixtureControlView`.
- Preset-slot custom labels (local-only) and pulling named presets from the desk are out of scope for v1 (recall-by-number ships instead).
