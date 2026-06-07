import XCTest
@testable import SaettaKit

final class MacroActionTests: XCTestCase {

    func test_library_has_six_actions() {
        XCTAssertEqual(MacroAction.library.count, 6)
    }

    func test_library_ids_are_unique() {
        let ids = MacroAction.library.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func test_every_action_has_nonempty_fields() {
        for a in MacroAction.library {
            XCTAssertFalse(a.id.isEmpty, "id empty")
            XCTAssertFalse(a.title.isEmpty, "title empty for \(a.id)")
            XCTAssertFalse(a.symbol.isEmpty, "symbol empty for \(a.id)")
            XCTAssertFalse(a.command.isEmpty, "command empty for \(a.id)")
        }
    }

    func test_command_strings_match_desk_keywords() {
        XCTAssertEqual(MacroAction.find("go_plus")?.command, "Go+")
        XCTAssertEqual(MacroAction.find("go_minus")?.command, "Go-")
        XCTAssertEqual(MacroAction.find("pause")?.command, "Pause")
        XCTAssertEqual(MacroAction.find("off")?.command, "Off")
        XCTAssertEqual(MacroAction.find("on")?.command, "On")
        XCTAssertEqual(MacroAction.find("top")?.command, "Top")
    }

    func test_find_returns_nil_for_unknown_id() {
        XCTAssertNil(MacroAction.find("nope"))
    }
}
