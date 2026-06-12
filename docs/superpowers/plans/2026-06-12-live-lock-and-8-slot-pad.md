# Live Tab Output Lock + 8-Slot Macro Pad Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the Live tab's fixed GO+/PAUSE/GO− transport, double the assignable macro pad to 8 slots (2×4), and add a tap-to-lock / hold-to-unlock output lock that greys out and hit-disables the whole Live surface.

**Architecture:** Lock is view-local `@State` in `LiveView` (no model, no persistence — session-scoped like the executor belief). The only `SaettaKit` change is `MacroPad.slotCount` 4→8 with a UserDefaults padding migration so existing 4-slot assignments survive. `MacroPadView` gains an `isLocked` parameter solely to flush held flashes when the lock engages.

**Tech Stack:** Swift / SwiftUI, XCTest, xcodegen + xcodebuild.

**Spec:** `docs/superpowers/specs/2026-06-12-live-lock-and-8-slot-pad-design.md`

---

## Worktree & commands

- Work in `~/cuelist-live-lock` on branch `feat/live-lock-8-slot-pad` (already created off `origin/main` `3960f42`).
- Run `xcodegen generate` in `~/cuelist-live-lock/ios` before every `xcodebuild`.
- Always `set -o pipefail` before piping xcodebuild to `tail`.
- SourceKit/IDE diagnostics on SaettaKit files are often false — xcodebuild output is authoritative.
- Kit test command (used throughout):
  ```bash
  cd ~/cuelist-live-lock/ios && xcodegen generate && set -o pipefail && \
  xcodebuild test -project Saetta.xcodeproj -scheme SaettaKit \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
  ```
  (If that simulator is missing, pick one from `xcrun simctl list devices available`.)
- App build command (Task 2 verification):
  ```bash
  cd ~/cuelist-live-lock/ios && xcodegen generate && set -o pipefail && \
  xcodebuild build -project Saetta.xcodeproj -scheme Saetta \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
  ```

## File map

| File | Change |
|---|---|
| `ios/Sources/Kit/Macro/MacroPad.swift` | `slotCount` 4→8; init pads short saved arrays |
| `ios/Tests/KitTests/MacroPadTests.swift` | update count assertion; add migration tests |
| `ios/Sources/App/LiveView.swift` | delete transport; add lock bar, dim/hit-disable, `LockOverlay` |
| `ios/Sources/App/MacroPadView.swift` | new `isLocked` param; flush held flashes on lock |

No other call sites exist: `TransportButton` is private to `LiveView.swift`, and the picker/load sheets already handle arbitrary slot indices.

---

### Task 1: `MacroPad` — 8 slots with padding migration

**Files:**
- Modify: `ios/Tests/KitTests/MacroPadTests.swift`
- Modify: `ios/Sources/Kit/Macro/MacroPad.swift`

- [ ] **Step 1: Update the existing count test and add the failing migration tests**

In `ios/Tests/KitTests/MacroPadTests.swift`, replace the existing `test_starts_with_four_empty_slots` (lines 11–15):

```swift
    func test_starts_with_eight_empty_slots() {
        let pad = freshPad()
        XCTAssertEqual(pad.slots.count, 8)
        XCTAssertTrue(pad.slots.allSatisfy { $0 == nil })
    }
```

Then add these new tests right after `test_unknown_persisted_id_reads_as_nil_but_is_preserved` (after line 68):

