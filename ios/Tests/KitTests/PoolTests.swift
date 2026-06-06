import XCTest
@testable import SaettaKit

final class PoolTests: XCTestCase {
    func testCanonicalOrder() {
        XCTAssertEqual(Pool.allCases, [.color, .dimmer, .position, .gobo, .beam, .focus])
    }

    func testPoolNumbers() {
        XCTAssertEqual(Pool.dimmer.number, 1)
        XCTAssertEqual(Pool.position.number, 2)
        XCTAssertEqual(Pool.gobo.number, 3)
        XCTAssertEqual(Pool.color.number, 4)
        XCTAssertEqual(Pool.beam.number, 5)
        XCTAssertEqual(Pool.focus.number, 6)
    }

    func testRawValuesMatchSchema() {
        XCTAssertEqual(Pool.color.rawValue, "color")
        XCTAssertEqual(Pool.allCases.map(\.rawValue),
                       ["color", "dimmer", "position", "gobo", "beam", "focus"])
    }

    func testStoreModeFlag() {
        XCTAssertEqual(StoreMode.overwrite.flag, "/Overwrite")
        XCTAssertEqual(StoreMode.merge.flag, "/Merge")
    }
}
