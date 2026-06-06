import XCTest
@testable import SaettaKit

@MainActor
final class TcSelectionTests: XCTestCase {
    private func store() -> ProjectStore {
        ProjectStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    func test_toggle_and_clear() {
        let s = store()
        let id = UUID()
        XCTAssertFalse(s.isTcSelected(id))
        s.toggleTc(id)
        XCTAssertTrue(s.isTcSelected(id))
        s.toggleTc(id)
        XCTAssertFalse(s.isTcSelected(id))
        s.toggleTc(id)
        s.clearTcSelection()
        XCTAssertTrue(s.tcSelection.isEmpty)
    }

    func test_removeTc_removes_only_that_id() {
        let s = store()
        let a = UUID(), b = UUID()
        s.toggleTc(a); s.toggleTc(b)
        s.removeTc(a)
        XCTAssertFalse(s.isTcSelected(a))
        XCTAssertTrue(s.isTcSelected(b))
        s.removeTc(a)   // removing an absent id is a no-op
        XCTAssertTrue(s.isTcSelected(b))
    }

    func test_removeCue_clears_its_tick() {
        let s = store()
        s.addCue()
        let id = s.activeSong.cues[0].id
        s.toggleTc(id)
        XCTAssertTrue(s.isTcSelected(id))
        s.removeCue(id: id)
        XCTAssertFalse(s.isTcSelected(id), "deleting a cue must drop its TC tick (no ghost UUID)")
    }

    func test_removeCues_clears_their_ticks() {
        let s = store()
        s.addCue(); s.addCue()
        let a = s.activeSong.cues[0].id, b = s.activeSong.cues[1].id
        s.toggleTc(a); s.toggleTc(b)
        s.removeCues(ids: [a, b])
        XCTAssertTrue(s.tcSelection.isEmpty, "bulk-deleting cues must drop their TC ticks")
    }

    func test_selection_not_persisted() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let id = UUID()
        do { let s = ProjectStore(directory: dir); s.toggleTc(id); s.saveNow() }
        let reloaded = ProjectStore(directory: dir)
        XCTAssertTrue(reloaded.tcSelection.isEmpty, "TC ticks must never persist across launches")
    }
}
