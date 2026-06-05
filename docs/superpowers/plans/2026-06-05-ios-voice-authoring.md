# iOS Voice Authoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a freeform voice-command feature to the Cuelist Compiler iOS app — speak an instruction, Whisper transcribes it, an Anthropic LLM turns it into validated edit operations over the show, the app previews them in plain language, and applies them on confirm.

**Architecture:** Pipeline split across `CuelistCompilerKit` (transcription/interpretation/edit-engine, all behind protocols + injected transports, fully unit-tested) and the thin app (`AVAudioRecorder` capture, SwiftUI preview sheet, Settings key entry). The LLM emits a whitelisted `ShowEdit` operation list via Anthropic tool-use; a pure `ShowEditApplier` resolves human references (song ordinal/name, cue number, pool name) to model objects, applies the ops to a *copy*, and returns the new project plus a deterministic plain-language summary and warnings. The app commits that precomputed copy on Apply — preview can never disagree with the result.

**Tech Stack:** Swift 5.9, SwiftUI, `@Observable`, XCTest, `URLSession` (OpenAI Whisper + Anthropic Messages API), AVFoundation, Keychain. Default model `claude-sonnet-4-6` with prompt caching.

**Spec:** `docs/superpowers/specs/2026-06-05-ios-voice-authoring-design.md`

**Branch:** `feat/voice-authoring` (off `feat/ios-shell`).

**Conventions (match existing code):**
- Tests are `XCTest`, `@testable import CuelistCompilerKit`, one file per type under `ios/Tests/KitTests/`.
- Dependencies are injected via protocols + factory closures (see `HubClient(makeConnection:)` / `MockHubConnection`).
- Build/test command: `cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- App-only code (SwiftUI, AVFoundation) is **not** in the test target; verify those tasks with `xcodebuild build -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- After any change to files/targets, re-run `xcodegen generate` before building.

**File structure (created unless noted):**

| File | Responsibility |
|---|---|
| `ios/Sources/Kit/Voice/HTTPTransport.swift` | `HTTPTransport` protocol + `URLSessionHTTPTransport`; the seam both API clients mock |
| `ios/Sources/Kit/Voice/ShowEdit.swift` | `ShowEdit` op enum + `CueField` + strict `Decodable` from tool input + `ToolInput` wrapper |
| `ios/Sources/Kit/Voice/ShowEditApplier.swift` | `ApplyResult` + pure `apply(_:to:defaults:)`: reference resolution, op application, summary, warnings |
| `ios/Sources/Kit/Voice/ProjectSnapshot.swift` | Compact JSON projection of a `Project` for the model |
| `ios/Sources/Kit/Voice/InterpretedCommand.swift` | `{ transcript, edits, clarification? }` value type |
| `ios/Sources/Kit/Voice/Transcriber.swift` | `Transcriber` protocol + `WhisperTranscriber` (OpenAI multipart) |
| `ios/Sources/Kit/Voice/CommandInterpreter.swift` | `CommandInterpreter` protocol + `AnthropicInterpreter` (tool-use request build + response parse) |
| `ios/Sources/Kit/Voice/AIKeyStore.swift` | `AIKeyStore` protocol + `KeychainAIKeyStore` (+ `InMemoryAIKeyStore` for tests/wiring) |
| `ios/Sources/Kit/Voice/AudioRecorder.swift` | `AudioRecorder` protocol (record start/stop/permission) — concrete impl in App |
| `ios/Sources/Kit/Voice/VoiceCaptureController.swift` | `@MainActor @Observable` state machine orchestrating recorder→transcribe→interpret→pending preview |
| `ios/Sources/Kit/Store/ProjectStore+Mutations.swift` *(modify)* | add `apply(_ result: ApplyResult)` to commit a precomputed copy |
| `ios/Sources/App/AVAudioFileRecorder.swift` | Concrete `AudioRecorder` over `AVAudioRecorder` + mic permission |
| `ios/Sources/App/VoicePreviewSheet.swift` | Preview UI: transcript + summary + warnings + Apply/Discard |
| `ios/Sources/App/SettingsView.swift` *(modify)* | two `SecureField`s for the keys → `KeychainAIKeyStore` |
| `ios/Sources/App/RootView.swift` *(modify)* | mic button, working indicator, present preview sheet |
| `ios/Sources/App/App.swift` *(modify)* | build + inject `VoiceCaptureController` |
| `ios/project.yml` *(modify)* | `NSMicrophoneUsageDescription` |

---

## Task 1: HTTPTransport seam

**Files:**
- Create: `ios/Sources/Kit/Voice/HTTPTransport.swift`
- Test: `ios/Tests/KitTests/HTTPTransportTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CuelistCompilerKit

final class HTTPTransportTests: XCTestCase {
    func testMockReturnsScriptedResponse() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            XCTAssertEqual(req.url?.host, "example.com")
            return (Data("ok".utf8), HTTPURLResponse(url: req.url!, statusCode: 200,
                                                     httpVersion: nil, headerFields: nil)!)
        }
        let (data, resp) = try await mock.send(URLRequest(url: URL(string: "https://example.com")!))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
        XCTAssertEqual(resp.statusCode, 200)
        XCTAssertEqual(mock.sentRequests.count, 1)
    }
}
```

`MockHTTPTransport` is a reusable test double — define it in the test target now (other tests reuse it).

```swift
// append to HTTPTransportTests.swift
final class MockHTTPTransport: HTTPTransport, @unchecked Sendable {
    var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    private(set) var sentRequests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sentRequests.append(request)
        guard let handler else { throw URLError(.badServerResponse) }
        return try handler(request)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CuelistCompilerKitTests/HTTPTransportTests`
Expected: FAIL — `cannot find type 'HTTPTransport' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ios/Sources/Kit/Voice/HTTPTransport.swift
import Foundation

/// The single HTTP seam both API clients depend on, so tests inject canned
/// responses instead of hitting the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/HTTPTransport.swift ios/Tests/KitTests/HTTPTransportTests.swift ios/project.yml ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): HTTPTransport seam + MockHTTPTransport for voice API clients"
```

---

## Task 2: ShowEdit op type + tool-input decoding

**Files:**
- Create: `ios/Sources/Kit/Voice/ShowEdit.swift`
- Test: `ios/Tests/KitTests/ShowEditDecodeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CuelistCompilerKit

final class ShowEditDecodeTests: XCTestCase {
    private func decode(_ json: String) throws -> ToolInput {
        try JSONDecoder().decode(ToolInput.self, from: Data(json.utf8))
    }

    func testDecodesPresetAndGroupEdits() throws {
        let input = try decode("""
        { "edits": [
          { "op": "setGroup",  "cue": 1, "group": "1" },
          { "op": "setPreset", "cue": 1, "pool": "color", "name": "Deep Blue", "fade": "5" }
        ] }
        """)
        XCTAssertNil(input.clarification)
        XCTAssertEqual(input.edits, [
            .setGroup(song: nil, cue: 1, group: "1", block: nil),
            .setPreset(song: nil, cue: 1, pool: .color, name: "Deep Blue", fade: "5", delay: nil, block: nil)
        ])
    }

    func testDecodesSongAndCueOps() throws {
        let input = try decode("""
        { "edits": [
          { "op": "addSong", "name": "Encore", "sequence": 12 },
          { "op": "setCue", "song": "2", "cue": 0.1, "field": "name", "value": "DB CUE" },
          { "op": "setDefault", "pool": "dimmer", "fade": "3" },
          { "op": "setStoreMode", "mode": "Merge" }
        ] }
        """)
        XCTAssertEqual(input.edits, [
            .addSong(name: "Encore", sequence: 12),
            .setCue(song: "2", cue: 0.1, field: .name, value: "DB CUE"),
            .setDefault(pool: .dimmer, fade: "3", delay: nil),
            .setStoreMode(mode: .merge)
        ])
    }

    func testClarificationOnlyShape() throws {
        let input = try decode(#"{ "edits": [], "clarification": "Which song?" }"#)
        XCTAssertTrue(input.edits.isEmpty)
        XCTAssertEqual(input.clarification, "Which song?")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CuelistCompilerKitTests/ShowEditDecodeTests`
