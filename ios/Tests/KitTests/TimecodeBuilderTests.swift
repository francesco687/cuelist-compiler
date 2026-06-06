import XCTest
@testable import SaettaKit

final class TimecodeBuilderTests: XCTestCase {

    private func song() -> Song {
        let c1 = Cue(n: 1, name: "A", position: "00:00:05:00")        // valid, ticked
        let c2 = Cue(n: 2, name: "B", position: "")                   // no TC
        let c3 = Cue(n: 3, name: "C", position: "00:00:10:00")        // valid, NOT ticked
        let c4 = Cue(n: 4, name: "D", position: "bad")                // invalid, ticked → skipped
        return Song(id: "s1", sequence: 12, cues: [c1, c2, c3, c4])
    }

    func test_only_ticked_valid_cues_in_ascending_order() {
        let s = song()
        let ticked: Set<UUID> = [s.cues[0].id, s.cues[3].id]   // c1 (valid) + c4 (invalid)
        let events = TimecodeBuilder.events(song: s, ticked: ticked)
        XCTAssertEqual(events.map(\.cueN), [1])                 // c4 dropped (invalid), c3 not ticked
        XCTAssertEqual(events[0].sequence, 12)
        XCTAssertEqual(events[0].seconds, "5.0")
    }

    func test_lines_emit_one_inline_lua_per_event() {
        let s = song()
        let ticked: Set<UUID> = [s.cues[0].id]
        let lines = TimecodeBuilder.lines(song: s, ticked: ticked)
        XCTAssertEqual(lines.count, 1)
        // Append-only: NO Delete commands anywhere (would clobber existing events).
        XCTAssertFalse(lines.joined().contains("Delete"))
        // Proven inner commands are present, addressed at the self-counted next index.
        let line = lines[0]
        XCTAssertTrue(line.hasPrefix("Lua \""))
        XCTAssertTrue(line.contains("Store Timecode '..n..'.1.1.1.1"))
        XCTAssertTrue(line.contains("Goto Cue 1 Sequence '..n"))
        XCTAssertTrue(line.contains("Property"))
        XCTAssertTrue(line.contains("5.0"))
    }
}
