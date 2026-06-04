# Cuelist Compiler iOS — M1 Plan 1: Engine & Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the headless, fully-tested engine of the iOS app — data models that round-trip the `show.json` schema, the `CommandBuilder` that reproduces `web/js/compile.js` byte-for-byte, OSC UDP transport, and local JSON persistence — inside a `CuelistCompilerKit` framework.

**Architecture:** A `CuelistCompilerKit` iOS framework holds Models/Compile/Transport/Store. A thin `CuelistCompiler` app target (stub UI in this plan; real UI in Plan 2) depends on it. Tests live in `CuelistCompilerKitTests` and use `@testable import CuelistCompilerKit` with no host app. Contract parity is enforced by golden fixtures generated from the JS reference.

**Tech Stack:** Swift 5.9 / iOS 17, SwiftUI (app shell only here), Network.framework (UDP), XCTest, xcodegen, Node (golden-fixture generator).

**Design doc:** `docs/superpowers/specs/2026-06-04-ios-frontend-design.md`

**Standard test command (run from repo root):**
```bash
cd ios && xcodegen generate >/dev/null && \
xcodebuild test -project CuelistCompiler.xcodeproj -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Always run `xcodegen generate` before `xcodebuild` (regenerates the project from `project.yml`).

---

## Task 1: xcodegen scaffold + green build/test loop

**Files:**
- Create: `ios/project.yml`
- Create: `ios/Sources/Kit/Kit.swift`
- Create: `ios/Sources/App/App.swift`
- Create: `ios/Tests/KitTests/SmokeTests.swift`
- Create: `ios/.gitignore`

- [ ] **Step 1: Write `ios/project.yml`**

```yaml
name: CuelistCompiler
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
  CuelistCompilerKit:
    type: framework
    platform: iOS
    sources:
      - path: Sources/Kit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.blearred.cuelistcompiler.kit
        ENABLE_TESTABILITY: YES
  CuelistCompiler:
    type: application
    platform: iOS
    sources:
      - path: Sources/App
    dependencies:
      - target: CuelistCompilerKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.blearred.cuelistcompiler
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait
  CuelistCompilerKitTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests/KitTests
      - path: ../examples/SONG_1.json
        buildPhase: resources
      - path: ../examples/SONG_1.lua
        buildPhase: resources
      - path: ../examples/SONG_1.cmdlines.txt
        buildPhase: resources
        optional: true
    dependencies:
      - target: CuelistCompilerKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.blearred.cuelistcompiler.kittests
        GENERATE_INFOPLIST_FILE: YES
schemes:
  CuelistCompilerKit:
    build:
      targets:
        CuelistCompilerKit: all
    test:
      targets:
        - CuelistCompilerKitTests
  CuelistCompiler:
    build:
      targets:
        CuelistCompiler: all
```

Note: `SONG_1.cmdlines.txt` is marked `optional: true` because it does not exist until Task 5. Remove `optional: true` after Task 5.

- [ ] **Step 2: Write `ios/Sources/Kit/Kit.swift`** (placeholder so the framework has at least one source)

```swift
import Foundation

/// Marker for the CuelistCompilerKit module. Real types live in Models/Compile/Transport/Store.
public enum CuelistCompilerKit {
    public static let schemaVersion = 1
}
```

- [ ] **Step 3: Write `ios/Sources/App/App.swift`** (minimal runnable shell; real UI in Plan 2)

```swift
import SwiftUI
import CuelistCompilerKit

@main
struct CuelistCompilerApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Text("Cuelist Compiler").font(.title.bold())
                Text("Engine v\(CuelistCompilerKit.schemaVersion) — UI lands in Plan 2")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
```

- [ ] **Step 4: Write `ios/Tests/KitTests/SmokeTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

final class SmokeTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(CuelistCompilerKit.schemaVersion, 1)
    }
}
```

- [ ] **Step 5: Write `ios/.gitignore`**

```
# Xcode / xcodegen
*.xcodeproj
build/
DerivedData/
*.xcuserstate
.DS_Store
```

- [ ] **Step 6: Generate project and run the test**

Run:
```bash
cd ios && xcodegen generate && \
xcodebuild test -project CuelistCompiler.xcodeproj -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: build succeeds, `SmokeTests.testModuleLoads` PASSES.

- [ ] **Step 7: Commit**

```bash
git add ios/project.yml ios/Sources ios/Tests ios/.gitignore
git commit -m "feat(ios): xcodegen scaffold — Kit framework + app shell + green test loop"
```

---

## Task 2: Pool and StoreMode value types

**Files:**
- Create: `ios/Sources/Kit/Models/Pool.swift`
- Create: `ios/Sources/Kit/Models/StoreMode.swift`
- Test: `ios/Tests/KitTests/PoolTests.swift`

- [ ] **Step 1: Write the failing test `PoolTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

final class PoolTests: XCTestCase {
    func testCanonicalOrder() {
        XCTAssertEqual(Pool.allCases, [.color, .dimmer, .position, .gobo, .beam, .focus])
    }

    func testPoolNumbers() {
        XCTAssertEqual(Pool.dimmer.number, 1)
        XCTAssertEqual(Pool.position.number, 2)
        XCTAssertEqual(Pool.gobo.number, 3)
        XCTAssertEqual(Pool.color.number, 4)
        XCTAssertEqual(Pool.beam.number, 5)
        XCTAssertEqual(Pool.focus.number, 6)
    }

    func testRawValuesMatchSchema() {
        XCTAssertEqual(Pool.color.rawValue, "color")
        XCTAssertEqual(Pool.allCases.map(\.rawValue),
                       ["color", "dimmer", "position", "gobo", "beam", "focus"])
    }

    func testStoreModeFlag() {
        XCTAssertEqual(StoreMode.overwrite.flag, "/Overwrite")
        XCTAssertEqual(StoreMode.merge.flag, "/Merge")
    }
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run the standard test command (filtering optional). Expected: FAIL — `Pool`/`StoreMode` undefined.

- [ ] **Step 3: Write `Pool.swift`**

```swift
import Foundation

/// The six grandMA3 preset pools. `allCases` order is the canonical iteration
/// order used by the command builder (mirrors web `POOLS`). `number` mirrors
/// web `POOL_NUM` (the MA3 pool index, which is NOT the iteration order).
public enum Pool: String, CaseIterable, Codable, Hashable, Sendable {
    case color, dimmer, position, gobo, beam, focus

    public var number: Int {
        switch self {
        case .dimmer:   return 1
        case .position: return 2
        case .gobo:     return 3
        case .color:    return 4
        case .beam:     return 5
        case .focus:    return 6
        }
    }
}
```

- [ ] **Step 4: Write `StoreMode.swift`**

```swift
import Foundation

/// Show store mode. Mirrors web `state.storeMode`.
public enum StoreMode: String, Codable, Sendable {
    case overwrite = "Overwrite"
    case merge = "Merge"

