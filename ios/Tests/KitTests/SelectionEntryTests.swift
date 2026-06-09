// Tests/KitTests/SelectionEntryTests.swift
import XCTest
@testable import SaettaKit

final class SelectionEntryTests: XCTestCase {

    func test_single_fixture() {
        var e = SelectionEntry()
        e.tapKeyword(.fixture); e.tapDigit(1); e.tapDigit(0); e.tapDigit(1)
        XCTAssertEqual(e.command, "Fixture 101")
        XCTAssertFalse(e.isEmpty)
    }

    func test_fixture_range_with_thru() {
        var e = SelectionEntry()
        e.tapKeyword(.fixture); e.tapDigit(1); e.tapDigit(0); e.tapDigit(1)
        e.tapKeyword(.thru); e.tapDigit(1); e.tapDigit(0); e.tapDigit(5)
        XCTAssertEqual(e.command, "Fixture 101 Thru 105")
    }

    func test_group_then_plus_fixture() {
        var e = SelectionEntry()
        e.tapKeyword(.group); e.tapDigit(2)
        e.tapKeyword(.plus); e.tapKeyword(.fixture); e.tapDigit(7)
        XCTAssertEqual(e.command, "Group 2 + Fixture 7")
    }

    func test_backspace_removes_trailing_digit_then_token() {
        var e = SelectionEntry()
        e.tapKeyword(.fixture); e.tapDigit(1); e.tapDigit(2)
        e.backspace()                       // "Fixture 1"
        XCTAssertEqual(e.command, "Fixture 1")
        e.backspace()                       // "Fixture"
        XCTAssertEqual(e.command, "Fixture")
        e.backspace()                       // ""
        XCTAssertEqual(e.command, "")
        XCTAssertTrue(e.isEmpty)
    }

    func test_reset_clears_everything() {
        var e = SelectionEntry()
        e.tapKeyword(.fixture); e.tapDigit(9)
        e.reset()
        XCTAssertTrue(e.isEmpty)
        XCTAssertEqual(e.command, "")
    }
}
