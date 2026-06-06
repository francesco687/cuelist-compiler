# Saetta — Rename + Send-Tab Split + Per-Cue Timecode Insert — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the iOS app `CuelistCompiler` → **Saetta**, split the Send tab into three decoupled actions (Send Cues / Send Notes / Send Timecode), and add a per-cue tick box that appends only the ticked cues' SMPTE timecode to the grandMA3 Timecode pool without disturbing existing events.

**Architecture:** All command generation moves into `SaettaKit` as pure Swift (Approach A) — the hub/relay are untouched. A new `MA3CommandBuilder` produces cue-structure-only and notes-only command lines (mirroring `web/js/compile.js`, minus the entangling). A new `Smpte`/`TimecodeBuilder` pair turns ticked cues into append-only Timecode commands. `HubClient` gains a throttled batch sender (`sendLines`) that streams the same client-side progress the UI already binds to, sending each line as a raw `cmd` frame (20 ms spacing, matching the hub's `compile-send` throttle). The iOS use of `compile-send` is retired.

**Tech Stack:** Swift 5.9, SwiftUI, `@Observable`, XCTest, xcodegen. grandMA3 command-line / OSC via the existing hub `cmd` channel.

**Spec:** `docs/superpowers/specs/2026-06-06-saetta-rename-and-send-split-design.md`

---

## Conventions used throughout

**Build/test commands (run from repo root). Note the scheme names change after Task 2.**

Before rename (Task 1 only):
```bash
cd ios && xcodegen generate && xcodebuild build -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

After rename (Task 2 onward) — Kit tests:
```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

After rename — app build:
```bash
cd ios && xcodegen generate && xcodebuild build -scheme Saetta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

> **xcodegen note:** any time a *new* file is added under `Sources/` or `Tests/`, run `xcodegen generate` before building so the `.xcodeproj` picks it up. The commands above already do this.

**Command-contract reference:** `web/js/compile.js` `buildCmdLines()` is the source of truth being mirrored. Pool iteration order is `Pool.allCases` = `[color, dimmer, position, gobo, beam, focus]`, which is byte-identical to web `POOLS`. `Pool.number` gives the MA3 pool index.

---

## Part A — Rename to Saetta

### Task 1: Rename project config, Info.plist, and app type

**Files:**
- Modify: `ios/project.yml`
- Modify: `ios/Sources/App/Info.plist`
- Modify: `ios/Sources/App/App.swift`

- [ ] **Step 1: Edit `ios/project.yml` — rename targets, bundle ids, schemes**

Replace the whole file with:

```yaml
name: Saetta
options:
  bundleIdPrefix: com.blearred
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
settings:
  base:
    DEVELOPMENT_TEAM: UWJSLFQDGL
    CODE_SIGN_STYLE: Automatic
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    SWIFT_VERSION: "5.9"
targets:
  SaettaKit:
    type: framework
    platform: iOS
    sources:
      - path: Sources/Kit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.blearred.saetta.kit
        ENABLE_TESTABILITY: YES
        GENERATE_INFOPLIST_FILE: YES
  Saetta:
    type: application
    platform: iOS
    sources:
      - path: Sources/App
    dependencies:
      - target: SaettaKit
    info:
      path: Sources/App/Info.plist
      properties:
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        NSLocalNetworkUsageDescription: "Saetta connects to your hub on the local network to send shows to your console."
        NSMicrophoneUsageDescription: "Saetta records short voice commands to author cues."
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.blearred.saetta
  SaettaKitTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests/KitTests
      - path: ../examples/SONG_1.json
        buildPhase: resources
    dependencies:
      - target: SaettaKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.blearred.saetta.kittests
        GENERATE_INFOPLIST_FILE: YES
schemes:
  SaettaKit:
    build:
      targets:
        SaettaKit: all
    test:
      targets:
        - SaettaKitTests
  Saetta:
    build:
      targets:
        Saetta: all
```

- [ ] **Step 2: Edit `ios/Sources/App/Info.plist` — bundle name + display name**

Find the `CFBundleName` key/value pair. It currently reads:

```xml
	<key>CFBundleName</key>
	<string>CuelistCompiler</string>
```

Replace with (add `CFBundleDisplayName` immediately after):

```xml
	<key>CFBundleName</key>
	<string>Saetta</string>
	<key>CFBundleDisplayName</key>
	<string>Saetta</string>
```

(If `CFBundleName`'s value is `$(PRODUCT_NAME)` or similar rather than a literal, leave it and just add the `CFBundleDisplayName` key/value pair shown above.)

- [ ] **Step 3: Edit `ios/Sources/App/App.swift` — rename the App struct**

Current top of file:

```swift
import CuelistCompilerKit

struct CuelistCompilerApp: App {
```

becomes:

```swift
import SaettaKit

struct SaettaApp: App {
```

Leave the rest of `App.swift` unchanged for now (other `CuelistCompilerKit` imports are handled in Task 2; this file's import is fixed here so the struct rename compiles in isolation conceptually — the global sweep in Task 2 will no-op on it).

- [ ] **Step 4: Commit (config only — build happens after the import sweep in Task 2)**

```bash
git add ios/project.yml ios/Sources/App/Info.plist ios/Sources/App/App.swift
git commit -m "chore(saetta): rename project config, Info.plist, app type to Saetta"
```

> The project will NOT build cleanly until Task 2 fixes the 50 `import CuelistCompilerKit` statements. These two tasks are a unit; do them back to back.

---

### Task 2: Sweep `import CuelistCompilerKit` → `import SaettaKit`, regenerate, delete old project

**Files:**
- Modify: every `.swift` under `ios/Sources/` and `ios/Tests/` containing `import CuelistCompilerKit` (~50 files)
- Delete: `ios/CuelistCompiler.xcodeproj` (regenerated as `ios/Saetta.xcodeproj`)

- [ ] **Step 1: Global import rename**

```bash
cd ios
grep -rl "import CuelistCompilerKit" Sources Tests \
  | xargs sed -i '' 's/import CuelistCompilerKit/import SaettaKit/g'
```

- [ ] **Step 2: Verify no stale references remain**

```bash
cd ios && grep -rn "CuelistCompilerKit\|CuelistCompiler\b" Sources Tests
```
Expected: **no output** (App.swift's struct is now `SaettaApp`; the only remaining matches would be in comments — if any comment mentions the old name, leave it unless it's misleading).

- [ ] **Step 3: Remove the old generated project and regenerate**

```bash
cd ios && rm -rf CuelistCompiler.xcodeproj && xcodegen generate
```
Expected: creates `ios/Saetta.xcodeproj`.

- [ ] **Step 4: Run Kit tests under the new scheme**

```bash
cd ios && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: **all existing Kit tests PASS** (the module renamed; behavior unchanged).

- [ ] **Step 5: Build the app target**

```bash
cd ios && xcodebuild build -scheme Saetta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 6: Commit**

```bash
cd /Users/jordanbabev/cuelist-compiler
git add -A ios/
git commit -m "chore(saetta): rename module to SaettaKit across sources + regenerate project"
```

---

## Part B — Native command builders (cues + notes)

### Task 3: `MA3CommandBuilder` — cue-structure lines (no notes) + scope helper

**Files:**
- Create: `ios/Sources/Kit/Send/MA3CommandBuilder.swift`
- Create: `ios/Tests/KitTests/MA3CommandBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/KitTests/MA3CommandBuilderTests.swift`:

```swift
import XCTest
@testable import SaettaKit

final class MA3CommandBuilderTests: XCTestCase {

    // A song: seq 5, one cue "VERSE" with one action group "MOVERS" carrying a
    // color preset "RED" and a dimmer preset "FULL" with an explicit fade.
    private func sampleSong() -> Song {
        var color = Preset(name: "RED")
        var dimmer = Preset(name: "FULL", fade: "3")
        var presets: [Pool: Preset] = [:]
        for p in Pool.allCases { presets[p] = Preset() }
        presets[.color] = color
        presets[.dimmer] = dimmer
        let action = Action(group: "MOVERS", presets: presets)
        let cue = Cue(n: 1, name: "VERSE", fade: "2", delay: "", position: "", actions: [action], notes: "ignored note")
        return Song(id: "s1", name: "SONG", sequence: 5, cues: [cue])
    }

    func test_cueLines_emit_structure_and_no_note_lines() {
        let song = sampleSong()
        let lines = MA3CommandBuilder.cueLines(songs: [song], defaults: Defaults(), storeMode: .overwrite)
        XCTAssertEqual(lines, [
            "ClearAll",
            "Group \"MOVERS\"",
            "At Preset 4.\"RED\"",        // color = pool number 4, first in allCases order
            "At Preset 1.\"FULL\"",       // dimmer = pool number 1
            "Fade 3 FeatureGroup 1",
            "Store Sequence 5 Cue 1 \"VERSE\" /Overwrite /NoConfirmation",
            "Set Sequence 5 Cue 1 Fade 2",
            "ClearAll",
        ])
        XCTAssertFalse(lines.contains { $0.contains("\"Note\"") }, "cueLines must not emit note lines")
    }

    func test_cueLines_merge_mode_flag() {
        let song = sampleSong()
        let lines = MA3CommandBuilder.cueLines(songs: [song], defaults: Defaults(), storeMode: .merge)
        XCTAssertTrue(lines.contains("Store Sequence 5 Cue 1 \"VERSE\" /Merge /NoConfirmation"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SaettaKitTests/MA3CommandBuilderTests -quiet
```
Expected: FAIL — `MA3CommandBuilder` is undefined.

- [ ] **Step 3: Write the implementation**

Create `ios/Sources/Kit/Send/MA3CommandBuilder.swift`:

```swift
import Foundation

/// Native Swift port of the cue/notes half of `web/js/compile.js`.
/// Splits what the web compiler entangles: cue STRUCTURE (no notes) and NOTES are
/// produced by separate functions so the Send tab can fire them independently.
/// Output ordering and quoting mirror `buildCmdLines()` exactly.
public enum MA3CommandBuilder {

    /// Collapse a free-text note to one safe command-line token:
    /// newlines/tabs/whitespace runs → single space, trimmed, then `"` → `\"`.
    /// Returns "" for empty/whitespace-only input.
    public static func sanitizeNote(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "[\\r\\n\\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return collapsed.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func escapeQuotes(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func formatN(_ n: Double) -> String {
        n.rounded() == n ? String(Int(n)) : String(n)
    }

    /// The songs a selection targets, mirroring `hub/src/compile-bridge.js`:
    /// `.current` = active song (by id, fallback first) iff it has cues; else none.
    /// `.all` = every song that has at least one cue.
    public static func songsInScope(_ project: Project, selection: Selection) -> [Song] {
        switch selection {
        case .current:
            let active = project.songs.first(where: { $0.id == project.activeSongId }) ?? project.songs.first
            guard let active, !active.cues.isEmpty else { return [] }
            return [active]
        case .all:
            return project.songs.filter { !$0.cues.isEmpty }
        }
    }

    /// Cue-structure command lines (ClearAll / Group / At Preset / Fade / Delay /
    /// Store / Set Fade / Set Delay), NO note lines. Mirrors `buildCmdLines`.
    public static func cueLines(songs: [Song], defaults: Defaults, storeMode: StoreMode) -> [String] {
        let flag = storeMode.flag   // "/Overwrite" or "/Merge"
        var out: [String] = []
        for song in songs {
            let seq = song.sequence
            for cue in song.cues {
                out.append("ClearAll")
                let actions = cue.actions.filter { !$0.group.trimmingCharacters(in: .whitespaces).isEmpty }
                for a in actions {
                    out.append("Group \"\(escapeQuotes(a.group))\"")
                    for pool in Pool.allCases {
                        let p = a.presets[pool] ?? Preset()
                        let name = p.name.trimmingCharacters(in: .whitespaces)
                        if name.isEmpty { continue }
                        out.append("At Preset \(pool.number).\"\(escapeQuotes(p.name))\"")
                        let fade = p.fade.trimmingCharacters(in: .whitespaces).isEmpty ? defaults.fade(pool) : p.fade
                        let delay = p.delay.trimmingCharacters(in: .whitespaces).isEmpty ? defaults.delay(pool) : p.delay
                        if !fade.trimmingCharacters(in: .whitespaces).isEmpty {
                            out.append("Fade \(fade) FeatureGroup \(pool.number)")
                        }
                        if !delay.trimmingCharacters(in: .whitespaces).isEmpty {
                            out.append("Delay \(delay) FeatureGroup \(pool.number)")
                        }
                    }
                }
                let cueName = escapeQuotes(cue.name)
                if !cueName.isEmpty {
                    out.append("Store Sequence \(seq) Cue \(formatN(cue.n)) \"\(cueName)\" \(flag) /NoConfirmation")
                } else {
                    out.append("Store Sequence \(seq) Cue \(formatN(cue.n)) \(flag) /NoConfirmation")
                }
                if !cue.fade.trimmingCharacters(in: .whitespaces).isEmpty {
                    out.append("Set Sequence \(seq) Cue \(formatN(cue.n)) Fade \(cue.fade)")
                }
                if !cue.delay.trimmingCharacters(in: .whitespaces).isEmpty {
                    out.append("Set Sequence \(seq) Cue \(formatN(cue.n)) Delay \(cue.delay)")
                }
            }
        }
        out.append("ClearAll")
        return out
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SaettaKitTests/MA3CommandBuilderTests -quiet
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Send/MA3CommandBuilder.swift ios/Tests/KitTests/MA3CommandBuilderTests.swift ios/project.yml
git commit -m "feat(saetta): MA3CommandBuilder.cueLines — cue structure without notes"
```

---

### Task 4: `MA3CommandBuilder.noteLines` — notes-only command lines

**Files:**
- Modify: `ios/Sources/Kit/Send/MA3CommandBuilder.swift`
- Modify: `ios/Tests/KitTests/MA3CommandBuilderTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `MA3CommandBuilderTests`:

```swift
    func test_noteLines_only_for_cues_with_notes() {
        var presets: [Pool: Preset] = [:]
        for p in Pool.allCases { presets[p] = Preset() }
        let withNote = Cue(n: 1, name: "A", actions: [Action(group: "G", presets: presets)],
                           notes: "  multi\nline\tnote with \"quote\"  ")
        let noNote = Cue(n: 2, name: "B", actions: [Action(group: "G", presets: presets)], notes: "   ")
        let song = Song(id: "s1", sequence: 7, cues: [withNote, noNote])
        let lines = MA3CommandBuilder.noteLines(songs: [song])
        XCTAssertEqual(lines, [
            "Set Sequence 7 Cue 1 \"Note\" \"multi line note with \\\"quote\\\"\"",
        ])
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SaettaKitTests/MA3CommandBuilderTests/test_noteLines_only_for_cues_with_notes -quiet
```
Expected: FAIL — `noteLines` undefined.

- [ ] **Step 3: Implement `noteLines`**

Add to `MA3CommandBuilder` (inside the enum, after `cueLines`):

```swift
    /// `Set Sequence N Cue n "Note" "..."` for every cue with a non-empty
    /// sanitized note. Emits nothing for empty/whitespace-only notes.
    public static func noteLines(songs: [Song]) -> [String] {
        var out: [String] = []
        for song in songs {
            for cue in song.cues {
                let note = sanitizeNote(cue.notes)
                if note.isEmpty { continue }
                out.append("Set Sequence \(song.sequence) Cue \(formatN(cue.n)) \"Note\" \"\(note)\"")
            }
        }
        return out
    }
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SaettaKitTests/MA3CommandBuilderTests -quiet
```
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Send/MA3CommandBuilder.swift ios/Tests/KitTests/MA3CommandBuilderTests.swift
git commit -m "feat(saetta): MA3CommandBuilder.noteLines — notes-only send path"
```

---

## Part C — Timecode (SMPTE → append-only events)

### Task 5: `Smpte` — validation + seconds conversion

**Files:**
- Create: `ios/Sources/Kit/Send/Smpte.swift`
- Create: `ios/Tests/KitTests/SmpteTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/KitTests/SmpteTests.swift`:

```swift
import XCTest
@testable import SaettaKit

final class SmpteTests: XCTestCase {
    func test_isValid_accepts_well_formed_25fps() {
        XCTAssertTrue(Smpte.isValid("00:00:00:00"))
        XCTAssertTrue(Smpte.isValid("01:23:45:24"))   // FF 24 ok at 25 fps
    }
    func test_isValid_rejects_malformed_or_out_of_range() {
        XCTAssertFalse(Smpte.isValid(""))
        XCTAssertFalse(Smpte.isValid("1:2:3:4"))
        XCTAssertFalse(Smpte.isValid("00:60:00:00")) // MM >= 60
        XCTAssertFalse(Smpte.isValid("00:00:60:00")) // SS >= 60
        XCTAssertFalse(Smpte.isValid("00:00:00:25")) // FF >= 25
        XCTAssertFalse(Smpte.isValid("00:00:00"))
    }
    func test_secondsString_converts_at_25fps() {
        XCTAssertEqual(Smpte.secondsString("00:00:00:00"), "0.0")
        XCTAssertEqual(Smpte.secondsString("00:00:05:00"), "5.0")
        XCTAssertEqual(Smpte.secondsString("00:00:00:05"), "0.2")   // 5/25
        XCTAssertEqual(Smpte.secondsString("01:00:00:00"), "3600.0")
        XCTAssertNil(Smpte.secondsString("bad"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SaettaKitTests/SmpteTests -quiet
```
Expected: FAIL — `Smpte` undefined.

- [ ] **Step 3: Implement**

Create `ios/Sources/Kit/Send/Smpte.swift`:

```swift
import Foundation

/// SMPTE `HH:MM:SS:FF` helpers, hard-coded to 25 fps (PAL/EBU), matching the
/// web timecode contract. `time` on a grandMA3 Timecode event is float seconds.
public enum Smpte {
    public static let fps = 25

    private static let pattern = try! NSRegularExpression(pattern: "^(\\d{2}):(\\d{2}):(\\d{2}):(\\d{2})$")

    private static func parts(_ s: String) -> (h: Int, m: Int, sec: Int, f: Int)? {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = pattern.firstMatch(in: s, range: range) else { return nil }
        func grp(_ i: Int) -> Int { Int((s as NSString).substring(with: m.range(at: i))) ?? 0 }
        return (grp(1), grp(2), grp(3), grp(4))
    }

    public static func isValid(_ s: String) -> Bool {
        guard let p = parts(s) else { return false }
        return p.m < 60 && p.sec < 60 && p.f < fps
    }

    /// Seconds as a float STRING for the MA3 `Set ... Property 'time' <secs>` command.
    /// nil for invalid input. Uses the shortest exact decimal (e.g. "0.2", "5.0").
    public static func secondsString(_ s: String) -> String? {
        guard isValid(s), let p = parts(s) else { return nil }
        let seconds = Double(p.h) * 3600 + Double(p.m) * 60 + Double(p.sec) + Double(p.f) / Double(fps)
        // Trim to avoid float noise; keep at least one decimal place.
        var str = String(format: "%.6f", seconds)
        while str.contains("."), str.hasSuffix("0") { str.removeLast() }
        if str.hasSuffix(".") { str += "0" }
        return str
    }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SaettaKitTests/SmpteTests -quiet
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Send/Smpte.swift ios/Tests/KitTests/SmpteTests.swift ios/project.yml
git commit -m "feat(saetta): Smpte — 25fps SMPTE validation + seconds conversion"
```

---

### Task 6: `TimecodeBuilder` — append-only events for ticked cues

> **DESK-VERIFIED LINE (the only thing deferred to onPC):** the inline-Lua command below appends one event and sets its `time` desk-side, self-counting so existing events are never deleted. The `count` accessor expression (`<<TC_COUNT_EXPR>>` below, encoded in `tcCountLuaExpr`) is our best hypothesis from the web-branch exploration notes; **Task 12 (onPC smoke) verifies and, if needed, corrects this one expression + its golden test.** Everything else here is proven from `web/js/compile.js` and is fully tested offline.

**Files:**
- Create: `ios/Sources/Kit/Send/TimecodeBuilder.swift`
- Create: `ios/Tests/KitTests/TimecodeBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/KitTests/TimecodeBuilderTests.swift`:

```swift
import XCTest
@testable import SaettaKit

final class TimecodeBuilderTests: XCTestCase {

    private func song() -> Song {
        let c1 = Cue(n: 1, name: "A", position: "00:00:05:00")        // valid, ticked
        let c2 = Cue(n: 2, name: "B", position: "")                   // no TC
        let c3 = Cue(n: 3, name: "C", position: "00:00:10:00")        // valid, NOT ticked
        let c4 = Cue(n: 4, name: "D", position: "bad")                // invalid, ticked → skipped
        return Song(id: "s1", sequence: 12, cues: [c1, c2, c3, c4])
    }

    func test_only_ticked_valid_cues_in_ascending_order() {
        let s = song()
        let ticked: Set<UUID> = [s.cues[0].id, s.cues[3].id]   // c1 (valid) + c4 (invalid)
        let events = TimecodeBuilder.events(song: s, ticked: ticked)
        XCTAssertEqual(events.map(\.cueN), [1])                 // c4 dropped (invalid), c3 not ticked
        XCTAssertEqual(events[0].sequence, 12)
        XCTAssertEqual(events[0].seconds, "5.0")
    }

    func test_lines_emit_one_inline_lua_per_event() {
        let s = song()
        let ticked: Set<UUID> = [s.cues[0].id]
        let lines = TimecodeBuilder.lines(song: s, ticked: ticked)
        XCTAssertEqual(lines.count, 1)
        // Append-only: NO Delete commands anywhere (would clobber existing events).
        XCTAssertFalse(lines.joined().contains("Delete"))
        // Proven inner commands are present, addressed at the self-counted next index.
        let line = lines[0]
        XCTAssertTrue(line.hasPrefix("Lua \""))
        XCTAssertTrue(line.contains("Store Timecode '..n..'.1.1.1.1"))
        XCTAssertTrue(line.contains("Goto Cue 1 Sequence '..n"))
        XCTAssertTrue(line.contains("Property"))
        XCTAssertTrue(line.contains("5.0"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SaettaKitTests/TimecodeBuilderTests -quiet
```
Expected: FAIL — `TimecodeBuilder` undefined.

- [ ] **Step 3: Implement**

Create `ios/Sources/Kit/Send/TimecodeBuilder.swift`:

```swift
import Foundation

/// Turns ticked cues into APPEND-ONLY grandMA3 Timecode commands.
/// Convention: TC pool number == sequence number. 25 fps. `time` is float seconds.
///
/// Append-only is the whole point: we never issue the web overwrite path's
/// `Delete ... × 200` cleanup, so timecodes already on the desk for other cues are
/// untouched. Each ticked cue becomes ONE inline-Lua command that, desk-side:
///   1. reads the current event count of TC pool N's subtrack,
///   2. `Store`s a new `Goto Cue c Sequence N` event (lands at the next index),
///   3. `Set`s that event's `time` property to the SMPTE→seconds value.
/// The two inner `Cmd(...)` strings are proven (see web ma3-command-spec). Only the
/// count accessor (`tcCountLuaExpr`) is desk-verified in the onPC smoke task.
public enum TimecodeBuilder {

    public struct Event: Equatable {
        public let sequence: Int
        public let cueN: Double
        public let seconds: String
    }

    private static func formatN(_ n: Double) -> String {
        n.rounded() == n ? String(Int(n)) : String(n)
    }

    /// Lua expression (evaluated desk-side) yielding the count of existing events
    /// in TC pool `n`'s subtrack, so the new event appends at `count + 1`.
    /// HYPOTHESIS — verified/corrected in the onPC smoke task. Isolated here so the
    /// fix is one constant + one golden test, nothing else.
    static func tcCountLuaExpr(_ poolVar: String) -> String {
        "Root().ShowData.DataPools.Default.Timecodes:Ptr(\(poolVar)).Tracks:Ptr(1).TrackGroups:Ptr(1).Tracks:Ptr(1).Count"
    }

    /// Ticked + valid cues for this song, ascending by cue number.
    public static func events(song: Song, ticked: Set<UUID>) -> [Event] {
        song.cues
            .filter { ticked.contains($0.id) }
            .filter { Smpte.isValid($0.position) }
            .sorted { $0.n < $1.n }
            .compactMap { cue -> Event? in
                guard let secs = Smpte.secondsString(cue.position) else { return nil }
                return Event(sequence: song.sequence, cueN: cue.n, seconds: secs)
            }
    }

    /// One inline-Lua `cmd` line per ticked+valid cue. Append-only.
    public static func lines(song: Song, ticked: Set<UUID>) -> [String] {
        events(song: song, ticked: ticked).map { ev in
            let n = ev.sequence
            let c = formatN(ev.cueN)
            let s = ev.seconds
            // Build the Lua body, then escape the outer `cmd` string's quotes.
            // Inner single quotes wrap MA3 Cmd strings; \" appears in the Goto label.
            let count = tcCountLuaExpr("n")
            let body =
                "local n=\(n) " +
                "local i=(\(count) or 0)+1 " +
                "Cmd('Store Timecode '..n..'.1.1.1.1 \\\"Goto Cue \(c) Sequence '..n..'\\\" /NoConfirmation') " +
                "Cmd('Set Timecode '..n..'.1.1.1.1.'..i..' Property \\'time\\' \(s)')"
            return "Lua \"\(body)\""
        }
    }
}
```

> Note: the test in Step 1 asserts substrings (`Store Timecode '..n..'.1.1.1.1`, `Goto Cue 1 Sequence '..n`, `Property`, `5.0`) rather than the full line, so a later correction to `tcCountLuaExpr` during onPC does not churn the test beyond its own dedicated assertion. Keep the substring assertions; the onPC task may add/adjust an explicit golden assertion for the count expression.

- [ ] **Step 4: Run to verify it passes**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SaettaKitTests/TimecodeBuilderTests -quiet
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Send/TimecodeBuilder.swift ios/Tests/KitTests/TimecodeBuilderTests.swift ios/project.yml
git commit -m "feat(saetta): TimecodeBuilder — append-only TC events for ticked cues"
```

---

## Part D — Wiring (HubClient batch send + transient selection)

### Task 7: `HubClient.sendLines` + `sendCues`/`sendNotes`/`sendTimecode`

**Files:**
- Modify: `ios/Sources/Kit/Hub/HubClient.swift`
- Modify: `ios/Tests/KitTests/HubClientTests.swift`

- [ ] **Step 1: Write the failing test**

First inspect the existing test's fake connection helper:
```bash
sed -n '1,60p' ios/Tests/KitTests/HubClientTests.swift
```
It defines a spy/fake `HubConnection` capturing sent frames (used by existing send tests). Reuse that exact fake. Append this test (adapt the fake's type/initializer name to match what the file already uses — referred to below as `makeClient()` returning `(HubClient, spy)`):

```swift
    func test_sendLines_sends_each_line_as_cmd_and_reports_done() async {
        let (client, spy) = makeOnlineClient()   // helper already in this file pattern
        client.sendLines(["A", "B", "C"], intervalMs: 0)
        // Let the throttled Task drain.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let sentLines = spy.sentFrames.compactMap { frameToCmdLine($0) }
        XCTAssertEqual(sentLines, ["A", "B", "C"])
        XCTAssertEqual(client.lastResult, .done(total: 3))
        XCTAssertNil(client.progress)
    }
```

> If the existing file has no `makeOnlineClient()` / `frameToCmdLine` helpers, add small local ones in this test file: build a `HubClient` with the fake connection factory the other tests use, drive it to `.online` the same way they do, and parse the `{"type":"cmd","line":"..."}` JSON frame for its `line`.

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SaettaKitTests/HubClientTests/test_sendLines_sends_each_line_as_cmd_and_reports_done -quiet
```
Expected: FAIL — `sendLines` undefined.

- [ ] **Step 3: Implement on `HubClient`**

Add these methods to `HubClient` (after `sendCommand`):

```swift
    /// Send a batch of command lines as individual `cmd` frames, throttled to
    /// match the hub's compile-send pacing (the hub forwards single `cmd` frames
    /// immediately, so spacing must happen here). Drives the same progress/result
    /// the Send tab already binds to. No desk ack is awaited.
    public func sendLines(_ lines: [String], intervalMs: Int = 20) {
        if !state.isOnline { connect() }
        guard connection != nil else { lastResult = .failed("not connected"); return }
        guard !lines.isEmpty else { return }
        progress = SendProgress(sent: 0, total: lines.count)
        lastResult = nil
        Task { @MainActor in
            for (i, line) in lines.enumerated() {
                guard let conn = self.connection else { break }
                if let text = try? OutgoingMessage.cmd(line: line).jsonString() {
                    conn.send(text)
                }
                self.progress = SendProgress(sent: i + 1, total: lines.count)
                if i < lines.count - 1, intervalMs > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(intervalMs) * 1_000_000)
                }
            }
            self.progress = nil
            self.lastResult = .done(total: lines.count)
        }
    }

    /// Send cue STRUCTURE only (no notes) for the selection.
    public func sendCues(project: Project, defaults: Defaults, selection: Selection) {
        let songs = MA3CommandBuilder.songsInScope(project, selection: selection)
        guard !songs.isEmpty else { lastResult = .failed("no cues to send"); return }
        sendLines(MA3CommandBuilder.cueLines(songs: songs, defaults: defaults, storeMode: project.storeMode))
    }

    /// Send NOTES only for the selection.
    public func sendNotes(project: Project, selection: Selection) {
        let songs = MA3CommandBuilder.songsInScope(project, selection: selection)
        let lines = MA3CommandBuilder.noteLines(songs: songs)
        guard !lines.isEmpty else { lastResult = .failed("no notes to send"); return }
        sendLines(lines)
    }

    /// Append the ticked cues' timecode to the active song's sequence (append-only).
    public func sendTimecode(song: Song, ticked: Set<UUID>) {
        let lines = TimecodeBuilder.lines(song: song, ticked: ticked)
        guard !lines.isEmpty else { lastResult = .failed("no timecode to send"); return }
        sendLines(lines)
    }
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SaettaKitTests/HubClientTests -quiet
```
Expected: PASS (new test + all existing HubClient tests).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Hub/HubClient.swift ios/Tests/KitTests/HubClientTests.swift
git commit -m "feat(saetta): HubClient batch send — sendCues/sendNotes/sendTimecode"
```

---

### Task 8: Transient TC tick selection on `ProjectStore`

**Files:**
- Modify: `ios/Sources/Kit/Store/ProjectStore.swift`
- Create: `ios/Tests/KitTests/TcSelectionTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/KitTests/TcSelectionTests.swift`:

```swift
import XCTest
@testable import SaettaKit

@MainActor
final class TcSelectionTests: XCTestCase {
    private func store() -> ProjectStore {
        ProjectStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    func test_toggle_and_clear() {
        let s = store()
        let id = UUID()
        XCTAssertFalse(s.isTcSelected(id))
        s.toggleTc(id)
        XCTAssertTrue(s.isTcSelected(id))
        s.toggleTc(id)
        XCTAssertFalse(s.isTcSelected(id))
        s.toggleTc(id)
        s.clearTcSelection()
        XCTAssertTrue(s.tcSelection.isEmpty)
    }

    func test_selection_not_persisted() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let id = UUID()
        do { let s = ProjectStore(directory: dir); s.toggleTc(id); s.saveNow() }
        let reloaded = ProjectStore(directory: dir)
        XCTAssertTrue(reloaded.tcSelection.isEmpty, "TC ticks must never persist across launches")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SaettaKitTests/TcSelectionTests -quiet
```
Expected: FAIL — `tcSelection`/`toggleTc` undefined.

- [ ] **Step 3: Implement on `ProjectStore`**

Add to `ProjectStore` (as stored property near `project`/`defaults`, and methods anywhere in the class body):

```swift
    /// Cues (by `Cue.id`) ticked for the next Send Timecode. TRANSIENT: it is a
    /// plain property (not part of `project`), so it is never written to disk and
    /// resets to empty on every launch. Cleared after a successful TC send.
    public var tcSelection: Set<UUID> = []

    public func isTcSelected(_ id: UUID) -> Bool { tcSelection.contains(id) }

    public func toggleTc(_ id: UUID) {
        if tcSelection.contains(id) { tcSelection.remove(id) } else { tcSelection.insert(id) }
    }

    public func clearTcSelection() { tcSelection.removeAll() }
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SaettaKitTests/TcSelectionTests -quiet
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Store/ProjectStore.swift ios/Tests/KitTests/TcSelectionTests.swift ios/project.yml
git commit -m "feat(saetta): transient per-cue TC tick selection on ProjectStore"
```

---

## Part E — UI

### Task 9: Per-cue TC value + tick box in the cue card

**Files:**
- Modify: `ios/Sources/App/CueCardView.swift`

- [ ] **Step 1: Add the TC row to the expanded cue card**

In `CueCardView.swift`, locate the expanded-editor block — the `HStack(spacing: 14)` that holds the Fade/Delay `StepperField`s (inside the `else` branch of `if cue.collapsed || isEditing`). Immediately **after** that `HStack { … }.padding(.top, 2)`, insert this TC row:

```swift
                HStack(spacing: 10) {
                    Text("TC").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textDim)
                    TextField("HH:MM:SS:FF", text: $cue.position)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(tcValid ? Theme.text : Theme.danger)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .frame(maxWidth: 130)
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    Spacer()
                    Button {
                        store.toggleTc(cue.id)
                    } label: {
                        Image(systemName: store.isTcSelected(cue.id) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundStyle(tcValid ? Theme.accentSolid : Theme.textFaint)
                    }
                    .buttonStyle(.plain)
                    .disabled(!tcValid)
                    .accessibilityLabel("Include timecode in Send Timecode")
                }
                .padding(.top, 4)
```

- [ ] **Step 2: Add the `tcValid` helper + un-tick on invalid edit**

Add this computed property to `CueCardView` (near `presetCount`):

```swift
    private var tcValid: Bool { Smpte.isValid(cue.position) }
```

To prevent a stale tick when the operator edits the TC into an invalid value, add `.onChange` to the `TextField` you inserted in Step 1 (chain it directly after the `TextField` modifiers):

```swift
                        .onChange(of: cue.position) { _, newValue in
                            if !Smpte.isValid(newValue) { store.tcSelection.remove(cue.id) }
                        }
```

- [ ] **Step 3: Build the app to verify it compiles**

```bash
cd ios && xcodegen generate && xcodebuild build -scheme Saetta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/CueCardView.swift
git commit -m "feat(saetta): per-cue TC field + tick box in cue card"
```

---

### Task 10: Send tab — three decoupled buttons

**Files:**
- Modify: `ios/Sources/App/SendView.swift`

- [ ] **Step 1: Replace the "Primary actions" block with three rows**

In `SendView.swift`, replace the `// Primary actions` `VStack(spacing: 12) { … }` (the two buttons "Send → MA" and "Send All Songs", through its `.disabled`/`.opacity` modifiers) with:

```swift
                    // Three decoupled send actions
                    VStack(spacing: 14) {
                        sendRow(title: "Send Cues", systemImage: "paperplane.fill", primary: true) {
                            hub.sendCues(project: store.project, defaults: store.defaults, selection: .current)
                        } allAction: {
                            hub.sendCues(project: store.project, defaults: store.defaults, selection: .all)
                        }

                        sendRow(title: "Send Notes", systemImage: "square.and.pencil", primary: false) {
                            hub.sendNotes(project: store.project, selection: .current)
                        } allAction: {
                            hub.sendNotes(project: store.project, selection: .all)
                        }

                        // Timecode: active song only, ticked cues only.
                        Button {
                            if let song = store.project.activeSong {
                                hub.sendTimecode(song: song, ticked: store.tcSelection)
                                store.clearTcSelection()
                            }
                        } label: {
                            Text(tickedCount > 0 ? "Send Timecode (\(tickedCount) ticked)" : "Send Timecode")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
                                .foregroundStyle(tickedCount > 0 ? Theme.text : Theme.textDim)
                        }
                        .buttonStyle(.plain)
                        .disabled(tickedCount == 0)
                    }
                    .disabled(!hub.state.isOnline)
                    .opacity(hub.state.isOnline ? 1 : 0.5)
```

- [ ] **Step 2: Add the `sendRow` helper + `tickedCount`**

Add to the `SendView` struct (after `body`):

```swift
    private var tickedCount: Int {
        guard let song = store.project.activeSong else { return 0 }
        return song.cues.filter { store.tcSelection.contains($0.id) && Smpte.isValid($0.position) }.count
    }

    @ViewBuilder
    private func sendRow(title: String, systemImage: String, primary: Bool,
                         currentAction: @escaping () -> Void,
                         allAction: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: primary ? .semibold : .medium))
                .foregroundStyle(Theme.text)
            Spacer()
            Button("current", action: currentAction)
                .buttonStyle(.borderedProminent)
                .tint(primary ? Theme.accentSolid : Theme.surface2)
            Button("all songs", action: allAction)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
```

> The first parameter label in the call site uses Swift trailing-closure-plus-named form: `sendRow(... ) { current } allAction: { all }`. Ensure the function's first closure param is named `currentAction` (matched by the trailing closure) and `allAction:` is the explicit label — as written above.

- [ ] **Step 3: Build to verify it compiles**

```bash
cd ios && xcodegen generate && xcodebuild build -scheme Saetta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Full Kit test run (regression)**

```bash
cd ios && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/App/SendView.swift
git commit -m "feat(saetta): Send tab split into Send Cues / Send Notes / Send Timecode"
```

---

## Part F — Docs + device smoke

### Task 11: Documentation

**Files:**
- Modify: `shared/ma3-command-spec.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Append the iOS append-only TC section to `shared/ma3-command-spec.md`**

Add at the end:

```markdown
## Timecode insert (Saetta iOS — append-only)

Saetta sends timecode for individually **ticked** cues, appending to the desk's
Timecode pool **without** the overwrite path's delete-all cleanup, so existing
events for other cues are preserved.

Preconditions (operator, once per song on the desk): Sequence `<N>` exists with
cues; Timecode pool `<N>` exists; Track at `Timecode <N>.1.1` targets Sequence `<N>`.

Per ticked cue (sequence `<N>`, cue `<c>`, time `<secs>` = SMPTE→seconds at 25 fps),
one inline-Lua command appends the event at the self-counted next index:

```
Lua "local n=<N> local i=(<count-expr>)+1 Cmd('Store Timecode '..n..'.1.1.1.1 \"Goto Cue <c> Sequence '..n..'\" /NoConfirmation') Cmd('Set Timecode '..n..'.1.1.1.1.'..i..' Property \'time\' <secs>')"
```

`<count-expr>` reads the current event count of the pool's subtrack (see
`TimecodeBuilder.tcCountLuaExpr` — verified on hardware 2026-06-xx). The two inner
`Cmd` strings are the proven Store/Set pair from the overwrite spec above; only the
absence of the delete phase and the self-counted index differ.
```

- [ ] **Step 2: Update `README.md`**

Find any "Cuelist Compiler" references describing the iOS app and update the iOS section to name it **Saetta**, and add a one-line note: "Saetta (iOS) sends Cues, Notes, and per-cue Timecode as three independent actions; Timecode is append-only for ticked cues (pre-create the TC pool Track on the desk first)."

- [ ] **Step 3: Update `CHANGELOG.md`**

Add an entry under the current/unreleased section:

```markdown
- iOS app renamed to **Saetta**. Send tab split into Send Cues / Send Notes /
  Send Timecode. New per-cue timecode tick box: ticked cues are appended to the
  grandMA3 Timecode pool without disturbing existing events.
```

- [ ] **Step 4: Commit**

```bash
git add shared/ma3-command-spec.md README.md CHANGELOG.md
git commit -m "docs(saetta): rename + append-only TC contract + send-split notes"
```

---

### Task 12: onPC device smoke — resolve the TC append mechanism (THE GATE)

> Manual UAT against grandMA3 onPC + the menubar hub. This is where the one deferred unknown (`TimecodeBuilder.tcCountLuaExpr`) is verified or corrected. No code is written blind here — observe, then fix the single expression + its golden test if needed.

**Files (only if a correction is needed):**
- Modify: `ios/Sources/Kit/Send/TimecodeBuilder.swift` (the `tcCountLuaExpr` constant only)
- Modify: `ios/Tests/KitTests/TimecodeBuilderTests.swift` (add/adjust the golden assertion for the count expression)

- [ ] **Step 1: Bring up the loop**

Launch grandMA3 onPC; run the menubar hub from source (`cd menubar-hub && npm start`); point OSC Output **off** loopback to avoid the echo loop (per the internet-hub gotcha). Install Saetta on the simulator or jPhone(2) and connect (direct or relay).

- [ ] **Step 2: Pre-create the TC pool Track**

On the desk: Store Sequence N with cues (use Send Cues from Saetta). Create Timecode pool N. Drag Sequence N onto TC pool slot N so a Track at `Timecode N.1.1` targets Sequence N. Manually add ONE timecode event for an existing cue (e.g. cue 1 at `00:00:05:00`) so there is pre-existing content to protect.

- [ ] **Step 3: Test the append**

In Saetta: add a "missing" cue (e.g. cue 3), type `00:00:12:00`, tick it, tap Send Timecode.

- [ ] **Step 4: Verify the invariant**

On the desk, open TC pool N's events. Confirm: (a) the new cue-3 event exists at 12.0 s; (b) the pre-existing cue-1 event at 5.0 s is **still present and unchanged**. This is the core promise.

- [ ] **Step 5: If the event did not land — diagnose the count expression**

Run the inline Lua's count expression directly in the MA3 command line (`Lua "Echo(tostring(<count-expr>))"` with `n` substituted) to find the correct accessor for the subtrack event count. Update `TimecodeBuilder.tcCountLuaExpr` to the verified expression, update the golden assertion in `TimecodeBuilderTests`, re-run Kit tests, and repeat Steps 3–4. (Fallback per spec: if inline Lua proves unworkable, escalate to the read-back contingency — out of scope for this task unless inline Lua is conclusively dead.)

- [ ] **Step 6: Regression smoke — cues + notes decoupled**

Send Cues (no notes should appear on the desk's cue notes), then Send Notes (notes populate). Confirm the two are independent.

- [ ] **Step 7: Record results + commit any correction**

Append the dated smoke result (and the verified `tcCountLuaExpr`) to `docs/superpowers/specs/2026-06-06-saetta-rename-and-send-split-design.md` under a new "## Device smoke results" section.

```bash
git add ios/Sources/Kit/Send/TimecodeBuilder.swift ios/Tests/KitTests/TimecodeBuilderTests.swift docs/superpowers/specs/2026-06-06-saetta-rename-and-send-split-design.md
git commit -m "test(saetta): onPC TC append verified — existing events preserved"
```

---

## Self-review notes (for the executor)

- **Spec coverage:** Rename → Tasks 1–2. Send-tab split (3 buttons, notes decoupled from cues) → Tasks 3, 4, 7, 10. Per-cue TC tick box + transient selection → Tasks 5, 6, 8, 9. Append-only invariant → Tasks 6, 12. Docs → Task 11. Device-smoke gate → Task 12.
- **Type consistency:** `MA3CommandBuilder.cueLines/noteLines/songsInScope`, `Smpte.isValid/secondsString`, `TimecodeBuilder.events/lines/Event/tcCountLuaExpr`, `HubClient.sendLines/sendCues/sendNotes/sendTimecode`, `ProjectStore.tcSelection/toggleTc/isTcSelected/clearTcSelection` — names are used identically across the tasks that define and call them.
- **The one deferred unknown** is isolated to `TimecodeBuilder.tcCountLuaExpr` and verified in Task 12, exactly as the spec and the user approved. Everything else is offline-tested.
- **HubClientTests helper names** (`makeOnlineClient`, `frameToCmdLine`) must be matched to whatever the existing file already provides — Step 1 of Task 7 says to adapt. Read the file first.