    public var flag: String { "/" + rawValue }
}
```

- [ ] **Step 5: Run the test, verify it passes**

Expected: `PoolTests` all PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/Kit/Models/Pool.swift ios/Sources/Kit/Models/StoreMode.swift ios/Tests/KitTests/PoolTests.swift
git commit -m "feat(ios): Pool + StoreMode value types"
```

---

## Task 3: Codable models matching the show.json schema

The web `saveProject()` dumps `{ songs:[{ id,name,sequence,cues:[{ n,name,fade,delay,position,collapsed,actions:[{ group,presets:{ color:{name,fade,delay}, ... } }] }] }], activeSongId, storeMode }`. `Action.presets` must encode as a JSON **object** keyed by pool name (not an array), so `presets` gets a custom `Codable`.

**Files:**
- Create: `ios/Sources/Kit/Models/Preset.swift`
- Create: `ios/Sources/Kit/Models/Action.swift`
- Create: `ios/Sources/Kit/Models/Cue.swift`
- Create: `ios/Sources/Kit/Models/Song.swift`
- Create: `ios/Sources/Kit/Models/Project.swift`
- Create: `ios/Sources/Kit/Models/Defaults.swift`
- Test: `ios/Tests/KitTests/ModelCodecTests.swift`

- [ ] **Step 1: Write the failing test `ModelCodecTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

final class ModelCodecTests: XCTestCase {
    func testPresetsEncodeAsObjectWithAllSixPools() throws {
        var action = Action(group: "AROLLA FLOOR")
        action.presets[.color] = Preset(name: "BLUE")
        let data = try JSONEncoder().encode(action)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let presets = obj["presets"] as! [String: Any]
        XCTAssertEqual(Set(presets.keys),
                       ["color", "dimmer", "position", "gobo", "beam", "focus"])
        let color = presets["color"] as! [String: Any]
        XCTAssertEqual(color["name"] as? String, "BLUE")
        XCTAssertEqual(color["fade"] as? String, "")
    }

    func testNewFormatProjectRoundTrips() throws {
        let json = """
        {"songs":[{"id":"s1","name":"S","sequence":3,"audioFileName":"",
        "cues":[{"n":1,"name":"C","fade":"5","delay":"","position":"","collapsed":false,
        "actions":[{"group":"G","presets":{
        "color":{"name":"RED","fade":"","delay":""},
        "dimmer":{"name":"","fade":"","delay":""},
        "position":{"name":"","fade":"","delay":""},
        "gobo":{"name":"","fade":"","delay":""},
        "beam":{"name":"","fade":"","delay":""},
        "focus":{"name":"","fade":"","delay":""}}}]}]}],
        "activeSongId":"s1","storeMode":"Overwrite"}
        """.data(using: .utf8)!
        let project = try JSONDecoder().decode(Project.self, from: json)
        XCTAssertEqual(project.songs.count, 1)
        XCTAssertEqual(project.songs[0].cues[0].actions[0].presets[.color]?.name, "RED")
        XCTAssertEqual(project.storeMode, .overwrite)
        // re-encode and decode again: stable
        let data = try JSONEncoder().encode(project)
        let again = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(again.songs[0].name, "S")
        XCTAssertEqual(again.songs[0].cues[0].n, 1)
    }
}
```

- [ ] **Step 2: Run, verify it fails** (types undefined).

- [ ] **Step 3: Write `Preset.swift`**

```swift
import Foundation

/// One preset slot for a pool. fade/delay are Strings (mirrors web form fields;
/// the command builder trims and checks emptiness, so string fidelity matters).
public struct Preset: Codable, Equatable, Sendable {
    public var name: String
    public var fade: String
    public var delay: String

    public init(name: String = "", fade: String = "", delay: String = "") {
        self.name = name
        self.fade = fade
        self.delay = delay
    }
}
```

- [ ] **Step 4: Write `Action.swift`** (custom Codable so `presets` is a 6-key object)

```swift
import Foundation

public struct Action: Codable, Equatable, Sendable {
    public var group: String
    /// Always carries all six pools (empty Preset when unset), matching web `newAction()`.
    public var presets: [Pool: Preset]

    public init(group: String = "", presets: [Pool: Preset]? = nil) {
        self.group = group
        if let presets {
            self.presets = presets
        } else {
            var p: [Pool: Preset] = [:]
            for pool in Pool.allCases { p[pool] = Preset() }
            self.presets = p
        }
    }

    private enum CodingKeys: String, CodingKey { case group, presets }

    private struct PoolKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        init(_ pool: Pool) { self.stringValue = pool.rawValue }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        var result: [Pool: Preset] = [:]
        for pool in Pool.allCases { result[pool] = Preset() }
        if let pc = try? c.nestedContainer(keyedBy: PoolKey.self, forKey: .presets) {
            for pool in Pool.allCases {
                if let preset = try? pc.decode(Preset.self, forKey: PoolKey(pool)) {
                    result[pool] = preset
                }
            }
        }
        presets = result
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(group, forKey: .group)
        var pc = c.nestedContainer(keyedBy: PoolKey.self, forKey: .presets)
        for pool in Pool.allCases {
            try pc.encode(presets[pool] ?? Preset(), forKey: PoolKey(pool))
        }
    }
}
```

- [ ] **Step 5: Write `Cue.swift`**

```swift
import Foundation

public struct Cue: Codable, Equatable, Sendable {
    public var n: Double
    public var name: String
    public var fade: String
    public var delay: String
    public var position: String
    public var collapsed: Bool
    public var actions: [Action]

    public init(n: Double = 1, name: String = "", fade: String = "", delay: String = "",
                position: String = "", collapsed: Bool = false, actions: [Action] = [Action()]) {
        self.n = n; self.name = name; self.fade = fade; self.delay = delay
        self.position = position; self.collapsed = collapsed; self.actions = actions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = try c.decodeIfPresent(Double.self, forKey: .n) ?? 1
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        fade = try c.decodeIfPresent(String.self, forKey: .fade) ?? ""
        delay = try c.decodeIfPresent(String.self, forKey: .delay) ?? ""
        position = try c.decodeIfPresent(String.self, forKey: .position) ?? ""
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        actions = try c.decodeIfPresent([Action].self, forKey: .actions) ?? []
    }
}
```

- [ ] **Step 6: Write `Song.swift`**

```swift
import Foundation

public struct Song: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var sequence: Int
    public var cues: [Cue]
    public var audioFileName: String

    public init(id: String, name: String = "", sequence: Int = 1,
                cues: [Cue] = [], audioFileName: String = "") {
        self.id = id; self.name = name; self.sequence = sequence
        self.cues = cues; self.audioFileName = audioFileName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? IDGen.next()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        // web stores sequence as a number but tolerates strings via parseInt
        if let i = try? c.decode(Int.self, forKey: .sequence) {
            sequence = i
        } else if let s = try? c.decode(String.self, forKey: .sequence), let i = Int(s) {
            sequence = i
        } else {
            sequence = 1
        }
        cues = try c.decodeIfPresent([Cue].self, forKey: .cues) ?? []
        audioFileName = try c.decodeIfPresent(String.self, forKey: .audioFileName) ?? ""
    }
}
```

