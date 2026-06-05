import XCTest
@testable import CuelistCompilerKit

final class ShowEditApplierCueTests: XCTestCase {
    private func base() -> Project {
        Project(songs: [Song(id: "a", name: "Opener", sequence: 1, cues: [
            Cue(n: 0.1, name: "DB"), Cue(n: 1, name: "Intro")
        ])], activeSongId: "a")
    }

    func testAddCueAutoNumbers() {
        let r = ShowEditApplier.apply([.addCue(song: nil, n: nil, name: "Verse",
                                               fade: "3", delay: nil, position: nil)],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues.map(\.n), [0.1, 1, 2])
        XCTAssertEqual(r.project.songs[0].cues.last?.name, "Verse")
        XCTAssertEqual(r.project.songs[0].cues.last?.fade, "3")
        XCTAssertEqual(r.summary, ["Add cue 2 \u{201C}Verse\u{201D} (fade 3)"])
    }

    func testSetCueFieldByNumber() {
        let r = ShowEditApplier.apply([.setCue(song: nil, cue: 1, field: .name, value: "INTRO")],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues[1].name, "INTRO")
        XCTAssertEqual(r.summary, ["Cue 1 \u{00B7} name = \u{201C}INTRO\u{201D}"])
    }

    func testSetCueNumberRenumbers() {
        let r = ShowEditApplier.apply([.setCue(song: nil, cue: 0.1, field: .number, value: "0.5")],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues[0].n, 0.5)
    }

    func testDeleteCueAndMissingWarns() {
        let r = ShowEditApplier.apply([.deleteCue(song: nil, cue: 0.1),
                                       .deleteCue(song: nil, cue: 9)],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues.map(\.n), [1])
        XCTAssertEqual(r.warnings, ["Cue 9 not found in song 1 \u{2014} skipped deleteCue"])
    }

    func testSortCues() {
        var p = base(); p.songs[0].cues = [Cue(n: 2), Cue(n: 1), Cue(n: 0.1)]
        let r = ShowEditApplier.apply([.sortCues(song: nil)], to: p, defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues.map(\.n), [0.1, 1, 2])
    }
}
