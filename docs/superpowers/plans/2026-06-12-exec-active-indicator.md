# Executor Active Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every loaded executor cell on the Live-tab macro pad shows a left-edge stripe — red when the executor is believed inactive, green when believed active (phone-side belief, never desk truth).

**Architecture:** Belief is a session-scoped `Set<ExecutorTarget>` on `MacroPad` (Kit), mutated by three `record*` methods the view calls only after a successful send. Flash captures its target at press in a pad-internal map (mirroring the view's existing `flashPressed` release-command capture) so mid-hold retargets still release correctly. UI is a 4pt capsule stripe overlaid on loaded executor cells, with two new scoped Theme colors (the amber HUD has no green).

**Tech Stack:** Swift / SwiftUI, XCTest, xcodegen + xcodebuild (test sim: iPhone 17 Pro).

**Spec:** `docs/superpowers/specs/2026-06-12-exec-active-indicator-design.md`

**Build prelude for every test/build step** (xcodegen is REQUIRED before xcodebuild; SourceKit diagnostics on SaettaKit are known-false — xcodebuild is authoritative):

```bash
cd /tmp/exec-ind-wt/ios && xcodegen generate
```

Test command (always `set -o pipefail` before piping):

```bash
cd /tmp/exec-ind-wt/ios && set -o pipefail && xcodebuild -project Saetta.xcodeproj -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20
```

---

### Task 1: Belief set + tap transitions (`recordFire`)

`ExecutorTarget` becomes `Hashable`; `MacroPad` gains `activeExecutors`, `isActive(_:)`, and `recordFire(slot:)` — toggle flips belief, on latches it, everything else no-ops. Belief is never persisted.

**Files:**
- Modify: `ios/Sources/Kit/Macro/MacroSlot.swift` (one line: `ExecutorTarget` conformance)
- Modify: `ios/Sources/Kit/Macro/MacroPad.swift`
- Test: `ios/Tests/KitTests/MacroPadTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to the end of the `MacroPadTests` class in `ios/Tests/KitTests/MacroPadTests.swift`:

```swift
    // MARK: - Executor active belief (tap: toggle / on)

    /// Build a pad with a loaded executor in `slot` — the test-side analog of the
    /// double assign (assign function, then load target).
    private func padWithExecutor(slot: Int = 0, function: ExecutorFunction,
                                 target: ExecutorTarget) -> MacroPad {
        let pad = freshPad()
        pad.assignExecutor(slot: slot, function: function)
        pad.loadExecutor(slot: slot, target: target)
        return pad
    }

    func test_belief_starts_empty() {
        XCTAssertTrue(freshPad().activeExecutors.isEmpty)
    }

    func test_toggle_fire_flips_belief_on_then_off() {
        let pad = padWithExecutor(function: .toggle, target: .number(201))
        pad.recordFire(slot: 0)
        XCTAssertTrue(pad.isActive(.number(201)))
        pad.recordFire(slot: 0)
        XCTAssertFalse(pad.isActive(.number(201)))
        XCTAssertTrue(pad.activeExecutors.isEmpty)
    }

    func test_on_fire_latches_and_repeat_keeps_it() {
        let pad = padWithExecutor(function: .on, target: .name("Blinders"))
        pad.recordFire(slot: 0)
        pad.recordFire(slot: 0)
        XCTAssertTrue(pad.isActive(.name("Blinders")))
    }

    func test_toggle_flips_belief_latched_by_on_for_same_target() {
        let pad = padWithExecutor(slot: 0, function: .on, target: .number(201))
        pad.assignExecutor(slot: 1, function: .toggle)
        pad.loadExecutor(slot: 1, target: .number(201))
        pad.recordFire(slot: 0)                      // on → latched
        pad.recordFire(slot: 1)                      // toggle same target → off
        XCTAssertFalse(pad.isActive(.number(201)))
    }

    func test_shared_target_is_one_belief_entry() {
        let pad = padWithExecutor(slot: 0, function: .toggle, target: .number(201))
        pad.assignExecutor(slot: 1, function: .toggle)
        pad.loadExecutor(slot: 1, target: .number(201))
        pad.recordFire(slot: 0)
        XCTAssertEqual(pad.activeExecutors, [.number(201)])
        pad.recordFire(slot: 1)                      // other slot, same target → flips off
        XCTAssertTrue(pad.activeExecutors.isEmpty)
    }

    func test_name_and_number_do_not_alias() {
        let pad = padWithExecutor(slot: 0, function: .toggle, target: .number(201))
        pad.assignExecutor(slot: 1, function: .toggle)
        pad.loadExecutor(slot: 1, target: .name("Exec 201"))
        pad.recordFire(slot: 0)
        XCTAssertTrue(pad.isActive(.number(201)))
        XCTAssertFalse(pad.isActive(.name("Exec 201")))
    }

    func test_recordFire_noops_for_action_unloaded_flash_empty_and_out_of_range() {
        let pad = freshPad()
        pad.assign(slot: 0, action: MacroAction.find("off")!)
        pad.assignExecutor(slot: 1, function: .toggle)        // assigned, not loaded
        pad.assignExecutor(slot: 2, function: .flash)
        pad.loadExecutor(slot: 2, target: .number(7))         // flash is press-driven, not tap
        pad.recordFire(slot: 0)
        pad.recordFire(slot: 1)
        pad.recordFire(slot: 2)
        pad.recordFire(slot: 3)                               // empty
        pad.recordFire(slot: 9)                               // out of range
        XCTAssertTrue(pad.activeExecutors.isEmpty)
    }

    func test_clear_slot_leaves_belief_untouched() {
        let pad = padWithExecutor(function: .toggle, target: .number(201))
        pad.recordFire(slot: 0)
        pad.clear(slot: 0)
        XCTAssertTrue(pad.isActive(.number(201)))
    }

    func test_belief_is_not_persisted() {
        let suite = "macropad.belief.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let p1 = MacroPad(defaults: d)
        p1.assignExecutor(slot: 0, function: .toggle)
        p1.loadExecutor(slot: 0, target: .number(201))
        p1.recordFire(slot: 0)
        let p2 = MacroPad(defaults: d)
        XCTAssertTrue(p2.activeExecutors.isEmpty)             // slots persist, belief doesn't
        XCTAssertNotNil(p2.slot(at: 0))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /tmp/exec-ind-wt/ios && xcodegen generate && set -o pipefail && xcodebuild -project Saetta.xcodeproj -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20
```

Expected: **BUILD FAILS** — `activeExecutors`, `isActive`, `recordFire` don't exist, and `Set<ExecutorTarget>` needs `Hashable`. (Compile failure is this step's red.)

- [ ] **Step 3: Implement**

In `ios/Sources/Kit/Macro/MacroSlot.swift`, change the `ExecutorTarget` declaration line:

```swift
public enum ExecutorTarget: Equatable, Hashable, Sendable {
```

In `ios/Sources/Kit/Macro/MacroPad.swift`, add below the `slots` property:

```swift
    /// Believed-active executor targets — the phone's session-scoped belief about
    /// what it set, never desk truth (the transport is one-way; see the
    /// exec-active-indicator design spec for the accepted limitations). Keyed
    /// per-target so every slot pointing at the same target shares one belief.
    /// Deliberately not persisted: belief resets to unknown on every launch.
    public private(set) var activeExecutors: Set<ExecutorTarget> = []
```

Add below `loadExecutor`:

```swift
    /// Whether `target` is believed active.
    public func isActive(_ target: ExecutorTarget) -> Bool {
        activeExecutors.contains(target)
    }

    /// Record a successful tap-fire on `slot` — the view calls this only after the
    /// command was actually sent (online + loaded). Toggle flips belief; On latches
    /// it (a toggle slot on the same target can flip it back, matching the desk).
    /// Actions, unloaded executors, flash (press-driven), empty and out-of-range
    /// slots are no-ops.
    public func recordFire(slot: Int) {
        guard case .executor(let function, let target?)? = self.slot(at: slot) else { return }
        switch function {
        case .toggle:
            if activeExecutors.contains(target) { activeExecutors.remove(target) }
            else { activeExecutors.insert(target) }
        case .on:
            activeExecutors.insert(target)
        case .flash:
            break
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: **TEST SUCCEEDED**, all new `test_belief_*`/`test_toggle_*`/`test_on_*`/`test_shared_*`/`test_name_and_number_*`/`test_recordFire_*`/`test_clear_slot_leaves_*` pass, zero failures overall.

- [ ] **Step 5: Commit**

```bash
cd /tmp/exec-ind-wt && git add ios/Sources/Kit/Macro/MacroSlot.swift ios/Sources/Kit/Macro/MacroPad.swift ios/Tests/KitTests/MacroPadTests.swift && git commit -m "feat(kit): executor active belief — Hashable target, activeExecutors set, recordFire tap transitions"
```

---

### Task 2: Flash belief — press / release / flush with target capture

Flash marks its target active at touch-down and releases it at touch-up/cancel. The target is captured at press in a pad-internal `heldFlash` map (mirroring the view's `flashPressed` release-command capture) so a mid-hold retarget or clear still releases the belief that was engaged. A flush variant releases everything held (view disappear / scene background).

**Files:**
- Modify: `ios/Sources/Kit/Macro/MacroPad.swift`
- Test: `ios/Tests/KitTests/MacroPadTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `MacroPadTests` (uses `padWithExecutor` from Task 1):

```swift
    // MARK: - Executor active belief (flash press/release)

    func test_flash_press_marks_active_release_clears() {
        let pad = padWithExecutor(function: .flash, target: .number(7))
        pad.recordFlashPress(slot: 0)
        XCTAssertTrue(pad.isActive(.number(7)))
        pad.recordFlashRelease(slot: 0)
        XCTAssertFalse(pad.isActive(.number(7)))
    }

    func test_flash_release_without_press_is_noop() {
        let pad = padWithExecutor(function: .flash, target: .number(7))
        pad.recordFlashRelease(slot: 0)
        XCTAssertTrue(pad.activeExecutors.isEmpty)
    }

    func test_flash_press_noops_unless_loaded_flash() {
        let pad = freshPad()
        pad.assign(slot: 0, action: MacroAction.find("off")!)
        pad.assignExecutor(slot: 1, function: .toggle)
        pad.loadExecutor(slot: 1, target: .number(5))         // loaded, but toggle
        pad.assignExecutor(slot: 2, function: .flash)          // flash, not loaded
        pad.recordFlashPress(slot: 0)
        pad.recordFlashPress(slot: 1)
        pad.recordFlashPress(slot: 2)
        pad.recordFlashPress(slot: 9)
        XCTAssertTrue(pad.activeExecutors.isEmpty)
    }

    func test_flash_midhold_retarget_still_releases_captured_target() {
        let pad = padWithExecutor(function: .flash, target: .number(7))
        pad.recordFlashPress(slot: 0)
        pad.loadExecutor(slot: 0, target: .name("Blinders"))   // retarget mid-hold
        pad.recordFlashRelease(slot: 0)
        XCTAssertTrue(pad.activeExecutors.isEmpty)             // 7 released, Blinders never engaged
    }

    func test_flash_midhold_clear_still_releases_captured_target() {
        let pad = padWithExecutor(function: .flash, target: .number(7))
        pad.recordFlashPress(slot: 0)
        pad.clear(slot: 0)
        pad.recordFlashRelease(slot: 0)
        XCTAssertFalse(pad.isActive(.number(7)))
    }

    func test_flash_flush_releases_all_held() {
        let pad = padWithExecutor(slot: 0, function: .flash, target: .number(7))
        pad.assignExecutor(slot: 1, function: .flash)
        pad.loadExecutor(slot: 1, target: .name("Blinders"))
        pad.recordFlashPress(slot: 0)
        pad.recordFlashPress(slot: 1)
        pad.recordFlashFlush()
        XCTAssertTrue(pad.activeExecutors.isEmpty)
        pad.recordFlashRelease(slot: 0)                        // already flushed — no-op
        XCTAssertTrue(pad.activeExecutors.isEmpty)
    }

    func test_flash_release_does_not_unlatch_other_holds_of_same_target() {
        // Two flash slots on the SAME target: releasing one releases the shared
        // belief (accepted approximation — belief is a set, not a counter).
        let pad = padWithExecutor(slot: 0, function: .flash, target: .number(7))
        pad.assignExecutor(slot: 1, function: .flash)
        pad.loadExecutor(slot: 1, target: .number(7))
        pad.recordFlashPress(slot: 0)
        pad.recordFlashPress(slot: 1)
        pad.recordFlashRelease(slot: 0)
        XCTAssertFalse(pad.isActive(.number(7)))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /tmp/exec-ind-wt/ios && xcodegen generate && set -o pipefail && xcodebuild -project Saetta.xcodeproj -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20
```

Expected: **BUILD FAILS** — `recordFlashPress`/`recordFlashRelease`/`recordFlashFlush` don't exist.

- [ ] **Step 3: Implement**

In `ios/Sources/Kit/Macro/MacroPad.swift`, add below `activeExecutors`:

```swift
    /// Targets captured at flash press, keyed by slot — mirrors the view's
    /// `flashPressed` release-command capture, so a mid-hold retarget or clear
    /// still releases the belief that was actually engaged.
    private var heldFlash: [Int: ExecutorTarget] = [:]
```

Add below `recordFire`:

```swift
    /// Record flash touch-down on `slot`: mark its target believed-active and
    /// capture it for the matching release. No-op unless the slot holds a loaded
    /// flash executor (the view gates on the command actually sending).
    public func recordFlashPress(slot: Int) {
        guard case .executor(function: .flash, target: let target?)? = self.slot(at: slot) else { return }
        activeExecutors.insert(target)
        heldFlash[slot] = target
    }

    /// Record flash touch-up/cancel on `slot`: release the belief captured at
    /// press. No-op if this slot has no captured press. Releasing removes the
    /// target from the set even if a toggle/on had latched it — accepted belief
    /// approximation (see spec).
    public func recordFlashRelease(slot: Int) {
        guard let target = heldFlash.removeValue(forKey: slot) else { return }
        activeExecutors.remove(target)
    }

    /// Release every held flash belief — the counterpart of the view's
    /// `flushFlashReleases()` on view disappear / scene backgrounding.
    public func recordFlashFlush() {
        for target in heldFlash.values { activeExecutors.remove(target) }
        heldFlash.removeAll()
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: **TEST SUCCEEDED**, all `test_flash_*` pass, zero failures overall.

- [ ] **Step 5: Commit**

```bash
cd /tmp/exec-ind-wt && git add ios/Sources/Kit/Macro/MacroPad.swift ios/Tests/KitTests/MacroPadTests.swift && git commit -m "feat(kit): flash belief press/release/flush with press-time target capture"
```

---

### Task 3: Theme colors, stripe UI, view wiring

Two scoped Theme colors; `MacroButton` gains `isActive` and draws the stripe on loaded executor cells; `MacroPadView` wires the three `record*` calls into its existing success paths and passes belief down. No unit tests (App views aren't unit-tested in this repo) — verification is a clean build plus on-device acceptance.

**Files:**
- Modify: `ios/Sources/App/Theme.swift` (after the `danger` line, ~line 44)
- Modify: `ios/Sources/App/MacroPadView.swift`

- [ ] **Step 1: Add Theme colors**

In `ios/Sources/App/Theme.swift`, directly under the `danger` line:

```swift
    static let execActive = Color(hex: "#4cd964")!   // green — executor believed active (Live pad stripe)
    static let execInactive = Color(hex: "#ff6b6b")! // red — executor believed inactive (danger's hue, distinct semantic)
```

- [ ] **Step 2: Wire belief recording into MacroPadView handlers**

In `ios/Sources/App/MacroPadView.swift`:

`handleTap` — add `pad.recordFire(slot: slot)` after the send:

```swift
        case let value?:
            guard hub.state.isOnline, let command = value.command else { return }
            hub.sendCommand(command)
            pad.recordFire(slot: slot)
            onFire()
```

`handleFlashPress` — add `pad.recordFlashPress(slot: slot)` after capturing the release:

```swift
        hub.sendCommand(command)
        flashPressed[slot] = release
        pad.recordFlashPress(slot: slot)
        onFire()
```

`handleFlashRelease` — add `pad.recordFlashRelease(slot: slot)` after the send:

```swift
    private func handleFlashRelease(_ slot: Int) {
        guard let release = flashPressed.removeValue(forKey: slot) else { return }
        hub.sendCommand(release)
        pad.recordFlashRelease(slot: slot)
    }
```

`flushFlashReleases` — add `pad.recordFlashFlush()`:

```swift
    private func flushFlashReleases() {
        for release in flashPressed.values { hub.sendCommand(release) }
        flashPressed.removeAll()
        pad.recordFlashFlush()
    }
```

- [ ] **Step 3: Pass belief into MacroButton and draw the stripe**

Still in `MacroPadView`, add a helper below `flushFlashReleases()`:

```swift
    /// Belief for the stripe: only loaded executor slots have one.
    private func believedActive(_ slot: Int) -> Bool {
        guard case .executor(_, let target?)? = pad.slot(at: slot) else { return false }
        return pad.isActive(target)
    }
```

In `body`, add the parameter to the `MacroButton` call (after `isOnline:`):

```swift
                MacroButton(
                    slot: pad.slot(at: slot),
                    isOnline: hub.state.isOnline,
                    isActive: believedActive(slot),
                    onTap: { handleTap(slot) },
```

In `MacroButton`, add the stored property after `let isOnline: Bool`:

```swift
    let isActive: Bool
```

In `MacroButton.content`, replace the loaded-executor case with:

```swift
        case .executor(let function, let target?):
            VStack(spacing: 2) {
                targetText(target)
                Text(function.caption).font(.system(size: 11, weight: .semibold)).opacity(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accentSolid.gradient, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(alignment: .leading) {
                // Belief stripe: what Saetta thinks it set, not desk truth.
                Capsule()
                    .fill(isActive ? Theme.execActive : Theme.execInactive)
                    .frame(width: 4)
                    .padding(.vertical, 10)
                    .padding(.leading, 6)
                    .animation(.easeInOut(duration: 0.15), value: isActive)
            }
            .accessibilityLabel("Executor \(target.display), \(function.rawValue), \(isActive ? "active" : "inactive")")
```

- [ ] **Step 4: Build both schemes clean**

```bash
cd /tmp/exec-ind-wt/ios && xcodegen generate && set -o pipefail && xcodebuild -project Saetta.xcodeproj -scheme Saetta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**. (If `isActive` is missing from any `MacroButton` call site, this build catches it.)

- [ ] **Step 5: Commit**

```bash
cd /tmp/exec-ind-wt && git add ios/Sources/App/Theme.swift ios/Sources/App/MacroPadView.swift && git commit -m "feat(ios-ui): red/green belief stripe on executor macro cells + record wiring"
```

---

### Task 4: Full suite + final verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full Kit test suite**

```bash
cd /tmp/exec-ind-wt/ios && xcodegen generate && set -o pipefail && xcodebuild -project Saetta.xcodeproj -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20
```

Expected: **TEST SUCCEEDED**, 0 failures (244 pre-existing + ~16 new).

- [ ] **Step 2: App scheme builds**

```bash
cd /tmp/exec-ind-wt/ios && set -o pipefail && xcodebuild -project Saetta.xcodeproj -scheme Saetta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**.

- [ ] **Step 3: Verify branch ref matches last commit** (subagent branch-ref drift gotcha)

```bash
cd /tmp/exec-ind-wt && git rev-parse feat/exec-active-indicator HEAD && git log --oneline origin/main..HEAD
```

Expected: both SHAs identical; log shows the spec/plan docs commits + 3 code commits.

---

## After the plan (ship steps, not tasks)

1. Push branch, open PR against `francesco687/cuelist-compiler` `main`.
2. Device install on jPhone (2) `7DF307B3-6B1F-5CB1-8793-5DB9437E7FF8` via xcodebuild device build + `xcrun devicectl device install app` (team UWJSLFQDGL, automatic signing).
3. Desk acceptance: stripe flips on toggle, latches on On, tracks flash hold incl. tab-switch flush; launch starts all-red; desk-side changes invisible (expected, documented).