- [ ] **Step 7: Write `Project.swift`** (includes `IDGen`, the `genId` analog)

```swift
import Foundation

/// Mirrors web `genId()` shape ("s_" + base36 time + "_" + random). Ids never
/// appear in command output, so exact format is not contractual — only stable + unique.
public enum IDGen {
    public static func next() -> String {
        let t = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let r = String(UInt32.random(in: 0..<UInt32.max), radix: 36)
        return "s_\(t)_\(r.prefix(6))"
    }
}

public struct Project: Codable, Equatable, Sendable {
    public var songs: [Song]
    public var activeSongId: String
    public var storeMode: StoreMode

    public init(songs: [Song], activeSongId: String, storeMode: StoreMode = .overwrite) {
        self.songs = songs; self.activeSongId = activeSongId; self.storeMode = storeMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        songs = try c.decodeIfPresent([Song].self, forKey: .songs) ?? []
        activeSongId = try c.decodeIfPresent(String.self, forKey: .activeSongId) ?? ""
        let mode = try c.decodeIfPresent(String.self, forKey: .storeMode)
        storeMode = (mode == "Merge") ? .merge : .overwrite
    }

    /// A fresh project with one empty song (mirrors web `newProject()`).
    public static func empty() -> Project {
        let song = Song(id: IDGen.next(), sequence: 1, cues: [])
        return Project(songs: [song], activeSongId: song.id, storeMode: .overwrite)
    }

    public var activeSong: Song? {
        songs.first(where: { $0.id == activeSongId }) ?? songs.first
    }
}
```

- [ ] **Step 8: Write `Defaults.swift`** (stored separately, like web's `defaults` localStorage key)

```swift
import Foundation

/// Per-pool fallback fade/delay. Mirrors web `defaults`. Stored separately from Project.
public struct Defaults: Codable, Equatable, Sendable {
    public var values: [Pool: Preset]   // only fade/delay used; name ignored

    public init(values: [Pool: Preset]? = nil) {
        if let values {
            self.values = values
        } else {
            var v: [Pool: Preset] = [:]
            for pool in Pool.allCases { v[pool] = Preset() }
            self.values = v
        }
    }

    public func fade(_ pool: Pool) -> String { values[pool]?.fade ?? "" }
    public func delay(_ pool: Pool) -> String { values[pool]?.delay ?? "" }

    private struct PoolKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        init(_ pool: Pool) { self.stringValue = pool.rawValue }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PoolKey.self)
        var v: [Pool: Preset] = [:]
        for pool in Pool.allCases {
            v[pool] = (try? c.decode(Preset.self, forKey: PoolKey(pool))) ?? Preset()
        }
        values = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PoolKey.self)
        for pool in Pool.allCases {
            try c.encode(values[pool] ?? Preset(), forKey: PoolKey(pool))
        }
    }
}
```

- [ ] **Step 9: Run the test, verify it passes.** Expected: `ModelCodecTests` PASS.

- [ ] **Step 10: Commit**

```bash
git add ios/Sources/Kit/Models ios/Tests/KitTests/ModelCodecTests.swift
git commit -m "feat(ios): Codable models matching show.json schema"
```

---

## Task 4: Migration (old single-song format → current shape)

Mirrors web `migrateState`/`migrateCues`/`migrateActions`. The regression anchor `examples/SONG_1.json` is OLD format (`songName`/`sequence`/`cues` at top level; presets as bare strings). Migration must upgrade it before compilation.

**Files:**
- Create: `ios/Sources/Kit/Models/Migration.swift`
- Test: `ios/Tests/KitTests/MigrationTests.swift`

- [ ] **Step 1: Write the failing test `MigrationTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

final class MigrationTests: XCTestCase {
    private func loadSong1Raw() throws -> Data {
        let url = Bundle(for: MigrationTests.self).url(forResource: "SONG_1", withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url))
    }

    func testOldFormatUpgradesToOneSong() throws {
        let project = try Migration.project(fromShowJSON: loadSong1Raw())
        XCTAssertEqual(project.songs.count, 1)
        let song = project.songs[0]
        XCTAssertEqual(song.name, "SONG 1")
        XCTAssertEqual(song.sequence, 666)
        XCTAssertEqual(song.cues.count, 2)
    }

    func testBareStringPresetsBecomeObjects() throws {
        let project = try Migration.project(fromShowJSON: loadSong1Raw())
        let action = project.songs[0].cues[0].actions[0]
        XCTAssertEqual(action.group, "AROLLA FLOOR")
        XCTAssertEqual(action.presets[.color]?.name, "BLUE")
        XCTAssertEqual(action.presets[.dimmer]?.name, "DIMMER 100")
        XCTAssertEqual(action.presets[.gobo]?.name, "")          // was ""
        XCTAssertEqual(action.presets[.focus]?.name, "MEDIUM")
        XCTAssertEqual(action.presets[.color]?.fade, "")          // string presets get empty fade/delay
    }

    func testCueScalars() throws {
        let project = try Migration.project(fromShowJSON: loadSong1Raw())
        XCTAssertEqual(project.songs[0].cues[0].n, 0.1)
        XCTAssertEqual(project.songs[0].cues[0].name, "DB CUE")
        XCTAssertEqual(project.songs[0].cues[0].fade, "5")
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`Migration` undefined).

- [ ] **Step 3: Write `Migration.swift`**

```swift
import Foundation

/// Upgrades any saved show JSON (old single-song OR current multi-song format)
/// into a current `Project`. Mirrors web migrateState/migrateCues/migrateActions.
public enum Migration {

    public static func project(fromShowJSON data: Data) throws -> Project {
        let raw = try JSONSerialization.jsonObject(with: data)
        guard var dict = raw as? [String: Any] else {
            throw MigrationError.notAnObject
        }

        // Old single-song format: { songName, sequence, cues:[...] } with no `songs`.
        if dict["songs"] == nil, let cues = dict["cues"] {
            let song: [String: Any] = [
                "id": IDGen.next(),
                "name": dict["songName"] as? String ?? "",
                "sequence": dict["sequence"] ?? 1,
                "cues": cues,
                "audioFileName": ""
            ]
            dict = ["songs": [song], "activeSongId": song["id"]!, "storeMode": "Overwrite"]
        }

        // Normalize each song's cues/actions/presets to the current object shape.
        var songs = (dict["songs"] as? [[String: Any]]) ?? []
        for i in songs.indices {
            songs[i]["cues"] = normalizeCues(songs[i]["cues"] as? [[String: Any]] ?? [])
            if (songs[i]["id"] as? String) == nil { songs[i]["id"] = IDGen.next() }
            if (songs[i]["audioFileName"] as? String) == nil { songs[i]["audioFileName"] = "" }
        }
        dict["songs"] = songs

        let normalized = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(Project.self, from: normalized)
    }

    private static func normalizeCues(_ cues: [[String: Any]]) -> [[String: Any]] {
        cues.map { cue in
            var c = cue
            if (c["collapsed"] as? Bool) == nil { c["collapsed"] = false }
            if (c["position"] as? String) == nil { c["position"] = "" }
            c["actions"] = normalizeActions(c["actions"] as? [[String: Any]] ?? [])
            return c
        }
    }

    private static func normalizeActions(_ actions: [[String: Any]]) -> [[String: Any]] {
        actions.map { action in
            var a = action
            let rawPresets = a["presets"] as? [String: Any] ?? [:]
            var presets: [String: Any] = [:]
            for pool in Pool.allCases {
                let key = pool.rawValue
                switch rawPresets[key] {
                case let s as String:
                    presets[key] = ["name": s, "fade": "", "delay": ""]
                case let o as [String: Any]:
                    presets[key] = [
                        "name": o["name"] as? String ?? "",
                        "fade": stringify(o["fade"]),
                        "delay": stringify(o["delay"])
                    ]
                default:
                    presets[key] = ["name": "", "fade": "", "delay": ""]
                }
            }
            a["presets"] = presets
            if (a["group"] as? String) == nil { a["group"] = "" }
            return a
        }
    }

    /// Mirrors web's tolerance: fade/delay may arrive as number or string; store as string.
    private static func stringify(_ v: Any?) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return numberString(n)
        default: return ""
        }
    }

    private static func numberString(_ n: NSNumber) -> String {
        // Integers render without a decimal point (matches JS String(number)).
        if n === kCFBooleanTrue as NSNumber || n === kCFBooleanFalse as NSNumber { return "" }
        let d = n.doubleValue
        if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    }

    public enum MigrationError: Error { case notAnObject }
}
```

- [ ] **Step 4: Run the test, verify it passes.** Expected: `MigrationTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Models/Migration.swift ios/Tests/KitTests/MigrationTests.swift
git commit -m "feat(ios): show.json migration (old single-song -> current shape)"
```

---

## Task 5: Golden cmd-lines fixture generated from the JS reference

Generates `examples/SONG_1.cmdlines.txt` by running the actual web modules
(`constants.js` + `util.js` + `state.js` + `compile.js`) in a Node VM and calling
the real `buildCmdLines`. This is the source of truth the Swift builder is tested against.

**Files:**
- Create: `ios/tools/gen-golden.js`
- Create (generated): `examples/SONG_1.cmdlines.txt`
- Modify: `ios/project.yml` (remove `optional: true` from the cmdlines resource)

- [ ] **Step 1: Write `ios/tools/gen-golden.js`**

```javascript
'use strict';
// Regenerates examples/SONG_1.cmdlines.txt from the web JS reference.
// Run: node ios/tools/gen-golden.js   (from repo root)
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const repo = path.resolve(__dirname, '..', '..'); // ios/tools -> repo root
const webjs = (p) => fs.readFileSync(path.join(repo, 'web', 'js', p), 'utf8');

