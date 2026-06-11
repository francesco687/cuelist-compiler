# Executor Toggle Buttons on the Live Macro Pad — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an assignable "Executor (toggle)" button type to the Live tab's 2×2 macro pad — assigned from the picker, then long-press → "Load Executor…" to point it at an executor number; tap fires `Toggle Executor <n>`.

**Architecture:** A new `MacroSlot` enum in Kit (`.action(MacroAction)` / `.executor(number: Int?)`) decodes the single `String` per slot that `MacroPad` already persists (`"exec:"` prefix marks executor slots; anything else is an action id — old saved pads load unchanged, no migration). Command strings are built in Kit so they're unit-testable. The view renders the two new executor states and gains a small number-entry sheet.

**Tech Stack:** Swift / SwiftUI, `@Observable`, XCTest. Project generated with **xcodegen** (`cd ios && xcodegen generate` before every `xcodebuild`). Spec: `docs/superpowers/specs/2026-06-11-executor-macro-buttons-design.md`.

**Branch:** `feat/exec-macro-buttons` (already created off `main`).

**Verification gotchas:** always `set -o pipefail` before piping `xcodebuild` into `tail` (a bare pipe masks failures). Test sim: iPhone 17 Pro.

---

## File Structure

- **Create** `ios/Sources/Kit/Macro/MacroSlot.swift` — slot value enum: decode/encode the persisted string, build the fire command. Pure value type, no I/O.
- **Modify** `ios/Sources/Kit/Macro/MacroPad.swift` — add `slot(at:)`, `assignExecutor(slot:)`, `loadExecutor(slot:number:)`; reimplement `action(at:)` on top of `slot(at:)`. Storage format untouched.
- **Modify** `ios/Sources/App/MacroPadView.swift` — render executor states, "Load Executor…" context-menu item, `ExecutorLoadSheet`, "Executor (toggle)" picker row.
- **Create** `ios/Tests/KitTests/MacroSlotTests.swift` — decode/round-trip/command tests.
- **Modify** `ios/Tests/KitTests/MacroPadTests.swift` — executor assign/load/persist tests.

No hub, web, or desktop changes.

---

### Task 1: `MacroSlot` value type (Kit, TDD)

**Files:**
- Test: `ios/Tests/KitTests/MacroSlotTests.swift` (create)
- Create: `ios/Sources/Kit/Macro/MacroSlot.swift`

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/KitTests/MacroSlotTests.swift`:

```swift
import XCTest
@testable import SaettaKit

final class MacroSlotTests: XCTestCase {

    // MARK: Decoding

    func test_decodes_library_action_id() {
        guard case .action(let action)? = MacroSlot(rawValue: "go_plus") else {
            return XCTFail("expected .action")
        }
        XCTAssertEqual(action.id, "go_plus")
    }

