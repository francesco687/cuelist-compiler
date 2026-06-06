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
        // rawtime = round(5.0 * 16777216) = 83886080 (1 s = 2^24 internal units).
        XCTAssertEqual(events[0].rawtime, 5 * 16_777_216)
    }

    func test_lines_emit_one_object_api_command_per_song() {
        let s = song()
        let ticked: Set<UUID> = [s.cues[0].id]
        let lines = TimecodeBuilder.lines(song: s, ticked: ticked)
        // ONE inline-Lua command per song, not per cue.
        XCTAssertEqual(lines.count, 1)
        let line = lines[0]

        // Append-only: NO wipe phase — neither the command-line `Delete` keyword
        // nor the Object-API `:Delete()` mutator may appear (either clobbers events).
        XCTAssertFalse(line.contains("Delete"))

        // Object-API hierarchy on the proven path. Pool index goes through `n`.
        XCTAssertTrue(line.hasPrefix("Lua \""))
        XCTAssertTrue(line.contains("local n=12"))
        XCTAssertTrue(line.contains("DataPool().timecodes[n]"))
        XCTAssertTrue(line.contains("DataPool().sequences[n]"))
        XCTAssertTrue(line.contains("t:Children()[1]"))
        XCTAssertTrue(line.contains("local tr=tg[2]"), "must target tg[2], the user Track (tg[1] is a pseudo-track)")
        XCTAssertTrue(line.contains("rng=tr:Acquire()"))
        XCTAssertTrue(line.contains("sub=rng:Acquire('CmdSubTrack')"))
        XCTAssertTrue(line.contains("e:Set('rawtime',c[2])"))
        XCTAssertTrue(line.contains("GetObject('Sequence '..n..' Cue '..c[1])"))
        XCTAssertTrue(line.contains("e:Set('cuedestination',cue)"))
        // The {cueN,rawtime} literal for c1: 5 s → 83886080.
        XCTAssertTrue(line.contains("{1,83886080}"))

        // Diagnostics: every exit point Printfs to MA3's System Monitor, and the
        // whole thing runs under pcall so runtime errors surface instead of
        // vanishing silently (the reason an "accepted" command could leave the
        // timeline empty with no feedback).
        XCTAssertTrue(line.contains("[Saetta TC]"), "must carry Printf diagnostics")
        XCTAssertTrue(line.contains("pcall(go)"), "work must run under pcall to catch runtime errors")

        // The MA3 command-line tokenizer terminates a `Lua "..."` argument at the
        // first `"` and ignores backslash escapes — so the body must contain NO
        // double-quotes and NO backslashes. Single-quoted Lua throughout.
        let body = String(line.dropFirst("Lua \"".count).dropLast())   // strip outer Lua "..."
        XCTAssertFalse(body.contains("\""), "body must contain no double-quote chars")
        XCTAssertFalse(body.contains("\\"), "body must contain no backslash escapes")
    }

    func test_multiple_ticked_cues_share_one_command_ascending() {
        let s = song()
        let ticked: Set<UUID> = [s.cues[2].id, s.cues[0].id]   // c3 + c1, out of order
        let lines = TimecodeBuilder.lines(song: s, ticked: ticked)
        XCTAssertEqual(lines.count, 1)
        // Both pairs in one ipairs literal, ascending by cue number: c1 then c3.
        // c1: 5 s → 83886080; c3: 10 s → 167772160.
        XCTAssertTrue(lines[0].contains("{1,83886080},{3,167772160}"))
    }

    func test_no_ticked_valid_cues_emits_nothing() {
        let s = song()
        XCTAssertTrue(TimecodeBuilder.lines(song: s, ticked: []).isEmpty)
        // Only the invalid cue ticked → still empty.
        XCTAssertTrue(TimecodeBuilder.lines(song: s, ticked: [s.cues[3].id]).isEmpty)
    }
}