const sandbox = {
  console,
  window: {},
  localStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
  document: {
    createElement: () => ({ click() {}, style: {}, setAttribute() {} }),
    body: { appendChild() {}, removeChild() {} },
    getElementById: () => null,
  },
  alert: () => {},
  Blob: function () {},
  URL: { createObjectURL: () => '', revokeObjectURL: () => {} },
  setTimeout: () => {},
  Date, Math, JSON, parseInt, parseFloat, isNaN, isFinite,
  String, Number, Object, Array,
};
sandbox.globalThis = sandbox;
vm.createContext(sandbox);

// One combined script so top-level `const`/`let` lexical bindings are shared,
// then expose the functions/state we need out of that scope.
const combined = [
  webjs('constants.js'),
  webjs('util.js'),
  webjs('state.js'),
  webjs('compile.js'),
  'globalThis.__api = {' +
  '  buildCmdLines, buildLua, migrateState, makeDefaults,' +
  '  setState: (s) => { state = s; },' +
  '  setDefaults: (d) => { defaults = d; }' +
  '};',
].join('\n;\n');

vm.runInContext(combined, sandbox, { filename: 'combined.js' });
const api = sandbox.__api;

const raw = JSON.parse(fs.readFileSync(path.join(repo, 'examples', 'SONG_1.json'), 'utf8'));
const migrated = api.migrateState(raw);
api.setState(migrated);                  // buildCmdLines reads state.storeMode
api.setDefaults(api.makeDefaults());     // empty defaults (matches committed SONG_1.lua)

const lines = api.buildCmdLines(migrated.songs);
const outPath = path.join(repo, 'examples', 'SONG_1.cmdlines.txt');
fs.writeFileSync(outPath, lines.join('\n') + '\n');
console.log('wrote ' + path.relative(repo, outPath) + ' (' + lines.length + ' lines)');
```

- [ ] **Step 2: Run the generator**

Run (from repo root):
```bash
node ios/tools/gen-golden.js
```
Expected output: `wrote examples/SONG_1.cmdlines.txt (18 lines)`

- [ ] **Step 3: Verify the golden content**

Run: `cat examples/SONG_1.cmdlines.txt`
Expected (exactly):
```
ClearAll
Group "AROLLA FLOOR"
At Preset 4."BLUE"
At Preset 1."DIMMER 100"
At Preset 2."LOW"
At Preset 6."MEDIUM"
Store Sequence 666 Cue 0.1 "DB CUE" /Overwrite /NoConfirmation
Set Sequence 666 Cue 0.1 Fade 5
ClearAll
Group "AROLLA FLOOR"
At Preset 4."RED"
At Preset 1."DIMMER 0"
At Preset 2."AUD"
At Preset 6."WIDE"
Store Sequence 666 Cue 1 "INTRO" /Overwrite /NoConfirmation
Set Sequence 666 Cue 1 Fade 6
ClearAll
```
If output differs, STOP — the generator or the web reference changed; reconcile before continuing.

- [ ] **Step 4: Remove `optional: true` from the cmdlines resource in `ios/project.yml`**

Change:
```yaml
      - path: ../examples/SONG_1.cmdlines.txt
        buildPhase: resources
        optional: true
```
to:
```yaml
      - path: ../examples/SONG_1.cmdlines.txt
        buildPhase: resources
```

- [ ] **Step 5: Commit**

```bash
git add ios/tools/gen-golden.js examples/SONG_1.cmdlines.txt ios/project.yml
git commit -m "feat(ios): golden cmd-lines fixture generated from JS reference"
```

---

## Task 6: CommandBuilder.buildCmdLines — the OSC sequence (contract port)

**Files:**
- Create: `ios/Sources/Kit/Compile/JSNumber.swift`
- Create: `ios/Sources/Kit/Compile/CommandBuilder.swift`
- Test: `ios/Tests/KitTests/CommandBuilderCmdLinesTests.swift`

- [ ] **Step 1: Write the failing test `CommandBuilderCmdLinesTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

