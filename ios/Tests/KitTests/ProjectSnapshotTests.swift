import XCTest
@testable import SaettaKit

final class ProjectSnapshotTests: XCTestCase {
    func testSnapshotIsCompactAndIndexed() throws {
        var cue = Cue(n: 1, name: "Intro", fade: "5")
        cue.actions = [Action(group: "1", presets: [.color: Preset(name: "Blue", fade: "5"),
                                                     .dimmer: Preset()])]
        let p = Project(songs: [Song(id: "a", name: "Opener", sequence: 666, cues: [cue])],
                        activeSongId: "a")
        let json = ProjectSnapshot.json(p)
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        XCTAssertEqual(obj["activeSong"] as? Int, 1)
        let songs = obj["songs"] as! [[String: Any]]
        XCTAssertEqual(songs[0]["index"] as? Int, 1)
        XCTAssertEqual(songs[0]["name"] as? String, "Opener")
        XCTAssertEqual(songs[0]["sequence"] as? Int, 666)
        let cues = songs[0]["cues"] as! [[String: Any]]
        XCTAssertEqual(cues[0]["n"] as? Double, 1)
        let actions = cues[0]["actions"] as! [[String: Any]]
        XCTAssertEqual(actions[0]["group"] as? String, "1")
        let presets = actions[0]["presets"] as! [String: Any]
        XCTAssertNotNil(presets["color"])         // non-empty kept
        XCTAssertNil(presets["dimmer"])           // empty preset omitted to stay small
        XCTAssertEqual(obj["storeMode"] as? String, "Overwrite")
    }

    func testActiveSongIndexWithMultipleSongs() throws {
        let p = Project(songs: [Song(id: "x", name: "A", sequence: 1),
                                Song(id: "y", name: "B", sequence: 2)], activeSongId: "y")
        let obj = try JSONSerialization.jsonObject(with: Data(ProjectSnapshot.json(p).utf8)) as! [String: Any]
        XCTAssertEqual(obj["activeSong"] as? Int, 2)              // second song active
        let songs = obj["songs"] as! [[String: Any]]
        XCTAssertEqual(songs[0]["index"] as? Int, 1)
        XCTAssertEqual(songs[1]["index"] as? Int, 2)
    }

    func testEmptyActionsAndEmptyCueFieldsOmitted() throws {
        // a cue with a default empty Action() and no name/fade/delay/position
        let p = Project(songs: [Song(id: "a", name: "S", sequence: 1,
                                     cues: [Cue(n: 1)])], activeSongId: "a")
        let obj = try JSONSerialization.jsonObject(with: Data(ProjectSnapshot.json(p).utf8)) as! [String: Any]
        let cue = (obj["songs"] as! [[String: Any]])[0]["cues"] as! [[String: Any]]
        XCTAssertNil(cue[0]["actions"])     // empty action block omitted entirely
        XCTAssertNil(cue[0]["name"])        // empty name omitted
        XCTAssertEqual(cue[0]["n"] as? Double, 1)
    }
}
