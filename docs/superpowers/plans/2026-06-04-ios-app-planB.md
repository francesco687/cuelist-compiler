# Cuelist Compiler iOS — Plan B: Native app (M1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the native SwiftUI iPhone app that authors per-song grandMA3 cuelists locally and sends them to the (already-shipped, hardware-verified) Pi hub over WebSocket — no on-phone compiling or OSC.

**Architecture:** A `CuelistCompilerKit` framework holds the data models, migration, an `@Observable ProjectStore` (local JSON persistence), and an `@Observable HubClient` (WebSocket, behind a `HubConnection` protocol). A thin `CuelistCompiler` app target holds the SwiftUI authoring UI (one-scroll-per-song, all-6-pools editor, persistent hub pill + inline send). Tests target the Kit with no host app; the hub remains the single compiler so there are no command-parity tests on iOS.

**Tech Stack:** Swift 5.9 / iOS 17, SwiftUI, `@Observable` (Observation), `URLSessionWebSocketTask`, Network.framework (test-only ws server), XCTest, xcodegen, Node (already used by the hub).

**Design doc:** `docs/superpowers/specs/2026-06-04-ios-app-planB-design.md`
**Parent design:** `docs/superpowers/specs/2026-06-04-ios-frontend-design.md`
**Carries from (superseded):** `docs/superpowers/plans/2026-06-04-ios-frontend-m1-engine.md` — scaffold (Task 1), Pool/StoreMode (Task 2), Codable models (Task 3), Migration (Task 4), ProjectStore persistence (Task 10). **Drops** its Tasks 5–9 (golden fixture, Swift CommandBuilder, JSNumber, OSC encoding, DirectUDPTransport): the hub owns compiling + OSC.

**Standard test command (run from repo root):**
```bash
cd ios && xcodegen generate >/dev/null && \
xcodebuild test -project CuelistCompiler.xcodeproj -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Always run `xcodegen generate` before `xcodebuild` (regenerates the project from `project.yml`).

## File structure

```
ios/
  project.yml
  .gitignore
  Sources/
    Kit/
      Kit.swift
      Models/   Pool.swift StoreMode.swift Preset.swift Action.swift Cue.swift
                Song.swift Project.swift Defaults.swift Migration.swift
      Store/    ProjectStore.swift ProjectStore+Mutations.swift CueSummary.swift PoolDisplay.swift
      Hub/      HubMessages.swift HubConnection.swift HubClient.swift
                URLSessionWebSocketConnection.swift
    App/
      App.swift  RootView.swift  SongBarView.swift  CueListView.swift  CueCardView.swift
      ActionBlockView.swift  PoolRowView.swift  SendBarView.swift
      SettingsView.swift  DefaultsView.swift  ColorPickerPopover.swift
  Tests/
    KitTests/  SmokeTests.swift PoolTests.swift ModelCodecTests.swift MigrationTests.swift
               ProjectStoreTests.swift ProjectStoreMutationTests.swift CueSummaryTests.swift
               HubMessagesTests.swift HubClientTests.swift URLSessionWebSocketConnectionTests.swift
```

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
    info:
      path: Sources/App/Info.plist
      properties:
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        NSLocalNetworkUsageDescription: "Cuelist Compiler connects to your hub on the local network to send shows to your console."
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.blearred.cuelistcompiler
  CuelistCompilerKitTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests/KitTests
      - path: ../examples/SONG_1.json
        buildPhase: resources
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

Note: `Sources/App/Info.plist` is **generated by xcodegen** from `info.properties` above — do not hand-create it. `NSAllowsLocalNetworking` lets the app open `ws://` to LAN/tailnet IPs; `NSLocalNetworkUsageDescription` satisfies the iOS Local Network prompt on a physical device.

- [ ] **Step 2: Write `ios/Sources/Kit/Kit.swift`**

```swift
import Foundation

/// Marker for the CuelistCompilerKit module. Real types live in Models/Store/Hub.
public enum CuelistCompilerKit {
    public static let schemaVersion = 1
}
```

- [ ] **Step 3: Write `ios/Sources/App/App.swift`** (minimal runnable shell; real UI in later tasks)

```swift
import SwiftUI
import CuelistCompilerKit

@main
struct CuelistCompilerApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Text("Cuelist Compiler").font(.title.bold())
                Text("Engine v\(CuelistCompilerKit.schemaVersion) — UI lands in later tasks")
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

Run the standard test command. Expected: build succeeds, `SmokeTests.testModuleLoads` PASSES.

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

- [ ] **Step 2: Run the test, verify it fails** (`Pool`/`StoreMode` undefined).

- [ ] **Step 3: Write `Pool.swift`**

```swift
import Foundation

/// The six grandMA3 preset pools. `allCases` order is the canonical iteration
/// order (mirrors web `POOLS`). `number` mirrors web `POOL_NUM` (the MA3 pool
/// index, which is NOT the iteration order).
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
public enum StoreMode: String, Codable, Sendable, CaseIterable {
    case overwrite = "Overwrite"
    case merge = "Merge"

    public var flag: String { "/" + rawValue }
}
```

- [ ] **Step 5: Run the test, verify it passes.** Expected: `PoolTests` all PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/Kit/Models/Pool.swift ios/Sources/Kit/Models/StoreMode.swift ios/Tests/KitTests/PoolTests.swift
git commit -m "feat(ios): Pool + StoreMode value types"
```

---

## Task 3: Codable models matching the show.json schema