final class CommandBuilderCmdLinesTests: XCTestCase {

    private func song1() throws -> Project {
        let url = Bundle(for: type(of: self)).url(forResource: "SONG_1", withExtension: "json")
        return try Migration.project(fromShowJSON: Data(contentsOf: XCTUnwrap(url)))
    }

    private func goldenLines() throws -> [String] {
        let url = Bundle(for: type(of: self)).url(forResource: "SONG_1", withExtension: "cmdlines.txt")
        let text = try String(contentsOf: XCTUnwrap(url), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    func testMatchesGolden() throws {
        let project = try song1()
        let lines = CommandBuilder.buildCmdLines(songs: project.songs,
                                                 defaults: Defaults(),
                                                 storeMode: project.storeMode)
        XCTAssertEqual(lines, try goldenLines())
    }

    func testEmptyCueNameOmitsQuotes() {
        var cue = Cue(n: 2, name: "")
        cue.actions = []
        let song = Song(id: "s", name: "S", sequence: 7, cues: [cue])
        let lines = CommandBuilder.buildCmdLines(songs: [song], defaults: Defaults(), storeMode: .merge)
        XCTAssertTrue(lines.contains("Store Sequence 7 Cue 2 /Merge /NoConfirmation"))
        XCTAssertFalse(lines.contains(where: { $0.contains("Cue 2 \"") }))
    }

    func testPoolDefaultFadeFallbackAndEscaping() {
        var action = Action(group: "G\"X")
        action.presets[.color] = Preset(name: "C\"1")        // no own fade
        var cue = Cue(n: 1, name: "Q", actions: [action])
        cue.fade = ""; cue.delay = ""
        let song = Song(id: "s", name: "S", sequence: 1, cues: [cue])
        var defs = Defaults()
        defs.values[.color] = Preset(fade: "3")              // pool default fade
        let lines = CommandBuilder.buildCmdLines(songs: [song], defaults: defs, storeMode: .overwrite)
        XCTAssertTrue(lines.contains("Group \"G\\\"X\""))
        XCTAssertTrue(lines.contains("At Preset 4.\"C\\\"1\""))
        XCTAssertTrue(lines.contains("Fade 3 FeatureGroup 4"))
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`CommandBuilder`/`JSNumber` undefined).

- [ ] **Step 3: Write `JSNumber.swift`**

```swift
import Foundation

/// Renders a Double the way JavaScript `String(number)` does for the values this
/// app emits: integers without a decimal point (1.0 -> "1"), fractions as-is
/// (0.1 -> "0.1"). Used for cue numbers.
public enum JSNumber {
    public static func string(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e15 {
            return String(Int(d))
        }
        // Trim a trailing ".0"-style artifact; Swift's default matches JS for these ranges.
        return String(d)
    }
}
```

- [ ] **Step 4: Write `CommandBuilder.swift` (buildCmdLines only for now)**

```swift
import Foundation

/// PORT of web/js/compile.js. The single source of truth for the MA3 command
/// sequence on iOS. Any change here MUST also update web/js/compile.js and
/// shared/ma3-command-spec.md in the same PR; the golden fixtures catch drift.
public enum CommandBuilder {

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ s: String) -> Bool { !trimmed(s).isEmpty }

    /// Mirror of buildCmdLines() in compile.js — the raw command strings for OSC.
    public static func buildCmdLines(songs: [Song], defaults: Defaults, storeMode: StoreMode) -> [String] {
        let flag = storeMode.flag
        var out: [String] = []
        for song in songs {
            let seq = song.sequence
            for cue in song.cues {
                out.append("ClearAll")
                let actions = cue.actions.filter { nonEmpty($0.group) }
                for a in actions {
                    out.append("Group \"\(esc(trimmed(a.group)))\"")
                    for pool in Pool.allCases {
                        guard let p = a.presets[pool], nonEmpty(p.name) else { continue }
                        out.append("At Preset \(pool.number).\"\(esc(trimmed(p.name)))\"")
                        let fade = nonEmpty(p.fade) ? p.fade : defaults.fade(pool)
                        let delay = nonEmpty(p.delay) ? p.delay : defaults.delay(pool)
                        if nonEmpty(fade)  { out.append("Fade \(trimmedValue(fade)) FeatureGroup \(pool.number)") }
                        if nonEmpty(delay) { out.append("Delay \(trimmedValue(delay)) FeatureGroup \(pool.number)") }
                    }
                }
                let cueName = esc(trimmed(cue.name))
                let cueN = JSNumber.string(cue.n)
                if !cueName.isEmpty {
                    out.append("Store Sequence \(seq) Cue \(cueN) \"\(cueName)\" \(flag) /NoConfirmation")
                } else {
                    out.append("Store Sequence \(seq) Cue \(cueN) \(flag) /NoConfirmation")
                }
                if nonEmpty(cue.fade)  { out.append("Set Sequence \(seq) Cue \(cueN) Fade \(trimmedValue(cue.fade))") }
                if nonEmpty(cue.delay) { out.append("Set Sequence \(seq) Cue \(cueN) Delay \(trimmedValue(cue.delay))") }
            }
        }
        out.append("ClearAll")
        return out
    }

    // The JS interpolates fade/delay values verbatim after the empty-check; it does
    // NOT trim them in the output. compile.js uses the raw value (e.g. p.fade). To
    // match exactly, emit the raw value (not the trimmed one).
    private static func trimmedValue(_ s: String) -> String { s }
}
```

NOTE on `trimmedValue`: in `compile.js`, fade/delay are emitted as the raw stored
value (`Fade ${fade}`), not trimmed. The helper name is kept for readability but it
returns the value unchanged — matching the JS. The golden test for `SONG_1` (fade
`"5"`/`"6"`, no surrounding spaces) plus `testPoolDefaultFadeFallbackAndEscaping`
(`"3"`) cover this.

- [ ] **Step 5: Run the test, verify it passes.** Expected: `CommandBuilderCmdLinesTests` PASS (golden + 2 unit cases).

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/Kit/Compile/JSNumber.swift ios/Sources/Kit/Compile/CommandBuilder.swift ios/Tests/KitTests/CommandBuilderCmdLinesTests.swift
git commit -m "feat(ios): CommandBuilder.buildCmdLines — OSC sequence parity vs golden"
```

---

## Task 7: CommandBuilder.buildLua — the .lua plugin export

Ports `songToLuaEntry` + `buildLua`. Whitespace and ordering are exact. The header
`-- Generated:` line is the only non-deterministic part (timestamp), so `buildLua`
takes an injected `Date` and the test normalizes that line against `examples/SONG_1.lua`.

**Files:**
- Modify: `ios/Sources/Kit/Compile/CommandBuilder.swift` (add `buildLua` + `songToLuaEntry`)
- Test: `ios/Tests/KitTests/CommandBuilderLuaTests.swift`

- [ ] **Step 1: Write the failing test `CommandBuilderLuaTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

final class CommandBuilderLuaTests: XCTestCase {

    private func song1() throws -> Project {
        let url = Bundle(for: type(of: self)).url(forResource: "SONG_1", withExtension: "json")
        return try Migration.project(fromShowJSON: Data(contentsOf: XCTUnwrap(url)))
    }

    private func normalizeGeneratedLine(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            line.hasPrefix("-- Generated:") ? "-- Generated: <NORMALIZED>" : String(line)
        }.joined(separator: "\n")
    }

    func testMatchesGoldenLua() throws {
        let project = try song1()
        let url = Bundle(for: type(of: self)).url(forResource: "SONG_1", withExtension: "lua")
        let golden = try String(contentsOf: XCTUnwrap(url), encoding: .utf8)
        let built = CommandBuilder.buildLua(songs: project.songs,
                                            headerTitle: "Song: SONG 1",
                                            defaults: Defaults(),
                                            storeMode: project.storeMode,
                                            date: Date(timeIntervalSince1970: 0))
        // The committed file may or may not end with a trailing newline; compare trimmed-tail.
        XCTAssertEqual(normalizeGeneratedLine(built).trimmingCharacters(in: .newlines),
                       normalizeGeneratedLine(golden).trimmingCharacters(in: .newlines))
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`buildLua` undefined).

- [ ] **Step 3: Add `songToLuaEntry` + `buildLua` to `CommandBuilder.swift`**

Append inside the `CommandBuilder` enum (before the closing brace):

```swift
    /// Mirror of compile.js songToLuaEntry(): the lines for one song's SONGS table entry.
    static func songToLuaEntry(_ song: Song) -> [String] {
        var lines: [String] = []
        let seq = song.sequence
        let songName = esc(trimmed(song.name.isEmpty ? "(untitled)" : song.name))
        lines.append("  {name=\"\(songName)\", seq=\(seq), cues={")
        for cue in song.cues {
            let actionStrings: [String] = cue.actions
                .filter { nonEmpty($0.group) }
                .map { a in
                    let presetParts: [String] = Pool.allCases.compactMap { pool in
                        guard let v = a.presets[pool], nonEmpty(v.name) else { return nil }
                        let fade = nonEmpty(v.fade) ? v.fade : defaultsFade(pool)
                        let delay = nonEmpty(v.delay) ? v.delay : defaultsDelay(pool)
                        var parts = ["name=\"\(esc(trimmed(v.name)))\""]
                        if nonEmpty(fade)  { parts.append("fade=\(fade)") }
                        if nonEmpty(delay) { parts.append("delay=\(delay)") }
                        return "\(pool.rawValue)={\(parts.joined(separator: ", "))}"
                    }
                    return "      {group=\"\(esc(trimmed(a.group)))\", presets={\(presetParts.joined(separator: ", "))}},"
                }

            var header = "    {n=\(JSNumber.string(cue.n)), name=\"\(esc(trimmed(cue.name)))\""
            if nonEmpty(cue.fade)  { header += ", fade=\(cue.fade)" }
            if nonEmpty(cue.delay) { header += ", delay=\(cue.delay)" }
            if actionStrings.isEmpty {
                lines.append(header + ", actions={}},")
            } else {
                lines.append(header + ", actions={")
                lines.append(contentsOf: actionStrings)
                lines.append("    }},")
            }
        }
        lines.append("  }},")
        return lines
    }

    // buildLua resolves preset fade/delay against `defaults`, captured via these
    // closures set at the start of buildLua (kept simple: a task-local copy).
    private static var _defaults = Defaults()
    private static func defaultsFade(_ pool: Pool) -> String { _defaults.fade(pool) }
    private static func defaultsDelay(_ pool: Pool) -> String { _defaults.delay(pool) }

    public static func buildLua(songs: [Song], headerTitle: String,
                                defaults: Defaults, storeMode: StoreMode, date: Date) -> String {
        _defaults = defaults
        let mode = storeMode.rawValue
        var lines: [String] = []
        lines.append("-- Generated by Cuelist Compiler")
        lines.append("-- \(headerTitle)")
        lines.append("-- Generated: \(iso8601(date))")
        lines.append("-- Store mode: \(mode)")
        lines.append("-- WARNING: this plugin runs ClearAll before each cue. Run with an empty programmer.")
        lines.append("")
        lines.append("local POOL = {dimmer=1, position=2, gobo=3, color=4, beam=5, focus=6}")
        lines.append("local STORE_FLAG = \"/\(mode)\"")
        lines.append("")
        lines.append("local SONGS = {")
        for song in songs { lines.append(contentsOf: songToLuaEntry(song)) }
        lines.append("}")
        lines.append("")
        lines.append("local function main()")
        lines.append("  for _, song in ipairs(SONGS) do")
        lines.append("    Printf(\"Cuelist Compiler: storing \\\"\"..song.name..\"\\\" in Sequence \"..song.seq)")
        lines.append("    for _, c in ipairs(song.cues) do")
        lines.append("      Cmd(\"ClearAll\")")
        lines.append("      for _, a in ipairs(c.actions) do")
        lines.append("        Cmd('Group \"'..a.group..'\"')")
        lines.append("        for pool, p in pairs(a.presets) do")
        lines.append("          Cmd('At Preset '..POOL[pool]..'.\"'..p.name..'\"')")
        lines.append("          if p.fade  then Cmd('Fade '..p.fade..' FeatureGroup '..POOL[pool])   end")
        lines.append("          if p.delay then Cmd('Delay '..p.delay..' FeatureGroup '..POOL[pool]) end")
        lines.append("        end")
        lines.append("      end")
        lines.append("      if c.name ~= \"\" then")
        lines.append("        Cmd('Store Sequence '..song.seq..' Cue '..c.n..' \"'..c.name..'\" '..STORE_FLAG..' /NoConfirmation')")
        lines.append("      else")
        lines.append("        Cmd('Store Sequence '..song.seq..' Cue '..c.n..' '..STORE_FLAG..' /NoConfirmation')")
        lines.append("      end")
        lines.append("      if c.fade  then Cmd('Set Sequence '..song.seq..' Cue '..c.n..' Fade '..c.fade)   end")
        lines.append("      if c.delay then Cmd('Set Sequence '..song.seq..' Cue '..c.n..' Delay '..c.delay) end")
        lines.append("    end")
        lines.append("  end")
        lines.append("  Cmd(\"ClearAll\")")
        lines.append("  Printf(\"Cuelist Compiler: done.\")")
        lines.append("end")
        lines.append("")
        lines.append("return main")
        return lines.joined(separator: "\n")
    }

    private static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
```

NOTE: `buildCmdLines` does NOT use `_defaults`; it takes `defaults` as a parameter
and is unaffected. `_defaults` is set only inside `buildLua` immediately before use,
and `buildLua`/`buildCmdLines` are pure synchronous calls, so there is no shared-state
hazard in the single-threaded export path. (If concurrency is added later, thread
`defaults` through `songToLuaEntry` as a parameter instead.)

- [ ] **Step 4: Run the test, verify it passes.** Expected: `CommandBuilderLuaTests.testMatchesGoldenLua` PASS.

If it fails on whitespace, diff the built output against `examples/SONG_1.lua` line by line and fix the offending literal.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Compile/CommandBuilder.swift ios/Tests/KitTests/CommandBuilderLuaTests.swift
git commit -m "feat(ios): CommandBuilder.buildLua — .lua export parity vs golden"
```

---

## Task 8: OSC message encoding

Ports the OSC encoder from `proxy/ws2osc.js` (`oscString`, `buildOscMessage`) — the
exact wire format MA3 expects: null-terminated, 4-byte-padded strings, `,s` typetag,
one string argument.

**Files:**
- Create: `ios/Sources/Kit/Transport/OSCEncoding.swift`
- Test: `ios/Tests/KitTests/OSCEncodingTests.swift`

- [ ] **Step 1: Write the failing test `OSCEncodingTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

final class OSCEncodingTests: XCTestCase {
    func testOscStringPaddingNoNullBoundary() {
        // "abc" -> 3 bytes + null = 4 (already a multiple of 4)
        XCTAssertEqual(Array(OSCEncoding.oscString("abc")), [97, 98, 99, 0])
    }

    func testOscStringPaddingOnBoundary() {
        // "abcd" -> 4 bytes + null = 5 -> pad to 8 (3 trailing nulls)
        XCTAssertEqual(Array(OSCEncoding.oscString("abcd")), [97, 98, 99, 100, 0, 0, 0, 0])
    }

    func testMessageLayoutForClearAll() {
        let msg = OSCEncoding.message(address: "/gma3/cmd", string: "ClearAll")
        // address "/gma3/cmd" (9) + null -> 10 -> pad 12
        // typetag ",s" (2) + null -> 3 -> pad 4
        // arg "ClearAll" (8) + null -> 9 -> pad 12
        XCTAssertEqual(msg.count, 12 + 4 + 12)
        XCTAssertEqual(msg.count % 4, 0)
        let prefix = Array(msg.prefix(12))
        XCTAssertEqual(prefix, Array("/gma3/cmd".utf8) + [0, 0, 0])
        // typetag block
        let typetag = Array(msg[12..<16])
        XCTAssertEqual(typetag, Array(",s".utf8) + [0, 0])
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`OSCEncoding` undefined).

- [ ] **Step 3: Write `OSCEncoding.swift`**

```swift
import Foundation

/// OSC 1.0 wire encoding for a single string argument. Port of proxy/ws2osc.js.
public enum OSCEncoding {

    /// Null-terminated, padded to a 4-byte boundary.
    public static func oscString(_ s: String) -> Data {
        var bytes = Array(s.utf8)
        bytes.append(0)                                  // null terminator
        let pad = (4 - (bytes.count % 4)) % 4
        bytes.append(contentsOf: repeatElement(0, count: pad))
        return Data(bytes)
    }

    /// An OSC message: address + ",s" typetag + one string arg.
    public static func message(address: String, string arg: String) -> Data {
        var data = Data()
        data.append(oscString(address))
        data.append(oscString(",s"))
        data.append(oscString(arg))
        return data
    }
}
```

- [ ] **Step 4: Run the test, verify it passes.** Expected: `OSCEncodingTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Transport/OSCEncoding.swift ios/Tests/KitTests/OSCEncodingTests.swift
git commit -m "feat(ios): OSC message encoding (port of ws2osc.js)"
```

---

## Task 9: OSCTransport protocol + DirectUDPTransport

A pluggable transport. `DirectUDPTransport` sends OSC over UDP via Network.framework,
throttled at 20 ms between lines (mirrors web `OSC_SEND_INTERVAL_MS`). Tested against
a local UDP listener (loopback), so no MA3 is needed for the test.

**Files:**
- Create: `ios/Sources/Kit/Transport/OSCTransport.swift`
- Create: `ios/Sources/Kit/Transport/DirectUDPTransport.swift`
- Test: `ios/Tests/KitTests/DirectUDPTransportTests.swift`

- [ ] **Step 1: Write the failing test `DirectUDPTransportTests.swift`**

```swift
import XCTest
import Network
@testable import CuelistCompilerKit

final class DirectUDPTransportTests: XCTestCase {

    /// Spins up a UDP listener on an ephemeral port, sends two OSC lines through the
    /// transport, and asserts both datagrams arrive and decode to the expected strings.
    func testSendsDatagramsToLoopback() async throws {
        let received = Received()
        let listener = try NWListener(using: .udp, on: .any)
        listener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            func receive() {
                conn.receiveMessage { data, _, _, _ in
                    if let data { received.add(data) }
                    receive()
                }
            }
            receive()
        }
        listener.start(queue: .global())
        // Wait for the OS to assign a port.
        let port = try await waitForPort(listener)

        let transport = DirectUDPTransport(host: "127.0.0.1", port: port, prefix: "gma3")
        var progressSeen: [Int] = []
        try await transport.send(["ClearAll", "Group \"X\""]) { sent, total in
            progressSeen.append(sent)
            XCTAssertEqual(total, 2)
        }

        // Give datagrams a beat to land.
        try await Task.sleep(nanoseconds: 200_000_000)
        listener.cancel()

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(progressSeen, [1, 2])
        // First datagram should start with the OSC address.
        let first = received.first
        XCTAssertEqual(Array(first.prefix(12)), Array("/gma3/cmd".utf8) + [0, 0, 0])
    }

    private func waitForPort(_ listener: NWListener) async throws -> UInt16 {
        for _ in 0..<100 {
            if let p = listener.port?.rawValue, p != 0 { return p }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw XCTSkip("listener never bound a port")
    }

    /// Thread-safe collector.
    final class Received: @unchecked Sendable {
        private let lock = NSLock()
        private var data: [Data] = []
        func add(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return data.count }
        var first: Data { lock.lock(); defer { lock.unlock() }; return data.first ?? Data() }
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`DirectUDPTransport`/`OSCTransport` undefined).

- [ ] **Step 3: Write `OSCTransport.swift`**

```swift
import Foundation

public enum TransportState: Equatable, Sendable {
    case offline, connecting, online, sending
}

/// Abstraction over "how lines reach grandMA3". DirectUDPTransport ships first;
/// a future RelayTransport (WebSocket -> Pi proxy) conforms to the same protocol.
public protocol OSCTransport: Sendable {
    /// Sends each line as an OSC message, in order, with throttling.
    /// `progress(sent, total)` is called after each line.
    func send(_ lines: [String], progress: @escaping @Sendable (Int, Int) -> Void) async throws
}

public extension OSCTransport {
    func send(_ lines: [String]) async throws {
        try await send(lines, progress: { _, _ in })
    }
}

public enum TransportError: Error, Equatable {
    case notReady
    case sendFailed(String)
    case invalidHost
}
```

- [ ] **Step 4: Write `DirectUDPTransport.swift`**

```swift
import Foundation
import Network

/// Sends OSC over UDP straight to grandMA3 on the LAN. No proxy required.
public final class DirectUDPTransport: OSCTransport, @unchecked Sendable {
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let address: String
    private let intervalNanos: UInt64

    public init(host: String, port: UInt16, prefix: String = "gma3",
                intervalMs: UInt64 = 20) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port) ?? 8000
        self.address = "/\(prefix)/cmd"
        self.intervalNanos = intervalMs * 1_000_000
    }

    public func send(_ lines: [String],
                     progress: @escaping @Sendable (Int, Int) -> Void) async throws {
        let conn = NWConnection(host: host, port: port, using: .udp)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed(let err): cont.resume(throwing: TransportError.sendFailed("\(err)"))
                case .cancelled: cont.resume(throwing: TransportError.notReady)
                default: break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
        defer { conn.cancel() }

        let total = lines.count
        for (i, line) in lines.enumerated() {
            let packet = OSCEncoding.message(address: address, string: line)
            try await sendDatagram(conn, packet)
            progress(i + 1, total)
            if i < total - 1 { try await Task.sleep(nanoseconds: intervalNanos) }
        }
    }

    private func sendDatagram(_ conn: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: TransportError.sendFailed("\(err)")) }
                else { cont.resume() }
            })
        }
    }
}
```

- [ ] **Step 5: Run the test, verify it passes.** Expected: `DirectUDPTransportTests.testSendsDatagramsToLoopback` PASS. (If it flakes on timing in CI, the 200 ms settle window can be raised; on a Mac it is reliable.)

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/Kit/Transport/OSCTransport.swift ios/Sources/Kit/Transport/DirectUDPTransport.swift ios/Tests/KitTests/DirectUDPTransportTests.swift
git commit -m "feat(ios): OSCTransport protocol + DirectUDPTransport (UDP, loopback-tested)"
```

