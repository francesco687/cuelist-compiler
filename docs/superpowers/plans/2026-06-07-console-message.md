# Send Message to Console — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an inline text field on Saetta's Live tab that pops a titled message box on the grandMA3 desk, and shrink the transport buttons to ~half the screen to make room for a growing control area.

**Architecture:** A pure `ConsoleMessage` builder in SaettaKit sanitizes the note and emits one `Lua "MessageBox({...})"` command-line string. `HubClient.sendConsoleMessage` forwards it over the existing, desk-proven `cmd` OSC passthrough (the same path GO+/PAUSE/GO− use). `LiveView` splits into two flexible halves — transport on top, a top-aligned control area (message field + Send) on the bottom. No hub, protocol, or `OutgoingMessage` change.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, xcodegen. Kit target `SaettaKit`, test target `SaettaKitTests` (scheme `SaettaKit`).

**Hard constraint (proven on a real desk, see `TimecodeBuilder.swift`):** MA3's command-line tokenizer terminates a `Lua "..."` argument at the first `"` and ignores backslash escapes. Therefore the body between the outer quotes must contain **zero** `"` characters. We use Lua long-bracket strings `[[ ... ]]` (which need no quotes) and strip `"` and `]]` from user text.

**Test command (all tasks):**
```bash
cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
(Any installed iOS 17+ simulator works; substitute its name if iPhone 17 Pro is absent.)

## File Structure

- **Create** `ios/Sources/Kit/Send/ConsoleMessage.swift` — pure builder: sanitize + assemble the `Lua "MessageBox(...)"` line, or `nil`.
- **Create** `ios/Tests/KitTests/ConsoleMessageTests.swift` — builder unit tests.
- **Modify** `ios/Sources/Kit/Hub/HubClient.swift` — add `sendConsoleMessage(_:)`.
- **Modify** `ios/Tests/KitTests/HubClientTests.swift` — add two frame-level tests (reuses `makeOnlineClient`/`frameToCmdLine`).
- **Modify** `ios/Sources/App/LiveView.swift` — half-height transport + control area with the message field/Send + optimistic feedback.

---

### Task 1: `ConsoleMessage` builder (pure, SaettaKit)

**Files:**
- Create: `ios/Sources/Kit/Send/ConsoleMessage.swift`
- Test: `ios/Tests/KitTests/ConsoleMessageTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/KitTests/ConsoleMessageTests.swift`:

```swift
import XCTest
@testable import SaettaKit

final class ConsoleMessageTests: XCTestCase {

    func test_normal_text_builds_messagebox_line() {
        let line = ConsoleMessage.line(text: "hello")
        XCTAssertEqual(
            line,
            "Lua \"MessageBox({title=[[Saetta]], message=[[hello]], commands={{value=1,name=[[OK]]}}})\""
        )
    }

    func test_body_contains_no_double_quote() {
        // MA3 tokenizer terminates Lua "..." at the first inner ". Body must have none.
        let line = ConsoleMessage.line(text: "say \"go\" now")!
        // Strip the two outer wrapper quotes, assert nothing left inside is a quote.
        let inner = line.dropFirst("Lua \"".count).dropLast(1)   // remove `Lua "` and trailing `"`
        XCTAssertFalse(inner.contains("\""), "body must contain no double-quote")
    }

    func test_strips_double_quotes_from_text() {
        let line = ConsoleMessage.line(text: "a\"b")
        XCTAssertEqual(line, "Lua \"MessageBox({title=[[Saetta]], message=[[ab]], commands={{value=1,name=[[OK]]}}})\"")
    }

    func test_strips_long_bracket_close_from_text() {
        let line = ConsoleMessage.line(text: "a]]b")
        XCTAssertEqual(line, "Lua \"MessageBox({title=[[Saetta]], message=[[ab]], commands={{value=1,name=[[OK]]}}})\"")
    }

    func test_collapses_newlines_tabs_and_runs_to_single_space() {
        let line = ConsoleMessage.line(text: "a\n\tb   c")
        XCTAssertEqual(line, "Lua \"MessageBox({title=[[Saetta]], message=[[a b c]], commands={{value=1,name=[[OK]]}}})\"")
    }

    func test_trims_leading_and_trailing_whitespace() {
        let line = ConsoleMessage.line(text: "  hi  ")
        XCTAssertEqual(line, "Lua \"MessageBox({title=[[Saetta]], message=[[hi]], commands={{value=1,name=[[OK]]}}})\"")
    }

