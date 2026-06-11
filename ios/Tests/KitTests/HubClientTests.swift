import XCTest
@testable import SaettaKit

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

    /// Build a client already driven to `.online` with a connected mock socket.
    private func makeOnlineClient() -> (HubClient, MockHubConnection) {
        let (client, mock) = makeClient()
        client.connect(); mock.emit(.opened)
        return (client, mock)
    }

    /// Parse a captured `cmd` frame string back to its `line` value (nil if not a cmd frame).
    private func frameToCmdLine(_ frame: String) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: Any],
              obj["type"] as? String == "cmd" else { return nil }
        return obj["line"] as? String
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

    func testPullSequencesEmitsRequestAndStoresList() throws {
        let (client, mock) = makeClient()
        client.connect(); mock.emit(.opened)
        client.pullSequences()

        XCTAssertTrue(client.isPulling)
        XCTAssertEqual(mock.sent.count, 1)
        let obj = try JSONSerialization.jsonObject(with: Data(mock.sent[0].utf8)) as! [String: Any]
        XCTAssertEqual(obj["type"] as? String, "pull-sequences")

        mock.emit(.text(#"{"type":"sequences","version":1,"sequences":[{"no":1,"name":"A"},{"no":666,"name":"B"}]}"#))
        XCTAssertFalse(client.isPulling)
        XCTAssertEqual(client.sequences?.count, 2)
        XCTAssertEqual(client.sequences?.first, PulledSequence(no: 1, name: "A"))
        XCTAssertNil(client.pullError)
    }

    func testPullErrorSetsPullError() {
        let (client, mock) = makeClient()
        client.connect(); mock.emit(.opened)
        client.pullSequences()
        mock.emit(.text(#"{"type":"pull-error","message":"timed out"}"#))
        XCTAssertFalse(client.isPulling)
        XCTAssertEqual(client.pullError, "timed out")
        XCTAssertNil(client.sequences)
    }

    func testSendCommandEmitsCmdFrame() throws {
        let (client, mock) = makeClient()
        client.connect(); mock.emit(.opened)
        client.sendCommand("Go+")
        XCTAssertEqual(mock.sent.count, 1)
        let obj = try JSONSerialization.jsonObject(with: Data(mock.sent[0].utf8)) as! [String: Any]
        XCTAssertEqual(obj["type"] as? String, "cmd")
        XCTAssertEqual(obj["line"] as? String, "Go+")
    }

    func test_sendLines_sends_each_line_as_cmd_and_reports_done() async {
        let (client, spy) = makeOnlineClient()
        client.sendLines(["A", "B", "C"], intervalMs: 0)
        // Let the throttled Task drain.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let sentLines = spy.sent.compactMap { frameToCmdLine($0) }
        XCTAssertEqual(sentLines, ["A", "B", "C"])
        XCTAssertEqual(client.lastResult, .done(total: 3))
        XCTAssertNil(client.progress)
    }

    func test_sendLines_supersedes_prior_batch_cleanly() async {
        let (client, spy) = makeOnlineClient()
        // First batch with a real interval so it is still in flight when the second starts.
        client.sendLines(["X1", "X2", "X3"], intervalMs: 50)
        // Immediately supersede with a fast second batch.
        client.sendLines(["A", "B", "C"], intervalMs: 0)
        try? await Task.sleep(nanoseconds: 300_000_000)  // let everything drain
        let sent = spy.sent.compactMap { frameToCmdLine($0) }
        // The final result must reflect the SECOND batch, not be stomped by the first.
        XCTAssertEqual(client.lastResult, .done(total: 3))
        XCTAssertNil(client.progress)
        // The second batch's lines must all have been sent in order.
        XCTAssertEqual(sent.suffix(3), ["A", "B", "C"])
        // The first batch was cancelled, so its completion never overwrote the second's.
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

    // MARK: - Task 8: roster-driven state, device-name identity, auto-reconnect

    func testRosterDrivesOnlineState() {
        let (client, mock) = makeClient()
        client.mode = .relay; client.relayURL = "wss://x"; client.pairingCode = "code1234"
        client.connect(); mock.emit(.opened)
        XCTAssertEqual(client.state, .connecting)
        mock.emit(.text("{\"type\":\"roster\",\"hub\":true,\"phones\":[{\"cid\":\"p1\",\"name\":\"Matteo\"}]}"))
        XCTAssertEqual(client.state, .online)
        XCTAssertEqual(client.roster, [Operator(cid: "p1", name: "Matteo")])
        mock.emit(.text("{\"type\":\"roster\",\"hub\":false,\"phones\":[]}"))
        XCTAssertEqual(client.state, .connecting)
    }

    func testJoinSendsOperatorName() {
        let (client, mock) = makeClient()
        client.mode = .relay; client.relayURL = "wss://x"; client.pairingCode = "code1234"
        client.operatorName = "Matteo's iPhone"
        client.connect(); mock.emit(.opened)
        XCTAssertTrue(mock.sent.contains { $0.contains("\"name\":\"Matteo's iPhone\"") })
    }

    func testOperatorNamePersists() {
        let suite = "cc-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let c1 = HubClient(defaults: d, makeConnection: { _ in MockHubConnection() })
        XCTAssertEqual(c1.operatorName, "", "a fresh install has no name")
        c1.operatorName = "Francesco"
        let c2 = HubClient(defaults: d, makeConnection: { _ in MockHubConnection() })
        XCTAssertEqual(c2.operatorName, "Francesco")
    }

    func testHasNameTrimsWhitespace() {
        let (client, _) = makeClient()
        client.operatorName = ""
        XCTAssertFalse(client.hasName)
        client.operatorName = "   "
        XCTAssertFalse(client.hasName, "whitespace-only is not a name")
        client.operatorName = "  Matteo  "
        XCTAssertTrue(client.hasName)
    }

    func testAutoReconnectAfterCloseInRelayMode() {
        var conns: [MockHubConnection] = []
        var scheduled: [() -> Void] = []
        let d = UserDefaults(suiteName: "cc-test-\(UUID().uuidString)")!
        let client = HubClient(defaults: d,
                               makeConnection: { _ in let m = MockHubConnection(); conns.append(m); return m },
                               scheduleAfter: { _, work in scheduled.append(work) })
        client.mode = .relay; client.relayURL = "wss://x"; client.pairingCode = "code1234"
        client.connect()
        XCTAssertEqual(conns.count, 1)
        conns[0].emit(.closed(nil))
        XCTAssertEqual(scheduled.count, 1)     // a reconnect was scheduled
        scheduled[0]()                          // fire it
        XCTAssertEqual(conns.count, 2)          // reconnected with a fresh connection
    }

    func testNoReconnectAfterManualDisconnect() {
        var conns: [MockHubConnection] = []
        var scheduled: [() -> Void] = []
        let d = UserDefaults(suiteName: "cc-test-\(UUID().uuidString)")!
        let client = HubClient(defaults: d,
                               makeConnection: { _ in let m = MockHubConnection(); conns.append(m); return m },
                               scheduleAfter: { _, work in scheduled.append(work) })
        client.mode = .relay; client.relayURL = "wss://x"; client.pairingCode = "code1234"
        client.connect()
        client.disconnect()
        conns[0].emit(.closed(nil))
        XCTAssertEqual(scheduled.count, 0)     // user asked to stop; don't reconnect
    }

    // MARK: - Task 3: kicked frame

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

    func testBackoffDoublesAndCapsThenResetsOnHub() {
        // Backoff math: wait = backoff; backoff = min(backoff*2, 15)
        // Sequence: 1, 2, 4, 8, 15(=min(16,15)), 15(=min(30,15)) → [1,2,4,8,15,15]
        // After a roster with hub:true, backoff resets to 1 → next wait = 1.
        var conns: [MockHubConnection] = []
        var delays: [TimeInterval] = []
        var fire: [() -> Void] = []
        let d = UserDefaults(suiteName: "cc-test-\(UUID().uuidString)")!
        let client = HubClient(defaults: d,
                               makeConnection: { _ in let m = MockHubConnection(); conns.append(m); return m },
                               scheduleAfter: { delay, work in delays.append(delay); fire.append(work) })
        client.mode = .relay; client.relayURL = "wss://x"; client.pairingCode = "code1234"
        client.connect()                        // conns[0]
        // Drop 6 times, firing each scheduled reconnect to build the next connection.
        for i in 0..<6 {
            conns[i].emit(.closed(nil))         // triggers scheduleReconnect → appends to delays/fire
            fire[i]()                           // fires → connect() → builds conns[i+1]
        }
        XCTAssertEqual(delays, [1, 2, 4, 8, 15, 15])
        // conns[6] is now live; a healthy roster message resets backoff to 1.
        conns[6].emit(.text("{\"type\":\"roster\",\"hub\":true,\"phones\":[]}"))
        conns[6].emit(.closed(nil))             // triggers scheduleReconnect with reset backoff
        XCTAssertEqual(delays.last, 1)
    }
}
