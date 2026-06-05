import XCTest
@testable import CuelistCompilerKit

@MainActor
final class ProjectStoreNotesTests: XCTestCase {
    private func store() -> ProjectStore {
        let s = ProjectStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-notes-\(UUID().uuidString)"))
        s.project.songs[0].cues = [Cue(n: 1, name: "Intro"), Cue(n: 2, name: "Chorus")]
        return s
    }
    func testAppendNoteSetsThenAppendsNewlineJoined() {
        let s = store()
        s.appendNote(cueN: 1, text: "keep it dim")
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "keep it dim")
        s.appendNote(cueN: 1, text: "slow build")
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "keep it dim\nslow build")
    }
    func testApplyNotesRoutesToMatchingCues() {
        let s = store()
        s.applyNotes([NoteEdit(cue: 1, text: "dim"), NoteEdit(cue: 2, text: "harder")])
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "dim")
        XCTAssertEqual(s.project.songs[0].cues[1].notes, "harder")
    }
    func testApplyNotesSkipsEmptyAndUnknownCue() {
        let s = store()
        s.applyNotes([NoteEdit(cue: 1, text: "   "), NoteEdit(cue: 99, text: "lost")])
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "")
        XCTAssertEqual(s.project.songs[0].cues[1].notes, "")
    }
}
