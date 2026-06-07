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
}
