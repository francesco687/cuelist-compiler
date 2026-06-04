import XCTest
@testable import CuelistCompilerKit

final class ModelCodecTests: XCTestCase {
    func testPresetsEncodeAsObjectWithAllSixPools() throws {
        var action = Action(group: "AROLLA FLOOR")
        action.presets[.color] = Preset(name: "BLUE")
        let data = try JSONEncoder().encode(action)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let presets = obj["presets"] as! [String: Any]
        XCTAssertEqual(Set(presets.keys),
                       ["color", "dimmer", "position", "gobo", "beam", "focus"])
        let color = presets["color"] as! [String: Any]
        XCTAssertEqual(color["name"] as? String, "BLUE")
        XCTAssertEqual(color["fade"] as? String, "")
        XCTAssertEqual(obj["color"] as? String, "")   // action color defaults to ""
    }

    func testActionColorRoundTrips() throws {
        var action = Action(group: "G")
        action.color = "#d63a3a"
        let data = try JSONEncoder().encode(action)
        let again = try JSONDecoder().decode(Action.self, from: data)
        XCTAssertEqual(again.color, "#d63a3a")
    }

    func testNewFormatProjectRoundTrips() throws {
        let json = """
        {"songs":[{"id":"s1","name":"S","sequence":3,"audioFileName":"",
        "cues":[{"n":1,"name":"C","fade":"5","delay":"","position":"VERSE","collapsed":false,
        "actions":[{"group":"G","color":"","presets":{
        "color":{"name":"RED","fade":"","delay":""},
        "dimmer":{"name":"","fade":"","delay":""},
        "position":{"name":"","fade":"","delay":""},
        "gobo":{"name":"","fade":"","delay":""},
        "beam":{"name":"","fade":"","delay":""},
        "focus":{"name":"","fade":"","delay":""}}}]}]}],
        "activeSongId":"s1","storeMode":"Overwrite"}
        """.data(using: .utf8)!
        let project = try JSONDecoder().decode(Project.self, from: json)
        XCTAssertEqual(project.songs.count, 1)
        XCTAssertEqual(project.songs[0].cues[0].position, "VERSE")
        XCTAssertEqual(project.songs[0].cues[0].actions[0].presets[.color]?.name, "RED")
        XCTAssertEqual(project.storeMode, .overwrite)
        let data = try JSONEncoder().encode(project)
        let again = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(again.songs[0].name, "S")
        XCTAssertEqual(again.songs[0].cues[0].n, 1)
    }
}