Expected: FAIL — `cannot find type 'ToolInput'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ios/Sources/Kit/Voice/ShowEdit.swift
import Foundation

/// Which scalar field of a cue `setCue` targets.
public enum CueField: String, Codable, Sendable { case name, fade, delay, position, number }

/// One validated edit operation. The LLM emits these via the apply_show_edits tool;
/// `song`/`cue`/`pool`/`block` are human references resolved by ShowEditApplier.
public enum ShowEdit: Equatable, Sendable {
    case addSong(name: String?, sequence: Int?)
    case renameSong(song: String, name: String)
    case setSequence(song: String, sequence: Int)
    case selectSong(song: String)
    case deleteSong(song: String)
    case addCue(song: String?, n: Double?, name: String?, fade: String?, delay: String?, position: String?)
    case setCue(song: String?, cue: Double, field: CueField, value: String)
    case deleteCue(song: String?, cue: Double)
    case sortCues(song: String?)
    case setGroup(song: String?, cue: Double, group: String, block: Int?)
    case setPreset(song: String?, cue: Double, pool: Pool, name: String?, fade: String?, delay: String?, block: Int?)
    case clearPreset(song: String?, cue: Double, pool: Pool, block: Int?)
    case addActionBlock(song: String?, cue: Double)
    case removeActionBlock(song: String?, cue: Double, block: Int)
    case copyActions(song: String?, fromCue: Double, toCue: Double)
    case setDefault(pool: Pool, fade: String?, delay: String?)
    case setStoreMode(mode: StoreMode)
}

/// The whole tool input: the edit list plus an optional clarification question.
public struct ToolInput: Decodable, Equatable, Sendable {
    public let edits: [ShowEdit]
    public let clarification: String?
}

extension ShowEdit: Decodable {
    private enum K: String, CodingKey {
        case op, song, name, sequence, cue, n, fade, delay, position
        case field, value, group, block, pool, fromCue, toCue, mode
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let op = try c.decode(String.self, forKey: .op)
        func str(_ k: K) throws -> String { try c.decode(String.self, forKey: k) }
        func optStr(_ k: K) -> String? { try? c.decode(String.self, forKey: k) }
        func optInt(_ k: K) -> Int? { try? c.decode(Int.self, forKey: k) }
        func dbl(_ k: K) throws -> Double { try c.decode(Double.self, forKey: k) }
        func pool(_ k: K) throws -> Pool {
            guard let p = Pool(rawValue: try str(k)) else {
                throw DecodingError.dataCorruptedError(forKey: k, in: c, debugDescription: "bad pool")
            }
            return p
        }
        switch op {
        case "addSong":     self = .addSong(name: optStr(.name), sequence: optInt(.sequence))
        case "renameSong":  self = .renameSong(song: try str(.song), name: try str(.name))
        case "setSequence": self = .setSequence(song: try str(.song), sequence: try c.decode(Int.self, forKey: .sequence))
        case "selectSong":  self = .selectSong(song: try str(.song))
        case "deleteSong":  self = .deleteSong(song: try str(.song))
        case "addCue":      self = .addCue(song: optStr(.song), n: try? dbl(.n), name: optStr(.name),
                                           fade: optStr(.fade), delay: optStr(.delay), position: optStr(.position))
        case "setCue":      self = .setCue(song: optStr(.song), cue: try dbl(.cue),
                                           field: try c.decode(CueField.self, forKey: .field), value: try str(.value))
        case "deleteCue":   self = .deleteCue(song: optStr(.song), cue: try dbl(.cue))
        case "sortCues":    self = .sortCues(song: optStr(.song))
        case "setGroup":    self = .setGroup(song: optStr(.song), cue: try dbl(.cue), group: try str(.group), block: optInt(.block))
        case "setPreset":   self = .setPreset(song: optStr(.song), cue: try dbl(.cue), pool: try pool(.pool),
                                              name: optStr(.name), fade: optStr(.fade), delay: optStr(.delay), block: optInt(.block))
        case "clearPreset": self = .clearPreset(song: optStr(.song), cue: try dbl(.cue), pool: try pool(.pool), block: optInt(.block))
        case "addActionBlock":    self = .addActionBlock(song: optStr(.song), cue: try dbl(.cue))
        case "removeActionBlock": self = .removeActionBlock(song: optStr(.song), cue: try dbl(.cue), block: try c.decode(Int.self, forKey: .block))
        case "copyActions": self = .copyActions(song: optStr(.song), fromCue: try dbl(.fromCue), toCue: try dbl(.toCue))
        case "setDefault":  self = .setDefault(pool: try pool(.pool), fade: optStr(.fade), delay: optStr(.delay))
        case "setStoreMode":
            self = .setStoreMode(mode: (try str(.mode)) == "Merge" ? .merge : .overwrite)
        default:
            throw DecodingError.dataCorruptedError(forKey: .op, in: c, debugDescription: "unknown op \(op)")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/ShowEdit.swift ios/Tests/KitTests/ShowEditDecodeTests.swift ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): ShowEdit op vocabulary + tool-input decoding"
```

---

## Task 3: ShowEditApplier — reference resolution + song ops

**Files:**
- Create: `ios/Sources/Kit/Voice/ShowEditApplier.swift`
- Test: `ios/Tests/KitTests/ShowEditApplierSongTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CuelistCompilerKit

final class ShowEditApplierSongTests: XCTestCase {
    private func base() -> Project {
        Project(songs: [
            Song(id: "a", name: "Opener", sequence: 1, cues: []),
            Song(id: "b", name: "Closer", sequence: 2, cues: [])
        ], activeSongId: "a")
    }

    func testAddSongAppendsAndSummarizes() {
        let r = ShowEditApplier.apply([.addSong(name: "Encore", sequence: 12)],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs.count, 3)
        XCTAssertEqual(r.project.songs.last?.name, "Encore")
        XCTAssertEqual(r.project.songs.last?.sequence, 12)
        XCTAssertEqual(r.project.activeSongId, r.project.songs.last?.id)
        XCTAssertEqual(r.summary, ["Add song “Encore” (sequence 12)"])
        XCTAssertTrue(r.warnings.isEmpty)
    }

    func testRenameByOrdinalAndSequenceByName() {
        let r = ShowEditApplier.apply([
            .renameSong(song: "2", name: "Finale"),
            .setSequence(song: "Opener", sequence: 7)
        ], to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs[1].name, "Finale")
        XCTAssertEqual(r.project.songs[0].sequence, 7)
        XCTAssertEqual(r.summary.count, 2)
    }

    func testDeleteSongNeverDropsBelowOne() {
        var p = base(); p.songs = [p.songs[0]]; p.activeSongId = "a"
        let r = ShowEditApplier.apply([.deleteSong(song: "1")], to: p, defaults: Defaults())
        XCTAssertEqual(r.project.songs.count, 1)               // replaced with a fresh empty song
        XCTAssertNotEqual(r.project.songs[0].id, "a")
    }

    func testUnresolvedSongWarns() {
        let r = ShowEditApplier.apply([.renameSong(song: "9", name: "X")],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs.map(\.name), ["Opener", "Closer"])  // unchanged
        XCTAssertEqual(r.warnings, ["Song “9” not found — skipped renameSong"])
        XCTAssertTrue(r.summary.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CuelistCompilerKitTests/ShowEditApplierSongTests`
Expected: FAIL — `cannot find 'ShowEditApplier'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ios/Sources/Kit/Voice/ShowEditApplier.swift
import Foundation

public struct ApplyResult: Equatable, Sendable {
    public var project: Project
    public var defaults: Defaults
    public var summary: [String]
    public var warnings: [String]
}

/// Pure: resolves human references, applies the ops to copies, and records a
/// deterministic plain-language summary + warnings for skipped/unresolved ops.
public enum ShowEditApplier {

    public static func apply(_ edits: [ShowEdit], to project: Project, defaults: Defaults) -> ApplyResult {
        var p = project, d = defaults, summary: [String] = [], warnings: [String] = []
        for edit in edits { applyOne(edit, &p, &d, &summary, &warnings) }
        return ApplyResult(project: p, defaults: d, summary: summary, warnings: warnings)
    }

    // MARK: reference resolution

    /// nil ref → active song; an integer ref → 1-based index; else case-insensitive name.
    static func songIndex(_ ref: String?, _ p: Project) -> Int? {
        guard let ref else { return p.songs.firstIndex { $0.id == p.activeSongId } ?? (p.songs.isEmpty ? nil : 0) }
        let trimmed = ref.trimmingCharacters(in: .whitespaces)
        if let i = Int(trimmed), i >= 1, i <= p.songs.count { return i - 1 }
        return p.songs.firstIndex { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    static func cueIndex(_ cue: Double, _ songIdx: Int, _ p: Project) -> Int? {
        p.songs[songIdx].cues.firstIndex { $0.n == cue }
    }

    static func warn(_ warnings: inout [String], _ ref: String?, _ op: String) {
        warnings.append("Song “\(ref ?? "active")” not found — skipped \(op)")
    }

    // MARK: dispatch (song ops here; cue/action ops added in later tasks)

    static func applyOne(_ edit: ShowEdit, _ p: inout Project, _ d: inout Defaults,
                         _ summary: inout [String], _ warnings: inout [String]) {
        switch edit {
        case let .addSong(name, sequence):
            let s = Song(id: IDGen.next(), name: name ?? "", sequence: sequence ?? 1, cues: [])
            p.songs.append(s); p.activeSongId = s.id
            summary.append("Add song “\(s.name)” (sequence \(s.sequence))")

        case let .renameSong(song, name):
            guard let i = songIndex(song, p) else { return warn(&warnings, song, "renameSong") }
            p.songs[i].name = name
            summary.append("Rename song \(i + 1) → “\(name)”")

        case let .setSequence(song, sequence):
            guard let i = songIndex(song, p) else { return warn(&warnings, song, "setSequence") }
            p.songs[i].sequence = sequence
            summary.append("Song \(i + 1) sequence → \(sequence)")

        case let .selectSong(song):
            guard let i = songIndex(song, p) else { return warn(&warnings, song, "selectSong") }
            p.activeSongId = p.songs[i].id
            summary.append("Select song \(i + 1) (“\(p.songs[i].name)”)")

        case let .deleteSong(song):
            guard let i = songIndex(song, p) else { return warn(&warnings, song, "deleteSong") }
            let name = p.songs[i].name
            p.songs.remove(at: i)
            if p.songs.isEmpty {
                let ns = Song(id: IDGen.next(), sequence: 1, cues: [])
                p.songs = [ns]; p.activeSongId = ns.id
            } else if !p.songs.contains(where: { $0.id == p.activeSongId }) {
                p.activeSongId = p.songs[max(0, i - 1)].id
            }
            summary.append("Delete song “\(name)”")

        default:
            break   // cue/action/defaults/project ops handled in Tasks 4–5
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/ShowEditApplier.swift ios/Tests/KitTests/ShowEditApplierSongTests.swift ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): ShowEditApplier reference resolution + song ops"
```

