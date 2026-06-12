import XCTest
@testable import SaettaKit

@MainActor
final class MacroPadTests: XCTestCase {

    private func freshPad() -> MacroPad {
        MacroPad(defaults: UserDefaults(suiteName: "macropad.test.\(UUID().uuidString)")!)
    }

    func test_starts_with_four_empty_slots() {
        let pad = freshPad()
        XCTAssertEqual(pad.slots.count, 4)
        XCTAssertTrue(pad.slots.allSatisfy { $0 == nil })
    }

    func test_assign_sets_slot() {
        let pad = freshPad()
        pad.assign(slot: 0, action: MacroAction.find("off")!)
        XCTAssertEqual(pad.action(at: 0)?.id, "off")
    }

    func test_clear_empties_slot() {
        let pad = freshPad()
        pad.assign(slot: 1, action: MacroAction.find("on")!)
        pad.clear(slot: 1)
        XCTAssertNil(pad.action(at: 1))
    }

    func test_reassign_replaces() {
        let pad = freshPad()
        pad.assign(slot: 2, action: MacroAction.find("go_plus")!)
        pad.assign(slot: 2, action: MacroAction.find("top")!)
        XCTAssertEqual(pad.action(at: 2)?.id, "top")
    }

    func test_out_of_range_slot_is_safe_noop() {
        let pad = freshPad()
        pad.assign(slot: 9, action: MacroAction.find("off")!)
        pad.clear(slot: -1)
        XCTAssertNil(pad.action(at: 9))
        XCTAssertTrue(pad.slots.allSatisfy { $0 == nil })
    }

    func test_assignments_survive_reinit() {
        let suite = "macropad.persist.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let p1 = MacroPad(defaults: d)
        p1.assign(slot: 0, action: MacroAction.find("pause")!)
        p1.assign(slot: 3, action: MacroAction.find("go_minus")!)
        let p2 = MacroPad(defaults: d)
        XCTAssertEqual(p2.action(at: 0)?.id, "pause")
        XCTAssertEqual(p2.action(at: 3)?.id, "go_minus")
        XCTAssertNil(p2.action(at: 1))
    }

    func test_unknown_persisted_id_reads_as_nil_but_is_preserved() {
        let suite = "macropad.stale.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        // Simulate a slot persisted by a future/older build whose action id the
        // current library no longer knows. "" marks the other three empty slots.
        d.set(["ghost_action", "", "", ""], forKey: "macroPadSlots")

        let pad = MacroPad(defaults: d)

        XCTAssertNil(pad.action(at: 0), "unknown id must surface as an empty (nil) slot")
        XCTAssertEqual(pad.slots[0], "ghost_action", "raw id must be preserved, not auto-cleared")
    }

    // MARK: Executor slots

