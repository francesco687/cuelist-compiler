import XCTest
@testable import SaettaKit

final class ShowEditApplierActionTests: XCTestCase {
    private func base() -> Project {
        Project(songs: [Song(id: "a", name: "Opener", sequence: 1,
                             cues: [Cue(n: 1, name: "Intro")])], activeSongId: "a")
    }

    func testSetGroupAndPresetOnFirstBlock() {
        let r = ShowEditApplier.apply([
            .setGroup(song: nil, cue: 1, group: "1", block: nil),
            .setPreset(song: nil, cue: 1, pool: .color, name: "Deep Blue", fade: "5", delay: nil, block: nil)
        ], to: base(), defaults: Defaults())
        let action = r.project.songs[0].cues[0].actions[0]
        XCTAssertEqual(action.group, "1")
        XCTAssertEqual(action.presets[.color]?.name, "Deep Blue")
        XCTAssertEqual(action.presets[.color]?.fade, "5")
        XCTAssertEqual(r.summary, ["Cue 1 · group = 1", "Cue 1 · color = \u{201C}Deep Blue\u{201D} (fade 5)"])
    }

    func testClearPreset() {
        var p = base()
        p.songs[0].cues[0].actions[0].presets[.dimmer] = Preset(name: "full")
        let r = ShowEditApplier.apply([.clearPreset(song: nil, cue: 1, pool: .dimmer, block: nil)],
                                      to: p, defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues[0].actions[0].presets[.dimmer]?.name, "")
    }

    func testAddAndRemoveActionBlockNeverZero() {
        let r = ShowEditApplier.apply([
            .addActionBlock(song: nil, cue: 1),
            .removeActionBlock(song: nil, cue: 1, block: 0),
            .removeActionBlock(song: nil, cue: 1, block: 0)   // would empty → kept at one
        ], to: base(), defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues[0].actions.count, 1)
    }

    func testCopyActions() {
        var p = base()
        p.songs[0].cues[0].actions[0].group = "SRC"
        p.songs[0].cues.append(Cue(n: 2, name: "Verse"))
        let r = ShowEditApplier.apply([.copyActions(song: nil, fromCue: 1, toCue: 2)],
                                      to: p, defaults: Defaults())
        XCTAssertEqual(r.project.songs[0].cues[1].actions[0].group, "SRC")
    }

    func testSetDefaultAndStoreMode() {
        let r = ShowEditApplier.apply([
            .setDefault(pool: .dimmer, fade: "3", delay: nil),
            .setStoreMode(mode: .merge)
        ], to: base(), defaults: Defaults())
        XCTAssertEqual(r.defaults.fade(.dimmer), "3")
        XCTAssertEqual(r.project.storeMode, .merge)
        XCTAssertEqual(r.summary, ["Default dimmer · fade 3", "Store mode → Merge"])
    }

    func testSetPresetMissingActionBlockWarns() {
        let r = ShowEditApplier.apply([.setPreset(song: nil, cue: 1, pool: .color,
                                                   name: "Blue", fade: nil, delay: nil, block: 99)],
                                      to: base(), defaults: Defaults())
        XCTAssertEqual(r.warnings, ["Cue 1 has no action block 99 — skipped setPreset"])
        XCTAssertTrue(r.summary.isEmpty)
    }

    func testSetPresetNilFieldsLeaveExistingUntouched() {
        var p = base()
        p.songs[0].cues[0].actions[0].presets[.color] = Preset(name: "Blue", fade: "5", delay: "1")
        let r = ShowEditApplier.apply([.setPreset(song: nil, cue: 1, pool: .color,
                                                   name: nil, fade: nil, delay: nil, block: nil)],
                                      to: p, defaults: Defaults())
        let preset = r.project.songs[0].cues[0].actions[0].presets[.color]
        XCTAssertEqual(preset?.name, "Blue")    // unchanged
        XCTAssertEqual(preset?.fade, "5")       // unchanged
        XCTAssertEqual(preset?.delay, "1")      // unchanged
    }
}