---

## Task 4: ShowEditApplier — cue ops

**Files:**
- Modify: `ios/Sources/Kit/Voice/ShowEditApplier.swift` (replace the `default: break` in `applyOne` with the cue cases below, keep the rest)
- Test: `ios/Tests/KitTests/ShowEditApplierCueTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CuelistCompilerKit

final class ShowEditApplierCueTests: XCTestCase {
    private func base() -> Project {
        Project(songs: [Song(id: "a", name: "Opener", sequence: 1, cues: [
            Cue(n: 0.1, name: "DB"), Cue(n: 1, name: "Intro")
        ])], activeSongId: "a")
    }

    func testAddCueAutoNumbers() {
        let r = ShowEditApplier.apply([.addCue(song: nil, n: nil, name: "Verse",
                                               fade: "3", delay: nil, position: nil)],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues.map(\.n), [0.1, 1, 2])
        XCTAssertEqual(r.project.songs[0].cues.last?.name, "Verse")
        XCTAssertEqual(r.project.songs[0].cues.last?.fade, "3")
        XCTAssertEqual(r.summary, ["Add cue 2 “Verse” (fade 3)"])
    }

    func testSetCueFieldByNumber() {
        let r = ShowEditApplier.apply([.setCue(song: nil, cue: 1, field: .name, value: "INTRO")],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues[1].name, "INTRO")
        XCTAssertEqual(r.summary, ["Cue 1 · name = “INTRO”"])
    }

    func testSetCueNumberRenumbers() {
        let r = ShowEditApplier.apply([.setCue(song: nil, cue: 0.1, field: .number, value: "0.5")],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues[0].n, 0.5)
    }

    func testDeleteCueAndMissingWarns() {
        let r = ShowEditApplier.apply([.deleteCue(song: nil, cue: 0.1),
                                       .deleteCue(song: nil, cue: 9)],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues.map(\.n), [1])
        XCTAssertEqual(r.warnings, ["Cue 9 not found in song 1 — skipped deleteCue"])
    }

    func testSortCues() {
        var p = base(); p.songs[0].cues = [Cue(n: 2), Cue(n: 1), Cue(n: 0.1)]
        let r = ShowEditApplier.apply([.sortCues(song: nil)], to: p, defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues.map(\.n), [0.1, 1, 2])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CuelistCompilerKitTests/ShowEditApplierCueTests`
Expected: FAIL — cue ops fall through `default: break`, assertions fail.

- [ ] **Step 3: Write minimal implementation**

Add a cue-warning helper next to `warn(...)` in `ShowEditApplier.swift`:

```swift
    static func warnCue(_ warnings: inout [String], _ cue: Double, _ songIdx: Int, _ op: String) {
        warnings.append("Cue \(num(cue)) not found in song \(songIdx + 1) — skipped \(op)")
    }

    /// Trim a trailing ".0" so 1.0 prints as "1" but 0.1 stays "0.1".
    static func num(_ n: Double) -> String {
        n == n.rounded() ? String(Int(n)) : String(n)
    }
```

Replace `default: break` in `applyOne` with these cases (then a new `default: break` for the still-unhandled action ops):

```swift
        case let .addCue(song, n, name, fade, delay, position):
            guard let si = songIndex(song, p) else { return warn(&warnings, song, "addCue") }
            let next = n ?? ((p.songs[si].cues.map(\.n).max() ?? 0) + 1)
            var cue = Cue(n: next, name: name ?? "", fade: fade ?? "", delay: delay ?? "",
                          position: position ?? "")
            cue.actions = [Action()]
            p.songs[si].cues.append(cue)
            let fadeNote = (fade?.isEmpty == false) ? " (fade \(fade!))" : ""
            summary.append("Add cue \(num(next)) “\(cue.name)”\(fadeNote)")

        case let .setCue(song, cue, field, value):
            guard let si = songIndex(song, p) else { return warn(&warnings, song, "setCue") }
            guard let ci = cueIndex(cue, si, p) else { return warnCue(&warnings, cue, si, "setCue") }
            switch field {
            case .name:     p.songs[si].cues[ci].name = value
            case .fade:     p.songs[si].cues[ci].fade = value
            case .delay:    p.songs[si].cues[ci].delay = value
            case .position: p.songs[si].cues[ci].position = value
            case .number:   if let d = Double(value) { p.songs[si].cues[ci].n = d }
            }
            summary.append("Cue \(num(cue)) · \(field.rawValue) = “\(value)”")

        case let .deleteCue(song, cue):
            guard let si = songIndex(song, p) else { return warn(&warnings, song, "deleteCue") }
            guard let ci = cueIndex(cue, si, p) else { return warnCue(&warnings, cue, si, "deleteCue") }
            p.songs[si].cues.remove(at: ci)
            summary.append("Delete cue \(num(cue))")

        case let .sortCues(song):
            guard let si = songIndex(song, p) else { return warn(&warnings, song, "sortCues") }
            p.songs[si].cues.sort { $0.n < $1.n }
            summary.append("Sort cues in song \(si + 1)")
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2, plus the Task 3 suite to confirm no regression:
`-only-testing:CuelistCompilerKitTests/ShowEditApplierCueTests -only-testing:CuelistCompilerKitTests/ShowEditApplierSongTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/ShowEditApplier.swift ios/Tests/KitTests/ShowEditApplierCueTests.swift
git commit -m "feat(ios): ShowEditApplier cue ops"
```

---

## Task 5: ShowEditApplier — action/preset/defaults/project ops

**Files:**
- Modify: `ios/Sources/Kit/Voice/ShowEditApplier.swift` (replace the trailing `default: break` with these cases)
- Test: `ios/Tests/KitTests/ShowEditApplierActionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CuelistCompilerKit

final class ShowEditApplierActionTests: XCTestCase {
    private func base() -> Project {
        Project(songs: [Song(id: "a", name: "Opener", sequence: 1,
                             cues: [Cue(n: 1, name: "Intro")])], activeSongId: "a")
    }

    func testSetGroupAndPresetOnFirstBlock() {
        let r = ShowEditApplier.apply([
            .setGroup(song: nil, cue: 1, group: "1", block: nil),
            .setPreset(song: nil, cue: 1, pool: .color, name: "Deep Blue", fade: "5", delay: nil, block: nil)
        ], to: base(), defaults: Defaults())
        let action = r.project.songs[0].cues[0].actions[0]
        XCTAssertEqual(action.group, "1")
        XCTAssertEqual(action.presets[.color]?.name, "Deep Blue")
        XCTAssertEqual(action.presets[.color]?.fade, "5")
        XCTAssertEqual(r.summary, ["Cue 1 · group = 1", "Cue 1 · color = “Deep Blue” (fade 5)"])
    }

    func testClearPreset() {
        var p = base()
        p.songs[0].cues[0].actions[0].presets[.dimmer] = Preset(name: "full")
        let r = ShowEditApplier.apply([.clearPreset(song: nil, cue: 1, pool: .dimmer, block: nil)],
                                      to: p, defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues[0].actions[0].presets[.dimmer]?.name, "")
    }

    func testAddAndRemoveActionBlockNeverZero() {
        let r = ShowEditApplier.apply([
            .addActionBlock(song: nil, cue: 1),
            .removeActionBlock(song: nil, cue: 1, block: 0),
            .removeActionBlock(song: nil, cue: 1, block: 0)   // would empty → kept at one
        ], to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues[0].actions.count, 1)
    }