    func test_decodes_unloaded_executor() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:"), .executor(number: nil))
    }

    func test_decodes_loaded_executor() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:201"), .executor(number: 201))
    }

    func test_rejects_unknown_and_malformed_strings() {
        XCTAssertNil(MacroSlot(rawValue: "ghost_action"))
        XCTAssertNil(MacroSlot(rawValue: "exec:abc"))
        XCTAssertNil(MacroSlot(rawValue: "exec:0"))
        XCTAssertNil(MacroSlot(rawValue: "exec:10000"))
        XCTAssertNil(MacroSlot(rawValue: "exec:-3"))
    }

    // MARK: Round-trip

    func test_rawValue_round_trips() {
        let slots: [MacroSlot] = [
            .action(MacroAction.find("off")!),
            .executor(number: nil),
            .executor(number: 1),
            .executor(number: 9999),
        ]
        for slot in slots {
            XCTAssertEqual(MacroSlot(rawValue: slot.rawValue), slot)
        }
    }

    // MARK: Command

    func test_loaded_executor_builds_toggle_command() {
        XCTAssertEqual(MacroSlot.executor(number: 201).command, "Toggle Executor 201")
    }

    func test_unloaded_executor_has_no_command() {
        XCTAssertNil(MacroSlot.executor(number: nil).command)
    }

    func test_action_command_passes_through() {
        XCTAssertEqual(MacroSlot.action(MacroAction.find("go_plus")!).command, "Go+")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/cuelist-compiler/ios && xcodegen generate && set -o pipefail && \
xcodebuild test -project Saetta.xcodeproj -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: **BUILD FAILS** — `cannot find 'MacroSlot' in scope` (compile error counts as the failing state for a new type).

- [ ] **Step 3: Write the implementation**

Create `ios/Sources/Kit/Macro/MacroSlot.swift`:

```swift
import Foundation

/// The value held by one Live-tab macro-pad slot: either a curated parameter-free
/// action, or an executor toggle targeting a numbered executor on the desk's
/// current page. Encodes to/from the single `String` per slot that `MacroPad`
/// persists — an `"exec:"` prefix marks executor slots; anything else is an
/// action id, so pads saved by older builds load unchanged.
public enum MacroSlot: Equatable, Sendable {
    case action(MacroAction)
    /// `number == nil` — assigned but not yet loaded; renders as pending, never fires.
    case executor(number: Int?)

    /// Executor numbers the load sheet and the decoder accept.
    public static let executorRange = 1...9999

    private static let execPrefix = "exec:"

    /// Decode a persisted slot string. Unknown action ids and malformed or
    /// out-of-range executor numbers decode to nil (empty slot) — never a crash
    /// or a bad command.
    public init?(rawValue: String) {
        if rawValue.hasPrefix(Self.execPrefix) {
            let digits = rawValue.dropFirst(Self.execPrefix.count)
            if digits.isEmpty {
                self = .executor(number: nil)
            } else if let number = Int(digits), Self.executorRange.contains(number) {
                self = .executor(number: number)
            } else {
                return nil
            }
        } else if let action = MacroAction.find(rawValue) {
            self = .action(action)
        } else {
            return nil
        }
    }

    /// The string `MacroPad` persists for this slot.
    public var rawValue: String {
        switch self {
        case .action(let action): action.id
        case .executor(let number): Self.execPrefix + (number.map(String.init) ?? "")
        }
    }

    /// The command-line string a tap fires, or nil if this slot can't fire yet.
    public var command: String? {
        switch self {
        case .action(let action): action.command
        case .executor(let number): number.map { "Toggle Executor \($0)" }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: **TEST SUCCEEDED**, all `MacroSlotTests` pass, no existing test broken.

- [ ] **Step 5: Commit**

```bash
cd ~/cuelist-compiler && git add ios/Sources/Kit/Macro/MacroSlot.swift ios/Tests/KitTests/MacroSlotTests.swift && \
git commit -m "feat(kit): MacroSlot — action/executor slot value with exec: string codec"
```

---

### Task 2: `MacroPad` executor APIs (Kit, TDD)

**Files:**
- Test: `ios/Tests/KitTests/MacroPadTests.swift` (append inside the existing class)
- Modify: `ios/Sources/Kit/Macro/MacroPad.swift`

- [ ] **Step 1: Write the failing tests**

Append inside the existing `MacroPadTests` class (it is `@MainActor`; `freshPad()` already exists):

```swift
    // MARK: Executor slots

    func test_assignExecutor_sets_unloaded_executor() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0)
        XCTAssertEqual(pad.slot(at: 0), .executor(number: nil))
        XCTAssertNil(pad.action(at: 0), "an executor slot is not an action")
    }

    func test_loadExecutor_targets_number() {
        let pad = freshPad()
        pad.assignExecutor(slot: 1)
        pad.loadExecutor(slot: 1, number: 201)
        XCTAssertEqual(pad.slot(at: 1), .executor(number: 201))
    }

    func test_loadExecutor_retargets_loaded_slot() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0)
        pad.loadExecutor(slot: 0, number: 201)
        pad.loadExecutor(slot: 0, number: 7)
        XCTAssertEqual(pad.slot(at: 0), .executor(number: 7))
    }

    func test_loadExecutor_rejects_out_of_range_number() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0)
        pad.loadExecutor(slot: 0, number: 0)
        pad.loadExecutor(slot: 0, number: 10000)
        XCTAssertEqual(pad.slot(at: 0), .executor(number: nil))
    }

    func test_loadExecutor_on_non_executor_slot_is_noop() {
        let pad = freshPad()
        pad.assign(slot: 2, action: MacroAction.find("off")!)
        pad.loadExecutor(slot: 2, number: 201)
        XCTAssertEqual(pad.slot(at: 2), .action(MacroAction.find("off")!))
        pad.loadExecutor(slot: 3, number: 201)   // empty slot
        XCTAssertNil(pad.slot(at: 3))
    }

    func test_executor_assignments_survive_reinit() {
        let suite = "macropad.exec.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let p1 = MacroPad(defaults: d)
        p1.assignExecutor(slot: 0)
        p1.loadExecutor(slot: 0, number: 7)
        p1.assignExecutor(slot: 2)
        let p2 = MacroPad(defaults: d)
        XCTAssertEqual(p2.slot(at: 0), .executor(number: 7))
        XCTAssertEqual(p2.slot(at: 2), .executor(number: nil))
        XCTAssertNil(p2.slot(at: 1))
    }

    func test_slot_at_decodes_actions_too() {
        let pad = freshPad()
        pad.assign(slot: 0, action: MacroAction.find("pause")!)
        XCTAssertEqual(pad.slot(at: 0), .action(MacroAction.find("pause")!))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/cuelist-compiler/ios && xcodegen generate && set -o pipefail && \
xcodebuild test -project Saetta.xcodeproj -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: **BUILD FAILS** — `value of type 'MacroPad' has no member 'assignExecutor'` (and `slot(at:)`, `loadExecutor`).

- [ ] **Step 3: Write the implementation**

In `ios/Sources/Kit/Macro/MacroPad.swift`, replace the existing `action(at:)` method with the following block (keep `assign(slot:action:)`, `clear(slot:)`, and `persist()` exactly as they are):

```swift
    /// The decoded value in `slot`, or nil if empty / out of range / undecodable.
    public func slot(at slot: Int) -> MacroSlot? {
        guard slots.indices.contains(slot), let raw = slots[slot] else { return nil }
        return MacroSlot(rawValue: raw)
    }

    /// The action currently in `slot`, or nil if empty / not an action.
    public func action(at slot: Int) -> MacroAction? {
        if case .action(let action)? = self.slot(at: slot) { return action }
        return nil
    }

    /// Make a slot an executor button with no target yet (step 1 of the double
    /// assign). Out-of-range slots are ignored.
    public func assignExecutor(slot: Int) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = MacroSlot.executor(number: nil).rawValue
        persist()
    }

    /// Point an executor slot at a numbered executor (step 2). No-op unless the
    /// slot currently holds an executor and the number is in range.
    public func loadExecutor(slot: Int, number: Int) {
        guard case .executor? = self.slot(at: slot),
              MacroSlot.executorRange.contains(number) else { return }
        slots[slot] = MacroSlot.executor(number: number).rawValue
        persist()
    }
```

Also update the class doc comment's first line to mention both kinds, e.g.:

```swift
/// The Live tab's four-slot macro pad. Holds the operator's assigned actions and
/// executor toggles app-wide, persisted to UserDefaults like the hub host/port.
/// Pure state — never touches the network; firing is the view's job via HubClient.
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: **TEST SUCCEEDED** — new tests green, and every pre-existing `MacroPadTests` case (including `test_unknown_persisted_id_reads_as_nil_but_is_preserved`) still green: `slot(at:)` returns nil for `"ghost_action"` while the raw string stays in `slots[0]`, exactly as before.

- [ ] **Step 5: Commit**

```bash
cd ~/cuelist-compiler && git add ios/Sources/Kit/Macro/MacroPad.swift ios/Tests/KitTests/MacroPadTests.swift && \
git commit -m "feat(kit): MacroPad executor slots — assignExecutor/loadExecutor + slot(at:)"
```

---

### Task 3: Live-tab UI — executor button states, load sheet, picker row

**Files:**
- Modify: `ios/Sources/App/MacroPadView.swift` (whole file; final content below)

UI only — Kit is already done and tested. The view follows the spec's state table: unloaded executor renders pending `EXEC —` and a tap opens the load sheet (never fires); loaded renders the number big over an `EXEC` caption and fires `Toggle Executor <n>`; executor slots get a "Load Executor…" context-menu item above Reassign…/Clear; the assign picker gets an "Executor (toggle)" section above the action library.

- [ ] **Step 1: Replace `MacroPadView.swift`**

Full new content of `ios/Sources/App/MacroPadView.swift`:

```swift
import SwiftUI
import SaettaKit

/// The Live tab's 2×2 macro pad. Each cell holds an assignable value that fires on
/// the desk through the hub's `cmd` passthrough: a parameter-free action (runs on
/// the desk-selected executor) or an executor toggle (Toggle Executor <n>, current
/// page). Tap empty → picker; tap assigned → fire; tap an unloaded executor → load
/// sheet; long-press assigned → load/reassign/clear.
struct MacroPadView: View {
    @Environment(MacroPad.self) private var pad
    @Environment(HubClient.self) private var hub
    let onFire: () -> Void                     // haptic trigger, shared with transport

    private struct SlotTarget: Identifiable { let id: Int }   // id == slot index
    @State private var picker: SlotTarget?
    @State private var execLoad: SlotTarget?

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<MacroPad.slotCount, id: \.self) { slot in
                MacroButton(
                    slot: pad.slot(at: slot),
                    isOnline: hub.state.isOnline,
                    onTap: { handleTap(slot) },
                    onLoadExecutor: { execLoad = SlotTarget(id: slot) },
                    onReassign: { picker = SlotTarget(id: slot) },
                    onClear: { pad.clear(slot: slot) }
                )
            }
        }
        .sheet(item: $picker) { target in
            MacroPickerSheet(
                onPick: { action in
                    pad.assign(slot: target.id, action: action)
                    picker = nil
                },
                onPickExecutor: {
                    pad.assignExecutor(slot: target.id)
                    picker = nil
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $execLoad) { target in
            ExecutorLoadSheet(onLoad: { number in
                pad.loadExecutor(slot: target.id, number: number)
                execLoad = nil
            })
            .presentationDetents([.height(240)])
        }
    }

    private func handleTap(_ slot: Int) {
        switch pad.slot(at: slot) {
        case nil:
            picker = SlotTarget(id: slot)              // empty slot — assign even offline
        case .executor(number: nil):
            execLoad = SlotTarget(id: slot)            // step 2 of the double assign
        case let value?:
            guard hub.state.isOnline, let command = value.command else { return }
            hub.sendCommand(command)
            onFire()
        }
    }
}

