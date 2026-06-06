import XCTest
@testable import SaettaKit

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
    func testSetNoteOverwritesExisting() {
        let s = store()
        s.appendNote(cueN: 1, text: "old")
        s.setNote(cueN: 1, text: "new note")
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "new note")
    }
    func testSetNoteClearsOnWhitespace() {
        let s = store()
        s.appendNote(cueN: 1, text: "remove me")
        s.setNote(cueN: 1, text: "   ")
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "")
    }
    func testSetNoteIgnoresUnknownCue() {
        let s = store()
        s.appendNote(cueN: 1, text: "stay")
        s.setNote(cueN: 99, text: "lost")
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "stay")
    }
    func testSetNoteTrims() {
        let s = store()
        s.setNote(cueN: 2, text: "  trimmed  ")
        XCTAssertEqual(s.project.songs[0].cues[1].notes, "trimmed")
    }
}
