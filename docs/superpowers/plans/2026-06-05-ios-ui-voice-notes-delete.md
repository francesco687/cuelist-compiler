# iOS UI: bottom talk bar, safe cue-delete, cue notes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the iPhone app, move voice to a big aqua bottom talk bar, make cue deletion mis-tap-proof with confirmation, and let the operator attach notes to cues by text or voice via a light LLM pass.

**Architecture:** Three independently-committable slices (A delete-fix → B talk bar → C notes). The voice *interpret* pipeline is untouched — the talk bar is a new front-end for the existing `VoiceCaptureController`. Notes ride a new, separate `AnthropicNoteRouter` (same forced-tool-use shape as `AnthropicInterpreter`) and an additive `notes` field on `Cue`. Testable logic lives in `CuelistCompilerKit` (covered by `CuelistCompilerKitTests`); SwiftUI views in the App target are verified by build + device smoke (there is no App test target).

**Tech Stack:** Swift 5.9, SwiftUI, `@Observable`, Swift `@MainActor`, XCTest, xcodegen, Anthropic Messages API (forced tool-use), OpenAI Whisper transcription.

**Reference spec:** `docs/superpowers/specs/2026-06-05-ios-ui-voice-notes-delete-design.md`

---

## File Structure

**Slice A — Safe cue delete**
- Modify `ios/Sources/App/CueCardView.swift` — remove header trash; add expanded-footer Delete + `confirmationDialog`.

**Slice B — Bottom aqua talk bar**
- Modify `ios/Sources/App/Theme.swift` (lives in the App target) — add `Theme.aqua` + `aquaGradient` + `aquaTint`.
- Modify `ios/Sources/Kit/Voice/VoiceCaptureController.swift` — add a presentation helper `Phase.talkBarLabel` + `Phase.isRecording`/`isBusy` (pure, testable in Kit).
- Create `ios/Sources/App/TalkBarView.swift` — the aqua bar; reads `voice.phase`.
- Modify `ios/Sources/App/RootView.swift` — remove the toolbar mic; add `TalkBarView()` at the bottom.
- Test: `ios/Tests/KitTests/TalkBarLabelTests.swift`.

**Slice C — Cue notes**
- Modify `ios/Sources/Kit/Models/Cue.swift` — add `notes: String`.
- Create `ios/Sources/Kit/Voice/NoteRouter.swift` — `NoteEdit`, `NoteInterpreter`, `AnthropicNoteRouter`.
- Modify `ios/Sources/Kit/Store/ProjectStore+Mutations.swift` — `applyNotes(_:)` + `appendNote(cueN:text:)`.
- Create `ios/Sources/Kit/Voice/NotesCaptureController.swift` — record→transcribe→route, `@Observable`.
- Create `ios/Sources/App/NotesCaptureView.swift` — sheet: text field + mic + routing preview.
- Modify `ios/Sources/App/CueCardView.swift` — per-cue ✎ Note button (expanded footer) + note line display.
- Modify `ios/Sources/App/SendBarView.swift` — global ✎ Notes button.
- Modify `ios/Sources/App/RootView.swift` — present the global notes sheet.
- Modify `ios/Sources/App/App.swift` — construct `NotesCaptureController` + inject.
- Tests: `ios/Tests/KitTests/CueNotesCodecTests.swift`, `ProjectStoreNotesTests.swift`, `NoteRouterTests.swift`.

**Run commands (used throughout):**

- Kit tests:
  ```bash
  cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
  ```
- App build (views — no App test target, so build is the gate):
  ```bash
  cd ios && xcodegen generate && xcodebuild build -scheme CuelistCompiler \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
  ```

> **xcodegen note:** any time a *new* file is added under `Sources/` or `Tests/`, run `xcodegen generate` before building so the `.xcodeproj` picks it up. The run commands above already do this.

---

## SLICE A — Safe cue delete

### Task A1: Move cue delete out of the collapsed header into a confirmed expanded-footer action

**Files:**
- Modify: `ios/Sources/App/CueCardView.swift`

This is App-target view code; there is no App unit-test target, so it's verified by build + device smoke. Make the change precisely.

- [ ] **Step 1: Remove the trash button from the header**

In `ios/Sources/App/CueCardView.swift`, the header `Button`'s `HStack` currently contains a destructive trash button between the `Spacer` and the chevron. Delete these lines:

```swift
                    Button(role: .destructive) {
                        store.removeCue(id: cue.id)
                    } label: { Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Theme.danger) }
                    .buttonStyle(.plain)
```

The header `HStack` should now read: `CueBadge` · `TextField` · `Spacer(minLength: 4)` · chevron `Image`.

- [ ] **Step 2: Add delete-confirmation state**

Add a `@State` property near the top of `CueCardView` (next to `@Binding var cue: Cue`):

```swift
    @State private var confirmingDelete = false
```

- [ ] **Step 3: Add the expanded-footer Delete button**

In the `else` (expanded) branch, the last element today is the Fade/Delay `HStack`. Immediately after that `HStack` (still inside the `else` block), add a trailing-aligned Delete button:

```swift
                HStack {
                    Spacer()
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete cue", systemImage: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.danger)
                            .padding(.vertical, 6).padding(.horizontal, 11)
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                .strokeBorder(Theme.danger.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
```

- [ ] **Step 4: Attach the confirmation dialog**

Add this modifier to the outer `VStack` in `body` (the one ending with `.padding(13)` / `.cardSurface()`), placed right before `.padding(13)`:

```swift
        .confirmationDialog("Delete cue \(cueLabel)?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.removeCue(id: cue.id) }
            Button("Cancel", role: .cancel) { }
        }
```

And add a small computed helper inside `CueCardView` (used by the title) so the dialog reads naturally whether or not the cue is named:

```swift
    private var cueLabel: String {
        let name = cue.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "\(formatN(cue.n))" : "\(formatN(cue.n)) “\(name)”"
    }
    private func formatN(_ n: Double) -> String {
        n.rounded() == n ? String(Int(n)) : String(n)
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run:
```bash
cd ios && xcodegen generate && xcodebuild build -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: `** BUILD SUCCEEDED **`. (Collapsed cards now show only the chevron; expanding a cue reveals "Delete cue" which prompts a confirmation dialog.)

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/App/CueCardView.swift
git commit -m "fix(ios): move cue delete to confirmed expanded-footer action

Collapsed cards show only the chevron — the trash no longer sits next
to the expand target. Delete lives in the expanded card footer and
prompts a confirmationDialog before removing the cue."
```

---

## SLICE B — Bottom aqua talk bar

### Task B1: Add the aqua theme tokens

**Files:**
- Modify: `ios/Sources/App/Theme.swift`

- [ ] **Step 1: Add aqua color + gradient**

In `ios/Sources/App/Theme.swift`, after the accent block (after `accentTint`), add:

```swift
    // Aqua — the iOS "capture/voice" accent (talk bar, notes). Distinct from the
    // violet→blue accent, which stays the "commit to MA" action. Tunable hex.
    static let aqua = Color(hex: "#21D4C4")!
    static var aquaGradient: RadialGradient {
        RadialGradient(colors: [Color(hex: "#3DF0DC")!, Color(hex: "#16C6B4")!],
                       center: UnitPoint(x: 0.38, y: 0.28), startRadius: 2, endRadius: 220)
    }
    static let aquaTint = Color(hex: "#21D4C4")!.opacity(0.10)
```

- [ ] **Step 2: Build to verify**

Run:
```bash
cd ios && xcodebuild build -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/Sources/App/Theme.swift
git commit -m "feat(ios): add aqua theme tokens for voice/notes accent"
```

### Task B2: Add a testable talk-bar presentation helper on `VoiceCaptureController.Phase`

**Files:**
- Modify: `ios/Sources/Kit/Voice/VoiceCaptureController.swift`
- Test: `ios/Tests/KitTests/TalkBarLabelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/KitTests/TalkBarLabelTests.swift`:

```swift
import XCTest
@testable import CuelistCompilerKit

final class TalkBarLabelTests: XCTestCase {
    typealias Phase = VoiceCaptureController.Phase

    func testLabels() {
        XCTAssertEqual(Phase.idle.talkBarLabel, "Tap to talk")
        XCTAssertEqual(Phase.error("x").talkBarLabel, "Tap to talk")
        XCTAssertEqual(Phase.recording.talkBarLabel, "Listening… tap to stop")
        XCTAssertEqual(Phase.transcribing.talkBarLabel, "Thinking…")
        XCTAssertEqual(Phase.interpreting.talkBarLabel, "Thinking…")
        XCTAssertEqual(Phase.preview.talkBarLabel, "Reviewing…")
    }

