import XCTest
@testable import SaettaKit

final class SmpteTests: XCTestCase {
    func test_isValid_accepts_well_formed_25fps() {
        XCTAssertTrue(Smpte.isValid("00:00:00:00"))
        XCTAssertTrue(Smpte.isValid("01:23:45:24"))   // FF 24 ok at 25 fps
    }
    func test_isValid_rejects_malformed_or_out_of_range() {
        XCTAssertFalse(Smpte.isValid(""))
        XCTAssertFalse(Smpte.isValid("1:2:3:4"))
        XCTAssertFalse(Smpte.isValid("00:60:00:00")) // MM >= 60
        XCTAssertFalse(Smpte.isValid("00:00:60:00")) // SS >= 60
        XCTAssertFalse(Smpte.isValid("00:00:00:25")) // FF >= 25
        XCTAssertFalse(Smpte.isValid("00:00:00"))
    }
    func test_secondsString_converts_at_25fps() {
        XCTAssertEqual(Smpte.secondsString("00:00:00:00"), "0.0")
        XCTAssertEqual(Smpte.secondsString("00:00:05:00"), "5.0")
        XCTAssertEqual(Smpte.secondsString("00:00:00:05"), "0.2")   // 5/25
        XCTAssertEqual(Smpte.secondsString("01:00:00:00"), "3600.0")
        XCTAssertNil(Smpte.secondsString("bad"))
    }
}
