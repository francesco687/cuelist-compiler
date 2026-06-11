import XCTest
@testable import SaettaKit

final class SmokeTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(SaettaKit.schemaVersion, 1)
    }
}
