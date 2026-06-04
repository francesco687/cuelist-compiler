import XCTest
@testable import CuelistCompilerKit

final class SmokeTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(CuelistCompilerKit.schemaVersion, 1)
    }
}