/// One macro-pad cell, rendered per slot value:
/// action → tinted symbol + title; loaded executor → big number over EXEC caption;
/// unloaded executor → pending "EXEC —"; empty → dashed Assign placeholder.
private struct MacroButton: View {
    let slot: MacroSlot?
    let isOnline: Bool
    let onTap: () -> Void
    let onLoadExecutor: () -> Void
    let onReassign: () -> Void
    let onClear: () -> Void

    private var isExecutor: Bool {
        if case .executor = slot { return true }
        return false
    }

    /// Only slots that can actually fire dim when the hub is offline; the pending
    /// executor's tap opens the load sheet, which works offline.
    private var canFire: Bool { slot?.command != nil }

    var body: some View {
        if slot != nil {
            button.contextMenu {
                if isExecutor {
                    Button { onLoadExecutor() } label: { Label("Load Executor\u{2026}", systemImage: "number") }
                }
                Button { onReassign() } label: { Label("Reassign\u{2026}", systemImage: "arrow.triangle.2.circlepath") }
                Button(role: .destructive) { onClear() } label: { Label("Clear", systemImage: "xmark") }
            }
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: onTap) {
            content
                .frame(maxWidth: .infinity)
                .frame(height: 76)
        }
        .buttonStyle(PressScaleStyle())
        .opacity(canFire && !isOnline ? 0.4 : 1)
    }

