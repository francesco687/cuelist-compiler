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