`Action.presets` must encode as a JSON **object** keyed by pool name (not an array). `Action` also carries `color` (UI-only) and `Cue` carries `position` (UI-only). NOTE: `Cue.position` (a free-text label) is unrelated to the `Pool.position` preset pool — do not conflate them.

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
        XCTAssertEqual(obj["color"] as? String, "")   // action color defaults to ""
    }

    func testActionColorRoundTrips() throws {
        var action = Action(group: "G")
        action.color = "#d63a3a"
        let data = try JSONEncoder().encode(action)
        let again = try JSONDecoder().decode(Action.self, from: data)
        XCTAssertEqual(again.color, "#d63a3a")
    }

    func testNewFormatProjectRoundTrips() throws {
        let json = """
        {"songs":[{"id":"s1","name":"S","sequence":3,"audioFileName":"",
        "cues":[{"n":1,"name":"C","fade":"5","delay":"","position":"VERSE","collapsed":false,
        "actions":[{"group":"G","color":"","presets":{
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
        XCTAssertEqual(project.songs[0].cues[0].position, "VERSE")
        XCTAssertEqual(project.songs[0].cues[0].actions[0].presets[.color]?.name, "RED")
        XCTAssertEqual(project.storeMode, .overwrite)
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

/// One preset slot for a pool. fade/delay are Strings (the hub's compiler trims and
/// checks emptiness, so string fidelity matters).
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

- [ ] **Step 4: Write `Action.swift`** (custom Codable so `presets` is a 6-key object; `color` is a plain key)

```swift
import Foundation

public struct Action: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()              // identity for SwiftUI lists; NOT persisted (omitted from CodingKeys)
    public var group: String
    public var color: String            // UI-only tag (hex or ""), not used by the compiler
    /// Always carries all six pools (empty Preset when unset), matching web `newAction()`.
    public var presets: [Pool: Preset]

    public init(group: String = "", color: String = "", presets: [Pool: Preset]? = nil) {
        self.group = group
        self.color = color
        if let presets {
            self.presets = presets
        } else {
            var p: [Pool: Preset] = [:]
            for pool in Pool.allCases { p[pool] = Preset() }
            self.presets = p
        }
    }

    private enum CodingKeys: String, CodingKey { case group, color, presets }

    private struct PoolKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ pool: Pool) { self.stringValue = pool.rawValue }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
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
        try c.encode(color, forKey: .color)
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

public struct Cue: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()              // identity for SwiftUI lists; not persisted
    public var n: Double
    public var name: String
    public var fade: String
    public var delay: String
    public var position: String         // UI-only label (NOT the Pool.position pool)
    public var collapsed: Bool
    public var actions: [Action]

    public init(n: Double = 1, name: String = "", fade: String = "", delay: String = "",
                position: String = "", collapsed: Bool = false, actions: [Action] = [Action()]) {
        self.n = n; self.name = name; self.fade = fade; self.delay = delay
        self.position = position; self.collapsed = collapsed; self.actions = actions
    }

    private enum CodingKeys: String, CodingKey {
        case n, name, fade, delay, position, collapsed, actions
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

    private enum CodingKeys: String, CodingKey { case id, name, sequence, cues, audioFileName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? IDGen.next()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
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

- [ ] **Step 7: Write `Project.swift`** (includes `IDGen`)

```swift
import Foundation

/// Mirrors web `genId()` shape. Ids never appear in command output, so the exact
/// format is not contractual — only stable + unique.
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

    private enum CodingKeys: String, CodingKey { case songs, activeSongId, storeMode }

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

- [ ] **Step 8: Write `Defaults.swift`**

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
        init?(intValue: Int) { return nil }
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
git commit -m "feat(ios): Codable models (show.json schema) incl. action color + cue position"
```

---

## Task 4: Migration (old single-song format → current shape)

Mirrors web `migrateState`/`migrateCues`/`migrateActions`. The anchor `examples/SONG_1.json` is OLD format (`songName`/`sequence`/`cues` at top level; presets as bare strings). Migration upgrades any saved show before use.

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
        XCTAssertEqual(action.presets[.gobo]?.name, "")
        XCTAssertEqual(action.presets[.focus]?.name, "MEDIUM")
        XCTAssertEqual(action.presets[.color]?.fade, "")
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
        guard var dict = raw as? [String: Any] else { throw MigrationError.notAnObject }

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
            if (a["color"] as? String) == nil { a["color"] = "" }
            return a
        }
    }

    /// fade/delay may arrive as number or string; store as string (matches JS String()).
    private static func stringify(_ v: Any?) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return numberString(n)
        default: return ""
        }
    }

    private static func numberString(_ n: NSNumber) -> String {
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

## Task 5: ProjectStore — local JSON persistence

Holds the in-memory `Project` + `Defaults`, persists them as JSON in a directory (Documents in the app; a temp dir in tests). `@Observable` for SwiftUI. On launch, a file of an older shape is upgraded via `Migration`.

**Files:**
- Create: `ios/Sources/Kit/Store/ProjectStore.swift`
- Test: `ios/Tests/KitTests/ProjectStoreTests.swift`

- [ ] **Step 1: Write the failing test `ProjectStoreTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

@MainActor      // ProjectStore is @MainActor-isolated; the test class must match
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

    func testLoadUpgradesOldFormatFile() throws {
        let dir = tempDir()
        // Write an OLD-format file (no `songs`, bare-string presets) directly.
        let old = """
        {"songName":"Legacy","sequence":12,"cues":[
          {"n":1,"name":"A","fade":"2","actions":[{"group":"G","presets":{"color":"BLUE"}}]}]}
        """.data(using: .utf8)!
        try old.write(to: dir.appendingPathComponent("project.json"))

        let store = ProjectStore(directory: dir)
        XCTAssertEqual(store.project.songs.count, 1)
        XCTAssertEqual(store.project.songs[0].name, "Legacy")
        XCTAssertEqual(store.project.songs[0].cues[0].actions[0].presets[.color]?.name, "BLUE")
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`ProjectStore` undefined).

- [ ] **Step 3: Write `ProjectStore.swift`**

```swift
import Foundation
import Observation

/// Owns the in-memory show + defaults and persists them as JSON. The UI binds to this.
@MainActor
@Observable
public final class ProjectStore {
    public var project: Project { didSet { scheduleSave() } }
    public var defaults: Defaults { didSet { scheduleSave() } }

    @ObservationIgnored let directory: URL
    @ObservationIgnored private let projectURL: URL
    @ObservationIgnored private let defaultsURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = dir
        self.projectURL = dir.appendingPathComponent("project.json")
        self.defaultsURL = dir.appendingPathComponent("defaults.json")

        let dec = JSONDecoder()
        if let data = try? Data(contentsOf: projectURL) {
            if let p = try? dec.decode(Project.self, from: data) {
                self.project = p
            } else if let migrated = try? Migration.project(fromShowJSON: data) {
                self.project = migrated   // upgrade an older saved shape
            } else {
                self.project = Project.empty()
            }
        } else {
            self.project = Project.empty()
        }
        if let data = try? Data(contentsOf: defaultsURL),
           let d = try? dec.decode(Defaults.self, from: data) {
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

- [ ] **Step 4: Run the test, verify it passes.** Expected: `ProjectStoreTests` PASS. (The test class is `@MainActor`, matching the `@MainActor` store.)

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Store/ProjectStore.swift ios/Tests/KitTests/ProjectStoreTests.swift
git commit -m "feat(ios): ProjectStore — observable local JSON persistence (+ legacy upgrade)"
```

---

## Task 6: ProjectStore mutations (the UI's single mutation surface)

Mirrors web `state.js` operations. Invariant: a cue never has zero action blocks (removing the last re-seeds an empty one, as web does).

**Files:**
- Create: `ios/Sources/Kit/Store/ProjectStore+Mutations.swift`
- Test: `ios/Tests/KitTests/ProjectStoreMutationTests.swift`

- [ ] **Step 1: Write the failing test `ProjectStoreMutationTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

@MainActor      // ProjectStore is @MainActor-isolated; the test class must match
final class ProjectStoreMutationTests: XCTestCase {
    private func store() -> ProjectStore {
        ProjectStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-mut-\(UUID().uuidString)"))
    }

    func testAddAndRemoveSongKeepsAtLeastOne() {
        let s = store()
        let firstId = s.project.songs[0].id
        s.addSong()
        XCTAssertEqual(s.project.songs.count, 2)
        XCTAssertEqual(s.project.activeSongId, s.project.songs[1].id)  // new song active
        s.removeSong(id: s.project.songs[1].id)
        XCTAssertEqual(s.project.songs.count, 1)
        s.removeSong(id: firstId)                                      // remove the last
        XCTAssertEqual(s.project.songs.count, 1)                       // re-seeded, never zero
        XCTAssertEqual(s.project.songs[0].cues.count, 0)
    }

    func testAddCueAppendsToActiveSong() {
        let s = store()
        s.addCue()
        XCTAssertEqual(s.activeSong.cues.count, 1)
        XCTAssertEqual(s.activeSong.cues[0].actions.count, 1)          // one empty block
    }

    func testRemoveLastActionBlockReseeds() {
        let s = store()
        s.addCue()
        let cueId = s.activeSong.cues[0].id
        s.removeActionBlock(cueId: cueId, at: 0)
        XCTAssertEqual(s.activeSong.cues[0].actions.count, 1)          // never zero
    }

    func testCopyActionsReplacesTarget() {
        let s = store()
        s.addCue(); s.addCue()
        let src = s.activeSong.cues[0].id
        let dst = s.activeSong.cues[1].id
        s.updateActiveCue(id: src) { cue in
            cue.actions = [Action(group: "WASH")]
        }
        s.copyActions(fromCueId: src, toCueId: dst)
        XCTAssertEqual(s.activeSong.cues[1].actions.first?.group, "WASH")
    }

    func testSortActiveCuesByNumber() {
        let s = store()
        s.addCue(); s.addCue()
        s.updateActiveCue(id: s.activeSong.cues[0].id) { $0.n = 5 }
        s.updateActiveCue(id: s.activeSong.cues[1].id) { $0.n = 1 }
        s.sortActiveCues()
        XCTAssertEqual(s.activeSong.cues.map(\.n), [1, 5])
    }
}
```

- [ ] **Step 2: Run, verify it fails** (mutation methods undefined).

- [ ] **Step 3: Write `ProjectStore+Mutations.swift`**

```swift
import Foundation

public extension ProjectStore {

    /// The active song, or the first one (never nil — Project always has ≥1 song).
    var activeSong: Song {
        project.activeSong ?? project.songs[0]
    }

    private func activeSongIndex() -> Int {
        project.songs.firstIndex(where: { $0.id == project.activeSongId })
            ?? 0
    }

    // MARK: Songs

    func addSong() {
        let s = Song(id: IDGen.next(), sequence: 1, cues: [])
        project.songs.append(s)
        project.activeSongId = s.id
    }

    func setActiveSong(_ id: String) {
        project.activeSongId = id
    }

    func removeSong(id: String) {
        guard let idx = project.songs.firstIndex(where: { $0.id == id }) else { return }
        project.songs.remove(at: idx)
        if project.songs.isEmpty {
            let ns = Song(id: IDGen.next(), sequence: 1, cues: [])
            project.songs = [ns]
            project.activeSongId = ns.id
        } else if project.activeSongId == id {
            project.activeSongId = project.songs[max(0, idx - 1)].id
        }
    }

    // MARK: Cues (operate on the active song)

    func addCue() {
        let i = activeSongIndex()
        let nextN = (project.songs[i].cues.map(\.n).max() ?? 0) + 1
        project.songs[i].cues.append(Cue(n: nextN))
    }

    func removeCue(id: UUID) {
        let i = activeSongIndex()
        project.songs[i].cues.removeAll { $0.id == id }
    }

    func sortActiveCues() {
        let i = activeSongIndex()
        project.songs[i].cues.sort { $0.n < $1.n }
    }

    /// Edit one cue of the active song in place.
    func updateActiveCue(id: UUID, _ edit: (inout Cue) -> Void) {
        let i = activeSongIndex()
        guard let c = project.songs[i].cues.firstIndex(where: { $0.id == id }) else { return }
        edit(&project.songs[i].cues[c])
    }

    // MARK: Action blocks

    func addActionBlock(cueId: UUID) {
        updateActiveCue(id: cueId) { $0.actions.append(Action()) }
    }

    func removeActionBlock(cueId: UUID, at index: Int) {
        updateActiveCue(id: cueId) { cue in
            guard cue.actions.indices.contains(index) else { return }
            cue.actions.remove(at: index)
            if cue.actions.isEmpty { cue.actions.append(Action()) }   // never zero
        }
    }

    /// Replace the target cue's action blocks with a deep copy of the source cue's.
    func copyActions(fromCueId src: UUID, toCueId dst: UUID) {
        let i = activeSongIndex()
        guard let s = project.songs[i].cues.firstIndex(where: { $0.id == src }) else { return }
        let cloned = project.songs[i].cues[s].actions
        updateActiveCue(id: dst) { $0.actions = cloned }
    }
}
```

- [ ] **Step 4: Run the test, verify it passes.** Expected: `ProjectStoreMutationTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Store/ProjectStore+Mutations.swift ios/Tests/KitTests/ProjectStoreMutationTests.swift
git commit -m "feat(ios): ProjectStore mutations (songs/cues/blocks/copy) with invariants"
```

---

## Task 7: Hub messages (wire protocol codecs)

Encodes the outgoing `compile-send` and decodes the hub's `progress`/`done`/`error` replies — the exact protocol verified on the desk 2026-06-04.

**Files:**
- Create: `ios/Sources/Kit/Hub/HubMessages.swift`
- Test: `ios/Tests/KitTests/HubMessagesTests.swift`

- [ ] **Step 1: Write the failing test `HubMessagesTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

final class HubMessagesTests: XCTestCase {
    func testEncodeCompileSendHasShowJsonShape() throws {
        let project = Project.empty()
        let msg = OutgoingMessage.compileSend(project: project, defaults: Defaults(), selection: .all)
        let data = try msg.jsonData()
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["type"] as? String, "compile-send")
        XCTAssertEqual(obj["selection"] as? String, "all")
        let proj = obj["project"] as! [String: Any]
        XCTAssertNotNil(proj["songs"])
        XCTAssertNotNil(proj["activeSongId"])
        XCTAssertEqual(proj["storeMode"] as? String, "Overwrite")
        XCTAssertNotNil(obj["defaults"])
    }

    func testDecodeProgress() throws {
        let m = try IncomingMessage.decode(#"{"type":"progress","sent":3,"total":17}"#)
        XCTAssertEqual(m, .progress(sent: 3, total: 17))
    }

    func testDecodeDone() throws {
        XCTAssertEqual(try IncomingMessage.decode(#"{"type":"done","total":17}"#), .done(total: 17))
    }

    func testDecodeError() throws {
        XCTAssertEqual(try IncomingMessage.decode(#"{"type":"error","message":"nope"}"#),
                       .error(message: "nope"))
    }

    func testDecodeUnknownTypeIsIgnored() throws {
        XCTAssertEqual(try IncomingMessage.decode(#"{"type":"pong"}"#), .other)
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`OutgoingMessage`/`IncomingMessage` undefined).

- [ ] **Step 3: Write `HubMessages.swift`**

```swift
import Foundation

/// Selection for a send: just the active song, or every song with cues.
public enum Selection: String, Sendable { case current, all }

/// What the phone sends to the hub.
public enum OutgoingMessage {
    case compileSend(project: Project, defaults: Defaults, selection: Selection)

    private struct CompileSend: Encodable {
        let type = "compile-send"
        let project: Project
        let defaults: Defaults
        let selection: String
    }

    public func jsonData() throws -> Data {
        switch self {
        case let .compileSend(project, defaults, selection):
            let enc = JSONEncoder()
            return try enc.encode(CompileSend(project: project, defaults: defaults,
                                              selection: selection.rawValue))
        }
    }

    public func jsonString() throws -> String {
        String(decoding: try jsonData(), as: UTF8.self)
    }
}

/// What the hub sends back.
public enum IncomingMessage: Equatable, Sendable {
    case progress(sent: Int, total: Int)
    case done(total: Int)
    case error(message: String)
    case other                                  // pong / sent / unknown — ignored by the client

    private struct Envelope: Decodable {
        let type: String
        let sent: Int?
        let total: Int?
        let message: String?
    }

    public static func decode(_ text: String) throws -> IncomingMessage {
        let e = try JSONDecoder().decode(Envelope.self, from: Data(text.utf8))
        switch e.type {
        case "progress": return .progress(sent: e.sent ?? 0, total: e.total ?? 0)
        case "done":     return .done(total: e.total ?? 0)
        case "error":    return .error(message: e.message ?? "unknown error")
        default:         return .other
        }
    }
}
```

- [ ] **Step 4: Run the test, verify it passes.** Expected: `HubMessagesTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Hub/HubMessages.swift ios/Tests/KitTests/HubMessagesTests.swift
git commit -m "feat(ios): hub wire-protocol codecs (compile-send / progress / done / error)"
```

---

## Task 8: HubConnection protocol + HubClient (tested against a mock)

`HubClient` is the `@Observable` the send bar binds to. It drives a `HubConnection` (a thin socket abstraction), tracks connection state, sends `compile-send`, and surfaces streamed progress/result. Tested with a `MockHubConnection` (no real socket).

**Files:**
- Create: `ios/Sources/Kit/Hub/HubConnection.swift`
- Create: `ios/Sources/Kit/Hub/HubClient.swift`
- Test: `ios/Tests/KitTests/HubClientTests.swift`

- [ ] **Step 1: Write the failing test `HubClientTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

@MainActor
final class HubClientTests: XCTestCase {

    /// A scriptable in-memory connection. The client calls connect/send/close;
    /// the test drives events back via `emit`. `@MainActor` to satisfy the
    /// `@MainActor` HubConnection protocol.
    @MainActor
    final class MockHubConnection: HubConnection {
        var onEvent: ((HubConnectionEvent) -> Void)?
        private(set) var connectCount = 0
        private(set) var sent: [String] = []
        func connect(onEvent: @escaping (HubConnectionEvent) -> Void) {
            self.onEvent = onEvent; connectCount += 1
        }
        func send(_ text: String) { sent.append(text) }
        func close() {}
        func emit(_ e: HubConnectionEvent) { onEvent?(e) }
    }

    private func makeClient() -> (HubClient, MockHubConnection) {
        let mock = MockHubConnection()
        let client = HubClient(defaults: UserDefaults(suiteName: "cc-test-\(UUID().uuidString)")!,
                               makeConnection: { _ in mock })
        return (client, mock)
    }

    func testConnectMovesToOnlineOnOpen() {
        let (client, mock) = makeClient()
        client.connect()
        XCTAssertEqual(client.state, .connecting)
        mock.emit(.opened)
        XCTAssertEqual(client.state, .online)
        XCTAssertEqual(mock.connectCount, 1)
    }

    func testSendEmitsCompileSendAndStreamsProgress() throws {
        let (client, mock) = makeClient()
        client.connect(); mock.emit(.opened)
        client.send(project: Project.empty(), defaults: Defaults(), selection: .all)

        XCTAssertEqual(mock.sent.count, 1)
        let obj = try JSONSerialization.jsonObject(with: Data(mock.sent[0].utf8)) as! [String: Any]
        XCTAssertEqual(obj["type"] as? String, "compile-send")

        mock.emit(.text(#"{"type":"progress","sent":1,"total":2}"#))
        XCTAssertEqual(client.progress?.sent, 1)
        XCTAssertEqual(client.progress?.total, 2)
        mock.emit(.text(#"{"type":"done","total":2}"#))
        XCTAssertEqual(client.lastResult, .done(total: 2))
        XCTAssertNil(client.progress)               // cleared on completion
    }

    func testErrorFrameSetsFailureResult() {
        let (client, mock) = makeClient()
        client.connect(); mock.emit(.opened)
        client.send(project: Project.empty(), defaults: Defaults(), selection: .current)
        mock.emit(.text(#"{"type":"error","message":"bad"}"#))
        XCTAssertEqual(client.lastResult, .failed("bad"))
    }

    func testClosedWithErrorSetsErrorState() {
        let (client, mock) = makeClient()
        client.connect(); mock.emit(.opened)
        mock.emit(.closed("socket dropped"))
        XCTAssertEqual(client.state, .error("socket dropped"))
    }

    func testHostPortPersist() {
        let suite = "cc-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let c1 = HubClient(defaults: d, makeConnection: { _ in MockHubConnection() })
        c1.host = "10.0.0.5"; c1.port = 9100
        let c2 = HubClient(defaults: d, makeConnection: { _ in MockHubConnection() })
        XCTAssertEqual(c2.host, "10.0.0.5")
        XCTAssertEqual(c2.port, 9100)
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`HubConnection`/`HubClient` undefined).

- [ ] **Step 3: Write `HubConnection.swift`**

```swift
import Foundation

/// Events a connection reports back to the client.
public enum HubConnectionEvent: Sendable {
    case opened
    case text(String)
    case closed(String?)      // non-nil message = error reason
}

/// A minimal socket abstraction so `HubClient` can be tested without a real WebSocket.
@MainActor
public protocol HubConnection: AnyObject {
    func connect(onEvent: @escaping (HubConnectionEvent) -> Void)
    func send(_ text: String)
    func close()
}
```

- [ ] **Step 4: Write `HubClient.swift`**

```swift
import Foundation
import Observation

public enum ConnectionState: Equatable, Sendable {
    case offline, connecting, online
    case error(String)

    public var isOnline: Bool { self == .online }
}

public struct SendProgress: Equatable, Sendable { public var sent: Int; public var total: Int }

public enum SendResult: Equatable, Sendable {
    case done(total: Int)
    case failed(String)
}

/// The observable the send bar binds to. Drives a HubConnection, tracks state,
/// sends compile-send, and surfaces streamed progress/result.
@MainActor
@Observable
public final class HubClient {
    public private(set) var state: ConnectionState = .offline
    public private(set) var progress: SendProgress?
    public private(set) var lastResult: SendResult?

    public var host: String { didSet { defaults.set(host, forKey: Keys.host) } }
    public var port: Int    { didSet { defaults.set(port, forKey: Keys.port) } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeConnection: (URL) -> HubConnection
    @ObservationIgnored private var connection: HubConnection?

    private enum Keys { static let host = "hubHost"; static let port = "hubPort" }

    public init(defaults: UserDefaults = .standard,
                makeConnection: @escaping (URL) -> HubConnection) {
        self.defaults = defaults
        self.makeConnection = makeConnection
        self.host = defaults.string(forKey: Keys.host) ?? ""
        let p = defaults.integer(forKey: Keys.port)
        self.port = p == 0 ? 9000 : p
    }

    public var url: URL? { URL(string: "ws://\(host):\(port)") }

    public func connect() {
        guard let url else { state = .error("set hub host first"); return }
        state = .connecting
        let conn = makeConnection(url)
        connection = conn
        conn.connect { [weak self] event in
            guard let self else { return }
            switch event {
            case .opened:
                self.state = .online
            case let .text(text):
                self.handle(text)
            case let .closed(reason):
                self.state = reason.map(ConnectionState.error) ?? .offline
            }
        }
    }

    public func send(project: Project, defaults: Defaults, selection: Selection) {
        if !state.isOnline { connect() }
        guard let conn = connection else { return }
        do {
            let text = try OutgoingMessage
                .compileSend(project: project, defaults: defaults, selection: selection)
                .jsonString()
            progress = nil
            lastResult = nil
            conn.send(text)
        } catch {
            lastResult = .failed("encode failed: \(error.localizedDescription)")
        }
    }

    private func handle(_ text: String) {
        guard let msg = try? IncomingMessage.decode(text) else { return }
        switch msg {
        case let .progress(sent, total):
            progress = SendProgress(sent: sent, total: total)
        case let .done(total):
            progress = nil
            lastResult = .done(total: total)
        case let .error(message):
            progress = nil
            lastResult = .failed(message)
        case .other:
            break
        }
    }
}
```

- [ ] **Step 5: Run the test, verify it passes.** Expected: `HubClientTests` PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/Kit/Hub/HubConnection.swift ios/Sources/Kit/Hub/HubClient.swift ios/Tests/KitTests/HubClientTests.swift
git commit -m "feat(ios): HubClient + HubConnection protocol (mock-tested state machine)"
```

---

## Task 9: URLSessionWebSocketConnection (production socket) + loopback integration test

The real `HubConnection` over `URLSessionWebSocketTask`. Verified on the simulator against a tiny Network.framework WebSocket server scripted to reply with `progress`/`done`.

**Files:**
- Create: `ios/Sources/Kit/Hub/URLSessionWebSocketConnection.swift`
- Test: `ios/Tests/KitTests/URLSessionWebSocketConnectionTests.swift`

- [ ] **Step 1: Write the failing test `URLSessionWebSocketConnectionTests.swift`**

```swift
import XCTest
import Network
@testable import CuelistCompilerKit

@MainActor
final class URLSessionWebSocketConnectionTests: XCTestCase {

    /// Minimal ws server: on the first text frame it receives, replies with
    /// progress then done. Returns the bound port.
    final class FakeHubServer {
        let listener: NWListener
        var conn: NWConnection?
        init() throws {
            let params = NWParameters.tcp
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
            listener = try NWListener(using: params, on: .any)
        }
        func start() {
            listener.newConnectionHandler = { [weak self] c in
                self?.conn = c
                c.start(queue: .global())
                self?.receive(c)
            }
            listener.start(queue: .global())
        }
        private func receive(_ c: NWConnection) {
            c.receiveMessage { [weak self] _, _, _, _ in
                self?.sendText(c, #"{"type":"progress","sent":1,"total":1}"#)
                self?.sendText(c, #"{"type":"done","total":1}"#)
            }
        }
        private func sendText(_ c: NWConnection, _ s: String) {
            let meta = NWProtocolWebSocket.Metadata(opcode: .text)
            let ctx = NWConnection.ContentContext(identifier: "t", metadata: [meta])
            c.send(content: Data(s.utf8), contentContext: ctx, completion: .contentProcessed { _ in })
        }
        func stop() { listener.cancel(); conn?.cancel() }
        func port() async throws -> Int {
            for _ in 0..<100 {
                if let p = listener.port?.rawValue, p != 0 { return Int(p) }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            throw XCTSkip("server never bound a port")
        }
    }

    func testRealSocketReachesDoneAgainstFakeServer() async throws {
        let server = try FakeHubServer()
        server.start()
        defer { server.stop() }
        let port = try await server.port()

        let suite = "cc-ws-\(UUID().uuidString)"
        let client = HubClient(defaults: UserDefaults(suiteName: suite)!,
                               makeConnection: { url in URLSessionWebSocketConnection(url: url) })
        client.host = "127.0.0.1"
        client.port = port
        client.connect()

        // Wait for online.
        try await poll { client.state == .online }
        client.send(project: Project.empty(), defaults: Defaults(), selection: .all)
        try await poll { client.lastResult == .done(total: 1) }
        XCTAssertEqual(client.lastResult, .done(total: 1))
    }

    /// Poll a main-actor condition up to ~3s.
    private func poll(_ cond: @MainActor () -> Bool) async throws {
        for _ in 0..<150 {
            if cond() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("condition not met in time")
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`URLSessionWebSocketConnection` undefined).

- [ ] **Step 3: Write `URLSessionWebSocketConnection.swift`**

```swift
import Foundation

/// Production HubConnection backed by URLSessionWebSocketTask. Hops all events to
/// the main actor so HubClient (a @MainActor @Observable) updates safely.
@MainActor
public final class URLSessionWebSocketConnection: NSObject, HubConnection, URLSessionWebSocketDelegate {
    private let url: URL
    private var task: URLSessionWebSocketTask?
    private var onEvent: ((HubConnectionEvent) -> Void)?
    private lazy var session: URLSession =
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    public init(url: URL) { self.url = url }

    public func connect(onEvent: @escaping (HubConnectionEvent) -> Void) {
        self.onEvent = onEvent
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receive()
    }

    public func send(_ text: String) {
        task?.send(.string(text)) { [weak self] err in
            guard let err else { return }
            Task { @MainActor in self?.onEvent?(.closed(err.localizedDescription)) }
        }
    }

    public func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(.string(text)):
                    self.onEvent?(.text(text))
                    self.receive()
                case .success(.data):
                    self.receive()                       // ignore binary
                case .success:
                    self.receive()
                case let .failure(err):
                    self.onEvent?(.closed(err.localizedDescription))
                }
            }
        }
    }

    // URLSessionWebSocketDelegate — open/close signals.
    nonisolated public func urlSession(_ session: URLSession,
                                       webSocketTask: URLSessionWebSocketTask,
                                       didOpenWithProtocol proto: String?) {
        Task { @MainActor in self.onEvent?(.opened) }
    }

    nonisolated public func urlSession(_ session: URLSession,
                                       webSocketTask: URLSessionWebSocketTask,
                                       didCloseWith code: URLSessionWebSocketTask.CloseCode,
                                       reason: Data?) {
        Task { @MainActor in self.onEvent?(.closed(nil)) }
    }
}
```

- [ ] **Step 4: Run the test, verify it passes.** Expected: `URLSessionWebSocketConnectionTests` PASS. If the ws server bind flakes in CI, the test self-skips via `XCTSkip`; on a Mac it is reliable.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Hub/URLSessionWebSocketConnection.swift ios/Tests/KitTests/URLSessionWebSocketConnectionTests.swift
git commit -m "feat(ios): URLSessionWebSocketConnection + loopback ws integration test"
```

---

## Task 10: UI helpers — pool display + cue summary (testable presentation logic)

SwiftUI views are build/smoke-verified, so the testable presentation logic lives here in the Kit and is unit-tested. `PoolDisplay` mirrors web `POOL_ABBR`/`POOL_ACCENT`/`ACTION_COLORS`; `CueSummary` mirrors web `cueSummary`.

**Files:**
- Create: `ios/Sources/Kit/Store/PoolDisplay.swift`
- Create: `ios/Sources/Kit/Store/CueSummary.swift`
- Test: `ios/Tests/KitTests/CueSummaryTests.swift`

- [ ] **Step 1: Write the failing test `CueSummaryTests.swift`**

```swift
import XCTest
@testable import CuelistCompilerKit

final class CueSummaryTests: XCTestCase {
    func testSummaryComposesParts() {
        var cue = Cue(n: 1, name: "Intro", fade: "5", delay: "", position: "VERSE")
        cue.actions = [Action(group: "A"), Action(group: "B"), Action(group: "  ")]
        XCTAssertEqual(CueSummary.text(for: cue), "VERSE · 2 groups · fade 5")
    }

    func testEmptySummaryIsEmptyString() {
        var cue = Cue(n: 1)
        cue.actions = [Action()]            // empty group → not counted
        XCTAssertEqual(CueSummary.text(for: cue), "")
    }

    func testPoolAbbreviations() {
        XCTAssertEqual(Pool.color.abbreviation, "COL")
        XCTAssertEqual(Pool.dimmer.abbreviation, "DIM")
        XCTAssertEqual(Pool.focus.abbreviation, "FOC")
    }

    func testActionColorsPaletteNonEmpty() {
        XCTAssertEqual(PoolDisplay.actionColors.first, "#d63a3a")
        XCTAssertEqual(PoolDisplay.actionColors.count, 19)
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`CueSummary`/`PoolDisplay`/`abbreviation` undefined).

- [ ] **Step 3: Write `PoolDisplay.swift`**

```swift
import Foundation

public extension Pool {
    /// Mirrors web POOL_ABBR.
    var abbreviation: String {
        switch self {
        case .color:    return "COL"
        case .dimmer:   return "DIM"
        case .position: return "POS"
        case .gobo:     return "GOB"
        case .beam:     return "BEM"
        case .focus:    return "FOC"
        }
    }

    /// Mirrors web POOL_ACCENT (hex).
    var accentHex: String {
        switch self {
        case .color:    return "#c44d8f"
        case .dimmer:   return "#d8d8d8"
        case .position: return "#5fb86a"
        case .gobo:     return "#e8a23a"
        case .beam:     return "#56c2d6"
        case .focus:    return "#a574d6"
        }
    }
}

public enum PoolDisplay {
    /// Mirrors web ACTION_COLORS — the group-block swatch palette.
    public static let actionColors = [
        "#d63a3a", "#e8552d", "#e88332", "#f0a830", "#e8c83a",
        "#d8d83a", "#b8d83a", "#6fc850", "#3aa860", "#2c8470",
        "#3ac8c8", "#56b0e0", "#4a7ed6", "#3a5ad8", "#6a52d6",
        "#a050d6", "#d650b8", "#e85a8e", "#d8d8d8"
    ]
}
```

- [ ] **Step 4: Write `CueSummary.swift`**

```swift
import Foundation

/// Mirrors web `cueSummary` — the one-line text under a collapsed cue.
public enum CueSummary {
    public static func text(for cue: Cue) -> String {
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var parts: [String] = []
        if !clean(cue.position).isEmpty { parts.append(clean(cue.position)) }
        let groups = cue.actions.filter { !clean($0.group).isEmpty }.count
        if groups > 0 { parts.append("\(groups) group\(groups > 1 ? "s" : "")") }
        if !clean(cue.fade).isEmpty { parts.append("fade \(clean(cue.fade))") }
        if !clean(cue.delay).isEmpty { parts.append("delay \(clean(cue.delay))") }
        return parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 5: Run the test, verify it passes.** Expected: `CueSummaryTests` PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/Kit/Store/PoolDisplay.swift ios/Sources/Kit/Store/CueSummary.swift ios/Tests/KitTests/CueSummaryTests.swift
git commit -m "feat(ios): pool display metadata + cue summary helper"
```

---

## Task 11: App wiring + root scaffold + hex Color helper

Wire `ProjectStore` + `HubClient` into the app, build the `NavigationStack` root and the top song bar. SwiftUI views are verified by **build + simulator launch** (the testable logic is already covered in the Kit). After this task the app runs with a real (empty) show.

**Files:**
- Modify: `ios/Sources/App/App.swift`
- Create: `ios/Sources/App/RootView.swift`
- Create: `ios/Sources/App/SongBarView.swift`
- Create: `ios/Sources/App/Color+Hex.swift`

- [ ] **Step 1: Replace `ios/Sources/App/App.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

@main
struct CuelistCompilerApp: App {
    @State private var store = ProjectStore()
    @State private var hub = HubClient(makeConnection: { url in
        URLSessionWebSocketConnection(url: url)
    })

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(hub)
                .onAppear { if !hub.host.isEmpty { hub.connect() } }
        }
    }
}
```

- [ ] **Step 2: Write `ios/Sources/App/Color+Hex.swift`**

```swift
import SwiftUI

extension Color {
    /// Parse a "#rrggbb" string (the format used by PoolDisplay/action colors).
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self = Color(red: Double((v >> 16) & 0xff) / 255,
                     green: Double((v >> 8) & 0xff) / 255,
                     blue: Double(v & 0xff) / 255)
    }
}
```

- [ ] **Step 3: Write `ios/Sources/App/RootView.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

struct RootView: View {
    @Environment(ProjectStore.self) private var store
    @State private var showSettings = false
    @State private var showDefaults = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SongBarView()
                CueListView()              // added in Task 12
                SendBarView()              // added in Task 15
            }
            .navigationTitle("Cuelist Compiler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Defaults…") { showDefaults = true }
                        Button("Settings…") { showSettings = true }
                    } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }     // Task 15
            .sheet(isPresented: $showDefaults) { DefaultsView() }     // Task 15
        }
    }
}
```

- [ ] **Step 4: Write `ios/Sources/App/SongBarView.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

struct SongBarView: View {
    @Environment(ProjectStore.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 10) {
            Menu {
                ForEach(store.project.songs) { song in
                    Button {
                        store.setActiveSong(song.id)
                    } label: {
                        Label(song.name.isEmpty ? "(untitled)" : song.name,
                              systemImage: song.id == store.project.activeSongId ? "checkmark" : "")
                    }
                }
                Divider()
                Button("New Song") { store.addSong() }
                if store.project.songs.count > 1 {
                    Button("Remove “\(store.activeSong.name.isEmpty ? "(untitled)" : store.activeSong.name)”",
                           role: .destructive) {
                        store.removeSong(id: store.project.activeSongId)
                    }
                }
            } label: {
                HStack { Text(store.activeSong.name.isEmpty ? "(untitled)" : store.activeSong.name)
                    Image(systemName: "chevron.down").font(.caption) }
            }

            Spacer()

            // Song name + sequence editors bound to the active song.
            if let idx = store.project.songs.firstIndex(where: { $0.id == store.project.activeSongId }) {
                TextField("Song name", text: $store.project.songs[idx].name)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                Stepper("Seq \(store.project.songs[idx].sequence)",
                        value: $store.project.songs[idx].sequence, in: 1...9999)
                    .labelsHidden()
                Text("Seq \(store.project.songs[idx].sequence)").font(.caption).monospacedDigit()
            }
        }
        .padding(.horizontal).padding(.vertical, 6)
        .background(.bar)
    }
}
```

- [ ] **Step 5: Add temporary stubs so the project compiles before Tasks 12 & 15**

Create `ios/Sources/App/_Stubs.swift` (deleted in Task 15):

```swift
import SwiftUI
import CuelistCompilerKit

// Temporary placeholders so RootView compiles; replaced in Tasks 12 & 15.
struct CueListView: View { var body: some View { Spacer() } }
struct SendBarView: View { var body: some View { EmptyView() } }
struct SettingsView: View { var body: some View { Text("Settings — Task 15") } }
struct DefaultsView: View { var body: some View { Text("Defaults — Task 15") } }
```

- [ ] **Step 6: Build the app + run the Kit suite**

Run the standard test command (Kit suite still green), then build the app:
```bash
cd ios && xcodebuild build -project CuelistCompiler.xcodeproj -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: both succeed. Optionally launch in the simulator and confirm the song bar renders with one untitled song.

- [ ] **Step 7: Commit**

```bash
git add ios/Sources/App
git commit -m "feat(ios): app wiring (ProjectStore+HubClient), root scaffold, song bar, hex color"
```

---

## Task 12: Cue list + cue card (collapse/expand, add/remove cue)

The "one scroll per song" body: a scroll of collapsible cue cards sorted by `n`. Replaces the `CueListView` stub.

**Files:**
- Delete from `_Stubs.swift`: the `CueListView` stub (leave the others)
- Create: `ios/Sources/App/CueListView.swift`
- Create: `ios/Sources/App/CueCardView.swift`

- [ ] **Step 1: Remove the `CueListView` line from `ios/Sources/App/_Stubs.swift`**

The file should now contain only `SendBarView`, `SettingsView`, `DefaultsView` stubs.

- [ ] **Step 2: Write `ios/Sources/App/CueListView.swift`**

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
                    Text("No cues yet. Tap “+ Add Cue” to start.")
                        .foregroundStyle(.secondary).padding(.top, 40)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach($store.project.songs[i].cues) { $cue in
                            CueCardView(cue: $cue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                Button {
                    store.addCue()
                } label: { Label("Add Cue", systemImage: "plus") }
                    .padding(.vertical, 12)
            }
        }
    }
}
```

- [ ] **Step 3: Write `ios/Sources/App/CueCardView.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

struct CueCardView: View {
    @Environment(ProjectStore.self) private var store
    @Binding var cue: Cue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    cue.collapsed.toggle()
                } label: {
                    Image(systemName: cue.collapsed ? "chevron.right" : "chevron.down")
                }
                TextField("n", value: $cue.n, format: .number)
                    .frame(width: 48).textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                TextField("Cue name", text: $cue.name).textFieldStyle(.roundedBorder)
                Button(role: .destructive) {
                    store.removeCue(id: cue.id)
                } label: { Image(systemName: "trash") }
            }

            if cue.collapsed {
                let summary = CueSummary.text(for: cue)
                if !summary.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                CopyFromBar(cue: $cue)                     // Task 14
                ForEach($cue.actions) { $action in
                    ActionBlockView(cue: $cue, action: $action)   // Task 13
                }
                Button {
                    store.addActionBlock(cueId: cue.id)
                } label: { Label("Add Group block", systemImage: "plus.rectangle") }
                    .font(.callout)
                HStack {
                    Text("Fade"); TextField("", text: $cue.fade)
                        .textFieldStyle(.roundedBorder).frame(width: 60).keyboardType(.decimalPad)
                    Text("Delay"); TextField("", text: $cue.delay)
                        .textFieldStyle(.roundedBorder).frame(width: 60).keyboardType(.decimalPad)
                }.font(.caption)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}
```

- [ ] **Step 4: Add a temporary `ActionBlockView` + `CopyFromBar` stub** (replaced in Tasks 13 & 14)

Append to `ios/Sources/App/_Stubs.swift`:

```swift
struct ActionBlockView: View {
    @Binding var cue: Cue
    @Binding var action: Action
    var body: some View { Text("group: \(action.group)") }
}
struct CopyFromBar: View {
    @Binding var cue: Cue
    var body: some View { EmptyView() }
}
```

- [ ] **Step 5: Build the app + run the Kit suite**

Run the standard test command, then the app `xcodebuild build` from Task 11 Step 6. Expected: both succeed. Optionally launch: Add Cue adds a collapsible card; the n/name fields edit; collapse shows the summary.

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/App
git commit -m "feat(ios): cue list + collapsible cue card (add/remove/collapse)"
```

---

## Task 13: Action/group block + 6 pool rows + color swatch

The dense core: a group block = group name + color swatch + all 6 pool rows (`name / fade / delay`, placeholder = Defaults).

**Files:**
- Remove from `_Stubs.swift`: the `ActionBlockView` stub
- Create: `ios/Sources/App/ActionBlockView.swift`
- Create: `ios/Sources/App/PoolRowView.swift`
- Create: `ios/Sources/App/ColorPickerPopover.swift`

- [ ] **Step 1: Remove the `ActionBlockView` stub from `_Stubs.swift`** (keep `CopyFromBar`, `SendBarView`, `SettingsView`, `DefaultsView`).

- [ ] **Step 2: Write `ios/Sources/App/PoolRowView.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

struct PoolRowView: View {
    @Environment(ProjectStore.self) private var store
    let pool: Pool
    @Binding var action: Action

    private var binding: Binding<Preset> {
        Binding(get: { action.presets[pool] ?? Preset() },
                set: { action.presets[pool] = $0 })
    }

    var body: some View {
        let preset = binding
        HStack(spacing: 6) {
            Text(pool.abbreviation)
                .font(.caption2).bold()
                .frame(width: 34, alignment: .leading)
                .foregroundStyle(Color(hex: pool.accentHex) ?? .secondary)
            TextField("(none)", text: preset.name).textFieldStyle(.roundedBorder)
            TextField(store.defaults.fade(pool).isEmpty ? "f" : store.defaults.fade(pool),
                      text: preset.fade)
                .textFieldStyle(.roundedBorder).frame(width: 40).keyboardType(.decimalPad)
            TextField(store.defaults.delay(pool).isEmpty ? "d" : store.defaults.delay(pool),
                      text: preset.delay)
                .textFieldStyle(.roundedBorder).frame(width: 40).keyboardType(.decimalPad)
        }
    }
}
```

- [ ] **Step 3: Write `ios/Sources/App/ColorPickerPopover.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

struct ColorPickerPopover: View {
    @Binding var selection: String          // "" = no color
    @Environment(\.dismiss) private var dismiss

    private let cols = Array(repeating: GridItem(.fixed(34), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: cols, spacing: 8) {
            swatch(hex: "", isNone: true)
            ForEach(PoolDisplay.actionColors, id: \.self) { hex in swatch(hex: hex, isNone: false) }
        }
        .padding()
        .presentationCompactAdaptation(.popover)
    }

    private func swatch(hex: String, isNone: Bool) -> some View {
        Circle()
            .fill(isNone ? Color(.systemGray4) : (Color(hex: hex) ?? .gray))
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(.primary, lineWidth: selection == hex ? 2 : 0))
            .overlay(isNone ? Image(systemName: "slash.circle").font(.caption) : nil)
            .onTapGesture { selection = hex; dismiss() }
    }
}
```

- [ ] **Step 4: Write `ios/Sources/App/ActionBlockView.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

struct ActionBlockView: View {
    @Environment(ProjectStore.self) private var store
    @Binding var cue: Cue
    @Binding var action: Action
    @State private var showColors = false

    private var blockIndex: Int? { cue.actions.firstIndex(where: { $0.id == action.id }) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    showColors = true
                } label: {
                    Circle()
                        .fill(Color(hex: action.color) ?? Color(.systemGray4))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.secondary, lineWidth: 1))
                }
                .popover(isPresented: $showColors) { ColorPickerPopover(selection: $action.color) }

                TextField("Group name", text: $action.group).textFieldStyle(.roundedBorder)

                Button(role: .destructive) {
                    if let i = blockIndex { store.removeActionBlock(cueId: cue.id, at: i) }
                } label: { Image(systemName: "xmark.circle") }
            }
            ForEach(Pool.allCases, id: \.self) { pool in
                PoolRowView(pool: pool, action: $action)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
    }
}
```

Note: `blockIndex` matches on `action.id`. `Action` is already `Identifiable` (its `id` was defined in Task 3 and is excluded from `CodingKeys`), so `ForEach`/`firstIndex` by id work here with no model change.

- [ ] **Step 5: Run the Kit suite** (confirms the views compile against the model and nothing regressed)

Run the standard test command. Expected: all Kit tests still PASS.

- [ ] **Step 6: Build the app**

Run the app `xcodebuild build`. Expected: success. Optionally launch: expand a cue → group block shows group field, color swatch (popover palette), and all six pool rows with Defaults placeholders.

- [ ] **Step 7: Commit**

```bash
git add ios/Sources/App
git commit -m "feat(ios): group block + 6 pool rows + color swatch popover"
```

---

## Task 14: Copy-from-cue control

Replaces the `CopyFromBar` stub: pull another cue's action blocks into this one.

**Files:**
- Remove from `_Stubs.swift`: the `CopyFromBar` stub
- Create: `ios/Sources/App/CopyFromBar.swift`

- [ ] **Step 1: Remove the `CopyFromBar` stub from `_Stubs.swift`** (leaving only `SendBarView`, `SettingsView`, `DefaultsView`).

- [ ] **Step 2: Write `ios/Sources/App/CopyFromBar.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

struct CopyFromBar: View {
    @Environment(ProjectStore.self) private var store
    @Binding var cue: Cue

    /// Other cues in the active song that have at least one non-empty group block.
    private var sources: [Cue] {
        store.activeSong.cues.filter { other in
            other.id != cue.id &&
            other.actions.contains { !$0.group.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    var body: some View {
        if !sources.isEmpty {
            Menu {
                ForEach(sources) { src in
                    Button("Cue \(src.n, format: .number)\(src.name.isEmpty ? "" : " — \(src.name)")") {
                        store.copyActions(fromCueId: src.id, toCueId: cue.id)
                    }
                }
            } label: {
                Label("Copy from cue…", systemImage: "doc.on.doc").font(.caption)
            }
        }
    }
}
```

- [ ] **Step 3: Build the app + run Kit suite**

Run the standard test command, then the app `xcodebuild build`. Expected: both succeed. Optionally launch: with ≥2 cues where one has a group, the other shows "Copy from cue…" and copying replaces its blocks.

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App
git commit -m "feat(ios): copy-actions-from-another-cue control"
```

---

## Task 15: Send bar + status pill + Settings + Defaults

Replaces the remaining stubs: the bottom send bar (store-mode picker, Send current/all, status pill, inline progress) plus the Settings (hub host/port) and Defaults (per-pool fade/delay) screens.

**Files:**
- Delete: `ios/Sources/App/_Stubs.swift`
- Create: `ios/Sources/App/SendBarView.swift`
- Create: `ios/Sources/App/SettingsView.swift`
- Create: `ios/Sources/App/DefaultsView.swift`

- [ ] **Step 1: Delete `ios/Sources/App/_Stubs.swift`**

```bash
rm ios/Sources/App/_Stubs.swift
```

- [ ] **Step 2: Write `ios/Sources/App/SendBarView.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

struct SendBarView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(HubClient.self) private var hub

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 6) {
            HStack {
                pill
                Spacer()
                Picker("Store", selection: $store.project.storeMode) {
                    ForEach(StoreMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 180)
            }
            HStack(spacing: 10) {
                Button {
                    hub.send(project: store.project, defaults: store.defaults, selection: .current)
                } label: { Label("Send current", systemImage: "paperplane") }
                    .buttonStyle(.borderedProminent)
                Button {
                    hub.send(project: store.project, defaults: store.defaults, selection: .all)
                } label: { Label("Send all", systemImage: "paperplane.fill") }
                    .buttonStyle(.bordered)
            }
            .disabled(!hub.state.isOnline)

            if let p = hub.progress {
                ProgressView(value: Double(p.sent), total: Double(max(1, p.total)))
                Text("sending \(p.sent)/\(p.total)…").font(.caption2).foregroundStyle(.secondary)
            } else if let result = hub.lastResult {
                switch result {
                case let .done(total):
                    Label("Sent \(total) lines", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                case let .failed(msg):
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private var pill: some View {
        Button {
            hub.connect()
        } label: {
            switch hub.state {
            case .offline:    Label("hub offline", systemImage: "circle").foregroundStyle(.secondary)
            case .connecting: Label("connecting…", systemImage: "circle.dotted").foregroundStyle(.orange)
            case .online:     Label("hub online", systemImage: "circle.fill").foregroundStyle(.green)
            case let .error(m): Label(m, systemImage: "circle.fill").foregroundStyle(.red)
            }
        }
        .font(.caption).lineLimit(1)
    }
}
```

- [ ] **Step 3: Write `ios/Sources/App/SettingsView.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

struct SettingsView: View {
    @Environment(HubClient.self) private var hub
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var hub = hub
        NavigationStack {
            Form {
                Section("Hub") {
                    TextField("Host (Pi LAN or tailnet IP)", text: $hub.host)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Port", value: $hub.port, format: .number)
                        .keyboardType(.numberPad)
                    Button("Connect") { hub.connect() }
                }
                Section {
                    LabeledContent("Status") { Text(statusText) }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var statusText: String {
        switch hub.state {
        case .offline: return "offline"
        case .connecting: return "connecting…"
        case .online: return "online"
        case let .error(m): return "error: \(m)"
        }
    }
}
```

- [ ] **Step 4: Write `ios/Sources/App/DefaultsView.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

struct DefaultsView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Default fade / delay") {
                    Text("Used at send when a preset's own fade/delay is blank. Shown as placeholders in the cue editor.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Pool.allCases, id: \.self) { pool in
                        HStack {
                            Text(pool.rawValue.capitalized).frame(width: 90, alignment: .leading)
                            TextField("fade", text: bindingFade(pool))
                                .textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                            TextField("delay", text: bindingDelay(pool))
                                .textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                        }
                    }
                }
            }
            .navigationTitle("Defaults")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func bindingFade(_ pool: Pool) -> Binding<String> {
        Binding(get: { store.defaults.values[pool]?.fade ?? "" },
                set: { var p = store.defaults.values[pool] ?? Preset(); p.fade = $0; store.defaults.values[pool] = p })
    }
    private func bindingDelay(_ pool: Pool) -> Binding<String> {
        Binding(get: { store.defaults.values[pool]?.delay ?? "" },
                set: { var p = store.defaults.values[pool] ?? Preset(); p.delay = $0; store.defaults.values[pool] = p })
    }
}
```

- [ ] **Step 5: Build the app + run the full Kit suite**

Run the standard test command (all Kit tests green), then the app `xcodebuild build`. Expected: both succeed (no stubs remain; every view is real).

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/App
git commit -m "feat(ios): send bar + status pill + Settings + Defaults screens"
```

---

## Task 16: Manual device smoke (the live loop)

No code. Verify the whole path on real hardware — the loop already proven by hand on the desk 2026-06-04, now driven by the app instead of a scratch WS client.

- [ ] **Step 1: Start the hub against the desk** (Mac or Pi on the desk's LAN):

```bash
cd hub && MA3_HOST=<desk-ip> npm start
```

- [ ] **Step 2: Run the app** on a physical iPhone on the same network (or pointed at the hub's tailnet IP). In Settings, set Host = the hub machine's IP, Port = 9000, tap Connect → pill turns green. Accept the iOS Local Network prompt if shown.

- [ ] **Step 3: Author a tiny show** — one song (set Sequence), one cue (set a group + a Color preset name), then **Send current → MA**.

- [ ] **Step 4: Confirm** progress reaches "Sent N lines" and the desk stores the cue in the chosen sequence (Echo Input = Yes on the console's OSC input, port 8000, prefix `gma3`).

- [ ] **Step 5: Record the result** in the Cuelist Compiler memory topic (smoke passed / any issues).

---

## Done criteria for Plan B

- `xcodebuild test -scheme CuelistCompilerKit` green across all suites (model codec, migration, ProjectStore + mutations, cue summary, hub messages, HubClient state machine, URLSession ws integration).
- `xcodebuild build -scheme CuelistCompiler` succeeds; app launches and authors a show (songs/cues/group blocks/6 pools/defaults/store mode), persisting locally.
- The status pill reflects hub connection; Send current/all stream progress and report done/error inline.
- Manual device smoke: author on the phone → hub → grandMA3 stores the cues.
- No `web/` or `proxy/` changes. No on-phone compiling or OSC. No command-parity tests on iOS (the hub's golden fixture owns the contract).

**Deferred to later milestones (unchanged from the spec):** moods · pool picker/autocomplete · audio · CSV import · show.json import/export UI · multi-show files · mDNS discovery · hub auth · iCloud · iPad layout.