---

## Task 10: ProjectStore — local JSON persistence

Holds the in-memory `Project` + `Defaults`, persists them as JSON in the app's
Documents directory (mirrors web `localStorage`), and is the single mutation surface
the UI (Plan 2) will bind to. `@Observable` for SwiftUI. Persistence is tested via a
custom directory injected into the initializer.

**Files:**
- Create: `ios/Sources/Kit/Store/ProjectStore.swift`
- Test: `ios/Tests/KitTests/ProjectStoreTests.swift`

- [ ] **Step 1: Write the failing test `ProjectStoreTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

final class ProjectStoreTests: XCTestCase {

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-store-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testStartsWithEmptyProjectWhenNoFiles() {
        let store = ProjectStore(directory: tempDir())
        XCTAssertEqual(store.project.songs.count, 1)
        XCTAssertEqual(store.project.songs[0].cues.count, 0)
        XCTAssertEqual(store.project.storeMode, .overwrite)
    }

    func testSaveThenReloadRoundTrips() throws {
        let dir = tempDir()
        let store = ProjectStore(directory: dir)
        store.project.songs[0].name = "My Show"
        store.project.songs[0].sequence = 42
        store.defaults.values[.color] = Preset(fade: "3")
        store.saveNow()

        let reloaded = ProjectStore(directory: dir)
        XCTAssertEqual(reloaded.project.songs[0].name, "My Show")
        XCTAssertEqual(reloaded.project.songs[0].sequence, 42)
        XCTAssertEqual(reloaded.defaults.fade(.color), "3")
    }

    func testProjectFileIsShowJsonCompatible() throws {
        let dir = tempDir()
        let store = ProjectStore(directory: dir)
        store.project.songs[0].name = "Interop"
        store.saveNow()
        let data = try Data(contentsOf: dir.appendingPathComponent("project.json"))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(obj["songs"])
        XCTAssertNotNil(obj["activeSongId"])
        XCTAssertEqual(obj["storeMode"] as? String, "Overwrite")
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`ProjectStore` undefined).

- [ ] **Step 3: Write `ProjectStore.swift`**

```swift
import Foundation
import Observation

