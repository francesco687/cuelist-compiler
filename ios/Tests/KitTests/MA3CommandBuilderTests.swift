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

    // Verifies the per-pool default fade/delay fallback and the override behaviour:
    // • when a preset's own fade/delay is empty the default value is used
    // • when a preset specifies its own fade/delay it wins over the default
    func test_cueLines_default_fade_delay_fallback_and_override() {
        // Build Defaults: color pool (number 4) has fade "2.5" and delay "0.5".
        var defaultValues: [Pool: Preset] = [:]
        for pool in Pool.allCases { defaultValues[pool] = Preset() }
        defaultValues[.color] = Preset(fade: "2.5", delay: "0.5")
        let defaults = Defaults(values: defaultValues)

        // Cue 1 – color preset has empty fade/delay → fallback should kick in.
        var presetsA: [Pool: Preset] = [:]
        for pool in Pool.allCases { presetsA[pool] = Preset() }
        presetsA[.color] = Preset(name: "BLUE", fade: "", delay: "")   // empty → use default
        let actionA = Action(group: "WASH", presets: presetsA)
        let cueA = Cue(n: 1, name: "INTRO", fade: "", delay: "", position: "", actions: [actionA], notes: "")

        // Cue 2 – color preset has its own fade/delay → override wins, default ignored.
        var presetsB: [Pool: Preset] = [:]
        for pool in Pool.allCases { presetsB[pool] = Preset() }
        presetsB[.color] = Preset(name: "RED", fade: "1", delay: "0.2")  // own values → override
        let actionB = Action(group: "SPOT", presets: presetsB)
        let cueB = Cue(n: 2, name: "CHORUS", fade: "", delay: "", position: "", actions: [actionB], notes: "")

        let song = Song(id: "s2", name: "TRACK", sequence: 10, cues: [cueA, cueB])
        let lines = MA3CommandBuilder.cueLines(songs: [song], defaults: defaults, storeMode: .overwrite)

        // --- fallback assertions (cue 1 / WASH / BLUE) ---
        XCTAssertTrue(lines.contains("At Preset 4.\"BLUE\""),
                      "Expected 'At Preset 4.\"BLUE\"' in output")
        XCTAssertTrue(lines.contains("Fade 2.5 FeatureGroup 4"),
                      "Expected default fade '2.5' for color pool (number 4)")
        XCTAssertTrue(lines.contains("Delay 0.5 FeatureGroup 4"),
                      "Expected default delay '0.5' for color pool (number 4)")

        // --- override assertions (cue 2 / SPOT / RED) ---
        XCTAssertTrue(lines.contains("At Preset 4.\"RED\""),
                      "Expected 'At Preset 4.\"RED\"' in output")
        XCTAssertTrue(lines.contains("Fade 1 FeatureGroup 4"),
                      "Expected preset fade '1' to override default for color pool")
        XCTAssertTrue(lines.contains("Delay 0.2 FeatureGroup 4"),
                      "Expected preset delay '0.2' to override default for color pool")

        // Sanity: the default fade must NOT appear for cue 2 (different value would be the
        // only 'Fade 2.5 FeatureGroup 4' line, which belongs only to cue 1).
        let fade25Lines = lines.filter { $0 == "Fade 2.5 FeatureGroup 4" }
        XCTAssertEqual(fade25Lines.count, 1,
                       "Default fade line should appear exactly once (cue 1 only, not cue 2)")
    }

    func test_noteLines_only_for_cues_with_notes() {
        var presets: [Pool: Preset] = [:]
        for p in Pool.allCases { presets[p] = Preset() }
        let withNote = Cue(n: 1, name: "A", actions: [Action(group: "G", presets: presets)],
                           notes: "  multi\nline\tnote with \"quote\"  ")
        let noNote = Cue(n: 2, name: "B", actions: [Action(group: "G", presets: presets)], notes: "   ")
        let song = Song(id: "s1", sequence: 7, cues: [withNote, noNote])
        let lines = MA3CommandBuilder.noteLines(songs: [song])
        XCTAssertEqual(lines, [
            "Set Sequence 7 Cue 1 \"Note\" \"multi line note with \\\"quote\\\"\"",
        ])
    }
}
