# Saetta Hub "Disconnect all" (Soft Kick) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A confirm-gated "Disconnect all" button in the Saetta Hub popover that soft-kicks every paired phone; phones stop auto-reconnecting, show "disconnected by hub", and can rejoin with the same pairing code.

**Architecture:** The hub broadcasts a bare `{"type":"kicked"}` frame over its relay socket. The relay's existing legacy-broadcast path (`relay/src/rooms.js:83` — any non-`to-phone` hub frame goes to every phone in the room) delivers it, so the deployed Fly relay is untouched. The iOS app learns a `.kicked` incoming message and, on receipt, tears down like `disconnect()` but lands on `state = .error("disconnected by hub")`.

**Tech Stack:** Electron menubar app (`menubar-hub/`, plain Node, `node --test` hermetic tests with injected fake sockets) + SwiftUI iOS app (`ios/`, SaettaKit framework, XCTest via xcodegen + xcodebuild).

**Spec:** `docs/superpowers/specs/2026-06-11-hub-disconnect-all-design.md`

**Branch:** work directly on `fix/hub-local-network-permission` (the active hub line; the spec is already committed there).

**Test commands:**
- Hub: `cd menubar-hub && npm test` (baseline: 17 tests pass)
- iOS Kit: `cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
  (ALWAYS run `xcodegen generate` before any xcodebuild — the .xcodeproj is generated from `project.yml`.)

---

### Task 1: `RelayHubClient.kickAll()`

**Files:**
- Modify: `menubar-hub/src/relay-client.js` (add method to the `RelayHubClient` class, after `_scheduleReconnect()` around line 95)
- Test: `menubar-hub/test/relay-client.test.js` (append)

- [x] **Step 1: Write the failing test**

Append to `menubar-hub/test/relay-client.test.js` (the file already defines `FakeSocket`, `fakeDeps`, and `config` at the top — reuse them):

```js
test('kickAll broadcasts a bare kicked frame; safe no-op before connect', () => {
  const sock = new FakeSocket();
  const { core } = fakeDeps();
  const c = new RelayHubClient(config, {}, { makeSocket: () => sock, core });
  c.kickAll();                                  // no socket yet — must not throw, must not send
  c.connect();
  sock.emit('open');
  c.kickAll();
  // sent[0] is the join frame from 'open'; the kick must be the bare un-enveloped frame
  assert.deepStrictEqual(sock.sent.at(-1), { type: 'kicked' });
  assert.strictEqual(sock.sent.length, 2);      // exactly join + kicked (pre-connect call sent nothing)
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd menubar-hub && npm test 2>&1 | tail -15`
Expected: FAIL — `TypeError: c.kickAll is not a function (1 failing test, 17 passing)`

- [x] **Step 3: Write minimal implementation**

In `menubar-hub/src/relay-client.js`, add this method to `RelayHubClient` between `_scheduleReconnect()` and `close()`:

```js
  /**
   * Soft-kick every paired phone: broadcast a bare {type:'kicked'} frame. The
   * relay forwards any non-'to-phone' hub frame to ALL phones in the room
   * (legacy single-phone broadcast path), so the deployed relay needs no
   * changes. Updated phones disconnect and stop auto-reconnecting; they can
   * rejoin at any time with the same pairing code.
   */
  kickAll() {
    if (!this.ws || this.stopped) return;
    try { this.ws.send(JSON.stringify({ type: 'kicked' })); } catch { /* socket already dying */ }
  }
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd menubar-hub && npm test 2>&1 | tail -15`
Expected: PASS — 18 tests, 0 failures

- [x] **Step 5: Commit**

```bash
git add menubar-hub/src/relay-client.js menubar-hub/test/relay-client.test.js
git commit -m "feat(hub): RelayHubClient.kickAll() broadcasts a kicked frame to all phones"
```

---

### Task 2: IPC + preload bridge + popover button

No test harness exists for `main.js`, `preload.js`, or the renderer (Electron wiring is verified manually in Task 4); this task is pure wiring around the tested `kickAll()`.

**Files:**
- Modify: `menubar-hub/main.js` (IPC handler, after the `hub:regenCode` handler at line 124-129)
- Modify: `menubar-hub/preload.js` (bridge method, line 8)
- Modify: `menubar-hub/renderer/index.html` (button, after `<ul id="roster">` at line 21)
- Modify: `menubar-hub/renderer/app.js` (`renderRoster` + `init`)
- Modify: `menubar-hub/renderer/styles.css` (button style)

- [x] **Step 1: Add the IPC handler in `main.js`**

After the `hub:regenCode` handler block (ends line 129), add:

```js
  ipcMain.handle('hub:kickAll', () => { if (client) client.kickAll(); });
```

- [x] **Step 2: Expose it in `preload.js`**

After the `regenCode` line:

```js
  kickAll: () => ipcRenderer.invoke('hub:kickAll'),
```

- [x] **Step 3: Add the button in `renderer/index.html`**

Directly after `<ul id="roster"></ul>` (line 21), still inside `<section class="pairing">`:

```html
    <button id="kick" disabled>Disconnect all</button>
```

It starts `disabled` — `renderRoster` enables it only when phones are connected.

- [x] **Step 4: Wire it in `renderer/app.js`**

Replace the whole `renderRoster` function with (one added line at the end):

```js
function renderRoster(phones) {
  const ul = $('roster');
  ul.innerHTML = '';
  for (const p of phones) {
    const li = document.createElement('li');
    li.textContent = p.name;
    ul.appendChild(li);
  }
  $('kick').disabled = phones.length === 0;   // nothing to kick when the room is empty
}
```

In `init()`, after `setStatus(st.relay, st.peer);` add the initial roster render (popover can open after phones already joined):

```js
  renderRoster(st.roster || []);
```

And after the `$('regen').onclick` block, add the confirm-gated click handler (mirrors the regen guard style):

```js
  $('kick').onclick = async () => {
    if (!confirm('Disconnect all paired phones?\n\nThey can rejoin with the same pairing code.')) return;
    await window.hub.kickAll();
  };
```

(No bespoke roster bookkeeping after the kick: each phone's departure makes the relay broadcast a fresh roster, which empties the list and re-disables the button.)

- [x] **Step 5: Style the button in `renderer/styles.css`**

After the `ul#roster li` rule (line 26):

```css
button#kick { display: block; width: 100%; margin-top: 8px; }
button#kick:disabled { color: var(--faint); cursor: default; }
button#kick:disabled:hover { background: var(--surface); }
```

- [x] **Step 6: Run the hub test suite (regression check)**

Run: `cd menubar-hub && npm test 2>&1 | tail -5`
Expected: PASS — 18 tests, 0 failures

- [x] **Step 7: Commit**

```bash
git add menubar-hub/main.js menubar-hub/preload.js menubar-hub/renderer/index.html menubar-hub/renderer/app.js menubar-hub/renderer/styles.css
git commit -m "feat(hub): confirm-gated 'Disconnect all' button in the popover"
```

---

### Task 3: iOS — `.kicked` message + HubClient soft-kick handling

**Files:**
- Modify: `ios/Sources/Kit/Hub/HubMessages.swift` (enum case + decode, lines 64-103)
- Modify: `ios/Sources/Kit/Hub/HubClient.swift` (`handle(_:)`, lines 245-276)
- Test: `ios/Tests/KitTests/HubClientTests.swift` (append)

- [x] **Step 1: Write the failing tests**

Append inside `HubClientTests` (the file already defines `MockHubConnection` and the `makeConnection`/`scheduleAfter` injection pattern — `testNoReconnectAfterManualDisconnect` is the model):

```swift
    func testKickedFrameDecodes() throws {
        XCTAssertEqual(try IncomingMessage.decode(#"{"type":"kicked"}"#), .kicked)
    }

    func testKickedStopsReconnectClearsRosterAndExplains() {
        var conns: [MockHubConnection] = []
        var scheduled: [() -> Void] = []
        let d = UserDefaults(suiteName: "cc-test-\(UUID().uuidString)")!
        let client = HubClient(defaults: d,
                               makeConnection: { _ in let m = MockHubConnection(); conns.append(m); return m },
                               scheduleAfter: { _, work in scheduled.append(work) })
        client.mode = .relay; client.relayURL = "wss://x"; client.pairingCode = "code1234"
        client.connect()
        conns[0].emit(.opened)
        conns[0].emit(.text(#"{"type":"roster","hub":true,"phones":[{"cid":"p1","name":"Matteo"}]}"#))
        XCTAssertEqual(client.state, .online)
        XCTAssertEqual(client.roster.count, 1)

        conns[0].emit(.text(#"{"type":"kicked"}"#))
        XCTAssertEqual(client.state, .error("disconnected by hub"))
        XCTAssertEqual(client.roster, [])

        conns[0].emit(.closed(nil))             // the socket close that follows the teardown
        XCTAssertEqual(scheduled.count, 0)      // kicked: NO auto-reconnect
        XCTAssertEqual(client.state, .error("disconnected by hub"))  // late close must not clobber the reason

        client.connect()                        // manual rejoin with the same code works
        XCTAssertEqual(conns.count, 2)
        XCTAssertEqual(client.state, .connecting)
    }
```

- [x] **Step 2: Run tests to verify they fail**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: BUILD FAILURE — `type 'IncomingMessage' has no member 'kicked'`

- [x] **Step 3: Implement**

In `ios/Sources/Kit/Hub/HubMessages.swift`, add the case to `IncomingMessage` after `.joinError` (line 73):

```swift
    case kicked                                      // hub kicked everyone; do not auto-reconnect
```

And in `decode`, add after the `"join-error"` line (line 99):

```swift
        case "kicked":     return .kicked
```

In `ios/Sources/Kit/Hub/HubClient.swift`, add to the `switch msg` in `handle(_:)` after the `.joinError` case (line 272):

```swift
        case .kicked:
            disconnect()                            // full teardown + stops the reconnect loop
            state = .error("disconnected by hub")   // explain why, instead of plain offline
```

(`disconnect()` sets `stopped`, bumps `generation` — which also makes the trailing socket-close event a no-op — closes the connection, clears the roster, and lands on `.offline`; the next line replaces that with the explanatory error. Tapping Connect later works because `connect()` resets `stopped`.)

- [x] **Step 4: Run tests to verify they pass**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: TEST SUCCEEDED, including `testKickedFrameDecodes` and `testKickedStopsReconnectClearsRosterAndExplains`

- [x] **Step 5: Build the app target (regression check)**

Run: `cd ios && xcodebuild build -scheme Saetta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [x] **Step 6: Commit**

```bash
git add ios/Sources/Kit/Hub/HubMessages.swift ios/Sources/Kit/Hub/HubClient.swift ios/Tests/KitTests/HubClientTests.swift
git commit -m "feat(ios): honor the hub's kicked frame — stop reconnecting, explain, allow manual rejoin"
```

---

### Task 4: Full-suite pass + manual smoke notes

**Files:** none created; verification only.

- [x] **Step 1: Run every affected suite**

```bash
cd menubar-hub && npm test 2>&1 | tail -5
cd ../relay && npm test 2>&1 | tail -5
cd ../ios && xcodegen generate && xcodebuild test -scheme SaettaKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```

Expected: all PASS (relay is untouched — its suite is a regression check only).

- [x] **Step 2: Manual smoke (operator-driven, report instructions)**

Not automatable from this machine; print these instructions for the operator:

1. `cd menubar-hub && npm start` — popover shows **Disconnect all** greyed out under the (empty) roster.
2. Pair an iPhone running the updated Saetta build; button enables, roster shows the phone.
3. Click **Disconnect all** → confirm. Phone drops within a beat, shows "disconnected by hub", does NOT come back by itself; popover roster empties and the button re-disables.
4. On the phone tap Connect — it rejoins with the same code.

- [x] **Step 3: Commit any plan-checkbox updates**

```bash
git add docs/superpowers/plans/2026-06-11-hub-disconnect-all.md
git commit -m "docs: tick completed tasks on the disconnect-all plan"
```