    func test_assignExecutor_sets_unloaded_executor_with_function() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .flash)
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .flash, target: nil))
        XCTAssertNil(pad.action(at: 0), "an executor slot is not an action")
    }

    func test_loadExecutor_targets_number_keeping_function() {
        let pad = freshPad()
        pad.assignExecutor(slot: 1, function: .on)
        pad.loadExecutor(slot: 1, target: .number(201))
        XCTAssertEqual(pad.slot(at: 1), .executor(function: .on, target: .number(201)))
    }

    func test_loadExecutor_targets_name_trimmed() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .toggle)
        pad.loadExecutor(slot: 0, target: .name("  Blinders "))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .toggle, target: .name("Blinders")))
    }

    func test_loadExecutor_rejects_blank_name() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .toggle)
        pad.loadExecutor(slot: 0, target: .name("   "))
        pad.loadExecutor(slot: 0, target: .name(" \n "))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .toggle, target: nil))
    }

    func test_loadExecutor_rejects_quote_and_control_names() {
        // Mirrors the MacroSlot codec rules — a name the codec would refuse to
        // decode must never be persisted in the first place.
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .flash)
        pad.loadExecutor(slot: 0, target: .name("Bli\"nders"))
        pad.loadExecutor(slot: 0, target: .name("Line\nBreak"))
        pad.loadExecutor(slot: 0, target: .name("Tab\tName"))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .flash, target: nil))
    }

    func test_loadExecutor_retargets_loaded_slot() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .flash)
        pad.loadExecutor(slot: 0, target: .number(201))
        pad.loadExecutor(slot: 0, target: .name("Blinders"))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .flash, target: .name("Blinders")))
    }

    func test_loadExecutor_rejects_out_of_range_number() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .toggle)
        pad.loadExecutor(slot: 0, target: .number(0))
        pad.loadExecutor(slot: 0, target: .number(10000))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .toggle, target: nil))
    }

    func test_loadExecutor_on_non_executor_slot_is_noop() {
        let pad = freshPad()
        pad.assign(slot: 2, action: MacroAction.find("off")!)
        pad.loadExecutor(slot: 2, target: .number(201))
        XCTAssertEqual(pad.slot(at: 2), .action(MacroAction.find("off")!))
        pad.loadExecutor(slot: 3, target: .number(201))   // empty slot
        XCTAssertNil(pad.slot(at: 3), "loadExecutor on an empty slot must stay a noop")
    }

    func test_assignExecutor_out_of_range_slot_is_safe_noop() {
        let pad = freshPad()
        pad.assignExecutor(slot: 9, function: .toggle)
        pad.assignExecutor(slot: -1, function: .flash)
        XCTAssertTrue(pad.slots.allSatisfy { $0 == nil })
    }

    func test_executor_assignments_survive_reinit() {
        let suite = "macropad.exec.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let p1 = MacroPad(defaults: d)
        p1.assignExecutor(slot: 0, function: .flash)
        p1.loadExecutor(slot: 0, target: .name("Blinders"))
        p1.assignExecutor(slot: 2, function: .on)
        let p2 = MacroPad(defaults: d)
        XCTAssertEqual(p2.slot(at: 0), .executor(function: .flash, target: .name("Blinders")))
        XCTAssertEqual(p2.slot(at: 2), .executor(function: .on, target: nil))
        XCTAssertNil(p2.slot(at: 1))
    }

    func test_legacy_persisted_executor_loads_as_toggle() {
        let suite = "macropad.legacy.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        // A pad saved by the PR #32 build (pre-function codec).
        d.set(["exec:201", "exec:", "", ""], forKey: "macroPadSlots")
        let pad = MacroPad(defaults: d)
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .toggle, target: .number(201)))
        XCTAssertEqual(pad.slot(at: 1), .executor(function: .toggle, target: nil))
    }

    func test_slot_at_decodes_actions_too() {
        let pad = freshPad()
        pad.assign(slot: 0, action: MacroAction.find("pause")!)
        XCTAssertEqual(pad.slot(at: 0), .action(MacroAction.find("pause")!))
    }

    func test_loadExecutor_coerces_digit_name_to_number() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .toggle)
        pad.loadExecutor(slot: 0, target: .name(" 201 "))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .toggle, target: .number(201)))
    }

    func test_loadExecutor_rejects_out_of_range_digit_names() {
        // Without this, the pad would persist a string the codec refuses to
        // decode — a quietly dead cell.
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .flash)
        pad.loadExecutor(slot: 0, target: .name("0"))
        pad.loadExecutor(slot: 0, target: .name("10000"))
        pad.loadExecutor(slot: 0, target: .name("99999999999999999999"))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .flash, target: nil))
    }

    func test_loadExecutor_rejects_padded_out_of_range_digit_names() {
        let pad = freshPad()
        pad.assignExecutor(slot: 0, function: .flash)
        pad.loadExecutor(slot: 0, target: .name(" 0 "))
        pad.loadExecutor(slot: 0, target: .name(" 10000 "))
        pad.loadExecutor(slot: 0, target: .name(" 99999999999999999999 "))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .flash, target: nil))
    }

    func test_loadExecutor_retargets_legacy_slot_preserving_toggle() {
        let suite = "macropad.legacyupgrade.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(["exec:201", "", "", ""], forKey: "macroPadSlots")
        let pad = MacroPad(defaults: d)
        pad.loadExecutor(slot: 0, target: .name("Blinders"))
        XCTAssertEqual(pad.slot(at: 0), .executor(function: .toggle, target: .name("Blinders")))
        XCTAssertEqual(pad.slots[0], "exec:toggle:Blinders", "persisted form upgrades in place")
    }
}
