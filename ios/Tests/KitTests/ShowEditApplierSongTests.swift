import XCTest
@testable import CuelistCompilerKit

final class ShowEditApplierSongTests: XCTestCase {
    private func base() -> Project {
        Project(songs: [
            Song(id: "a", name: "Opener", sequence: 1, cues: []),
            Song(id: "b", name: "Closer", sequence: 2, cues: [])
        ], activeSongId: "a")
    }

    func testAddSongAppendsAndSummarizes() {
        let r = ShowEditApplier.apply([.addSong(name: "Encore", sequence: 12)],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs.count, 3)
        XCTAssertEqual(r.project.songs.last?.name, "Encore")
        XCTAssertEqual(r.project.songs.last?.sequence, 12)
        XCTAssertEqual(r.project.activeSongId, r.project.songs.last?.id)
        XCTAssertEqual(r.summary, ["Add song \u{201C}Encore\u{201D} (sequence 12)"])
        XCTAssertTrue(r.warnings.isEmpty)
    }

    func testRenameByOrdinalAndSequenceByName() {
        let r = ShowEditApplier.apply([
            .renameSong(song: "2", name: "Finale"),
            .setSequence(song: "Opener", sequence: 7)
        ], to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs[1].name, "Finale")
        XCTAssertEqual(r.project.songs[0].sequence, 7)
        XCTAssertEqual(r.summary.count, 2)
    }

    func testDeleteSongNeverDropsBelowOne() {
        var p = base(); p.songs = [p.songs[0]]; p.activeSongId = "a"
        let r = ShowEditApplier.apply([.deleteSong(song: "1")], to: p, defaults: Defaults())
        XCTAssertEqual(r.project.songs.count, 1)               // replaced with a fresh empty song
        XCTAssertNotEqual(r.project.songs[0].id, "a")
    }

    func testUnresolvedSongWarns() {
        let r = ShowEditApplier.apply([.renameSong(song: "9", name: "X")],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs.map(\.name), ["Opener", "Closer"])  // unchanged
        XCTAssertEqual(r.warnings, ["Song \u{201C}9\u{201D} not found \u{2014} skipped renameSong"])
        XCTAssertTrue(r.summary.isEmpty)
    }

    func testOrdinalTakesPriorityOverName() {
        var p = base()
        p.songs[0].name = "2"                 // song at index 0 is literally named "2"
        let r = ShowEditApplier.apply([.renameSong(song: "2", name: "X")],
                                      to: p, defaults: Defaults())
        XCTAssertEqual(r.project.songs[1].name, "X")   // ordinal "2" → index 1 wins
        XCTAssertEqual(r.project.songs[0].name, "2")   // name-"2" untouched
    }

    func testDeleteActiveSongRepairsActiveSongId() {
        let r = ShowEditApplier.apply([.deleteSong(song: "1")], to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs.count, 1)
        XCTAssertEqual(r.project.songs[0].id, "b")
        XCTAssertEqual(r.project.activeSongId, "b")     // repaired off the removed active song
    }

    func testDeleteNonActiveSongPreservesActiveSongId() {
        let r = ShowEditApplier.apply([.deleteSong(song: "2")], to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs.count, 1)
        XCTAssertEqual(r.project.activeSongId, "a")     // unchanged
    }

    func testAddSongNilDefaults() {
        let r = ShowEditApplier.apply([.addSong(name: nil, sequence: nil)],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs.last?.name, "")
        XCTAssertEqual(r.project.songs.last?.sequence, 1)
        XCTAssertEqual(r.summary, ["Add song \u{201C}\u{201D} (sequence 1)"])   // note curly quotes
    }

    func testSelectSongByOrdinal() {
        let r = ShowEditApplier.apply([.selectSong(song: "2")], to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.activeSongId, "b")
        XCTAssertEqual(r.summary, ["Select song 2 (\u{201C}Closer\u{201D})"])   // note curly quotes
    }
}
