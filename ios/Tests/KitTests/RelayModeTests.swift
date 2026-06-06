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