```swift
    // MARK: 4 → 8 slot migration

    func test_legacy_four_slot_array_pads_to_eight_preserving_assignments() {
        let suite = "macropad.migrate.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        // A pad saved by a 4-slot build: action, loaded executor, empty, action.
        d.set(["go_plus", "exec:flash:201", "", "pause"], forKey: "macroPadSlots")

        let pad = MacroPad(defaults: d)

        XCTAssertEqual(pad.slots.count, 8)
        XCTAssertEqual(pad.action(at: 0)?.id, "go_plus")
        XCTAssertEqual(pad.slot(at: 1), .executor(function: .flash, target: .number(201)))
        XCTAssertNil(pad.slot(at: 2))
        XCTAssertEqual(pad.action(at: 3)?.id, "pause")
        for slot in 4..<8 {
            XCTAssertNil(pad.slot(at: slot), "padded slot \(slot) must start empty")
        }
    }

    func test_legacy_array_persists_at_eight_after_first_mutation() {
        let suite = "macropad.migratepersist.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(["go_plus", "", "", ""], forKey: "macroPadSlots")

        let p1 = MacroPad(defaults: d)
        p1.assign(slot: 5, action: MacroAction.find("off")!)   // a slot that didn't exist at 4

        let p2 = MacroPad(defaults: d)
        XCTAssertEqual(p2.slots.count, 8)
        XCTAssertEqual(p2.action(at: 0)?.id, "go_plus", "legacy assignment must survive")
        XCTAssertEqual(p2.action(at: 5)?.id, "off", "new high slot must survive")
    }

    func test_oversized_saved_array_falls_back_to_all_empty() {
        let suite = "macropad.oversize.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(Array(repeating: "go_plus", count: 9), forKey: "macroPadSlots")

        let pad = MacroPad(defaults: d)

        XCTAssertEqual(pad.slots.count, 8)
        XCTAssertTrue(pad.slots.allSatisfy { $0 == nil })
    }

    func test_eight_slot_round_trip() {
        let suite = "macropad.eight.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let p1 = MacroPad(defaults: d)
        p1.assign(slot: 0, action: MacroAction.find("go_plus")!)
        p1.assign(slot: 7, action: MacroAction.find("top")!)

        let p2 = MacroPad(defaults: d)
        XCTAssertEqual(p2.action(at: 0)?.id, "go_plus")
        XCTAssertEqual(p2.action(at: 7)?.id, "top")
        XCTAssertNil(p2.action(at: 4))
    }
```

Note: the existing tests that seed 4-element arrays (`test_unknown_persisted_id_reads_as_nil_but_is_preserved`, `test_legacy_persisted_executor_loads_as_toggle`, `test_loadExecutor_retargets_legacy_slot_preserving_toggle`) will load through the new padding path; their assertions only touch slots 0–3 and keep passing unchanged. `test_out_of_range_slot_is_safe_noop` uses slot 9, which is still out of range at 8.

- [ ] **Step 2: Run the Kit tests to verify the new ones fail**

```bash
cd ~/cuelist-live-lock/ios && xcodegen generate && set -o pipefail && \
xcodebuild test -project Saetta.xcodeproj -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```

Expected: FAIL — `test_starts_with_eight_empty_slots` (count is 4), `test_legacy_four_slot_array_pads_to_eight_preserving_assignments` (4-element array loads as count 4, slot 4..<8 assertions trap on indices? No — `pad.slot(at:)` guards indices, so it returns nil; the `slots.count` assertion fails), `test_legacy_array_persists_at_eight_after_first_mutation` (assign to 5 is a no-op at 4), `test_eight_slot_round_trip` (assign to 7 is a no-op), `test_oversized_saved_array_falls_back_to_all_empty` (count assertion fails: 9-element array is rejected → falls back to 4 empties, count 4 ≠ 8).

- [ ] **Step 3: Implement slotCount 8 + padding loader**

In `ios/Sources/Kit/Macro/MacroPad.swift`:

Replace lines 10–11:

```swift
    /// Fixed number of assignable buttons. Bumped 4 → 8 when the Live tab's fixed
    /// transport was removed; the init pads shorter saved arrays so assignments
    /// made at the old count survive the upgrade.
    public static let slotCount = 8
```

Replace the init body's load block (lines 33–38):

```swift
        // Stored as a fixed-length [String]; "" marks an empty slot (plist can't
        // hold nil). Arrays saved by an older, smaller-count build are padded with
        // empty slots — existing assignments keep their indices. A LONGER array
        // can only come from corruption or a future build; rejected to all-empty.
        if let saved = defaults.array(forKey: Self.key) as? [String], saved.count <= Self.slotCount {
            self.slots = saved.map { $0.isEmpty ? nil : $0 }
                + Array(repeating: nil, count: Self.slotCount - saved.count)
        } else {
            self.slots = Array(repeating: nil, count: Self.slotCount)
        }
```

- [ ] **Step 4: Run the Kit tests to verify everything passes**

Same command as Step 2. Expected: PASS, `** TEST SUCCEEDED **`, zero failures across the whole SaettaKit suite.

- [ ] **Step 5: Commit**

```bash
cd ~/cuelist-live-lock && git add ios/Sources/Kit/Macro/MacroPad.swift ios/Tests/KitTests/MacroPadTests.swift && \
git commit -m "feat(kit): MacroPad 4 -> 8 slots with padding migration for legacy saves"
```

