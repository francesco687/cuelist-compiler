import XCTest
@testable import SaettaKit

@MainActor      // ProjectStore is @MainActor-isolated; the test class must match
final class ProjectStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-store-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testStartsWithEmptyProjectWhenNoFiles() {
        let store = ProjectStore(directory: tempDir())
        XCTAssertEqual(store.project.songs.count, 1)
        XCTAssertEqual(store.project.songs[0].cues.count, 0)
        XCTAssertEqual(store.project.storeMode, .overwrite)
    }

    func testSaveThenReloadRoundTrips() throws {
        let dir = tempDir()
        let store = ProjectStore(directory: dir)
        store.project.songs[0].name = "My Show"
        store.project.songs[0].sequence = 42
        store.defaults.values[.color] = Preset(fade: "3")
        store.saveNow()

        let reloaded = ProjectStore(directory: dir)
        XCTAssertEqual(reloaded.project.songs[0].name, "My Show")
        XCTAssertEqual(reloaded.project.songs[0].sequence, 42)
        XCTAssertEqual(reloaded.defaults.fade(.color), "3")
    }

    func testProjectFileIsShowJsonCompatible() throws {
        let dir = tempDir()
        let store = ProjectStore(directory: dir)
        store.project.songs[0].name = "Interop"
        store.saveNow()
        let data = try Data(contentsOf: dir.appendingPathComponent("project.json"))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(obj["songs"])
        XCTAssertNotNil(obj["activeSongId"])
        XCTAssertEqual(obj["storeMode"] as? String, "Overwrite")
    }

    func testLoadUpgradesOldFormatFile() throws {
        let dir = tempDir()
        // Write an OLD-format file (no `songs`, bare-string presets) directly.
        let old = """
        {"songName":"Legacy","sequence":12,"cues":[
          {"n":1,"name":"A","fade":"2","actions":[{"group":"G","presets":{"color":"BLUE"}}]}]}
        """.data(using: .utf8)!
        try old.write(to: dir.appendingPathComponent("project.json"))

        let store = ProjectStore(directory: dir)
        XCTAssertEqual(store.project.songs.count, 1)
        XCTAssertEqual(store.project.songs[0].name, "Legacy")
        XCTAssertEqual(store.project.songs[0].cues[0].actions[0].presets[.color]?.name, "BLUE")
    }
}
