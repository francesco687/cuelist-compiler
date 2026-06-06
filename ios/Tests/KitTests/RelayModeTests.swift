import XCTest
@testable import CuelistCompilerKit

final class RelayModeTests: XCTestCase {
    func testJoinFrameEncodesRoleAndRoom() throws {
        let json = try OutgoingMessage.join(room: "CODE1234", role: "phone").jsonString()
        XCTAssertTrue(json.contains("\"type\":\"join\""))
        XCTAssertTrue(json.contains("\"room\":\"CODE1234\""))
        XCTAssertTrue(json.contains("\"role\":\"phone\""))
    }

    func testDecodePeerConnected() throws {
        let msg = try IncomingMessage.decode("{\"type\":\"peer\",\"connected\":true}")
        XCTAssertEqual(msg, .peer(connected: true))
    }

    func testDecodeJoined() throws {
        let msg = try IncomingMessage.decode("{\"type\":\"joined\"}")
        XCTAssertEqual(msg, .joined)
    }
}

@MainActor
final class HubClientRelayTests: XCTestCase {
    // A fake connection that records sends and lets the test drive events.
    final class FakeConn: HubConnection {
        var sent: [String] = []
        var onEvent: ((HubConnectionEvent) -> Void)?
        func connect(onEvent: @escaping (HubConnectionEvent) -> Void) { self.onEvent = onEvent }
        func send(_ text: String) { sent.append(text) }
        func close() {}
    }

    func makeClient(_ conn: FakeConn) -> HubClient {
        let d = UserDefaults(suiteName: "relay.test.\(UUID().uuidString)")!
        let c = HubClient(defaults: d, makeConnection: { _ in conn })
        c.mode = .relay
        c.relayURL = "wss://cuelist-relay.fly.dev"
        c.pairingCode = "CODE1234"
        return c
    }

    func testRelayConnectSendsJoinOnOpen() {
        let conn = FakeConn()
        let c = makeClient(conn)
        c.connect()
        conn.onEvent?(.opened)
        XCTAssertTrue(conn.sent.contains { $0.contains("\"type\":\"join\"") && $0.contains("CODE1234") })
    }

    func testStaysConnectingUntilPeerThenOnline() {
        let conn = FakeConn()
        let c = makeClient(conn)
        c.connect()
        conn.onEvent?(.opened)
        XCTAssertEqual(c.state, .connecting)                       // joined, but no phone-side peer yet
        conn.onEvent?(.text("{\"type\":\"peer\",\"connected\":true}"))
        XCTAssertEqual(c.state, .online)
        conn.onEvent?(.text("{\"type\":\"peer\",\"connected\":false}"))
        XCTAssertEqual(c.state, .connecting)
    }

    func testRelayURLBuiltFromRelayURLNotHostPort() {
        let conn = FakeConn()
        let c = makeClient(conn)
        XCTAssertEqual(c.url?.absoluteString, "wss://cuelist-relay.fly.dev")
    }
}