    @ViewBuilder private var content: some View {
        switch slot {
        case .action(let action):
            VStack(spacing: 6) {
                Image(systemName: action.symbol).font(.system(size: 26, weight: .bold))
                Text(action.title).font(.system(size: 17, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accentSolid.gradient, in: RoundedRectangle(cornerRadius: Theme.radius))
        case .executor(let number?):
            VStack(spacing: 2) {
                Text("\(number)").font(Theme.mono(size: 26, weight: .heavy))
                Text("EXEC").font(.system(size: 11, weight: .semibold)).opacity(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accentSolid.gradient, in: RoundedRectangle(cornerRadius: Theme.radius))
        case .executor(nil):
            VStack(spacing: 2) {
                Text("\u{2014}").font(Theme.mono(size: 26, weight: .heavy))
                Text("EXEC").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            )
        case nil:
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
                Text("Assign").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            )
        }
    }
}

/// Lists the executor option then the curated macro library; one tap assigns and
/// dismisses.
private struct MacroPickerSheet: View {
    let onPick: (MacroAction) -> Void
    let onPickExecutor: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { onPickExecutor() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "switch.2")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.accentSolid)
                                .frame(width: 26)
                            Text("Executor (toggle)").foregroundStyle(Theme.text)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(Theme.surface1)
                }
                Section {
                    ForEach(MacroAction.library) { action in
                        Button { onPick(action) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: action.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.accentSolid)
                                    .frame(width: 26)
                                Text(action.title).foregroundStyle(Theme.text)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(Theme.surface1)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Assign action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accentSolid)
                }
            }
        }
    }
}