    func testCopyActions() {
        var p = base()
        p.songs[0].cues[0].actions[0].group = "SRC"
        p.songs[0].cues.append(Cue(n: 2, name: "Verse"))
        let r = ShowEditApplier.apply([.copyActions(song: nil, fromCue: 1, toCue: 2)],
                                      to: p, defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues[1].actions[0].group, "SRC")
    }

    func testSetDefaultAndStoreMode() {
        let r = ShowEditApplier.apply([
            .setDefault(pool: .dimmer, fade: "3", delay: nil),
            .setStoreMode(mode: .merge)
        ], to: base(), defaults: Defaults())
        XCTAssertEqual(r.defaults.fade(.dimmer), "3")
        XCTAssertEqual(r.project.storeMode, .merge)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CuelistCompilerKitTests/ShowEditApplierActionTests`
Expected: FAIL — action ops fall through `default: break`.

- [ ] **Step 3: Write minimal implementation**

Add a block-resolution helper beside the others:

```swift
    /// Resolve (songIdx, cueIdx, blockIdx). blockIdx defaults to 0; clamped to range.
    static func locate(_ song: String?, _ cue: Double, _ block: Int?, _ p: Project,
                       _ op: String, _ warnings: inout [String]) -> (Int, Int, Int)? {
        guard let si = songIndex(song, p) else { warn(&warnings, song, op); return nil }
        guard let ci = cueIndex(cue, si, p) else { warnCue(&warnings, cue, si, op); return nil }
        let blocks = p.songs[si].cues[ci].actions
        let bi = block ?? 0
        guard blocks.indices.contains(bi) else {
            warnings.append("Cue \(num(cue)) has no action block \(bi) — skipped \(op)"); return nil
        }
        return (si, ci, bi)
    }
```

Replace the trailing `default: break` with:

```swift
        case let .setGroup(song, cue, group, block):
            guard let (si, ci, bi) = locate(song, cue, block, p, "setGroup", &warnings) else { return }
            p.songs[si].cues[ci].actions[bi].group = group
            summary.append("Cue \(num(cue)) · group = \(group)")

        case let .setPreset(song, cue, pool, name, fade, delay, block):
            guard let (si, ci, bi) = locate(song, cue, block, p, "setPreset", &warnings) else { return }
            var preset = p.songs[si].cues[ci].actions[bi].presets[pool] ?? Preset()
            if let name { preset.name = name }
            if let fade { preset.fade = fade }
            if let delay { preset.delay = delay }
            p.songs[si].cues[ci].actions[bi].presets[pool] = preset
            let fadeNote = (fade?.isEmpty == false) ? " (fade \(fade!))" : ""
            summary.append("Cue \(num(cue)) · \(pool.rawValue) = “\(preset.name)”\(fadeNote)")

        case let .clearPreset(song, cue, pool, block):
            guard let (si, ci, bi) = locate(song, cue, block, p, "clearPreset", &warnings) else { return }
            p.songs[si].cues[ci].actions[bi].presets[pool] = Preset()
            summary.append("Cue \(num(cue)) · clear \(pool.rawValue)")

        case let .addActionBlock(song, cue):
            guard let si = songIndex(song, p) else { return warn(&warnings, song, "addActionBlock") }
            guard let ci = cueIndex(cue, si, p) else { return warnCue(&warnings, cue, si, "addActionBlock") }
            p.songs[si].cues[ci].actions.append(Action())
            summary.append("Cue \(num(cue)) · add action block")

        case let .removeActionBlock(song, cue, block):
            guard let si = songIndex(song, p) else { return warn(&warnings, song, "removeActionBlock") }
            guard let ci = cueIndex(cue, si, p) else { return warnCue(&warnings, cue, si, "removeActionBlock") }
            guard p.songs[si].cues[ci].actions.indices.contains(block) else {
                warnings.append("Cue \(num(cue)) has no action block \(block) — skipped removeActionBlock"); return
            }
            p.songs[si].cues[ci].actions.remove(at: block)
            if p.songs[si].cues[ci].actions.isEmpty { p.songs[si].cues[ci].actions.append(Action()) }
            summary.append("Cue \(num(cue)) · remove action block \(block)")

        case let .copyActions(song, fromCue, toCue):
            guard let si = songIndex(song, p) else { return warn(&warnings, song, "copyActions") }
            guard let from = cueIndex(fromCue, si, p) else { return warnCue(&warnings, fromCue, si, "copyActions") }
            guard let to = cueIndex(toCue, si, p) else { return warnCue(&warnings, toCue, si, "copyActions") }
            p.songs[si].cues[to].actions = p.songs[si].cues[from].actions
            summary.append("Copy actions from cue \(num(fromCue)) → cue \(num(toCue))")

        case let .setDefault(pool, fade, delay):
            var preset = d.values[pool] ?? Preset()
            if let fade { preset.fade = fade }
            if let delay { preset.delay = delay }
            d.values[pool] = preset
            summary.append("Default \(pool.rawValue) · fade \(preset.fade) delay \(preset.delay)")

        case let .setStoreMode(mode):
            p.storeMode = mode
            summary.append("Store mode → \(mode.rawValue)")
```

- [ ] **Step 4: Run test to verify it passes**

Run: all three applier suites:
`-only-testing:CuelistCompilerKitTests/ShowEditApplierActionTests -only-testing:CuelistCompilerKitTests/ShowEditApplierCueTests -only-testing:CuelistCompilerKitTests/ShowEditApplierSongTests`
Expected: PASS (the switch is now exhaustive; remove the trailing `default: break` if the compiler flags it as unreachable).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/ShowEditApplier.swift ios/Tests/KitTests/ShowEditApplierActionTests.swift
git commit -m "feat(ios): ShowEditApplier action/preset/defaults/project ops"
```

---

## Task 6: ProjectSnapshot — compact projection for the model

**Files:**
- Create: `ios/Sources/Kit/Voice/ProjectSnapshot.swift`
- Test: `ios/Tests/KitTests/ProjectSnapshotTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CuelistCompilerKit

final class ProjectSnapshotTests: XCTestCase {
    func testSnapshotIsCompactAndIndexed() throws {
        var cue = Cue(n: 1, name: "Intro", fade: "5")
        cue.actions = [Action(group: "1", presets: [.color: Preset(name: "Blue", fade: "5"),
                                                     .dimmer: Preset()])]
        let p = Project(songs: [Song(id: "a", name: "Opener", sequence: 666, cues: [cue])],
                        activeSongId: "a")
        let json = ProjectSnapshot.json(p)
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        XCTAssertEqual(obj["activeSong"] as? Int, 1)
        let songs = obj["songs"] as! [[String: Any]]
        XCTAssertEqual(songs[0]["index"] as? Int, 1)
        XCTAssertEqual(songs[0]["name"] as? String, "Opener")
        XCTAssertEqual(songs[0]["sequence"] as? Int, 666)
        let cues = songs[0]["cues"] as! [[String: Any]]
        XCTAssertEqual(cues[0]["n"] as? Double, 1)
        let actions = cues[0]["actions"] as! [[String: Any]]
        XCTAssertEqual(actions[0]["group"] as? String, "1")
        let presets = actions[0]["presets"] as! [String: Any]
        XCTAssertNotNil(presets["color"])         // non-empty kept
        XCTAssertNil(presets["dimmer"])           // empty preset omitted to stay small
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CuelistCompilerKitTests/ProjectSnapshotTests`
Expected: FAIL — `cannot find 'ProjectSnapshot'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ios/Sources/Kit/Voice/ProjectSnapshot.swift
import Foundation

/// A compact JSON projection of the show the LLM reads to resolve references.
/// 1-based song indices; UUIDs and empty fields omitted to keep the prompt small.
public enum ProjectSnapshot {
    public static func json(_ p: Project) -> String {
        let activeIdx = (p.songs.firstIndex { $0.id == p.activeSongId } ?? 0) + 1
        let songs: [[String: Any]] = p.songs.enumerated().map { (i, song) in
            [
                "index": i + 1,
                "name": song.name,
                "sequence": song.sequence,
                "cues": song.cues.map { cue in cueDict(cue) }
            ]
        }
        let root: [String: Any] = ["activeSong": activeIdx, "storeMode": p.storeMode.rawValue, "songs": songs]
        let data = (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func cueDict(_ cue: Cue) -> [String: Any] {
        var d: [String: Any] = ["n": cue.n]
        if !cue.name.isEmpty { d["name"] = cue.name }
        if !cue.fade.isEmpty { d["fade"] = cue.fade }
        if !cue.delay.isEmpty { d["delay"] = cue.delay }
        if !cue.position.isEmpty { d["position"] = cue.position }
        d["actions"] = cue.actions.map { actionDict($0) }
        return d
    }

    private static func actionDict(_ a: Action) -> [String: Any] {
        var presets: [String: Any] = [:]
        for pool in Pool.allCases {
            guard let preset = a.presets[pool] else { continue }
            if preset.name.isEmpty && preset.fade.isEmpty && preset.delay.isEmpty { continue }
            var pd: [String: Any] = [:]
            if !preset.name.isEmpty { pd["name"] = preset.name }
            if !preset.fade.isEmpty { pd["fade"] = preset.fade }
            if !preset.delay.isEmpty { pd["delay"] = preset.delay }
            presets[pool.rawValue] = pd
        }
        var d: [String: Any] = [:]
        if !a.group.isEmpty { d["group"] = a.group }
        if !presets.isEmpty { d["presets"] = presets }
        return d
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/ProjectSnapshot.swift ios/Tests/KitTests/ProjectSnapshotTests.swift ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): ProjectSnapshot compact projection for the LLM"
```

---

## Task 7: Transcriber + WhisperTranscriber

**Files:**
- Create: `ios/Sources/Kit/Voice/InterpretedCommand.swift`
- Create: `ios/Sources/Kit/Voice/Transcriber.swift`
- Test: `ios/Tests/KitTests/WhisperTranscriberTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CuelistCompilerKit

final class WhisperTranscriberTests: XCTestCase {
    func testBuildsMultipartAndParsesText() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            let ct = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            XCTAssertTrue(ct.hasPrefix("multipart/form-data; boundary="))
            let body = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
            XCTAssertTrue(body.contains(#"name="model""#))
            XCTAssertTrue(body.contains("whisper-1"))
            XCTAssertTrue(body.contains(#"name="file"; filename="audio.m4a""#))
            return (Data(#"{"text":"set group one to blue"}"#.utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("audio.m4a")
        try Data([0x00, 0x01, 0x02]).write(to: tmp)
        let t = WhisperTranscriber(apiKey: "sk-test", transport: mock)
        let text = try await t.transcribe(tmp)
        XCTAssertEqual(text, "set group one to blue")
    }

    func testHTTPErrorThrows() async {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            (Data(#"{"error":{"message":"bad key"}}"#.utf8),
             HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("a.m4a")
        try? Data([0x00]).write(to: tmp)
        let t = WhisperTranscriber(apiKey: "x", transport: mock)
        do { _ = try await t.transcribe(tmp); XCTFail("expected throw") }
        catch let VoiceError.api(status, _) { XCTAssertEqual(status, 401) }
        catch { XCTFail("wrong error: \(error)") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CuelistCompilerKitTests/WhisperTranscriberTests`
Expected: FAIL — `cannot find 'WhisperTranscriber'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ios/Sources/Kit/Voice/InterpretedCommand.swift
import Foundation

/// Result of interpreting one transcript: the validated edits + an optional
/// clarification question (when the model couldn't act).
public struct InterpretedCommand: Equatable, Sendable {
    public var transcript: String
    public var edits: [ShowEdit]
    public var clarification: String?
    public init(transcript: String, edits: [ShowEdit], clarification: String? = nil) {
        self.transcript = transcript; self.edits = edits; self.clarification = clarification
    }
}

/// Errors surfaced to the UI as toasts.
public enum VoiceError: Error, Equatable {
    case missingKey(String)        // which provider
    case api(status: Int, message: String)
    case emptyTranscript
    case badResponse(String)
}
```

```swift
// ios/Sources/Kit/Voice/Transcriber.swift
import Foundation

public protocol Transcriber: Sendable {
    func transcribe(_ audio: URL) async throws -> String
}

/// OpenAI Whisper (`whisper-1`) over multipart/form-data.
public struct WhisperTranscriber: Transcriber {
    private let apiKey: String
    private let transport: HTTPTransport
    public init(apiKey: String, transport: HTTPTransport = URLSessionHTTPTransport()) {
        self.apiKey = apiKey; self.transport = transport
    }

    public func transcribe(_ audio: URL) async throws -> String {
        guard !apiKey.isEmpty else { throw VoiceError.missingKey("OpenAI") }
        let boundary = "cc-\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = try multipartBody(boundary: boundary, audio: audio)

        let (data, resp) = try await transport.send(req)
        guard resp.statusCode == 200 else {
            throw VoiceError.api(status: resp.statusCode, message: String(decoding: data, as: UTF8.self))
        }
        struct R: Decodable { let text: String }
        let text = (try? JSONDecoder().decode(R.self, from: data).text) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceError.emptyTranscript
        }
        return text
    }

    private func multipartBody(boundary: String, audio: URL) throws -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        field("model", "whisper-1")
        let audioData = try Data(contentsOf: audio)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".utf8))
        body.append(Data("Content-Type: audio/m4a\r\n\r\n".utf8))
        body.append(audioData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/InterpretedCommand.swift ios/Sources/Kit/Voice/Transcriber.swift ios/Tests/KitTests/WhisperTranscriberTests.swift ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): InterpretedCommand + WhisperTranscriber (OpenAI multipart)"
```

---

## Task 8: CommandInterpreter + AnthropicInterpreter

**Files:**
- Create: `ios/Sources/Kit/Voice/CommandInterpreter.swift`
- Test: `ios/Tests/KitTests/AnthropicInterpreterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CuelistCompilerKit

final class AnthropicInterpreterTests: XCTestCase {
    private func project() -> Project {
        Project(songs: [Song(id: "a", name: "Opener", sequence: 1, cues: [Cue(n: 1)])], activeSongId: "a")
    }

    func testBuildsCachedToolRequestAndParsesEdits() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
            XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "claude-sonnet-4-6")
            XCTAssertEqual((body["tool_choice"] as? [String: Any])?["name"] as? String, "apply_show_edits")
            // system + tools carry cache_control
            let system = body["system"] as! [[String: Any]]
            XCTAssertNotNil(system.last?["cache_control"])
            let tools = body["tools"] as! [[String: Any]]
            XCTAssertNotNil(tools.last?["cache_control"])
            // transcript reached the user turn
            let messages = body["messages"] as! [[String: Any]]
            let content = messages.last?["content"] as? String ?? ""
            XCTAssertTrue(content.contains("set group 1 to blue"))

            let resp = """
            {"content":[{"type":"tool_use","name":"apply_show_edits","input":
              {"edits":[{"op":"setGroup","cue":1,"group":"1"}]}}]}
            """
            return (Data(resp.utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let interp = AnthropicInterpreter(apiKey: "sk-ant", transport: mock)
        let cmd = try await interp.interpret(transcript: "set group 1 to blue",
                                             project: project(), defaults: Defaults())
        XCTAssertEqual(cmd.edits, [.setGroup(song: nil, cue: 1, group: "1", block: nil)])
        XCTAssertNil(cmd.clarification)
    }

    func testParsesClarification() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            let resp = """
            {"content":[{"type":"tool_use","name":"apply_show_edits","input":
              {"edits":[],"clarification":"Which song?"}}]}
            """
            return (Data(resp.utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let interp = AnthropicInterpreter(apiKey: "sk-ant", transport: mock)
        let cmd = try await interp.interpret(transcript: "do the thing", project: project(), defaults: Defaults())
        XCTAssertTrue(cmd.edits.isEmpty)
        XCTAssertEqual(cmd.clarification, "Which song?")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CuelistCompilerKitTests/AnthropicInterpreterTests`
Expected: FAIL — `cannot find 'AnthropicInterpreter'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ios/Sources/Kit/Voice/CommandInterpreter.swift
import Foundation

public protocol CommandInterpreter: Sendable {
    func interpret(transcript: String, project: Project, defaults: Defaults) async throws -> InterpretedCommand
}

/// Anthropic Messages API with forced tool-use. The system prompt + tool schema
/// are cached (cache_control: ephemeral); only the project snapshot + transcript vary.
public struct AnthropicInterpreter: CommandInterpreter {
    private let apiKey: String
    private let model: String
    private let transport: HTTPTransport

    public init(apiKey: String, model: String = "claude-sonnet-4-6",
                transport: HTTPTransport = URLSessionHTTPTransport()) {
        self.apiKey = apiKey; self.model = model; self.transport = transport
    }

    public func interpret(transcript: String, project: Project, defaults: Defaults) async throws -> InterpretedCommand {
        guard !apiKey.isEmpty else { throw VoiceError.missingKey("Anthropic") }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let user = """
        Current show (JSON):
        \(ProjectSnapshot.json(project))

        Spoken command:
        \(transcript)
        """
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "tool_choice": ["type": "tool", "name": "apply_show_edits"],
            "system": [[
                "type": "text",
                "text": Self.systemPrompt,
                "cache_control": ["type": "ephemeral"]
            ]],
            "tools": [Self.tool],   // tool dict carries cache_control (see below)
            "messages": [["role": "user", "content": user]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await transport.send(req)
        guard resp.statusCode == 200 else {
            throw VoiceError.api(status: resp.statusCode, message: String(decoding: data, as: UTF8.self))
        }
        return try Self.parse(data, transcript: transcript)
    }

    /// Pull the apply_show_edits tool_use input out of the response and decode it.
    static func parse(_ data: Data, transcript: String) throws -> InterpretedCommand {
        struct Resp: Decodable {
            struct Block: Decodable { let type: String; let name: String?; let input: ToolInput? }
            let content: [Block]
        }
        guard let resp = try? JSONDecoder().decode(Resp.self, from: data),
              let input = resp.content.first(where: { $0.type == "tool_use" && $0.name == "apply_show_edits" })?.input
        else { throw VoiceError.badResponse(String(decoding: data, as: UTF8.self)) }
        return InterpretedCommand(transcript: transcript, edits: input.edits, clarification: input.clarification)
    }

    // MARK: prompt + tool schema

    static let systemPrompt = """
    You convert a lighting operator's spoken command into edits on a grandMA3 cue \
    list, by calling the apply_show_edits tool. Never reply in prose.

    Domain:
    - A show has SONGS (1-based index, a name, an integer sequence number).
    - Each song has CUES, addressed by their number `n` (may be fractional, e.g. 0.1, 1, 2).
    - Each cue has one or more ACTION BLOCKS; each block has a `group` and up to six \
    POOL presets. The six pools are: color, dimmer, position, gobo, beam, focus. \
    Each preset has a name, a fade, and a delay (all strings).
    - There are per-pool DEFAULT fade/delay, and a store mode (Overwrite or Merge).

    Reference rules:
    - `song` may be a 1-based ordinal ("2") or a name; omit it to mean the active song.
    - `cue` is the cue number `n`. `pool` is one of the six names. `block` defaults to 0.
    - Fades/delays are strings of seconds ("5"). Group is a string ("1", "A", "AROLLA FLOOR").

    Emit the smallest set of edits that satisfies the command. Only touch what was \
    asked. If the command is ambiguous, unsupported, or you cannot identify the target, \
    return an empty edits array and set `clarification` to a one-sentence question. \
    Otherwise omit clarification.

    Examples:
    - "in the intro cue set group one to deep blue with a five second fade and dimmer to full"
      → setGroup(cue:1, group:"1"); setPreset(cue:1, pool:"color", name:"Deep Blue", fade:"5"); \
    setPreset(cue:1, pool:"dimmer", name:"full")
    - "add a chorus cue" → addCue(name:"chorus")
    - "rename the second song to finale" → renameSong(song:"2", name:"finale")
    - "make song two sequence twelve" → setSequence(song:"2", sequence:12)
    """

    /// The single tool; its input_schema IS the ShowEdit vocabulary. cache_control on
    /// the tool dict marks the cached prefix boundary (system + tools).
    static let tool: [String: Any] = [
        "name": "apply_show_edits",
        "description": "Apply a list of validated edits to the show, or ask for clarification.",
        "cache_control": ["type": "ephemeral"],
        "input_schema": [
            "type": "object",
            "properties": [
                "clarification": ["type": "string",
                                  "description": "A one-sentence question; set ONLY when edits is empty."],
                "edits": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "required": ["op"],
                        "properties": [
                            "op": ["type": "string", "enum": [
                                "addSong", "renameSong", "setSequence", "selectSong", "deleteSong",
                                "addCue", "setCue", "deleteCue", "sortCues",
                                "setGroup", "setPreset", "clearPreset",
                                "addActionBlock", "removeActionBlock", "copyActions",
                                "setDefault", "setStoreMode"
                            ]],
                            "song": ["type": "string"],
                            "name": ["type": "string"],
                            "sequence": ["type": "integer"],
                            "cue": ["type": "number"],
                            "n": ["type": "number"],
                            "fade": ["type": "string"],
                            "delay": ["type": "string"],
                            "position": ["type": "string"],
                            "field": ["type": "string", "enum": ["name", "fade", "delay", "position", "number"]],
                            "value": ["type": "string"],
                            "group": ["type": "string"],
                            "block": ["type": "integer"],
                            "pool": ["type": "string",
                                     "enum": ["color", "dimmer", "position", "gobo", "beam", "focus"]],
                            "fromCue": ["type": "number"],
                            "toCue": ["type": "number"],
                            "mode": ["type": "string", "enum": ["Overwrite", "Merge"]]
                        ]
                    ]
                ]
            ],
            "required": ["edits"]
        ]
    ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/CommandInterpreter.swift ios/Tests/KitTests/AnthropicInterpreterTests.swift ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): AnthropicInterpreter (tool-use + prompt caching, Sonnet 4.6)"
```

---

## Task 9: AIKeyStore (Keychain)

**Files:**
- Create: `ios/Sources/Kit/Voice/AIKeyStore.swift`
- Test: `ios/Tests/KitTests/AIKeyStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CuelistCompilerKit

final class AIKeyStoreTests: XCTestCase {
    func testInMemoryRoundTrip() {
        let s = InMemoryAIKeyStore()
        XCTAssertNil(s.key(for: .openAI))
        s.set("sk-o", for: .openAI)
        s.set("sk-a", for: .anthropic)
        XCTAssertEqual(s.key(for: .openAI), "sk-o")
        XCTAssertEqual(s.key(for: .anthropic), "sk-a")
        s.set("", for: .openAI)                 // empty clears
        XCTAssertNil(s.key(for: .openAI))
    }

    func testKeychainRoundTrip() {
        let svc = "cc-test-\(UUID().uuidString)"
        let s = KeychainAIKeyStore(service: svc)
        s.set("sk-keychain", for: .anthropic)
        XCTAssertEqual(s.key(for: .anthropic), "sk-keychain")
        s.set("", for: .anthropic)
        XCTAssertNil(s.key(for: .anthropic))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CuelistCompilerKitTests/AIKeyStoreTests`
Expected: FAIL — `cannot find 'InMemoryAIKeyStore'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ios/Sources/Kit/Voice/AIKeyStore.swift
import Foundation
import Security

public enum AIProvider: String, Sendable, CaseIterable { case openAI, anthropic }

public protocol AIKeyStore: AnyObject, Sendable {
    func key(for provider: AIProvider) -> String?
    func set(_ value: String, for provider: AIProvider)
}

/// Non-persistent store for tests and previews.
public final class InMemoryAIKeyStore: AIKeyStore, @unchecked Sendable {
    private var store: [AIProvider: String] = [:]
    public init() {}
    public func key(for provider: AIProvider) -> String? { store[provider] }
    public func set(_ value: String, for provider: AIProvider) {
        if value.isEmpty { store[provider] = nil } else { store[provider] = value }
    }
}

/// Keychain-backed store. One generic-password item per provider.
public final class KeychainAIKeyStore: AIKeyStore, @unchecked Sendable {
    private let service: String
    public init(service: String = "com.blearred.cuelistcompiler.keys") { self.service = service }

    public func key(for provider: AIProvider) -> String? {
        var q = baseQuery(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty
        else { return nil }
        return s
    }

    public func set(_ value: String, for provider: AIProvider) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
        guard !value.isEmpty else { return }
        var q = baseQuery(provider)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    private func baseQuery(_ provider: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS. (If the Keychain test fails in the sim with `errSecMissingEntitlement`, keep the `InMemory` test and mark the Keychain one `XCTSkip` with a note that it is covered by the Task 16 device smoke.)

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/AIKeyStore.swift ios/Tests/KitTests/AIKeyStoreTests.swift ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): AIKeyStore (Keychain + in-memory)"
```

---

## Task 10: ProjectStore.apply(ApplyResult)

**Files:**
- Modify: `ios/Sources/Kit/Store/ProjectStore+Mutations.swift` (add one method to the existing `extension ProjectStore`)
- Test: `ios/Tests/KitTests/ProjectStoreApplyTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CuelistCompilerKit

@MainActor
final class ProjectStoreApplyTests: XCTestCase {
    func testApplyCommitsProjectAndDefaults() {
        let store = ProjectStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
        var p = Project.empty(); p.songs[0].name = "From Voice"
        var d = Defaults(); d.values[.dimmer] = Preset(fade: "9")
        let result = ApplyResult(project: p, defaults: d, summary: [], warnings: [])
        store.apply(result)
        XCTAssertEqual(store.project.songs[0].name, "From Voice")
        XCTAssertEqual(store.defaults.fade(.dimmer), "9")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CuelistCompilerKitTests/ProjectStoreApplyTests`
Expected: FAIL — `value of type 'ProjectStore' has no member 'apply'`.

- [ ] **Step 3: Write minimal implementation**

Append to the existing `public extension ProjectStore` in `ProjectStore+Mutations.swift`:

```swift
    /// Commit a precomputed voice-edit result (project + defaults) in one shot.
    /// Triggers the store's normal debounced save via the `project`/`defaults` didSet.
    func apply(_ result: ApplyResult) {
        project = result.project
        defaults = result.defaults
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Store/ProjectStore+Mutations.swift ios/Tests/KitTests/ProjectStoreApplyTests.swift
git commit -m "feat(ios): ProjectStore.apply(ApplyResult) commit hook"
```

---

## Task 11: AudioRecorder protocol + VoiceCaptureController

**Files:**
- Create: `ios/Sources/Kit/Voice/AudioRecorder.swift`
- Create: `ios/Sources/Kit/Voice/VoiceCaptureController.swift`
- Test: `ios/Tests/KitTests/VoiceCaptureControllerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CuelistCompilerKit

@MainActor
final class VoiceCaptureControllerTests: XCTestCase {

    final class MockRecorder: AudioRecorder, @unchecked Sendable {
        var permission = true
        var fileToReturn: URL? = FileManager.default.temporaryDirectory.appendingPathComponent("x.m4a")
        private(set) var started = false
        func requestPermission() async -> Bool { permission }
        func start() throws { started = true }
        func stop() async -> URL? { started = false; return fileToReturn }
    }
    struct StubTranscriber: Transcriber { let text: String
        func transcribe(_ audio: URL) async throws -> String { text } }
    struct StubInterpreter: CommandInterpreter { let cmd: InterpretedCommand
        func interpret(transcript: String, project: Project, defaults: Defaults) async throws -> InterpretedCommand { cmd } }

    private func make(_ transcriber: Transcriber, _ interp: CommandInterpreter, _ rec: MockRecorder = MockRecorder())
        -> VoiceCaptureController {
        VoiceCaptureController(recorder: rec, transcriber: transcriber, interpreter: interp)
    }

    func testHappyPathProducesPendingPreview() async {
        let interp = StubInterpreter(cmd: InterpretedCommand(
            transcript: "set group 1 to blue",
            edits: [.setGroup(song: nil, cue: 1, group: "1", block: nil)]))
        let c = make(StubTranscriber(text: "set group 1 to blue"), interp)
        var p = Project.empty(); p.songs[0].cues = [Cue(n: 1)]
        await c.startRecording()
        await c.stopAndProcess(project: p, defaults: Defaults())
        guard case .preview = c.phase else { return XCTFail("expected preview, got \(c.phase)") }
        XCTAssertEqual(c.pending?.transcript, "set group 1 to blue")
        XCTAssertEqual(c.pending?.summary, ["Cue 1 · group = 1"])
        XCTAssertEqual(c.pending?.result.project.songs[0].cues[0].actions[0].group, "1")
    }

    func testTranscribeErrorGoesToError() async {
        struct Boom: Transcriber { func transcribe(_ u: URL) async throws -> String { throw VoiceError.emptyTranscript } }
        let c = make(Boom(), StubInterpreter(cmd: InterpretedCommand(transcript: "", edits: [])))
        await c.startRecording()
        await c.stopAndProcess(project: Project.empty(), defaults: Defaults())
        guard case .error = c.phase else { return XCTFail("expected error, got \(c.phase)") }
    }

    func testClarificationShowsPreviewWithNoEdits() async {
        let interp = StubInterpreter(cmd: InterpretedCommand(transcript: "do it", edits: [], clarification: "Which song?"))
        let c = make(StubTranscriber(text: "do it"), interp)
        await c.startRecording()
        await c.stopAndProcess(project: Project.empty(), defaults: Defaults())
        guard case .preview = c.phase else { return XCTFail("expected preview") }
        XCTAssertEqual(c.pending?.clarification, "Which song?")
        XCTAssertTrue(c.pending?.summary.isEmpty ?? false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CuelistCompilerKitTests/VoiceCaptureControllerTests`
Expected: FAIL — `cannot find 'AudioRecorder'` / `'VoiceCaptureController'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ios/Sources/Kit/Voice/AudioRecorder.swift
import Foundation

/// Records mic audio to a file. Concrete AVFoundation impl lives in the app;
/// tests inject a mock.
@MainActor public protocol AudioRecorder: AnyObject {
    func requestPermission() async -> Bool
    func start() throws
    func stop() async -> URL?
}
```

```swift
// ios/Sources/Kit/Voice/VoiceCaptureController.swift
import Foundation
import Observation

@MainActor @Observable
public final class VoiceCaptureController {

    /// What the preview sheet renders.
    public struct Pending: Equatable, Sendable {
        public var transcript: String
        public var summary: [String]
        public var warnings: [String]
        public var clarification: String?
        public var result: ApplyResult
        public var canApply: Bool { clarification == nil && !result.summary.isEmpty }
    }

    public enum Phase: Equatable {
        case idle, recording, transcribing, interpreting, preview, error(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var pending: Pending?

    @ObservationIgnored private let recorder: AudioRecorder
    @ObservationIgnored private let transcriber: Transcriber
    @ObservationIgnored private let interpreter: CommandInterpreter

    public init(recorder: AudioRecorder, transcriber: Transcriber, interpreter: CommandInterpreter) {
        self.recorder = recorder; self.transcriber = transcriber; self.interpreter = interpreter
    }

    public func startRecording() async {
        guard await recorder.requestPermission() else { phase = .error("Microphone access denied"); return }
        do { try recorder.start(); phase = .recording }
        catch { phase = .error("Couldn't start recording") }
    }

    public func stopAndProcess(project: Project, defaults: Defaults) async {
        guard let audio = await recorder.stop() else { phase = .error("No audio captured"); return }
        do {
            phase = .transcribing
            let transcript = try await transcriber.transcribe(audio)
            phase = .interpreting
            let cmd = try await interpreter.interpret(transcript: transcript, project: project, defaults: defaults)
            let result = ShowEditApplier.apply(cmd.edits, to: project, defaults: defaults)
            pending = Pending(transcript: transcript, summary: result.summary, warnings: result.warnings,
                              clarification: cmd.clarification, result: result)
            phase = .preview
        } catch let VoiceError.api(status, _) {
            phase = .error("Service error (\(status))")
        } catch VoiceError.emptyTranscript {
            phase = .error("Didn't catch that — try again")
        } catch let VoiceError.missingKey(p) {
            phase = .error("Add your \(p) API key in Settings")
        } catch {
            phase = .error("Couldn't interpret that — try rephrasing")
        }
    }

    public func cancel() { phase = .idle; pending = nil }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/AudioRecorder.swift ios/Sources/Kit/Voice/VoiceCaptureController.swift ios/Tests/KitTests/VoiceCaptureControllerTests.swift ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): AudioRecorder protocol + VoiceCaptureController state machine"
```

---

## Task 12: AVAudioFileRecorder (concrete) + mic permission

**Files:**
- Create: `ios/Sources/App/AVAudioFileRecorder.swift`
- Modify: `ios/project.yml` (add `NSMicrophoneUsageDescription`)

This task is app-only (AVFoundation) — verify by **building the app target**, not unit tests.

- [ ] **Step 1: Add the mic usage string**

In `ios/project.yml`, under `targets: CuelistCompiler: info: properties:`, add alongside the existing keys:

```yaml
        NSMicrophoneUsageDescription: "Cuelist Compiler records short voice commands to author cues."
```

- [ ] **Step 2: Implement the recorder**

```swift
// ios/Sources/App/AVAudioFileRecorder.swift
import Foundation
import AVFoundation
import CuelistCompilerKit

/// Concrete AudioRecorder backed by AVAudioRecorder. Records ~AAC m4a to a temp file.
@MainActor
final class AVAudioFileRecorder: AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.record()
        recorder = rec; fileURL = url
    }

    func stop() async -> URL? {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        return fileURL
    }
}
```

- [ ] **Step 3: Regenerate + build the app**

Run: `cd ios && xcodegen generate && xcodebuild build -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/AVAudioFileRecorder.swift ios/project.yml ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): AVAudioFileRecorder + mic usage description"
```

---

## Task 13: VoicePreviewSheet

**Files:**
- Create: `ios/Sources/App/VoicePreviewSheet.swift`

App-only SwiftUI — verify by building the app target.

- [ ] **Step 1: Implement the sheet**

```swift
// ios/Sources/App/VoicePreviewSheet.swift
import SwiftUI
import CuelistCompilerKit

/// Renders a VoiceCaptureController.Pending: transcript + change summary + warnings,
/// with Apply / Discard. Apply is disabled for clarification-only results.
struct VoicePreviewSheet: View {
    let pending: VoiceCaptureController.Pending
    let onApply: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Heard") { Text("“\(pending.transcript)”").italic() }

                if let q = pending.clarification {
                    Section("Needs clarification") {
                        Label(q, systemImage: "questionmark.circle").foregroundStyle(.orange)
                    }
                }

                if !pending.summary.isEmpty {
                    Section("Will change") {
                        ForEach(Array(pending.summary.enumerated()), id: \.offset) { _, line in
                            Label(line, systemImage: "pencil")
                        }
                    }
                }

                if !pending.warnings.isEmpty {
                    Section("Skipped") {
                        ForEach(Array(pending.warnings.enumerated()), id: \.offset) { _, w in
                            Label(w, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Voice command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Discard", role: .cancel, action: onDiscard) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: onApply).disabled(!pending.canApply).bold()
                }
            }
        }
    }
}
```

- [ ] **Step 2: Regenerate + build the app**

Run: `cd ios && xcodegen generate && xcodebuild build -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/Sources/App/VoicePreviewSheet.swift ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): VoicePreviewSheet (transcript + summary + warnings)"
```

---

## Task 14: Settings — API key fields

**Files:**
- Modify: `ios/Sources/App/SettingsView.swift`

App-only — verify by building the app target.

- [ ] **Step 1: Add key fields wired to the Keychain**

Replace the contents of `SettingsView.swift` with (keeps the existing Hub section, adds a Keys section):

```swift
import SwiftUI
import CuelistCompilerKit

struct SettingsView: View {
    @Environment(HubClient.self) private var hub
    @Environment(\.dismiss) private var dismiss

    private let keyStore = KeychainAIKeyStore()
    @State private var openAIKey = ""
    @State private var anthropicKey = ""

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
                Section("Voice (API keys)") {
                    SecureField("OpenAI API key", text: $openAIKey)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    SecureField("Anthropic API key", text: $anthropicKey)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                } footer: {
                    Text("Stored in your device Keychain. Voice commands send audio to OpenAI and the show context to Anthropic over HTTPS.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveKeys(); dismiss() }
                }
            }
            .onAppear {
                openAIKey = keyStore.key(for: .openAI) ?? ""
                anthropicKey = keyStore.key(for: .anthropic) ?? ""
            }
        }
    }

    private func saveKeys() {
        keyStore.set(openAIKey, for: .openAI)
        keyStore.set(anthropicKey, for: .anthropic)
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

- [ ] **Step 2: Regenerate + build the app**

Run: `cd ios && xcodegen generate && xcodebuild build -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/Sources/App/SettingsView.swift
git commit -m "feat(ios): Settings — OpenAI + Anthropic key fields (Keychain)"
```

---

## Task 15: Wire the mic into App + RootView

**Files:**
- Modify: `ios/Sources/App/App.swift`
- Modify: `ios/Sources/App/RootView.swift`

App-only — verify by building the app target.

- [ ] **Step 1: Build + inject the controller in App.swift**

Replace `App.swift` with:

```swift
import SwiftUI
import CuelistCompilerKit

@main
struct CuelistCompilerApp: App {
    @State private var store = ProjectStore()
    @State private var hub = HubClient(makeConnection: { url in
        URLSessionWebSocketConnection(url: url)
    })
    @State private var voice = VoiceCaptureController(
        recorder: AVAudioFileRecorder(),
        transcriber: WhisperTranscriber(apiKey: KeychainAIKeyStore().key(for: .openAI) ?? ""),
        interpreter: AnthropicInterpreter(apiKey: KeychainAIKeyStore().key(for: .anthropic) ?? "")
    )
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(hub)
                .environment(voice)
                .onAppear { if !hub.host.isEmpty { hub.connect() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveNow() }
        }
    }
}
```

> Note: keys are read once at launch. After entering keys in Settings the first time, the operator relaunches the app (documented in the Task 16 smoke). A live key refresh is deferred per spec §10.

- [ ] **Step 2: Add the mic button + preview sheet in RootView.swift**

Replace `RootView.swift` with:

```swift
import SwiftUI
import CuelistCompilerKit

struct RootView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(VoiceCaptureController.self) private var voice
    @State private var showSettings = false
    @State private var showDefaults = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SongBarView()
                CueListView()
                SendBarView()
            }
            .navigationTitle("Cuelist Compiler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { micButton }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Defaults…") { showDefaults = true }
                        Button("Settings…") { showSettings = true }
                    } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
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
        }
    }

    @ViewBuilder private var micButton: some View {
        switch voice.phase {
        case .idle, .error:
            Button { Task { await voice.startRecording() } } label: { Image(systemName: "mic") }
        case .recording:
            Button {
                Task { await voice.stopAndProcess(project: store.project, defaults: store.defaults) }
            } label: { Image(systemName: "stop.circle.fill").foregroundStyle(.red) }
        case .transcribing, .interpreting:
            ProgressView()
        case .preview:
            Image(systemName: "mic").foregroundStyle(.secondary)
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

- [ ] **Step 3: Regenerate + build the app**

Run: `cd ios && xcodegen generate && xcodebuild build -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the full Kit test suite (no regressions)**

Run: `cd ios && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: all tests PASS (existing 35 + the new voice suites).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/App/App.swift ios/Sources/App/RootView.swift ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): wire voice capture into App + RootView (mic button + preview sheet)"
```

---

## Task 16: Manual device smoke

**Files:** none (manual verification on a physical iPhone, mirroring the Plan B Task 16 smoke).

This is the only end-to-end proof that the real OpenAI + Anthropic calls work; unit tests cover everything behind mocks.

- [ ] **Step 1: Install on jPhone (2)**

Run:
```bash
cd ios && xcodegen generate
xcodebuild -project CuelistCompiler.xcodeproj -scheme CuelistCompiler -configuration Debug \
  -destination 'id=7DF307B3-6B1F-5CB1-8793-5DB9437E7FF8' -derivedDataPath /tmp/cc-voice -allowProvisioningUpdates build
xcrun devicectl device install app --device 7DF307B3-6B1F-5CB1-8793-5DB9437E7FF8 \
  /tmp/cc-voice/Build/Products/Debug-iphoneos/CuelistCompiler.app
```
Expected: `App installed`.

- [ ] **Step 2: Enter keys + relaunch**

In the app: **Settings (gear) → Voice** → paste your OpenAI and Anthropic keys → **Done**. Force-quit and relaunch (keys are read at launch). Accept the mic permission prompt on first record.

- [ ] **Step 3: Run a command**

Make sure there's at least one song with a cue (the app starts with one empty song — add a cue if needed). Tap the **mic**, say *"In cue one set group one to deep blue with a five second fade, and dimmer to full,"* tap **stop**. Confirm the preview sheet shows the transcript and a "Will change" list (group = 1; color = Deep Blue (fade 5); dimmer = full). Tap **Apply** and confirm the cue card now shows those values.

- [ ] **Step 4: Try a clarification path**

Tap mic, say something vague like *"make it better,"* stop. Confirm the sheet shows a clarification question and **Apply is disabled**. Discard.

- [ ] **Step 5: Record the result**

Record pass/issues in the Cuelist Compiler memory topic (mirror the Plan B Task 16 entry). If the send-to-MA path is desired afterward, the existing "Send → MA" flow is unchanged.

---

## Self-Review

**Spec coverage:** §2 decisions → Tasks 7 (Whisper), 8 (Anthropic phone-direct + caching + Sonnet), 9 (Keychain), 11/13 (preview+confirm), 2–5 (Approach A op list). §3 components → all created in the mapped files. §4 op vocabulary → Tasks 2 (decode) + 3–5 (apply), every op covered. §5 safety contract → Task 11 (`Pending.result` precomputed) + Task 15 (`store.apply(pending.result)` on Apply) + `canApply` gating clarification. §6 Anthropic → Task 8 (system+tools `cache_control`, forced `tool_choice`, `claude-sonnet-4-6`, snapshot). §7 security → Task 9 + 14 + footer note + Task 12 mic string. §8 error matrix → Task 11 error mapping + Task 15 alert + Task 14 key entry. §9 testing → every Kit task is TDD; §10 scope (one-shot, no model picker, no live key refresh) honored (Task 15 note). 

**Placeholder scan:** no TBD/TODO; all steps carry real code and exact commands.

**Type consistency:** `ApplyResult`, `ShowEdit`, `CueField`, `Pool`, `ToolInput`, `InterpretedCommand`, `VoiceError`, `AIProvider`, `Pending`, `Phase` used identically across tasks; `ShowEditApplier.apply(_:to:defaults:)`, `ProjectStore.apply(_:)`, `VoiceCaptureController(recorder:transcriber:interpreter:)`, `startRecording()`, `stopAndProcess(project:defaults:)` signatures match between definition and call sites; `MockHTTPTransport` defined in Task 1 reused in Tasks 7–8.

**Note on `Project` initializer:** tasks construct `Project(songs:activeSongId:)` (storeMode defaults to `.overwrite`) — matches the existing `Project.init`.
