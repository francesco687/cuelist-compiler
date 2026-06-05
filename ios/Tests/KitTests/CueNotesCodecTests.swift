import XCTest
@testable import CuelistCompilerKit

final class CueNotesCodecTests: XCTestCase {
    func testDecodesMissingNotesAsEmpty() throws {
        let json = Data(#"{"n":1,"name":"Intro","fade":"","delay":"","position":"","collapsed":false,"actions":[]}"#.utf8)
        let cue = try JSONDecoder().decode(Cue.self, from: json)
        XCTAssertEqual(cue.notes, "")
    }
    func testRoundTripsNotes() throws {
        var cue = Cue(n: 2, name: "Chorus")
        cue.notes = "hit harder"
        let data = try JSONEncoder().encode(cue)
        let back = try JSONDecoder().decode(Cue.self, from: data)
        XCTAssertEqual(back.notes, "hit harder")
    }
    func testInitDefaultsNotesToEmpty() {
        XCTAssertEqual(Cue(n: 1).notes, "")
    }
}