    func test_caps_message_at_200_chars() {
        let long = String(repeating: "x", count: 250)
        let line = ConsoleMessage.line(text: long)!
        // Extract the message between `message=[[` and `]], commands`.
        let start = line.range(of: "message=[[")!.upperBound
        let end = line.range(of: "]], commands")!.lowerBound
        let msg = String(line[start..<end])
        XCTAssertEqual(msg.count, 200)
    }

    func test_empty_text_returns_nil() {
        XCTAssertNil(ConsoleMessage.line(text: ""))
    }

    func test_whitespace_only_returns_nil() {
        XCTAssertNil(ConsoleMessage.line(text: "   \n\t "))
    }

    func test_sanitizes_to_empty_returns_nil() {
        XCTAssertNil(ConsoleMessage.line(text: "\"\""))   // both quotes stripped → empty
    }

    func test_custom_title_appears_and_is_sanitized() {
        let line = ConsoleMessage.line(text: "hi", title: "LX\"Note")
        XCTAssertEqual(line, "Lua \"MessageBox({title=[[LXNote]], message=[[hi]], commands={{value=1,name=[[OK]]}}})\"")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the test command above.
Expected: FAIL — `cannot find 'ConsoleMessage' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `ios/Sources/Kit/Send/ConsoleMessage.swift`:

```swift
import Foundation

/// Builds the grandMA3 command-line string that pops a `MessageBox` on the desk
/// from a free-text operator note. Sent over the existing `cmd` OSC passthrough.
///
/// HARD CONSTRAINT (see TimecodeBuilder): MA3's command-line tokenizer terminates a
/// `Lua "..."` argument at the first inner `"` and ignores backslash escapes — so the
/// body must contain NO double-quotes. We wrap title/message in Lua long brackets
/// `[[ ... ]]` (no quotes needed) and strip `"` and `]]` from the text.
public enum ConsoleMessage {

    /// Max characters kept from the note (the `Lua "..."` arg also truncates near 1 KB
    /// on the desk; 200 keeps us comfortably under and readable on screen).
    static let maxLength = 200

    /// One command-line string, or `nil` if the message sanitizes to empty.
    /// `title` defaults to the app name so the operator knows the source at a glance.
    public static func line(text: String, title: String = "Saetta") -> String? {
        let msg = sanitize(text)
        guard !msg.isEmpty else { return nil }
        let t = sanitize(title)
        return "Lua \"MessageBox({title=[[\(t)]], message=[[\(msg)]], commands={{value=1,name=[[OK]]}}})\""
    }

    /// Make arbitrary text safe for the two parsers (MA command line + Lua long bracket).
    static func sanitize(_ s: String) -> String {
        var out = s
        for ws in ["\n", "\r", "\t"] { out = out.replacingOccurrences(of: ws, with: " ") }
        out = out.replacingOccurrences(of: "\"", with: "")   // would close the outer Lua "..."
        out = out.replacingOccurrences(of: "]]", with: "")   // would close the Lua [[ ... ]]
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        out = out.trimmingCharacters(in: .whitespaces)
        if out.count > maxLength { out = String(out.prefix(maxLength)) }
        return out
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the test command above.
Expected: PASS — all `ConsoleMessageTests` green, existing tests unaffected.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Send/ConsoleMessage.swift ios/Tests/KitTests/ConsoleMessageTests.swift
git commit -m "feat(saetta): ConsoleMessage builder for desk MessageBox popup"
```

---

### Task 2: `HubClient.sendConsoleMessage` (SaettaKit)

**Files:**
- Modify: `ios/Sources/Kit/Hub/HubClient.swift` (add method after `sendCommand`, ~line 141)
- Test: `ios/Tests/KitTests/HubClientTests.swift` (append tests; reuses `makeOnlineClient` + `frameToCmdLine`)

- [ ] **Step 1: Write the failing tests**

Append these methods inside the `HubClientTests` class in `ios/Tests/KitTests/HubClientTests.swift` (before the closing `}` of the class):

```swift
    func testSendConsoleMessageEmitsCmdFrameWithMessageBox() {
        let (client, mock) = makeOnlineClient()
        client.sendConsoleMessage("standby please")
        XCTAssertEqual(mock.sent.count, 1)
        let line = frameToCmdLine(mock.sent[0])
        XCTAssertEqual(line, ConsoleMessage.line(text: "standby please"))
        XCTAssertEqual(line?.contains("MessageBox"), true)
        XCTAssertEqual(line?.contains("[[standby please]]"), true)
    }

    func testSendConsoleMessageEmptyDoesNothing() {
        let (client, mock) = makeOnlineClient()
        client.sendConsoleMessage("   ")
        XCTAssertEqual(mock.sent.count, 0)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run the test command above.
Expected: FAIL — `value of type 'HubClient' has no member 'sendConsoleMessage'`.

- [ ] **Step 3: Write minimal implementation**

In `ios/Sources/Kit/Hub/HubClient.swift`, add this method immediately after `sendCommand(_:)` (after its closing `}` near line 141):

```swift
    /// Pop a free-text note as a `MessageBox` on the desk. Builds the command-line
    /// string via `ConsoleMessage` and forwards it over the same optimistic `cmd`
    /// passthrough as the transport buttons. No-ops if the note sanitizes to empty.
    public func sendConsoleMessage(_ text: String) {
        guard let line = ConsoleMessage.line(text: text) else { return }
        sendCommand(line)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the test command above.
Expected: PASS — both new tests green, all prior tests unaffected.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Hub/HubClient.swift ios/Tests/KitTests/HubClientTests.swift
git commit -m "feat(saetta): HubClient.sendConsoleMessage forwards via cmd passthrough"
```

---

### Task 3: Live tab — half-height transport + message control (App)

**Files:**
- Modify: `ios/Sources/App/LiveView.swift` (replace the body `VStack` and add the control area)

This task is SwiftUI view code with no unit test; verification is a clean build of the app target plus a manual device smoke (separate, after the plan).

- [ ] **Step 1: Replace `LiveView`'s body to split the screen and add the message control**

In `ios/Sources/App/LiveView.swift`, replace the entire `struct LiveView` (lines 8–57, from `struct LiveView: View {` through its closing `}` before the `TransportButton` struct) with:

```swift
struct LiveView: View {
    @Environment(HubClient.self) private var hub
    @State private var fireCount = 0
    @State private var messageText = ""
    @State private var didSend = false

    private var canSend: Bool {
        hub.state.isOnline && ConsoleMessage.line(text: messageText) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 14) {
                    connectionRow

                    // Top half — transport (was full-screen).
                    VStack(spacing: 14) {
                        TransportButton(title: "GO+", symbol: "arrow.right.circle.fill",
                                        tint: Theme.ok) { fire("Go+") }
                        TransportButton(title: "PAUSE", symbol: "pause.circle.fill",
                                        tint: Theme.warn) { fire("Pause") }
                        TransportButton(title: "GO-", symbol: "arrow.left.circle.fill",
                                        tint: Theme.textFaint) { fire("Go-") }
                    }
                    .frame(maxHeight: .infinity)
                    .disabled(!hub.state.isOnline)
                    .opacity(hub.state.isOnline ? 1 : 0.4)

                    // Bottom half — control area (grows with future controls).
                    controlSection
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(20)
            }
            .navigationTitle("Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sensoryFeedback(.impact(weight: .medium), trigger: fireCount)
        }
    }

    // MARK: Control area

    @ViewBuilder private var controlSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("Message to console\u{2026}", text: $messageText)
                    .textFieldStyle(.plain)
                    .submitLabel(.send)
                    .onSubmit { sendMessage() }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))

                Button("Send") { sendMessage() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentSolid)
                    .disabled(!canSend)
            }
            if didSend {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.ok)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    private func sendMessage() {
        guard canSend else { return }
        hub.sendConsoleMessage(messageText)
        fireCount += 1                         // haptic, same trigger as transport
        messageText = ""
        withAnimation { didSend = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { didSend = false }
        }
    }

    private func fire(_ line: String) {
        fireCount += 1
        hub.sendCommand(line)
    }

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
        }
        .buttonStyle(.plain)
    }
}
```

Leave the `TransportButton` and `PressScaleStyle` structs (below the view) unchanged.

- [ ] **Step 2: Build the app target to verify it compiles**

Run:
```bash
cd ios && xcodegen generate && xcodebuild build -scheme Saetta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the Kit test suite to confirm no regressions**

Run the test command from the top of this plan.
Expected: PASS — full `SaettaKitTests` suite green.

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/LiveView.swift
git commit -m "feat(saetta): Live tab half-height transport + send-message-to-console control"
```

---

## Manual verification (after the plan, on hardware)

1. Install on jPhone (2), connect to the hub, ensure a grandMA3 (onPC or desk) is reachable.
2. Type a note on the Live tab, tap **Send** → a `MessageBox` titled **Saetta** appears on the focused MA screen with the note and an **OK** button; tapping OK dismisses it.
3. Confirm transport (GO+/PAUSE/GO−) still fires and now occupies ~the top half.
4. Try edge text (`"`, `]]`, a long paragraph) → still pops cleanly, no Lua error in the System Monitor.

