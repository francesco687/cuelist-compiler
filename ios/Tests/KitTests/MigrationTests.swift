import XCTest
@testable import SaettaKit

final class MigrationTests: XCTestCase {
    private func loadSong1Raw() throws -> Data {
        let url = Bundle(for: MigrationTests.self).url(forResource: "SONG_1", withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url))
    }

    func testOldFormatUpgradesToOneSong() throws {
        let project = try Migration.project(fromShowJSON: loadSong1Raw())
        XCTAssertEqual(project.songs.count, 1)
        let song = project.songs[0]
        XCTAssertEqual(song.name, "SONG 1")
        XCTAssertEqual(song.sequence, 666)
        XCTAssertEqual(song.cues.count, 2)
    }

    func testBareStringPresetsBecomeObjects() throws {
        let project = try Migration.project(fromShowJSON: loadSong1Raw())
        let action = project.songs[0].cues[0].actions[0]
        XCTAssertEqual(action.group, "AROLLA FLOOR")
        XCTAssertEqual(action.presets[.color]?.name, "BLUE")
        XCTAssertEqual(action.presets[.dimmer]?.name, "DIMMER 100")
        XCTAssertEqual(action.presets[.gobo]?.name, "")
        XCTAssertEqual(action.presets[.focus]?.name, "MEDIUM")
        XCTAssertEqual(action.presets[.color]?.fade, "")
    }

    func testCueScalars() throws {
        let project = try Migration.project(fromShowJSON: loadSong1Raw())
        XCTAssertEqual(project.songs[0].cues[0].n, 0.1)
        XCTAssertEqual(project.songs[0].cues[0].name, "DB CUE")
        XCTAssertEqual(project.songs[0].cues[0].fade, "5")
    }
}
