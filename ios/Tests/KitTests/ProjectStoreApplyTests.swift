import XCTest
@testable import SaettaKit

@MainActor
final class ProjectStoreApplyTests: XCTestCase {
    func testApplyCommitsProjectAndDefaults() {
        let store = ProjectStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
        var p = Project.empty(); p.songs[0].name = "From Voice"
        var d = Defaults(); d.values[.dimmer] = Preset(fade: "9")
        let result = ApplyResult(project: p, defaults: d, summary: [], warnings: [])
        store.apply(result)
        XCTAssertEqual(store.project.songs[0].name, "From Voice")
        XCTAssertEqual(store.defaults.fade(.dimmer), "9")
    }
}
