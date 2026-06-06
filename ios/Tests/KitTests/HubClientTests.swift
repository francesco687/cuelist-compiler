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