/// Owns the in-memory show + defaults and persists them as JSON. The UI binds to this.
@Observable
public final class ProjectStore {
    public var project: Project { didSet { scheduleSave() } }
    public var defaults: Defaults { didSet { scheduleSave() } }

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let projectURL: URL
    @ObservationIgnored private let defaultsURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = dir
        self.projectURL = dir.appendingPathComponent("project.json")
        self.defaultsURL = dir.appendingPathComponent("defaults.json")

        let enc = JSONDecoder()
        if let data = try? Data(contentsOf: projectURL),
           let p = try? enc.decode(Project.self, from: data) {
            self.project = p
        } else {
            self.project = Project.empty()
        }
        if let data = try? Data(contentsOf: defaultsURL),
           let d = try? enc.decode(Defaults.self, from: data) {
            self.defaults = d
        } else {
            self.defaults = Defaults()
        }
    }

    /// Debounced background save (mirrors web saveState on each mutation).
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            self?.saveNow()
        }
    }

    /// Synchronous write — used by tests and on background/terminate.
    public func saveNow() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let p = try? enc.encode(project) { try? p.write(to: projectURL) }
        if let d = try? enc.encode(defaults) { try? d.write(to: defaultsURL) }
    }
}
```

- [ ] **Step 4: Run the test, verify it passes.** Expected: `ProjectStoreTests` PASS.

- [ ] **Step 5: Run the FULL suite to confirm nothing regressed**

Run the standard test command. Expected: all tests across all files PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/Kit/Store/ProjectStore.swift ios/Tests/KitTests/ProjectStoreTests.swift
git commit -m "feat(ios): ProjectStore — observable local JSON persistence (show.json compatible)"
```

---

## Done criteria for Plan 1

- `xcodebuild test -scheme CuelistCompilerKit` is green across all suites.
- `examples/SONG_1.cmdlines.txt` exists and is byte-identical to the JS reference output.
- `CommandBuilder.buildCmdLines` and `buildLua` match their golden fixtures.
- The engine is usable headlessly: construct a `Project`, call `CommandBuilder`,
  and `DirectUDPTransport.send(...)` reaches a UDP listener.
- App target builds and launches the placeholder shell.

**Platform note for Plan 2:** sending UDP to MA3 on a *physical device* triggers
iOS Local Network permission. Plan 2's app target must add
`INFOPLIST_KEY_NSLocalNetworkUsageDescription` (e.g. "Cuelist Compiler sends OSC
commands to your grandMA3 console on the local network.") to `project.yml`. The
Kit tests use loopback in the simulator and are unaffected.

**Next:** Plan 2 — Authoring UI (SwiftUI screens binding to `ProjectStore`, send via
`DirectUDPTransport`, `.lua` export via share sheet, connection settings).
