import XCTest
@testable import CuelistCompilerKit

@MainActor      // ProjectStore is @MainActor-isolated; the test class must match
final class ProjectStoreMutationTests: XCTestCase {
    private func store() -> ProjectStore {
        ProjectStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-mut-\(UUID().uuidString)"))
    }

    func testAddAndRemoveSongKeepsAtLeastOne() {
        let s = store()
        let firstId = s.project.songs[0].id
        s.addSong()
        XCTAssertEqual(s.project.songs.count, 2)
        XCTAssertEqual(s.project.activeSongId, s.project.songs[1].id)  // new song active
        s.removeSong(id: s.project.songs[1].id)
        XCTAssertEqual(s.project.songs.count, 1)
        s.removeSong(id: firstId)                                      // remove the last
        XCTAssertEqual(s.project.songs.count, 1)                       // re-seeded, never zero
        XCTAssertEqual(s.project.songs[0].cues.count, 0)
    }

    func testAddCueAppendsToActiveSong() {
        let s = store()
        s.addCue()
        XCTAssertEqual(s.activeSong.cues.count, 1)
        XCTAssertEqual(s.activeSong.cues[0].actions.count, 1)          // one empty block
    }

    func testRemoveLastActionBlockReseeds() {
        let s = store()
        s.addCue()
        let cueId = s.activeSong.cues[0].id
        s.removeActionBlock(cueId: cueId, at: 0)
        XCTAssertEqual(s.activeSong.cues[0].actions.count, 1)          // never zero
    }

    func testCopyActionsReplacesTarget() {
        let s = store()
        s.addCue(); s.addCue()
        let src = s.activeSong.cues[0].id
        let dst = s.activeSong.cues[1].id
        s.updateActiveCue(id: src) { cue in
            cue.actions = [Action(group: "WASH")]
        }
        s.copyActions(fromCueId: src, toCueId: dst)
        XCTAssertEqual(s.activeSong.cues[1].actions.first?.group, "WASH")
    }

    func testSortActiveCuesByNumber() {
        let s = store()
        s.addCue(); s.addCue()
        s.updateActiveCue(id: s.activeSong.cues[0].id) { $0.n = 5 }
        s.updateActiveCue(id: s.activeSong.cues[1].id) { $0.n = 1 }
        s.sortActiveCues()
        XCTAssertEqual(s.activeSong.cues.map(\.n), [1, 5])
    }

    func testCollapseAndExpandAllCues() {
        let s = store()
        s.addCue(); s.addCue()
        s.collapseAllCues()
        XCTAssertTrue(s.activeSong.cues.allSatisfy { $0.collapsed })
        s.expandAllCues()
        XCTAssertTrue(s.activeSong.cues.allSatisfy { !$0.collapsed })
    }
    func testCollapseAllOnEmptySongIsNoOp() {
        let s = store()
        s.collapseAllCues()                       // no cues — must not crash
        XCTAssertEqual(s.activeSong.cues.count, 0)
    }

    func testMoveCuesReordersActiveSong() {
        let s = store()
        s.addCue(); s.addCue(); s.addCue()          // n = 1,2,3 in array order
        XCTAssertEqual(s.activeSong.cues.map(\.n), [1, 2, 3])
        s.moveCues(from: IndexSet(integer: 0), to: 3)  // move first to end
        XCTAssertEqual(s.activeSong.cues.map(\.n), [2, 3, 1])
    }

    func testRemoveCuesBulkDeletesByID() {
        let s = store()
        s.addCue(); s.addCue(); s.addCue()
        let ids = Set([s.activeSong.cues[0].id, s.activeSong.cues[2].id])
        s.removeCues(ids: ids)
        XCTAssertEqual(s.activeSong.cues.map(\.n), [2])     // middle one survives
    }

    func testRenumberFromOneAssignsSequentialIntegers() {
        let s = store()
        s.addCue(); s.addCue(); s.addCue()
        s.updateActiveCue(id: s.activeSong.cues[0].id) { $0.n = 10 }
        s.updateActiveCue(id: s.activeSong.cues[1].id) { $0.n = 2.5 }
        s.renumberFromOne()
        XCTAssertEqual(s.activeSong.cues.map(\.n), [1, 2, 3])   // display order, integer steps
    }
}
