import XCTest
@testable import SaettaKit

final class MacroSlotTests: XCTestCase {

    // MARK: Decoding

    func test_decodes_library_action_id() {
        guard case .action(let action)? = MacroSlot(rawValue: "go_plus") else {
            return XCTFail("expected .action")
        }
        XCTAssertEqual(action.id, "go_plus")
    }

    func test_decodes_unloaded_executor() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:"), .executor(number: nil))
    }

    func test_decodes_loaded_executor() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:201"), .executor(number: 201))
    }

    func test_rejects_unknown_and_malformed_strings() {
        XCTAssertNil(MacroSlot(rawValue: "ghost_action"))
        XCTAssertNil(MacroSlot(rawValue: "exec:abc"))
        XCTAssertNil(MacroSlot(rawValue: "exec:0"))
        XCTAssertNil(MacroSlot(rawValue: "exec:10000"))
        XCTAssertNil(MacroSlot(rawValue: "exec:-3"))
    }

    // MARK: Round-trip

    func test_rawValue_round_trips() {
        let slots: [MacroSlot] = [
            .action(MacroAction.find("off")!),
            .executor(number: nil),
            .executor(number: 1),
            .executor(number: 9999),
        ]
        for slot in slots {
            XCTAssertEqual(MacroSlot(rawValue: slot.rawValue), slot)
        }
    }

    // MARK: Command

    func test_loaded_executor_builds_toggle_command() {
        XCTAssertEqual(MacroSlot.executor(number: 201).command, "Toggle Executor 201")
    }

    func test_unloaded_executor_has_no_command() {
        XCTAssertNil(MacroSlot.executor(number: nil).command)
    }

    func test_action_command_passes_through() {
        XCTAssertEqual(MacroSlot.action(MacroAction.find("go_plus")!).command, "Go+")
    }
}