/// Number-pad sheet that points an executor slot at a desk executor (1–9999,
/// current page). Load is disabled until the input is a valid number.
private struct ExecutorLoadSheet: View {
    let onLoad: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var number: Int? {
        guard let n = Int(text), MacroSlot.executorRange.contains(n) else { return nil }
        return n
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField("Executor number", text: $text)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .font(Theme.mono(size: 24, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .hudPanel()

                Button("Load") { if let n = number { onLoad(n) } }
                    .buttonStyle(AmberCTAStyle())
                    .disabled(number == nil)
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.canvas)
            .navigationTitle("Load Executor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accentSolid)
                }
            }
            .onAppear { focused = true }
        }
    }
}
```

- [ ] **Step 2: Build the app + run the full Kit suite**

```bash
cd ~/cuelist-compiler/ios && xcodegen generate && set -o pipefail && \
xcodebuild build -project Saetta.xcodeproj -scheme Saetta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5 && \
xcodebuild test -project Saetta.xcodeproj -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED** then **TEST SUCCEEDED** (full Kit suite — nothing else in the app referenced `pad.action(at:)`, only this view did).

- [ ] **Step 3: Commit**

```bash
cd ~/cuelist-compiler && git add ios/Sources/App/MacroPadView.swift && \
git commit -m "feat(ios-ui): executor toggle buttons on the Live macro pad — double assign + load sheet"
```

---

## Acceptance (manual, sim or device — after all tasks)

1. Live tab → tap an empty pad slot → picker shows "Executor (toggle)" section above the action list.
2. Pick it → slot renders pending `— / EXEC` dashed style.
3. Tap the pending slot → "Load Executor" sheet opens; Load disabled for empty/`0`/`10000`; enter `201` → Load.
4. Slot shows `201 / EXEC`; with the hub online a tap fires `Toggle Executor 201` (visible in the hub console / desk); offline the button dims and doesn't fire.
5. Long-press the slot → menu shows Load Executor… / Reassign… / Clear; Load re-targets, Reassign returns to the picker, Clear empties.
6. Kill and relaunch the app → assignments (including an unloaded executor) survive.
