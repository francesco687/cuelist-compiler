import XCTest
@testable import SaettaKit

final class MacroSlotTests: XCTestCase {

    // MARK: Decoding — actions

    func test_decodes_library_action_id() {
        guard case .action(let action)? = MacroSlot(rawValue: "go_plus") else {
            return XCTFail("expected .action")
        }
        XCTAssertEqual(action.id, "go_plus")
    }

    // MARK: Decoding — legacy executor form (PR #32, no function segment)

    func test_decodes_legacy_unloaded_executor_as_toggle() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:"),
                       .executor(function: .toggle, target: nil))
    }

    func test_decodes_legacy_loaded_executor_as_toggle() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:201"),
                       .executor(function: .toggle, target: .number(201)))
    }

    // MARK: Decoding — new executor form exec:<function>:<target>

    func test_decodes_function_with_number_target() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:toggle:201"),
                       .executor(function: .toggle, target: .number(201)))
        XCTAssertEqual(MacroSlot(rawValue: "exec:flash:7"),
                       .executor(function: .flash, target: .number(7)))
        XCTAssertEqual(MacroSlot(rawValue: "exec:on:9999"),
                       .executor(function: .on, target: .number(9999)))
    }

    func test_decodes_function_with_name_target() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:flash:Blinders"),
                       .executor(function: .flash, target: .name("Blinders")))
    }

    func test_decodes_unloaded_executor_per_function() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:flash:"),
                       .executor(function: .flash, target: nil))
        XCTAssertEqual(MacroSlot(rawValue: "exec:on:"),
                       .executor(function: .on, target: nil))
    }

    func test_name_containing_colon_survives() {
        // Only the FIRST colon after "exec:" splits function from target.
        XCTAssertEqual(MacroSlot(rawValue: "exec:on:FX: Strobe"),
                       .executor(function: .on, target: .name("FX: Strobe")))
    }

    func test_rejects_unknown_and_malformed_strings() {
        XCTAssertNil(MacroSlot(rawValue: "ghost_action"))
        XCTAssertNil(MacroSlot(rawValue: "exec:abc"))          // legacy body must be digits
        XCTAssertNil(MacroSlot(rawValue: "exec:0"))
        XCTAssertNil(MacroSlot(rawValue: "exec:10000"))
        XCTAssertNil(MacroSlot(rawValue: "exec:-3"))
        XCTAssertNil(MacroSlot(rawValue: "exec:strobe:201"))   // unknown function
        XCTAssertNil(MacroSlot(rawValue: "exec:flash:0"))      // all-digits out of range
        XCTAssertNil(MacroSlot(rawValue: "exec:on:10000"))
        XCTAssertNil(MacroSlot(rawValue: "exec:toggle:   "))   // whitespace-only name
    }

    // MARK: Round-trip

    func test_rawValue_round_trips() {
        let slots: [MacroSlot] = [
            .action(MacroAction.find("off")!),
            .executor(function: .toggle, target: nil),
            .executor(function: .toggle, target: .number(1)),
            .executor(function: .flash, target: .number(9999)),
            .executor(function: .on, target: .name("Blinders")),
            .executor(function: .flash, target: .name("FX: Strobe")),
        ]
        for slot in slots {
            XCTAssertEqual(MacroSlot(rawValue: slot.rawValue), slot)
        }
    }

    func test_legacy_value_reencodes_in_new_form() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:201")!.rawValue, "exec:toggle:201")
        XCTAssertEqual(MacroSlot(rawValue: "exec:")!.rawValue, "exec:toggle:")
    }

    // MARK: Commands

    func test_toggle_command_has_no_release() {
        let slot = MacroSlot.executor(function: .toggle, target: .number(201))
        XCTAssertEqual(slot.command, "Toggle Executor 201")
        XCTAssertNil(slot.releaseCommand)
    }

    func test_flash_commands_press_and_release() {
        let slot = MacroSlot.executor(function: .flash, target: .number(201))
        XCTAssertEqual(slot.command, "Flash Executor 201")
        XCTAssertEqual(slot.releaseCommand, "FlashOff Executor 201")
    }

    func test_on_command_has_no_release() {
        let slot = MacroSlot.executor(function: .on, target: .number(201))
        XCTAssertEqual(slot.command, "On Executor 201")
        XCTAssertNil(slot.releaseCommand)
    }

    func test_named_target_renders_quoted() {
        let slot = MacroSlot.executor(function: .flash, target: .name("Blinders"))
        XCTAssertEqual(slot.command, "Flash Executor \"Blinders\"")
        XCTAssertEqual(slot.releaseCommand, "FlashOff Executor \"Blinders\"")
    }

    func test_unloaded_executor_has_no_commands() {
        XCTAssertNil(MacroSlot.executor(function: .flash, target: nil).command)
        XCTAssertNil(MacroSlot.executor(function: .flash, target: nil).releaseCommand)
    }

    func test_action_command_passes_through_and_has_no_release() {
        let slot = MacroSlot.action(MacroAction.find("go_plus")!)
        XCTAssertEqual(slot.command, "Go+")
        XCTAssertNil(slot.releaseCommand)
    }

    // MARK: Security / bad-command perimeter

    func test_rejects_names_with_quotes_or_control_characters() {
        XCTAssertNil(MacroSlot(rawValue: "exec:flash:A\""))
        XCTAssertNil(MacroSlot(rawValue: "exec:toggle:Bli\"nders"))
        XCTAssertNil(MacroSlot(rawValue: "exec:on:Line\nBreak"))
        XCTAssertNil(MacroSlot(rawValue: "exec:toggle:Tab\tName"))
        XCTAssertNil(MacroSlot(rawValue: "exec:toggle:\n"))
    }

    func test_non_ascii_numerics_decode_as_names() {
        XCTAssertEqual(MacroSlot(rawValue: "exec:toggle:Ⅻ"),
                       .executor(function: .toggle, target: .name("Ⅻ")))
        XCTAssertEqual(MacroSlot(rawValue: "exec:on:٢٠١"),
                       .executor(function: .on, target: .name("٢٠١")))
    }

    func test_fail_safe_perimeter() {
        XCTAssertNil(MacroSlot(rawValue: "exec:toggle"))     // no second colon, non-digit legacy body
        XCTAssertNil(MacroSlot(rawValue: "exec::201"))       // empty function
        XCTAssertNil(MacroSlot(rawValue: "exec:TOGGLE:201")) // case-sensitive functions
        XCTAssertNil(MacroSlot(rawValue: "exec:toggle:99999999999999999999")) // Int overflow
        // Legacy/new asymmetry: "-" is invalid in legacy bodies but a fine name char.
        XCTAssertNil(MacroSlot(rawValue: "exec:-3"))
        XCTAssertEqual(MacroSlot(rawValue: "exec:toggle:-3"),
                       .executor(function: .toggle, target: .name("-3")))
    }
}
