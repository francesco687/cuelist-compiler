import XCTest
@testable import CuelistCompilerKit

final class ShowEditDecodeTests: XCTestCase {
    private func decode(_ json: String) throws -> ToolInput {
        try JSONDecoder().decode(ToolInput.self, from: Data(json.utf8))
    }

    func testDecodesPresetAndGroupEdits() throws {
        let input = try decode("""
        { "edits": [
          { "op": "setGroup",  "cue": 1, "group": "1" },
          { "op": "setPreset", "cue": 1, "pool": "color", "name": "Deep Blue", "fade": "5" }
        ] }
        """)
        XCTAssertNil(input.clarification)
        XCTAssertEqual(input.edits, [
            .setGroup(song: nil, cue: 1, group: "1", block: nil),
            .setPreset(song: nil, cue: 1, pool: .color, name: "Deep Blue", fade: "5", delay: nil, block: nil)
        ])
    }

    func testDecodesSongAndCueOps() throws {
        let input = try decode("""
        { "edits": [
          { "op": "addSong", "name": "Encore", "sequence": 12 },
          { "op": "setCue", "song": "2", "cue": 0.1, "field": "name", "value": "DB CUE" },
          { "op": "setDefault", "pool": "dimmer", "fade": "3" },
          { "op": "setStoreMode", "mode": "Merge" }
        ] }
        """)
        XCTAssertEqual(input.edits, [
            .addSong(name: "Encore", sequence: 12),
            .setCue(song: "2", cue: 0.1, field: .name, value: "DB CUE"),
            .setDefault(pool: .dimmer, fade: "3", delay: nil),
            .setStoreMode(mode: .merge)
        ])
    }

    func testClarificationOnlyShape() throws {
        let input = try decode(#"{ "edits": [], "clarification": "Which song?" }"#)
        XCTAssertTrue(input.edits.isEmpty)
        XCTAssertEqual(input.clarification, "Which song?")
    }
}
