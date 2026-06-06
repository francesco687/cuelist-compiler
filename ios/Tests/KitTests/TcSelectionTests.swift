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

    func test_selection_not_persisted() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let id = UUID()
        do { let s = ProjectStore(directory: dir); s.toggleTc(id); s.saveNow() }
        let reloaded = ProjectStore(directory: dir)
        XCTAssertTrue(reloaded.tcSelection.isEmpty, "TC ticks must never persist across launches")
    }
}
