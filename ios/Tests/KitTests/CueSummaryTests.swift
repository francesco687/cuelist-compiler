import XCTest
@testable import SaettaKit

final class CueSummaryTests: XCTestCase {
    func testSummaryComposesParts() {
        var cue = Cue(n: 1, name: "Intro", fade: "5", delay: "", position: "VERSE")
        cue.actions = [Action(group: "A"), Action(group: "B"), Action(group: "  ")]
        XCTAssertEqual(CueSummary.text(for: cue), "VERSE · 2 groups · fade 5")
    }

    func testEmptySummaryIsEmptyString() {
        var cue = Cue(n: 1)
        cue.actions = [Action()]            // empty group → not counted
        XCTAssertEqual(CueSummary.text(for: cue), "")
    }

    func testPoolAbbreviations() {
        XCTAssertEqual(Pool.color.abbreviation, "COL")
        XCTAssertEqual(Pool.dimmer.abbreviation, "DIM")
        XCTAssertEqual(Pool.focus.abbreviation, "FOC")
    }

    func testActionColorsPaletteNonEmpty() {
        XCTAssertEqual(PoolDisplay.actionColors.first, "#d63a3a")
        XCTAssertEqual(PoolDisplay.actionColors.count, 19)
    }
}