---

### Task 2: `LiveView` — transport out, lock in; `MacroPadView` lock flush

**Files:**
- Modify: `ios/Sources/App/LiveView.swift`
- Modify: `ios/Sources/App/MacroPadView.swift`

No Kit logic here — the flash-flush belief path (`recordFlashFlush`) is already tested; this task only wires the lock to the existing flush. Verification is by build + simulator.

- [ ] **Step 1: Add the `isLocked` parameter and lock-flush to `MacroPadView`**

In `ios/Sources/App/MacroPadView.swift`:

After line 15 (`let onFire: () -> Void` declaration), add:

```swift
    /// Live-tab output lock. The pad only OBSERVES it — when the lock engages,
    /// held flashes are flushed so the desk is never left flashed behind a lock.
    /// Hit-disabling while locked is the parent's job (`allowsHitTesting`).
    let isLocked: Bool
```

In the `body`, extend the existing scene-phase flush (the `.onChange(of: scenePhase)` modifier) by adding directly below it:

```swift
        .onChange(of: isLocked) { _, locked in
            if locked { flushFlashReleases() }
        }
```

- [ ] **Step 2: Rewrite the `LiveView` body — remove transport, add lock**

In `ios/Sources/App/LiveView.swift`:

Add the lock state after the existing `@State` properties (after `sentResetTask`, line 13):

```swift
    /// Live-tab output lock — session-scoped UI state (relaunch starts unlocked,
    /// same convention as the executor belief). Locks THIS tab's surface only;
    /// the HubClient send path is not gated.
    @State private var isLocked = false
```

Replace the `VStack(spacing: 14) { ... }` body content (connectionRow + transport block + MacroPadView + controlSection, lines 19–41) with:

```swift
                VStack(spacing: 14) {
                    connectionRow            // stays live while locked — reconnect is harmless

                    ZStack {
                        VStack(spacing: 14) {
                            lockBar

                            // Assignable macro pad — fires on the desk-selected executor.
                            MacroPadView(onFire: { fireCount += 1 }, isLocked: isLocked)
                                .frame(maxHeight: .infinity, alignment: .top)

                            // Message-to-console field.
                            controlSection
                        }
                        .opacity(isLocked ? 0.3 : 1)
                        .allowsHitTesting(!isLocked)

                        if isLocked {
                            LockOverlay {
                                withAnimation(.easeOut(duration: 0.2)) { isLocked = false }
                            }
                            .transition(.opacity)
                        }
                    }
                }
                .padding(20)
```

Add the lock bar as a new computed property next to `connectionRow`:

```swift
    /// Slim full-width arm bar. Locking is a single frictionless tap; unlocking
    /// requires the overlay's press-and-hold.
    private var lockBar: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { isLocked = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textDim)
                Text("TAP TO LOCK")
                    .font(Theme.mono(size: 11, weight: .medium)).hudLabel()
                    .foregroundStyle(Theme.textDim)
                Spacer()
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .hudPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lock controls")
    }
```

Add a haptic for lock state changes on the `NavigationStack`'s `ZStack`, next to the existing `.sensoryFeedback(.impact(weight: .medium), trigger: fireCount)`:

```swift
            .sensoryFeedback(.impact(weight: .heavy), trigger: isLocked)
```

Delete the entire `TransportButton` struct at the bottom of the file (the `/// One large transport button...` doc comment and struct). Keep `PressScaleStyle` — the macro cells use it. Update the file's header doc comment (lines 4–7) to:

```swift
/// The Live tab — run cues on the console-selected executor via the assignable
/// macro pad, with a one-tap output lock (hold to unlock) so a pocketed or
/// handed-over phone can't fire anything. Optimistic: each tap fires immediately
/// with haptic + a press pulse; cells disable when the hub is offline.
```

- [ ] **Step 3: Add the `LockOverlay` component**

At the bottom of `ios/Sources/App/LiveView.swift` (where `TransportButton` was), add:

```swift
/// The locked state: a big centered lock with a hold-to-unlock progress ring.
/// Tap-engage / hold-release asymmetry is the point — a stray pocket tap can
/// lock but never unlock. Releasing before the ring closes cancels the unlock.
private struct LockOverlay: View {
    let onUnlock: () -> Void
    @State private var holdProgress: CGFloat = 0

    private static let holdDuration: TimeInterval = 1.0

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Theme.borderStrong, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Theme.accentSolid, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            .frame(width: 110, height: 110)

            Text("HOLD TO UNLOCK")
                .font(Theme.mono(size: 12, weight: .medium)).hudLabel()
                .foregroundStyle(Theme.textDim)
        }
        .padding(40)                            // generous press target around the ring
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 40) {
            onUnlock()
        } onPressingChanged: { pressing in
            if pressing {
                withAnimation(.linear(duration: Self.holdDuration)) { holdProgress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
            }
        }
        .accessibilityLabel("Locked. Hold to unlock")
        .accessibilityAction { onUnlock() }     // VoiceOver can't sustain a hold
    }
}
```

- [ ] **Step 4: Build the app**

```bash
cd ~/cuelist-live-lock/ios && xcodegen generate && set -o pipefail && \
xcodebuild build -project Saetta.xcodeproj -scheme Saetta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. If the compiler flags a missing `isLocked` argument anywhere, that call site was missed — `LiveView` is the only instantiator of `MacroPadView`.

- [ ] **Step 5: Run the full test suite (Kit tests must still pass)**

```bash
cd ~/cuelist-live-lock/ios && set -o pipefail && \
xcodebuild test -project Saetta.xcodeproj -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd ~/cuelist-live-lock && git add ios/Sources/App/LiveView.swift ios/Sources/App/MacroPadView.swift && \
git commit -m "feat(ios-ui): Live tab output lock + 2x4 macro pad, fixed transport removed"
```

---

### Task 3: Simulator verification pass

**Files:** none (verification only)

- [ ] **Step 1: Boot the app in the simulator**

```bash
cd ~/cuelist-live-lock/ios && set -o pipefail && \
xcodebuild build -project Saetta.xcodeproj -scheme Saetta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/saetta-lock-dd 2>&1 | tail -3 && \
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null; \
xcrun simctl install "iPhone 17 Pro" /tmp/saetta-lock-dd/Build/Products/Debug-iphonesimulator/Saetta.app && \
xcrun simctl launch "iPhone 17 Pro" $(defaults read /tmp/saetta-lock-dd/Build/Products/Debug-iphonesimulator/Saetta.app/Info CFBundleIdentifier)
```

(If first-run naming gate appears, complete it; if the bundle id read fails, get it with `plutil -p .../Info.plist | grep CFBundleIdentifier`.)

- [ ] **Step 2: Visual checklist on the Live tab (screenshot each state with `xcrun simctl io "iPhone 17 Pro" screenshot /tmp/lock-N.png` and READ the screenshots)**

1. Unlocked: connection row → lock bar ("TAP TO LOCK", open lock) → 8 assignable cells in 2×4 → message row. No GO+/PAUSE/GO− fixed buttons anywhere.
2. Tap the lock bar → surface dims, big lock + ring + "HOLD TO UNLOCK" centered; pad cells and message row do not respond to taps.
3. Short tap on the big lock → stays locked (ring resets).
4. The connection row still responds while locked.
5. Hold the big lock ~1 s → unlocks, surface returns to full opacity.

Note: simulator can't verify haptics or real long-press ring animation timing precisely — device smoke covers feel. Driving taps may need the user's hands (no idb/cliclick on this Mac); if so, present the checklist to the user instead of self-driving, and verify what's verifiable from screenshots (layout, 8 cells, no transport).

- [ ] **Step 3: Report**

Report the checklist results honestly. On-device install (jPhone (2)) + desk acceptance of flush-on-lock are the user's owed items after merge, per project convention.

---

## Self-review notes

- Spec coverage: layout (Task 2 Step 2), locked state + hold-to-unlock (Task 2 Steps 2–3), flush-on-lock (Task 2 Step 1), session-scoped lock (`@State`), connection-row-stays-live (outside the dimmed ZStack), migration (Task 1), transport removal with `PressScaleStyle` kept (Task 2 Step 2), out-of-scope items untouched. ✓
- Type consistency: `MacroPadView(onFire:isLocked:)` matches the call site; `LockOverlay(onUnlock:)` trailing closure matches. ✓
- The `test_unknown_persisted_id_reads_as_nil_but_is_preserved` test seeds a 4-array and asserts `pad.slots[0]` — padding preserves index 0. ✓
