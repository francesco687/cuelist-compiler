import XCTest
@testable import SaettaKit

final class MA3CommandBuilderTests: XCTestCase {

    // A song: seq 5, one cue "VERSE" with one action group "MOVERS" carrying a
    // color preset "RED" and a dimmer preset "FULL" with an explicit fade.
    private func sampleSong() -> Song {
        let color = Preset(name: "RED")
        let dimmer = Preset(name: "FULL", fade: "3")
        var presets: [Pool: Preset] = [:]
        for p in Pool.allCases { presets[p] = Preset() }
        presets[.color] = color
        presets[.dimmer] = dimmer
        let action = Action(group: "MOVERS", presets: presets)
        let cue = Cue(n: 1, name: "VERSE", fade: "2", delay: "", position: "", actions: [action], notes: "ignored note")
        return Song(id: "s1", name: "SONG", sequence: 5, cues: [cue])
    }

    func test_cueLines_emit_structure_and_no_note_lines() {
        let song = sampleSong()
        let lines = MA3CommandBuilder.cueLines(songs: [song], defaults: Defaults(), storeMode: .overwrite)
        XCTAssertEqual(lines, [
            "ClearAll",
            "Group \"MOVERS\"",
            "At Preset 4.\"RED\"",        // color = pool number 4, first in allCases order
            "At Preset 1.\"FULL\"",       // dimmer = pool number 1
            "Fade 3 FeatureGroup 1",
            "Store Sequence 5 Cue 1 \"VERSE\" /Overwrite /NoConfirmation",
            "Set Sequence 5 Cue 1 Fade 2",
            "ClearAll",
        ])
        XCTAssertFalse(lines.contains { $0.contains("\"Note\"") }, "cueLines must not emit note lines")
    }

    func test_cueLines_merge_mode_flag() {
        let song = sampleSong()
        let lines = MA3CommandBuilder.cueLines(songs: [song], defaults: Defaults(), storeMode: .merge)
        XCTAssertTrue(lines.contains("Store Sequence 5 Cue 1 \"VERSE\" /Merge /NoConfirmation"))
    }
}
