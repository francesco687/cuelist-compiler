import XCTest
@testable import CuelistCompilerKit

final class HubMessagesTests: XCTestCase {
    func testEncodeCompileSendHasShowJsonShape() throws {
        let project = Project.empty()
        let msg = OutgoingMessage.compileSend(project: project, defaults: Defaults(), selection: .all)
        let data = try msg.jsonData()
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["type"] as? String, "compile-send")
        XCTAssertEqual(obj["selection"] as? String, "all")
        let proj = obj["project"] as! [String: Any]
        XCTAssertNotNil(proj["songs"])
        XCTAssertNotNil(proj["activeSongId"])
        XCTAssertEqual(proj["storeMode"] as? String, "Overwrite")
        XCTAssertNotNil(obj["defaults"])
    }

    func testDecodeProgress() throws {
        let m = try IncomingMessage.decode(#"{"type":"progress","sent":3,"total":17}"#)
        XCTAssertEqual(m, .progress(sent: 3, total: 17))
    }

    func testDecodeDone() throws {
        XCTAssertEqual(try IncomingMessage.decode(#"{"type":"done","total":17}"#), .done(total: 17))
    }

    func testDecodeError() throws {
        XCTAssertEqual(try IncomingMessage.decode(#"{"type":"error","message":"nope"}"#),
                       .error(message: "nope"))
    }

    func testDecodeUnknownTypeIsIgnored() throws {
        XCTAssertEqual(try IncomingMessage.decode(#"{"type":"pong"}"#), .other)
    }
}
