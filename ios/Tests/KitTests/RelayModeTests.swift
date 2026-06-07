import XCTest
@testable import SaettaKit

final class RelayModeTests: XCTestCase {
    func testJoinFrameEncodesRoleRoomAndName() throws {
        let json = try OutgoingMessage.join(room: "code1234", role: "phone", name: "Matteo's iPhone").jsonString()
        XCTAssertTrue(json.contains("\"type\":\"join\""))
        XCTAssertTrue(json.contains("\"room\":\"code1234\""))
        XCTAssertTrue(json.contains("\"role\":\"phone\""))
        XCTAssertTrue(json.contains("\"name\":\"Matteo's iPhone\""))
    }

    func testDecodePeerConnected() throws {
        let msg = try IncomingMessage.decode("{\"type\":\"peer\",\"connected\":true}")
        XCTAssertEqual(msg, .peer(connected: true))
    }

    func testDecodeJoinedWithCid() throws {
        let msg = try IncomingMessage.decode("{\"type\":\"joined\",\"cid\":\"p1\"}")
        XCTAssertEqual(msg, .joined(cid: "p1"))
    }

    func testDecodeRoster() throws {
        let msg = try IncomingMessage.decode(
            "{\"type\":\"roster\",\"hub\":true,\"phones\":[{\"cid\":\"p1\",\"name\":\"Matteo\"}]}")
        XCTAssertEqual(msg, .roster(hub: true, phones: [Operator(cid: "p1", name: "Matteo")]))
    }

    func testDecodeJoinError() throws {
        let msg = try IncomingMessage.decode("{\"type\":\"join-error\",\"message\":\"role taken\"}")
        XCTAssertEqual(msg, .joinError(message: "role taken"))
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

    func testJoinErrorSurfacesReasonAsErrorState() {
        let conn = FakeConn()
        let c = makeClient(conn)
        c.connect()
        conn.onEvent?(.opened)
        conn.onEvent?(.text("{\"type\":\"join-error\",\"message\":\"role taken\"}"))
        XCTAssertEqual(c.state, .error("role taken"))
    }
}