    func testFlags() {
        XCTAssertTrue(Phase.recording.isRecording)
        XCTAssertFalse(Phase.idle.isRecording)
        XCTAssertTrue(Phase.transcribing.isBusy)
        XCTAssertTrue(Phase.interpreting.isBusy)
        XCTAssertFalse(Phase.idle.isBusy)
        XCTAssertFalse(Phase.recording.isBusy)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20
```
Expected: FAIL — `value of type 'VoiceCaptureController.Phase' has no member 'talkBarLabel'`.

- [ ] **Step 3: Add the helper**

In `ios/Sources/Kit/Voice/VoiceCaptureController.swift`, add this extension at the bottom of the file (after the class):

```swift
public extension VoiceCaptureController.Phase {
    /// Label for the bottom talk bar. Pure presentation — kept in Kit so it's testable.
    var talkBarLabel: String {
        switch self {
        case .idle, .error:                 return "Tap to talk"
        case .recording:                    return "Listening… tap to stop"
        case .transcribing, .interpreting:  return "Thinking…"
        case .preview:                      return "Reviewing…"
        }
    }
    var isRecording: Bool { if case .recording = self { return true } else { return false } }
    var isBusy: Bool {
        switch self { case .transcribing, .interpreting: return true; default: return false }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd ios && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20
```
Expected: PASS (TalkBarLabelTests green, all other tests still green).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/VoiceCaptureController.swift ios/Tests/KitTests/TalkBarLabelTests.swift
git commit -m "feat(kit): testable talk-bar phase labels + flags"
```

### Task B3: Create `TalkBarView` and wire it into `RootView` (removing the toolbar mic)

**Files:**
- Create: `ios/Sources/App/TalkBarView.swift`
- Modify: `ios/Sources/App/RootView.swift`

- [ ] **Step 1: Create `TalkBarView`**

Create `ios/Sources/App/TalkBarView.swift`:

```swift
import SwiftUI
import CuelistCompilerKit

/// Full-width aqua tap-to-talk bar at the bottom of the screen. Drives the
/// existing VoiceCaptureController; the preview/error UI is owned by RootView.
struct TalkBarView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(VoiceCaptureController.self) private var voice

    var body: some View {
        Button {
            Task {
                if voice.phase.isRecording {
                    await voice.stopAndProcess(project: store.project, defaults: store.defaults)
                } else {
                    await voice.startRecording()
                }
            }
        } label: {
            HStack(spacing: 10) {
                if voice.phase.isBusy {
                    ProgressView().tint(Color(hex: "#04302b"))
                } else {
                    Image(systemName: voice.phase.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .bold))
                        .symbolEffect(.pulse, isActive: voice.phase.isRecording)
                }
                Text(voice.phase.talkBarLabel)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(Color(hex: "#04302b")!)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.aquaGradient, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Theme.aqua.opacity(0.5), radius: 22, y: 4)
            .opacity(voice.phase.isBusy ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(voice.phase.isBusy)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 4)
    }
}
```

- [ ] **Step 2: Remove the toolbar mic from `RootView`**

In `ios/Sources/App/RootView.swift`:

(a) Delete the leading toolbar item:
```swift
                ToolbarItem(placement: .topBarLeading) { micButton }
```
(b) Delete the entire `micButton` view (the `@ViewBuilder private var micButton` block, lines ~120–133) and the now-unused `previewBinding`/`errorBinding`/`errorText` stay (still used by the sheet/alert).

- [ ] **Step 3: Add `TalkBarView` to the bottom of the layout**

In `RootView.body`, the inner `VStack(spacing: 0)` currently is:
```swift
                VStack(spacing: 0) {
                    subbar
                    CueListView()
                    SendBarView()
                }
```
Change it to add the talk bar as the bottom-most element:
```swift
                VStack(spacing: 0) {
                    subbar
                    CueListView()
                    SendBarView()
                    TalkBarView()
                }
```

- [ ] **Step 4: Build to verify**

Run:
```bash
cd ios && xcodegen generate && xcodebuild build -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: `** BUILD SUCCEEDED **`. If the compiler complains `micButton` is undefined, you missed a reference in Step 2(a).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/App/TalkBarView.swift ios/Sources/App/RootView.swift
git commit -m "feat(ios): bottom aqua tap-to-talk bar, replacing the toolbar mic

Voice moves entirely to a full-width aqua bar at the bottom for
one-handed reach. Tap to start / tap to stop, driving the existing
VoiceCaptureController; the preview sheet and error alert are unchanged."
```

---

## SLICE C — Cue notes

### Task C1: Add the `notes` field to the `Cue` model

**Files:**
- Modify: `ios/Sources/Kit/Models/Cue.swift`
- Test: `ios/Tests/KitTests/CueNotesCodecTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/KitTests/CueNotesCodecTests.swift`:

```swift
import XCTest
@testable import CuelistCompilerKit

final class CueNotesCodecTests: XCTestCase {
    func testDecodesMissingNotesAsEmpty() throws {
        // Old project JSON has no `notes` key.
        let json = Data(#"{"n":1,"name":"Intro","fade":"","delay":"","position":"","collapsed":false,"actions":[]}"#.utf8)
        let cue = try JSONDecoder().decode(Cue.self, from: json)
        XCTAssertEqual(cue.notes, "")
    }

    func testRoundTripsNotes() throws {
        var cue = Cue(n: 2, name: "Chorus")
        cue.notes = "hit harder"
        let data = try JSONEncoder().encode(cue)
        let back = try JSONDecoder().decode(Cue.self, from: data)
        XCTAssertEqual(back.notes, "hit harder")
    }

    func testInitDefaultsNotesToEmpty() {
        XCTAssertEqual(Cue(n: 1).notes, "")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20
```
Expected: FAIL — `value of type 'Cue' has no member 'notes'`.

- [ ] **Step 3: Add the field**

In `ios/Sources/Kit/Models/Cue.swift`:

(a) Add the stored property after `actions`:
```swift
    public var actions: [Action]
    public var notes: String
```
(b) Add `notes` to the `init`, defaulting to `""`:
```swift
    public init(n: Double = 1, name: String = "", fade: String = "", delay: String = "",
                position: String = "", collapsed: Bool = false, actions: [Action] = [Action()],
                notes: String = "") {
        self.n = n; self.name = name; self.fade = fade; self.delay = delay
        self.position = position; self.collapsed = collapsed; self.actions = actions
        self.notes = notes
    }
```
(c) Add `notes` to `CodingKeys`:
```swift
    private enum CodingKeys: String, CodingKey {
        case n, name, fade, delay, position, collapsed, actions, notes
    }
```
(d) Decode it backward-compatibly in `init(from:)`, after the `actions` line:
```swift
        actions = try c.decodeIfPresent([Action].self, forKey: .actions) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd ios && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20
```
Expected: PASS (CueNotesCodecTests green; existing `ModelCodecTests`/`MigrationTests` still green).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Models/Cue.swift ios/Tests/KitTests/CueNotesCodecTests.swift
git commit -m "feat(kit): add backward-compatible notes field to Cue"
```

### Task C2: Add `NoteEdit` + `AnthropicNoteRouter`

**Files:**
- Create: `ios/Sources/Kit/Voice/NoteRouter.swift`
- Test: `ios/Tests/KitTests/NoteRouterTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/KitTests/NoteRouterTests.swift` (mirrors `AnthropicInterpreterTests`; reuses the `MockHTTPTransport` already defined in `HTTPTransportTests.swift`):

```swift
import XCTest
@testable import CuelistCompilerKit

final class NoteRouterTests: XCTestCase {
    private func project() -> Project {
        Project(songs: [Song(id: "a", name: "Opener", sequence: 1,
                             cues: [Cue(n: 1, name: "Intro"), Cue(n: 2, name: "Chorus")])],
                activeSongId: "a")
    }

    func testRoutesNotesToCues() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
            let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as! [String: Any]
            XCTAssertEqual((body["tool_choice"] as? [String: Any])?["name"] as? String, "attach_notes")
            // system + tools carry cache_control
            XCTAssertNotNil((body["system"] as! [[String: Any]]).last?["cache_control"])
            XCTAssertNotNil((body["tools"] as! [[String: Any]]).last?["cache_control"])
            let resp = """
            {"content":[{"type":"tool_use","name":"attach_notes","input":
              {"notes":[{"cue":1,"text":"keep it dim"},{"cue":2,"text":"hit harder"}]}}]}
            """
            return (Data(resp.utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let router = AnthropicNoteRouter(apiKey: "sk-ant", transport: mock)
        let edits = try await router.route(transcript: "dim intro, chorus harder",
                                           project: project(), targetCue: nil)
        XCTAssertEqual(edits, [NoteEdit(cue: 1, text: "keep it dim"),
                               NoteEdit(cue: 2, text: "hit harder")])
    }

    func testPinnedTargetCueReachesPrompt() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as! [String: Any]
            let content = (body["messages"] as! [[String: Any]]).last?["content"] as? String ?? ""
            XCTAssertTrue(content.contains("cue 2"))   // pinned target appears in the user turn
            let resp = #"{"content":[{"type":"tool_use","name":"attach_notes","input":{"notes":[{"cue":2,"text":"hit harder"}]}}]}"#
            return (Data(resp.utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let router = AnthropicNoteRouter(apiKey: "sk-ant", transport: mock)
        let edits = try await router.route(transcript: "make it punch", project: project(), targetCue: 2)
        XCTAssertEqual(edits, [NoteEdit(cue: 2, text: "hit harder")])
    }

    func testEmptyKeyThrowsMissingKey() async {
        let router = AnthropicNoteRouter(apiKey: "", transport: MockHTTPTransport())
        do { _ = try await router.route(transcript: "x", project: project(), targetCue: nil)
             XCTFail("expected throw") }
        catch VoiceError.missingKey(let who) { XCTAssertEqual(who, "Anthropic") }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testNon200ThrowsApi() async {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            (Data(#"{"error":{}}"#.utf8),
             HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
        let router = AnthropicNoteRouter(apiKey: "sk-ant", transport: mock)
        do { _ = try await router.route(transcript: "x", project: project(), targetCue: nil)
             XCTFail("expected throw") }
        catch let VoiceError.api(status, _) { XCTAssertEqual(status, 500) }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testMissingToolUseThrowsBadResponse() async {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            (Data(#"{"content":[{"type":"text","text":"sorry"}]}"#.utf8),
             HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let router = AnthropicNoteRouter(apiKey: "sk-ant", transport: mock)
        do { _ = try await router.route(transcript: "x", project: project(), targetCue: nil)
             XCTFail("expected throw") }
        catch VoiceError.badResponse(_) { }
        catch { XCTFail("wrong error: \(error)") }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20
```
Expected: FAIL — `cannot find 'AnthropicNoteRouter' / 'NoteEdit' in scope`.

- [ ] **Step 3: Implement `NoteRouter.swift`**

Create `ios/Sources/Kit/Voice/NoteRouter.swift`:

```swift
import Foundation

/// One note routed to a cue (by its number `n`).
public struct NoteEdit: Equatable, Sendable {
    public var cue: Double
    public var text: String
    public init(cue: Double, text: String) { self.cue = cue; self.text = text }
}

public protocol NoteInterpreter: Sendable {
    /// Route free-form notes onto cues. If `targetCue` is set, all notes are pinned to it
    /// (the model only tidies the text); otherwise the model decides which cue(s) each belongs to.
    func route(transcript: String, project: Project, targetCue: Double?) async throws -> [NoteEdit]
}

/// Anthropic Messages API with forced tool-use, mirroring AnthropicInterpreter.
/// System prompt + tool schema are cached (cache_control: ephemeral).
public struct AnthropicNoteRouter: NoteInterpreter {
    private let apiKey: String
    private let model: String
    private let transport: HTTPTransport

    public init(apiKey: String, model: String = "claude-sonnet-4-6",
                transport: HTTPTransport = URLSessionHTTPTransport()) {
        self.apiKey = apiKey; self.model = model; self.transport = transport
    }

    public func route(transcript: String, project: Project, targetCue: Double?) async throws -> [NoteEdit] {
        guard !apiKey.isEmpty else { throw VoiceError.missingKey("Anthropic") }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let pin = targetCue.map {
            "\nAttach every note to cue \(formatN($0)) only; do not route to other cues."
        } ?? ""
        let user = """
        Current show (JSON):
        \(ProjectSnapshot.json(project))

        Operator notes:
        \(transcript)\(pin)
        """
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "tool_choice": ["type": "tool", "name": "attach_notes"],
            "system": [[
                "type": "text",
                "text": Self.systemPrompt,
                "cache_control": ["type": "ephemeral"]
            ]],
            "tools": [Self.tool],
            "messages": [["role": "user", "content": user]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await transport.send(req)
        guard resp.statusCode == 200 else {
            throw VoiceError.api(status: resp.statusCode, message: String(decoding: data.prefix(512), as: UTF8.self))
        }
        return try Self.parse(data)
    }

    private func formatN(_ n: Double) -> String { n.rounded() == n ? String(Int(n)) : String(n) }

    static func parse(_ data: Data) throws -> [NoteEdit] {
        struct Item: Decodable { let cue: Double; let text: String }
        struct Input: Decodable { let notes: [Item] }
        struct Resp: Decodable {
            struct Block: Decodable { let type: String; let name: String?; let input: Input? }
            let content: [Block]
        }
        guard let resp = try? JSONDecoder().decode(Resp.self, from: data),
              let input = resp.content.first(where: { $0.type == "tool_use" && $0.name == "attach_notes" })?.input
        else { throw VoiceError.badResponse(String(decoding: data.prefix(512), as: UTF8.self)) }
        return input.notes.map { NoteEdit(cue: $0.cue, text: $0.text) }
    }

    static let systemPrompt = """
    You attach a lighting operator's free-form notes to the cues they refer to, by \
    calling the attach_notes tool. Never reply in prose.

    A show has SONGS, each with CUES addressed by their number `n` (may be fractional, \
    e.g. 0.1, 1, 2). Each note is a short reminder about how a cue should look or feel \
    ("keep the intro dim", "chorus should hit harder").

    For each note in the operator's text, decide which cue (by `n`) it is about and \
    emit a { cue, text } entry. Condense each note to a short imperative line; keep the \
    operator's intent, drop filler. One note may map to one cue; multiple notes may map \
    to the same or different cues. If a note is ambiguous, attach it to the most likely \
    cue rather than dropping it. Return an empty notes array only if there is genuinely \
    nothing to attach.
    """

    static let tool: [String: Any] = [
        "name": "attach_notes",
        "description": "Attach short notes to cues by cue number.",
        "cache_control": ["type": "ephemeral"],
        "input_schema": [
            "type": "object",
            "properties": [
                "notes": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "required": ["cue", "text"],
                        "properties": [
                            "cue": ["type": "number", "description": "The cue number n to attach to."],
                            "text": ["type": "string", "description": "Short condensed note line."]
                        ]
                    ]
                ]
            ],
            "required": ["notes"]
        ]
    ]
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20
```
Expected: PASS (NoteRouterTests green).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/NoteRouter.swift ios/Tests/KitTests/NoteRouterTests.swift
git commit -m "feat(kit): AnthropicNoteRouter — route free-form notes onto cues"
```

### Task C3: Add `applyNotes` / `appendNote` store mutations

**Files:**
- Modify: `ios/Sources/Kit/Store/ProjectStore+Mutations.swift`
- Test: `ios/Tests/KitTests/ProjectStoreNotesTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/KitTests/ProjectStoreNotesTests.swift`:

```swift
import XCTest
@testable import CuelistCompilerKit

@MainActor
final class ProjectStoreNotesTests: XCTestCase {
    private func store() -> ProjectStore {
        let s = ProjectStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-notes-\(UUID().uuidString)"))
        s.project.songs[0].cues = [Cue(n: 1, name: "Intro"), Cue(n: 2, name: "Chorus")]
        return s
    }

    func testAppendNoteSetsThenAppendsNewlineJoined() {
        let s = store()
        s.appendNote(cueN: 1, text: "keep it dim")
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "keep it dim")
        s.appendNote(cueN: 1, text: "slow build")
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "keep it dim\nslow build")
    }

    func testApplyNotesRoutesToMatchingCues() {
        let s = store()
        s.applyNotes([NoteEdit(cue: 1, text: "dim"), NoteEdit(cue: 2, text: "harder")])
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "dim")
        XCTAssertEqual(s.project.songs[0].cues[1].notes, "harder")
    }

    func testApplyNotesSkipsEmptyAndUnknownCue() {
        let s = store()
        s.applyNotes([NoteEdit(cue: 1, text: "   "), NoteEdit(cue: 99, text: "lost")])
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "")
        XCTAssertEqual(s.project.songs[0].cues[1].notes, "")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20
```
Expected: FAIL — `value of type 'ProjectStore' has no member 'appendNote'`.

- [ ] **Step 3: Add the mutations**

In `ios/Sources/Kit/Store/ProjectStore+Mutations.swift`, add inside the same extension (e.g. right before the `apply(_ result:)` method):

```swift
    /// Append notes onto cues of the active song by cue number `n`. Newline-joins
    /// onto any existing note; trims and skips empty text or unknown cue numbers.
    func applyNotes(_ edits: [NoteEdit]) {
        let i = activeSongIndex()
        for e in edits {
            let t = e.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty,
                  let c = project.songs[i].cues.firstIndex(where: { $0.n == e.cue }) else { continue }
            let existing = project.songs[i].cues[c].notes
            project.songs[i].cues[c].notes = existing.isEmpty ? t : existing + "\n" + t
        }
    }

    /// Convenience for the per-cue note button.
    func appendNote(cueN: Double, text: String) {
        applyNotes([NoteEdit(cue: cueN, text: text)])
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd ios && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20
```
Expected: PASS (ProjectStoreNotesTests green).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Store/ProjectStore+Mutations.swift ios/Tests/KitTests/ProjectStoreNotesTests.swift
git commit -m "feat(kit): applyNotes/appendNote — append routed notes onto cues"
```

### Task C4: Create `NotesCaptureController` (record → transcribe → route)

**Files:**
- Create: `ios/Sources/Kit/Voice/NotesCaptureController.swift`
- Test: `ios/Tests/KitTests/NotesCaptureControllerTests.swift`

This reuses the existing `AudioRecorder` and `Transcriber` protocols (same ones `VoiceCaptureController` takes) plus the new `NoteInterpreter`.

- [ ] **Step 1: Inspect the existing protocols to reuse**

Run:
```bash
grep -rn "public protocol AudioRecorder\|public protocol Transcriber" ios/Sources/Kit
```
Expected: both protocols exist in `ios/Sources/Kit/Voice/`. Note their method names (`requestPermission()`, `start()`, `stop()`, `transcribe(_:)`) — they match `VoiceCaptureController`'s usage. Use those exact signatures below.

- [ ] **Step 2: Write the failing test**

Create `ios/Tests/KitTests/NotesCaptureControllerTests.swift`. It uses lightweight in-test stubs for the recorder/transcriber and a stub router:

```swift
import XCTest
@testable import CuelistCompilerKit

@MainActor
final class NotesCaptureControllerTests: XCTestCase {

    private struct StubRouter: NoteInterpreter {
        let result: [NoteEdit]
        func route(transcript: String, project: Project, targetCue: Double?) async throws -> [NoteEdit] { result }
    }

    private func project() -> Project {
        Project(songs: [Song(id: "a", name: "S", sequence: 1, cues: [Cue(n: 1)])], activeSongId: "a")
    }

    func testRouteTextSetsPreviewEdits() async {
        let c = NotesCaptureController(recorder: NoopRecorder(), transcriber: NoopTranscriber(text: ""),
                                       router: StubRouter(result: [NoteEdit(cue: 1, text: "dim")]))
        await c.routeText("dim the intro", project: project(), targetCue: nil)
        XCTAssertEqual(c.routed, [NoteEdit(cue: 1, text: "dim")])
        XCTAssertEqual(c.phase, .preview)
    }

    func testRouterErrorSurfacesAsErrorPhase() async {
        struct Failing: NoteInterpreter {
            func route(transcript: String, project: Project, targetCue: Double?) async throws -> [NoteEdit] {
                throw VoiceError.missingKey("Anthropic")
            }
        }
        let c = NotesCaptureController(recorder: NoopRecorder(), transcriber: NoopTranscriber(text: ""),
                                       router: Failing())
        await c.routeText("x", project: project(), targetCue: nil)
        if case .error = c.phase {} else { XCTFail("expected error phase") }
    }
}

// Minimal stubs (AudioRecorder/Transcriber protocol methods mirror VoiceCaptureController usage).
private struct NoopRecorder: AudioRecorder {
    func requestPermission() async -> Bool { true }
    func start() throws {}
    func stop() async -> Data? { Data() }
}
private struct NoopTranscriber: Transcriber {
    let text: String
    func transcribe(_ audio: Data) async throws -> String { text }
}
```

> If the `AudioRecorder`/`Transcriber` protocol signatures from Step 1 differ from the stubs above, adjust the stub method signatures to match exactly (copy them from `VoiceCaptureController.swift`'s usage).

- [ ] **Step 3: Run the test to verify it fails**

Run:
```bash
cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20
```
Expected: FAIL — `cannot find 'NotesCaptureController' in scope`.

- [ ] **Step 4: Implement `NotesCaptureController`**

Create `ios/Sources/Kit/Voice/NotesCaptureController.swift`:

```swift
import Foundation
import Observation

/// Captures a note by text or voice and routes it onto cue(s) via a NoteInterpreter.
/// Separate from VoiceCaptureController (which edits the show); this only attaches notes.
@MainActor @Observable
public final class NotesCaptureController {

    public enum Phase: Equatable {
        case idle, recording, transcribing, routing, preview, error(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var routed: [NoteEdit] = []
    /// Filled after a voice capture so the sheet can show/edit the transcript before routing.
    public private(set) var transcript: String = ""

    @ObservationIgnored private let recorder: AudioRecorder
    @ObservationIgnored private let transcriber: Transcriber
    @ObservationIgnored private let router: NoteInterpreter

    public init(recorder: AudioRecorder, transcriber: Transcriber, router: NoteInterpreter) {
        self.recorder = recorder; self.transcriber = transcriber; self.router = router
    }

    public func startRecording() async {
        guard await recorder.requestPermission() else { phase = .error("Microphone access denied"); return }
        do { try recorder.start(); phase = .recording }
        catch { phase = .error("Couldn't start recording") }
    }

    /// Stop recording and transcribe; returns the transcript (also stored on `transcript`).
    @discardableResult
    public func stopAndTranscribe() async -> String {
        guard let audio = await recorder.stop() else { phase = .error("No audio captured"); return "" }
        do {
            phase = .transcribing
            let t = try await transcriber.transcribe(audio)
            transcript = t
            phase = .idle
            return t
        } catch {
            phase = .error("Didn't catch that — try again")
            return ""
        }
    }

    /// Route already-typed/transcribed text onto cues; fills `routed` and moves to `.preview`.
    public func routeText(_ text: String, project: Project, targetCue: Double?) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { phase = .error("Nothing to add"); return }
        do {
            phase = .routing
            let edits = try await router.route(transcript: trimmed, project: project, targetCue: targetCue)
            routed = edits
            phase = edits.isEmpty ? .error("Couldn't place that note") : .preview
        } catch let VoiceError.api(status, _) {
            phase = .error("Service error (\(status))")
        } catch let VoiceError.missingKey(p) {
            phase = .error("Add your \(p) API key in Settings")
        } catch {
            phase = .error("Couldn't route that — try rephrasing")
        }
    }

    public func reset() { phase = .idle; routed = []; transcript = "" }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20
```
Expected: PASS (NotesCaptureControllerTests green).

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/Kit/Voice/NotesCaptureController.swift ios/Tests/KitTests/NotesCaptureControllerTests.swift
git commit -m "feat(kit): NotesCaptureController — capture note by text/voice and route"
```

### Task C5: Create `NotesCaptureView` sheet

**Files:**
- Create: `ios/Sources/App/NotesCaptureView.swift`

App-target view; verified by build + smoke.

- [ ] **Step 1: Create the sheet**

Create `ios/Sources/App/NotesCaptureView.swift`:

```swift
import SwiftUI
import CuelistCompilerKit

/// Sheet for adding a note by text or voice. If `targetCue` is set the note is
/// pinned to that cue; otherwise the router decides which cue(s) it belongs to,
/// and a routing preview is shown before applying.
struct NotesCaptureView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(NotesCaptureController.self) private var notes
    @Environment(\.dismiss) private var dismiss

    /// nil = global brain-dump; set = per-cue.
    let targetCue: Double?

    @State private var text = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Type a note, or use the mic…", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .padding(12)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .foregroundStyle(Theme.text)

                    HStack(spacing: 12) {
                        micButton
                        Spacer()
                        Button {
                            Task {
                                await notes.routeText(text, project: store.project, targetCue: targetCue)
                                if case .preview = notes.phase, targetCue != nil {
                                    // per-cue: apply immediately, no routing ambiguity
                                    store.applyNotes(notes.routed); notes.reset(); dismiss()
                                }
                            }
                        } label: {
                            Text(targetCue == nil ? "Route" : "Add")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.vertical, 10).padding(.horizontal, 20)
                                .background(Theme.aqua, in: RoundedRectangle(cornerRadius: Theme.radius))
                                .foregroundStyle(Color(hex: "#04302b")!)
                        }
                        .buttonStyle(.plain)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    }

                    if case .routing = notes.phase { ProgressView("Routing…").tint(Theme.aqua) }
                    if case let .error(msg) = notes.phase {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(Theme.danger)
                    }

                    // Global routing preview (per-cue applies immediately above).
                    if targetCue == nil, case .preview = notes.phase, !notes.routed.isEmpty {
                        routingPreview
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle(targetCue == nil ? "Notes" : "Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { notes.reset(); dismiss() }
                }
            }
        }
        .onAppear { notes.reset() }
    }

    @ViewBuilder private var micButton: some View {
        if notes.phase.isNotesRecording {
            Button {
                Task { let t = await notes.stopAndTranscribe(); if !t.isEmpty { text = text.isEmpty ? t : text + " " + t } }
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.danger)
            }.buttonStyle(.plain)
        } else if case .transcribing = notes.phase {
            ProgressView().tint(Theme.aqua)
        } else {
            Button { Task { await notes.startRecording() } } label: {
                Label("Mic", systemImage: "mic.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.aqua)
            }.buttonStyle(.plain)
        }
    }

    private var routingPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routes to").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textDim)
            ForEach(Array(notes.routed.enumerated()), id: \.offset) { _, e in
                HStack(spacing: 8) {
                    Text("Cue \(formatN(e.cue))").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.aqua)
                    Text(e.text).font(.system(size: 12)).foregroundStyle(Theme.text)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Theme.aquaTint, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
            Button {
                store.applyNotes(notes.routed); notes.reset(); dismiss()
            } label: {
                Text("Add \(notes.routed.count) note\(notes.routed.count == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Theme.aquaGradient, in: RoundedRectangle(cornerRadius: Theme.radius))
                    .foregroundStyle(Color(hex: "#04302b")!)
            }.buttonStyle(.plain).padding(.top, 4)
        }
    }

    private func formatN(_ n: Double) -> String { n.rounded() == n ? String(Int(n)) : String(n) }
}
```

- [ ] **Step 2: Add the `isNotesRecording` helper used above**

The view references `notes.phase.isNotesRecording`. Add it to `NotesCaptureController.swift` (App can't extend a private case match cleanly, so expose it in Kit). Append to the bottom of `ios/Sources/Kit/Voice/NotesCaptureController.swift`:

```swift
public extension NotesCaptureController.Phase {
    var isNotesRecording: Bool { if case .recording = self { return true } else { return false } }
}
```

- [ ] **Step 3: Build to verify (after wiring in C8, the sheet is reachable; for now just compile)**

Run:
```bash
cd ios && xcodegen generate && xcodebuild build -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: `** BUILD SUCCEEDED **`. (The view isn't presented yet — that's Tasks C7/C8. It must still compile, which requires C8's environment injection to exist; if the build fails only because `NotesCaptureController` isn't in the environment yet, that's expected — do C6 next, then this build passes after C6.)

> **Ordering note:** Step 3's build will only succeed once Task C6 injects `NotesCaptureController` into the environment. If you're doing strict per-task builds, run C6 before this build, or accept that this specific build passes after C6. Commit the file now regardless.

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/NotesCaptureView.swift ios/Sources/Kit/Voice/NotesCaptureController.swift
git commit -m "feat(ios): NotesCaptureView — text/voice note entry + routing preview"
```

### Task C6: Wire `NotesCaptureController` into the app environment

**Files:**
- Modify: `ios/Sources/App/App.swift`

- [ ] **Step 1: Construct and inject the controller**

In `ios/Sources/App/App.swift`, add a `notes` state alongside `voice`, reusing the same keychain keys:

```swift
    @State private var notes = NotesCaptureController(
        recorder: AVAudioFileRecorder(),
        transcriber: WhisperTranscriber(apiKey: KeychainAIKeyStore().key(for: .openAI) ?? ""),
        router: AnthropicNoteRouter(apiKey: KeychainAIKeyStore().key(for: .anthropic) ?? "")
    )
```

And add it to the environment chain on `RootView()`:

```swift
            RootView()
                .environment(store)
                .environment(hub)
                .environment(voice)
                .environment(notes)
```

- [ ] **Step 2: Build to verify**

Run:
```bash
cd ios && xcodebuild build -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: `** BUILD SUCCEEDED **` (NotesCaptureView from C5 now resolves its `@Environment(NotesCaptureController.self)`).

- [ ] **Step 3: Commit**

```bash
git add ios/Sources/App/App.swift
git commit -m "feat(ios): inject NotesCaptureController into the app environment"
```

### Task C7: Global ✎ Notes button in the send strip

**Files:**
- Modify: `ios/Sources/App/SendBarView.swift`
- Modify: `ios/Sources/App/RootView.swift`

- [ ] **Step 1: Add a binding-free trigger to `SendBarView`**

`SendBarView` should not own the sheet (the controller lives in the environment and the sheet is shared with per-cue). Add a callback the parent supplies. At the top of `SendBarView`:

```swift
    var onOpenNotes: () -> Void = {}
```

Add the ✎ Notes button to the action `HStack` (the one with Send→MA and All), after the `All` button:

```swift
                Button(action: onOpenNotes) {
                    Label("Notes", systemImage: "square.and.pencil")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.vertical, 11).padding(.horizontal, 14)
                        .background(Theme.aquaTint, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .foregroundStyle(Theme.aqua)
                }
```

> Note: this button is *outside* the `.disabled(!hub.state.isOnline)` block — notes don't need the hub. If the existing `.disabled`/`.opacity` modifiers are applied to the whole `HStack`, move the Notes button into its own trailing position so it stays enabled offline. Simplest: keep Send→MA and All in their current `HStack` (with the disabled modifiers), and put the Notes button in that same row but split the disabled modifiers onto just the Send/All buttons. Concretely, wrap only Send+All:
> ```swift
> HStack(spacing: 10) {
>     HStack(spacing: 10) { /* Send→MA + All buttons */ }
>         .disabled(!hub.state.isOnline)
>         .opacity(hub.state.isOnline ? 1 : 0.5)
>     Button(action: onOpenNotes) { /* Notes label */ }
> }
> .buttonStyle(.plain)
> ```

- [ ] **Step 2: Present the global notes sheet from `RootView`**

In `ios/Sources/App/RootView.swift`:

(a) Add state:
```swift
    @State private var showNotes = false
```
(b) Pass the callback to `SendBarView` (in the `VStack`):
```swift
                    SendBarView(onOpenNotes: { showNotes = true })
```
(c) Add the sheet alongside the other `.sheet` modifiers:
```swift
            .sheet(isPresented: $showNotes) { NotesCaptureView(targetCue: nil) }
```

- [ ] **Step 3: Build to verify**

Run:
```bash
cd ios && xcodebuild build -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/SendBarView.swift ios/Sources/App/RootView.swift
git commit -m "feat(ios): global Notes button — brain-dump routed onto cues"
```

### Task C8: Per-cue ✎ Note button + note-line display on the card

**Files:**
- Modify: `ios/Sources/App/CueCardView.swift`

- [ ] **Step 1: Add per-cue notes sheet state**

In `CueCardView`, add:
```swift
    @State private var addingNote = false
```
And read the notes controller from the environment (add near the other `@Environment`):
```swift
    @Environment(NotesCaptureController.self) private var notes
```

- [ ] **Step 2: Add the ✎ Note button to the expanded footer**

In the expanded footer `HStack` created in Task A1 (the one with `Spacer()` then the Delete button), add a Note button **before** the Delete button:

```swift
                HStack {
                    Spacer()
                    Button { addingNote = true } label: {
                        Label("Note", systemImage: "square.and.pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.aqua)
                            .padding(.vertical, 6).padding(.horizontal, 11)
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                .strokeBorder(Theme.aqua.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete cue", systemImage: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.danger)
                            .padding(.vertical, 6).padding(.horizontal, 11)
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                .strokeBorder(Theme.danger.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
```
(This replaces the Delete-only footer `HStack` from Task A1.)

- [ ] **Step 3: Add the note-line display under the cue name**

Immediately after the header `Button` (the `.buttonStyle(.plain)` that closes the header), add a note line shown whenever the cue has notes (visible collapsed and expanded):

```swift
            if !cue.notes.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "square.and.pencil").font(.system(size: 10)).foregroundStyle(Theme.aqua)
                    Text(cue.notes).font(.system(size: 11)).foregroundStyle(Theme.text.opacity(0.85))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(Theme.aquaTint, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(Rectangle().frame(width: 2).foregroundStyle(Theme.aqua.opacity(0.5)),
                         alignment: .leading)
            }
```

- [ ] **Step 4: Present the per-cue note sheet**

Add to the outer `VStack` modifiers (next to the `.confirmationDialog` from Task A1):
```swift
        .sheet(isPresented: $addingNote) { NotesCaptureView(targetCue: cue.n) }
```

- [ ] **Step 5: Build to verify**

Run:
```bash
cd ios && xcodebuild build -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/App/CueCardView.swift
git commit -m "feat(ios): per-cue note button + aqua note line on the cue card"
```

### Task C9: Full Kit test pass + final verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full Kit test suite**

Run:
```bash
cd ios && xcodegen generate && xcodebuild test -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -25
```
Expected: `** TEST SUCCEEDED **`, all tests green (new: TalkBarLabelTests, CueNotesCodecTests, NoteRouterTests, ProjectStoreNotesTests, NotesCaptureControllerTests).

- [ ] **Step 2: Build the app target**

Run:
```bash
cd ios && xcodebuild build -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Confirm the branch ref matches the last commit (subagent drift guard)**

Run:
```bash
git rev-parse --short HEAD && git rev-parse --short feat/ios-ui-voice-notes-delete
```
Expected: both SHAs identical. (Per project norm — subagent execution can land commits on a detached HEAD.)

---

## Device smoke (manual, after the plan — not a code task)

On a physical jPhone with a hub reachable:
1. **Delete:** collapsed cards show only a chevron; expand a cue → "Delete cue" → confirmation dialog → delete works, Cancel leaves it.
2. **Talk bar:** big aqua bar at the bottom; tap → "Listening… tap to stop" → tap → "Thinking…" → existing preview sheet → apply. No mic in the toolbar.
3. **Notes (global):** ✎ Notes → type or dictate "keep the intro dim and make the chorus hit harder" → Route → preview shows Cue 1 / Cue 2 → Add → aqua note lines appear on those cards.
4. **Notes (per-cue):** expand a cue → ✎ Note → dictate → Add → tidied note line appears on that card.

---

## Self-review

**Spec coverage:**
- Data model `notes` field → C1. ✓
- Aqua theme token → B1. ✓
- Voice talk bar (tap-to-start/stop, removes toolbar mic, drives existing pipeline) → B2/B3. ✓
- NoteRouter as a separate interpreter (global routes, per-cue pinned) → C2. ✓
- Notes append (newline-joined) → C3. ✓
- Global ✎ Notes (preview) + per-cue ✎ Note (immediate) → C5/C7/C8. ✓
- Note display on card → C8. ✓
- Delete: collapsed = chevron only, expanded footer + confirmationDialog → A1. ✓
- Error handling reuses VoiceError surfaced in the sheet → C4/C5. ✓
- App.swift wiring reusing keychain keys → C6. ✓
- Three independently-committable slices, order A→B→C → structure. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. The one ordering caveat (C5 Step 3 build depends on C6) is called out explicitly rather than hidden. ✓

**Type consistency:** `NoteEdit(cue:text:)`, `NoteInterpreter.route(transcript:project:targetCue:)`, `AnthropicNoteRouter`, `NotesCaptureController.routeText/startRecording/stopAndTranscribe/reset/routed/phase`, `Phase.talkBarLabel/isRecording/isBusy`, `Phase.isNotesRecording`, `store.applyNotes(_:)`/`appendNote(cueN:text:)`, `Cue.notes`, `Theme.aqua/aquaGradient/aquaTint`, `SendBarView(onOpenNotes:)`, `NotesCaptureView(targetCue:)` — names used identically across tasks. ✓
