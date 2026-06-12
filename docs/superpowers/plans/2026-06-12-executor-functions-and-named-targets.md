# Executor Functions (toggle/flash/on) + Named Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Live-tab macro pad's executor buttons with three functions — toggle (tap), flash (momentary hold), on (tap) — and let a button target a desk executor by name string as well as by number.

**Architecture:** Extend the existing `exec:` string codec to `exec:<function>:<target>` over the same UserDefaults `[String]` storage (legacy `exec:`/`exec:201` decode as toggle — no migration). `MacroSlot` gains `ExecutorFunction` + `ExecutorTarget` and a `releaseCommand` (flash only); `MacroPad` gains function-aware assign/load; the view adds three picker rows, a smart number-or-name load field, function captions on cells, and a press-reporting button style for momentary flash.

**Tech Stack:** Swift / SwiftUI, XCTest, xcodegen + xcodebuild.

**Spec:** `docs/superpowers/specs/2026-06-12-executor-functions-and-named-targets-design.md`

**Environment:**
- Worktree: `/tmp/exec-fn-wt`, branch `feat/exec-functions` (off `origin/main` @ `3b37de2`). Do NOT touch `~/cuelist-compiler` — it's shared with another session.
- Run `xcodegen generate` in `/tmp/exec-fn-wt/ios` before every `xcodebuild`.
- Always `set -o pipefail` before piping xcodebuild to `tail`.
- SourceKit/IDE diagnostics on SaettaKit files are often false — xcodebuild output is authoritative.
- Kit test command (used throughout):
  ```bash
  cd /tmp/exec-fn-wt/ios && xcodegen generate && set -o pipefail && \
  xcodebuild test -project Saetta.xcodeproj -scheme SaettaKit \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
  ```
  (If that simulator is missing, pick one from `xcrun simctl list devices available`.)
- **The App target is allowed to NOT compile during Tasks 1–2** (it still uses the old enum shape). The `SaettaKit` test scheme builds only SaettaKit + SaettaKitTests, so Kit tests run fine. Task 3 fixes the app.

---

### Task 1: `MacroSlot` — functions, targets, new codec, commands

**Files:**
- Modify: `ios/Sources/Kit/Macro/MacroSlot.swift` (full rewrite below)
- Modify: `ios/Sources/Kit/Macro/MacroPad.swift` (mechanical compile fix only — full behavior is Task 2)
- Test: `ios/Tests/KitTests/MacroSlotTests.swift` (full rewrite below)

- [ ] **Step 1: Replace `MacroSlotTests.swift` with the new test suite**

Replace the entire contents of `ios/Tests/KitTests/MacroSlotTests.swift` with:

```swift
import XCTest
@testable import SaettaKit

final class MacroSlotTests: XCTestCase {

    // MARK: Decoding — actions

    func test_decodes_library_action_id() {
        guard case .action(let action)? = MacroSlot(rawValue: "go_plus") else {
            return XCTFail("expected .action")
        }
        XCTAssertEqual(action.id, "go_plus")
    }

    // MARK: Decoding — legacy executor form (PR #32, no function segment)

    func test_decodes_legacy_unloaded_executor_as_toggle() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:"),
                       .executor(function: .toggle, target: nil))
    }

    func test_decodes_legacy_loaded_executor_as_toggle() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:201"),
                       .executor(function: .toggle, target: .number(201)))
    }

    // MARK: Decoding — new executor form exec:<function>:<target>

    func test_decodes_function_with_number_target() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:toggle:201"),
                       .executor(function: .toggle, target: .number(201)))
        XCTAssertEqual(MacroSlot(rawValue: "exec:flash:7"),
                       .executor(function: .flash, target: .number(7)))
        XCTAssertEqual(MacroSlot(rawValue: "exec:on:9999"),
                       .executor(function: .on, target: .number(9999)))
    }

    func test_decodes_function_with_name_target() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:flash:Blinders"),
                       .executor(function: .flash, target: .name("Blinders")))
    }

    func test_decodes_unloaded_executor_per_function() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:flash:"),
                       .executor(function: .flash, target: nil))
        XCTAssertEqual(MacroSlot(rawValue: "exec:on:"),
                       .executor(function: .on, target: nil))
    }

    func test_name_containing_colon_survives() {
        // Only the FIRST colon after "exec:" splits function from target.
        XCTAssertEqual(MacroSlot(rawValue: "exec:on:FX: Strobe"),
                       .executor(function: .on, target: .name("FX: Strobe")))
    }

    func test_rejects_unknown_and_malformed_strings() {
        XCTAssertNil(MacroSlot(rawValue: "ghost_action"))
        XCTAssertNil(MacroSlot(rawValue: "exec:abc"))          // legacy body must be digits
        XCTAssertNil(MacroSlot(rawValue: "exec:0"))
        XCTAssertNil(MacroSlot(rawValue: "exec:10000"))
        XCTAssertNil(MacroSlot(rawValue: "exec:-3"))
        XCTAssertNil(MacroSlot(rawValue: "exec:strobe:201"))   // unknown function
        XCTAssertNil(MacroSlot(rawValue: "exec:flash:0"))      // all-digits out of range
        XCTAssertNil(MacroSlot(rawValue: "exec:on:10000"))
        XCTAssertNil(MacroSlot(rawValue: "exec:toggle:   "))   // whitespace-only name
    }

    // MARK: Round-trip

    func test_rawValue_round_trips() {
        let slots: [MacroSlot] = [
            .action(MacroAction.find("off")!),
            .executor(function: .toggle, target: nil),
            .executor(function: .toggle, target: .number(1)),
            .executor(function: .flash, target: .number(9999)),
            .executor(function: .on, target: .name("Blinders")),
            .executor(function: .flash, target: .name("FX: Strobe")),
        ]
        for slot in slots {
            XCTAssertEqual(MacroSlot(rawValue: slot.rawValue), slot)
        }
    }

    func test_legacy_value_reencodes_in_new_form() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:201")!.rawValue, "exec:toggle:201")
        XCTAssertEqual(MacroSlot(rawValue: "exec:")!.rawValue, "exec:toggle:")
    }

    // MARK: Commands

    func test_toggle_command_has_no_release() {
        let slot = MacroSlot.executor(function: .toggle, target: .number(201))
        XCTAssertEqual(slot.command, "Toggle Executor 201")
        XCTAssertNil(slot.releaseCommand)
    }

    func test_flash_commands_press_and_release() {
        let slot = MacroSlot.executor(function: .flash, target: .number(201))
        XCTAssertEqual(slot.command, "Flash Executor 201")
        XCTAssertEqual(slot.releaseCommand, "FlashOff Executor 201")
    }

    func test_on_command_has_no_release() {
        let slot = MacroSlot.executor(function: .on, target: .number(201))
        XCTAssertEqual(slot.command, "On Executor 201")
        XCTAssertNil(slot.releaseCommand)
    }

    func test_named_target_renders_quoted() {
        let slot = MacroSlot.executor(function: .flash, target: .name("Blinders"))
        XCTAssertEqual(slot.command, "Flash Executor \"Blinders\"")
        XCTAssertEqual(slot.releaseCommand, "FlashOff Executor \"Blinders\"")
    }

    func test_unloaded_executor_has_no_commands() {
        XCTAssertNil(MacroSlot.executor(function: .flash, target: nil).command)
        XCTAssertNil(MacroSlot.executor(function: .flash, target: nil).releaseCommand)
    }

    func test_action_command_passes_through_and_has_no_release() {
        let slot = MacroSlot.action(MacroAction.find("go_plus")!)
        XCTAssertEqual(slot.command, "Go+")
        XCTAssertNil(slot.releaseCommand)
    }
}
```

- [ ] **Step 2: Run Kit tests to verify they fail to compile**

Run the Kit test command (see Environment). Expected: **BUILD FAILED** — `MacroSlot` has no case `executor(function:target:)`, `ExecutorFunction`/`ExecutorTarget` unresolved.

- [ ] **Step 3: Rewrite `MacroSlot.swift`**

Replace the entire contents of `ios/Sources/Kit/Macro/MacroSlot.swift` with:

```swift
import Foundation

/// Which grandMA3 function an executor macro button performs.
/// `rawValue` doubles as the persisted codec segment.
public enum ExecutorFunction: String, CaseIterable, Sendable {
    case toggle, flash, on

    /// The grandMA3 keyword that engages the function.
    var keyword: String {
        switch self {
        case .toggle: "Toggle"
        case .flash: "Flash"
        case .on: "On"
        }
    }

    /// Caption rendered under the target on the macro cell.
    public var caption: String { rawValue.uppercased() }
}

/// What an executor macro button targets: an executor number on the desk's
/// current page, or an executor by its desk label.
public enum ExecutorTarget: Equatable, Sendable {
    case number(Int)      // 1...9999, current page
    case name(String)     // non-empty, trimmed

    /// The form persisted inside the slot string (no quoting).
    var encoded: String {
        switch self {
        case .number(let n): String(n)
        case .name(let s): s
        }
    }

    /// How the target renders in a grandMA3 command: bare number, quoted name.
    var commandForm: String {
        switch self {
        case .number(let n): String(n)
        case .name(let s): "\"\(s)\""
        }
    }

    /// What the macro cell displays.
    public var display: String {
        switch self {
        case .number(let n): String(n)
        case .name(let s): s
        }
    }
}

/// The value held by one Live-tab macro-pad slot: either a curated parameter-free
/// action, or an executor button (toggle / flash / on) targeting a desk executor
/// by number (current page) or by name. Encodes to/from the single `String` per
/// slot that `MacroPad` persists — an `"exec:"` prefix marks executor slots;
/// anything else is an action id. New form is `exec:<function>:<target>`; legacy
/// `exec:` / `exec:<digits>` (PR #32) decodes as a toggle, so saved pads load
/// unchanged.
public enum MacroSlot: RawRepresentable, Equatable, Sendable {
    case action(MacroAction)
    /// `target == nil` — assigned but not yet loaded; renders as pending, never fires.
    case executor(function: ExecutorFunction, target: ExecutorTarget?)

    /// Executor numbers the load sheet and the decoder accept.
    public static let executorRange: ClosedRange<Int> = 1...9999

    private static let execPrefix = "exec:"

    /// Decode a persisted slot string. Unknown action ids, unknown functions,
    /// out-of-range numbers, and whitespace-only names decode to nil (empty
    /// slot) — never a crash or a bad command.
    public init?(rawValue: String) {
        guard rawValue.hasPrefix(Self.execPrefix) else {
            guard let action = MacroAction.find(rawValue) else { return nil }
            self = .action(action)
            return
        }
        let body = rawValue.dropFirst(Self.execPrefix.count)
        let function: ExecutorFunction
        let targetRaw: Substring
        if let colon = body.firstIndex(of: ":") {
            guard let parsed = ExecutorFunction(rawValue: String(body[..<colon])) else { return nil }
            function = parsed
            targetRaw = body[body.index(after: colon)...]
        } else {
            // Legacy form only ever held digits (or nothing) and meant toggle.
            guard body.isEmpty || body.allSatisfy(\.isNumber) else { return nil }
            function = .toggle
            targetRaw = body
        }
        if targetRaw.isEmpty {
            self = .executor(function: function, target: nil)
        } else if targetRaw.allSatisfy(\.isNumber) {
            // All-digits is always a number — an executor *named* "201" resolves
            // to executor 201, which addresses the same object on MA3.
            guard let n = Int(targetRaw), Self.executorRange.contains(n) else { return nil }
            self = .executor(function: function, target: .number(n))
        } else {
            let name = targetRaw.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            self = .executor(function: function, target: .name(name))
        }
    }

    /// The string `MacroPad` persists for this slot — always the new
    /// three-segment form for executors.
    public var rawValue: String {
        switch self {
        case .action(let action): action.id
        case .executor(let function, let target):
            Self.execPrefix + function.rawValue + ":" + (target?.encoded ?? "")
        }
    }

    /// The command-line string a tap (toggle/on) or touch-down (flash) fires,
    /// or nil if this slot can't fire yet.
    public var command: String? {
        switch self {
        case .action(let action): action.command
        case .executor(let function, let target):
            target.map { "\(function.keyword) Executor \($0.commandForm)" }
        }
    }

    /// The command touch-up fires — only flash needs a release.
    public var releaseCommand: String? {
        guard case .executor(function: .flash, target: let target?) = self else { return nil }
        return "FlashOff Executor \(target.commandForm)"
    }
}
```

- [ ] **Step 4: Mechanical compile fix in `MacroPad.swift`**

`MacroPad` still references the old case shape and won't compile. Update ONLY these two methods (behavioral tests come in Task 2). In `ios/Sources/Kit/Macro/MacroPad.swift` replace `assignExecutor(slot:)` and `loadExecutor(slot:number:)` with:

```swift
    /// Make a slot an executor button with no target yet (step 1 of the double
    /// assign), remembering which function it performs. Out-of-range slots are
    /// ignored.
    public func assignExecutor(slot: Int, function: ExecutorFunction) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = MacroSlot.executor(function: function, target: nil).rawValue
        persist()
    }

    /// Point an executor slot at a target (step 2), keeping the slot's function.
    /// No-op unless the slot currently holds an executor and the target is valid.
    public func loadExecutor(slot: Int, target: ExecutorTarget) {
        guard case .executor(let function, _)? = self.slot(at: slot) else { return }
        if case .number(let n) = target, !MacroSlot.executorRange.contains(n) { return }
        slots[slot] = MacroSlot.executor(function: function, target: target).rawValue
        persist()
    }
```

Also update the class doc comment's first sentence to say "executor buttons" instead of "executor toggles".

`MacroPadTests.swift` still calls the old signatures and won't compile — update the three OLD call sites mechanically so the suite builds (full executor-section rewrite is Task 2):
- `pad.assignExecutor(slot: N)` → `pad.assignExecutor(slot: N, function: .toggle)`
- `pad.loadExecutor(slot: N, number: M)` → `pad.loadExecutor(slot: N, target: .number(M))`
- every `.executor(number: nil)` → `.executor(function: .toggle, target: nil)` and `.executor(number: M)` → `.executor(function: .toggle, target: .number(M))`

- [ ] **Step 5: Run Kit tests to verify they pass**

Run the Kit test command. Expected: **TEST SUCCEEDED**, zero failures.

- [ ] **Step 6: Commit**

```bash
cd /tmp/exec-fn-wt && git add ios/Sources/Kit/Macro/MacroSlot.swift ios/Sources/Kit/Macro/MacroPad.swift ios/Tests/KitTests/MacroSlotTests.swift ios/Tests/KitTests/MacroPadTests.swift && git commit -m "feat(kit): executor functions (toggle/flash/on) + named targets in MacroSlot codec"
```

---

### Task 2: `MacroPad` — function-preserving load + name validation

**Files:**
- Modify: `ios/Sources/Kit/Macro/MacroPad.swift` (name-trim validation in `loadExecutor`)
- Test: `ios/Tests/KitTests/MacroPadTests.swift` (rewrite the `// MARK: Executor slots` section)

- [ ] **Step 1: Rewrite the executor-slot tests**

In `ios/Tests/KitTests/MacroPadTests.swift`, replace everything from `// MARK: Executor slots` to the end of `test_executor_assignments_survive_reinit` (keep `test_slot_at_decodes_actions_too`) with:

```swift
    // MARK: Executor slots

    func test_assignExecutor_sets_unloaded_executor_with_function() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .flash)
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .flash, target: nil))
        XCTAssertNil(pad.action(at: 0), "an executor slot is not an action")
    }

    func test_loadExecutor_targets_number_keeping_function() {
        let pad = freshPad()
        pad.assignExecutor(slot: 1, function: .on)
        pad.loadExecutor(slot: 1, target: .number(201))
        XCTAssertEqual(pad.slot(at: 1), .executor(function: .on, target: .number(201)))
    }

    func test_loadExecutor_targets_name_trimmed() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .toggle)
        pad.loadExecutor(slot: 0, target: .name("  Blinders "))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .toggle, target: .name("Blinders")))
    }

    func test_loadExecutor_rejects_blank_name() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .toggle)
        pad.loadExecutor(slot: 0, target: .name("   "))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .toggle, target: nil))
    }

    func test_loadExecutor_retargets_loaded_slot() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .flash)
        pad.loadExecutor(slot: 0, target: .number(201))
        pad.loadExecutor(slot: 0, target: .name("Blinders"))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .flash, target: .name("Blinders")))
    }

    func test_loadExecutor_rejects_out_of_range_number() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .toggle)
        pad.loadExecutor(slot: 0, target: .number(0))
        pad.loadExecutor(slot: 0, target: .number(10000))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .toggle, target: nil))
    }

    func test_loadExecutor_on_non_executor_slot_is_noop() {
        let pad = freshPad()
        pad.assign(slot: 2, action: MacroAction.find("off")!)
        pad.loadExecutor(slot: 2, target: .number(201))
        XCTAssertEqual(pad.slot(at: 2), .action(MacroAction.find("off")!))
        pad.loadExecutor(slot: 3, target: .number(201))   // empty slot
        XCTAssertNil(pad.slot(at: 3), "loadExecutor on an empty slot must stay a noop")
    }

    func test_assignExecutor_out_of_range_slot_is_safe_noop() {
        let pad = freshPad()
        pad.assignExecutor(slot: 9, function: .toggle)
        pad.assignExecutor(slot: -1, function: .flash)
        XCTAssertTrue(pad.slots.allSatisfy { $0 == nil })
    }

    func test_executor_assignments_survive_reinit() {
        let suite = "macropad.exec.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let p1 = MacroPad(defaults: d)
        p1.assignExecutor(slot: 0, function: .flash)
        p1.loadExecutor(slot: 0, target: .name("Blinders"))
        p1.assignExecutor(slot: 2, function: .on)
        let p2 = MacroPad(defaults: d)
        XCTAssertEqual(p2.slot(at: 0), .executor(function: .flash, target: .name("Blinders")))
        XCTAssertEqual(p2.slot(at: 2), .executor(function: .on, target: nil))
        XCTAssertNil(p2.slot(at: 1))
    }

    func test_legacy_persisted_executor_loads_as_toggle() {
        let suite = "macropad.legacy.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        // A pad saved by the PR #32 build (pre-function codec).
        d.set(["exec:201", "exec:", "", ""], forKey: "macroPadSlots")
        let pad = MacroPad(defaults: d)
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .toggle, target: .number(201)))
        XCTAssertEqual(pad.slot(at: 1), .executor(function: .toggle, target: nil))
    }
```

- [ ] **Step 2: Run Kit tests to verify the new ones fail**

Run the Kit test command. Expected: `test_loadExecutor_targets_name_trimmed` and `test_loadExecutor_rejects_blank_name` **FAIL** (untrimmed name stored / blank name accepted); everything else passes.

- [ ] **Step 3: Add name validation to `loadExecutor`**

In `ios/Sources/Kit/Macro/MacroPad.swift`, replace the `loadExecutor` body with:

```swift
    /// Point an executor slot at a target (step 2), keeping the slot's function.
    /// No-op unless the slot currently holds an executor and the target is valid:
    /// numbers must be in range, names non-blank (stored trimmed).
    public func loadExecutor(slot: Int, target: ExecutorTarget) {
        guard case .executor(let function, _)? = self.slot(at: slot) else { return }
        let validated: ExecutorTarget
        switch target {
        case .number(let n):
            guard MacroSlot.executorRange.contains(n) else { return }
            validated = target
        case .name(let raw):
            let name = raw.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            validated = .name(name)
        }
        slots[slot] = MacroSlot.executor(function: function, target: validated).rawValue
        persist()
    }
```

- [ ] **Step 4: Run Kit tests to verify all pass**

Run the Kit test command. Expected: **TEST SUCCEEDED**, zero failures.

- [ ] **Step 5: Commit**

```bash
cd /tmp/exec-fn-wt && git add ios/Sources/Kit/Macro/MacroPad.swift ios/Tests/KitTests/MacroPadTests.swift && git commit -m "feat(kit): function-preserving executor load with name-target validation"
```

---

### Task 3: Macro pad UI — picker rows, smart load field, function captions, momentary flash

**Files:**
- Modify: `ios/Sources/App/MacroPadView.swift` (full rewrite below)

No new unit tests — this is SwiftUI glue over the Kit logic tested in Tasks 1–2; the flash gesture is verified on device during desk acceptance.

- [ ] **Step 1: Rewrite `MacroPadView.swift`**

Replace the entire contents of `ios/Sources/App/MacroPadView.swift` with:

```swift
import SwiftUI
import SaettaKit

/// The Live tab's 2×2 macro pad. Each cell holds an assignable value that fires on
/// the desk through the hub's `cmd` passthrough: a parameter-free action (runs on
/// the desk-selected executor) or an executor button — toggle / on fire on tap,
/// flash is momentary (Flash on touch-down, FlashOff on touch-up or cancel) —
/// targeting an executor by number (current page) or by desk name. Tap empty →
/// picker; tap assigned → fire; tap an unloaded executor → load sheet; long-press
/// assigned → load/reassign/clear.
struct MacroPadView: View {
    @Environment(MacroPad.self) private var pad
    @Environment(HubClient.self) private var hub
    let onFire: () -> Void                     // haptic trigger, shared with transport

    private struct SlotTarget: Identifiable { let id: Int }   // id == slot index
    @State private var picker: SlotTarget?
    @State private var execLoad: SlotTarget?
    /// Slots whose flash press actually sent — gates the matching FlashOff so a
    /// release never fires without its press, and at most once per press.
    @State private var flashPressed: Set<Int> = []

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<MacroPad.slotCount, id: \.self) { slot in
                MacroButton(
                    slot: pad.slot(at: slot),
                    isOnline: hub.state.isOnline,
                    onTap: { handleTap(slot) },
                    onFlashPress: { handleFlashPress(slot) },
                    onFlashRelease: { handleFlashRelease(slot) },
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
                onPickExecutor: { function in
                    pad.assignExecutor(slot: target.id, function: function)
                    picker = nil
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $execLoad) { target in
            ExecutorLoadSheet(onLoad: { execTarget in
                pad.loadExecutor(slot: target.id, target: execTarget)
                execLoad = nil
            })
            .presentationDetents([.height(240)])
        }
    }

    private func handleTap(_ slot: Int) {
        switch pad.slot(at: slot) {
        case nil:
            picker = SlotTarget(id: slot)              // empty slot — assign even offline
        case .executor(_, nil):
            execLoad = SlotTarget(id: slot)            // step 2 of the double assign
        case let value?:
            guard hub.state.isOnline, let command = value.command else { return }
            hub.sendCommand(command)
            onFire()
        }
    }

    /// Touch-down on a loaded flash cell: engage flash, remember the press.
    private func handleFlashPress(_ slot: Int) {
        guard hub.state.isOnline, let command = pad.slot(at: slot)?.command else { return }
        hub.sendCommand(command)
        flashPressed.insert(slot)
        onFire()
    }

    /// Touch-up or gesture cancel on a flash cell: release — only if this press
    /// engaged it, so the desk is never left flashed and never gets an orphan
    /// FlashOff.
    private func handleFlashRelease(_ slot: Int) {
        guard flashPressed.remove(slot) != nil,
              let release = pad.slot(at: slot)?.releaseCommand else { return }
        hub.sendCommand(release)
    }
}

/// One macro-pad cell, rendered per slot value:
/// action → tinted symbol + title; loaded executor → big target over its function
/// caption (TOGGLE / FLASH / ON); unloaded executor → pending "—"; empty →
/// dashed Assign placeholder.
private struct MacroButton: View {
    let slot: MacroSlot?
    let isOnline: Bool
    let onTap: () -> Void
    let onFlashPress: () -> Void
    let onFlashRelease: () -> Void
    let onLoadExecutor: () -> Void
    let onReassign: () -> Void
    let onClear: () -> Void

    private var isExecutor: Bool {
        if case .executor = slot { return true }
        return false
    }

    /// Loaded flash cells fire on press/release, not tap.
    private var isMomentary: Bool {
        if case .executor(function: .flash, target: .some) = slot { return true }
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

    @ViewBuilder private var button: some View {
        if isMomentary {
            // Momentary flash: the Button supplies pressed state; the style relays
            // touch-down/up — SwiftUI clears isPressed on cancellation too (e.g.
            // the context-menu long-press taking over), so FlashOff always follows.
            Button(action: {}) {
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
            }
            .buttonStyle(PressReportingScaleStyle(onPress: onFlashPress, onRelease: onFlashRelease))
            .opacity(canFire && !isOnline ? 0.4 : 1)
        } else {
            Button(action: onTap) {
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
            }
            .buttonStyle(PressScaleStyle())
            .opacity(canFire && !isOnline ? 0.4 : 1)
        }
    }

    @ViewBuilder private var content: some View {
        switch slot {
        case .action(let action):
            VStack(spacing: 6) {
                Image(systemName: action.symbol).font(.system(size: 26, weight: .bold))
                    .accessibilityHidden(true)
                Text(action.title).font(.system(size: 17, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accentSolid.gradient, in: RoundedRectangle(cornerRadius: Theme.radius))
            .accessibilityLabel("\(action.title), macro")
        case .executor(let function, let target?):
            VStack(spacing: 2) {
                targetText(target)
                Text(function.caption).font(.system(size: 11, weight: .semibold)).opacity(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accentSolid.gradient, in: RoundedRectangle(cornerRadius: Theme.radius))
            .accessibilityLabel("Executor \(target.display), \(function.rawValue)")
        case .executor(let function, nil):
            VStack(spacing: 2) {
                Text("\u{2014}").font(Theme.mono(size: 26, weight: .heavy))
                Text(function.caption).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            )
            .accessibilityLabel("Executor pending, tap to load")
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

    /// Numbers keep the big mono treatment; names shrink to fit one line.
    @ViewBuilder private func targetText(_ target: ExecutorTarget) -> some View {
        switch target {
        case .number(let n):
            Text("\(n)").font(Theme.mono(size: 26, weight: .heavy))
        case .name(let name):
            Text(name)
                .font(.system(size: 17, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 6)
        }
    }
}

/// PressScaleStyle that also reports touch-down / touch-up, for momentary cells.
struct PressReportingScaleStyle: ButtonStyle {
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                pressed ? onPress() : onRelease()
            }
    }
}

/// Lists the three executor functions then the curated macro library; one tap
/// assigns and dismisses.
private struct MacroPickerSheet: View {
    let onPick: (MacroAction) -> Void
    let onPickExecutor: (ExecutorFunction) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let executorRows: [(function: ExecutorFunction, title: String, symbol: String)] = [
        (.toggle, "Executor (toggle)", "switch.2"),
        (.flash, "Executor (flash)", "bolt.fill"),
        (.on, "Executor (on)", "power"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Executor") {
                    ForEach(Self.executorRows, id: \.function) { row in
                        Button { onPickExecutor(row.function) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: row.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.accentSolid)
                                    .frame(width: 26)
                                Text(row.title).foregroundStyle(Theme.text)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(Theme.surface1)
                    }
                }
                Section("Actions") {
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
            .navigationTitle("Assign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accentSolid)
                }
            }
        }
    }
}

/// One smart field that points an executor slot at a desk executor: all-digits
/// input is a number (1–9999, current page), anything else is the executor's
/// desk name. Load stays disabled until the input is valid.
private struct ExecutorLoadSheet: View {
    let onLoad: (ExecutorTarget) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var target: ExecutorTarget? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy(\.isNumber) {
            guard let n = Int(trimmed), MacroSlot.executorRange.contains(n) else { return nil }
            return .number(n)
        }
        return .name(trimmed)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField("Number or name", text: $text)
                    .keyboardType(.default)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .font(Theme.mono(size: 24, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .hudPanel()

                Button("Load") { if let t = target { onLoad(t) } }
                    .buttonStyle(AmberCTAStyle())
                    .disabled(target == nil)
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

- [ ] **Step 2: Build the app to verify it compiles**

```bash
cd /tmp/exec-fn-wt/ios && xcodegen generate && set -o pipefail && \
xcodebuild build -project Saetta.xcodeproj -scheme Saetta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**.

- [ ] **Step 3: Commit**

```bash
cd /tmp/exec-fn-wt && git add ios/Sources/App/MacroPadView.swift && git commit -m "feat(ios-ui): flash/on executor cells, three picker rows, number-or-name load field"
```

---

### Task 4: Full verification

- [ ] **Step 1: Run the entire Kit test suite**

Run the Kit test command (see Environment). Expected: **TEST SUCCEEDED**, zero failures (suite was 224 tests before this work; now larger).

- [ ] **Step 2: Build the app**

Run the app build command from Task 3 Step 2. Expected: **BUILD SUCCEEDED**.

- [ ] **Step 3: Check the tree is clean and the branch is coherent**

```bash
cd /tmp/exec-fn-wt && git status --short && git log --oneline origin/main..HEAD
```

Expected: empty status; commits = spec + plan docs, Task 1, Task 2, Task 3.

---

## Device acceptance (manual, after merge/install — not part of this plan)

- Assign each function; verify captions TOGGLE / FLASH / ON.
- Flash hold on the desk: lit while held, off on release; release also fires when the long-press context menu interrupts.
- Named target fires `Toggle Executor "Name"` correctly on the desk.
- Legacy pad from the PR #32 build loads unchanged as toggles.
```
