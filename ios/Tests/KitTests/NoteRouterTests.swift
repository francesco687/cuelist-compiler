import XCTest
@testable import CuelistCompilerKit

final class NoteRouterTests: XCTestCase {
    private func project() -> Project {
        Project(songs: [Song(id: "a", name: "Opener", sequence: 1,
                             cues: [Cue(n: 1, name: "Intro"), Cue(n: 2, name: "Chorus")])],
                activeSongId: "a")
    }

    func testRoutesNotesToCues() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
            let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as! [String: Any]
            XCTAssertEqual((body["tool_choice"] as? [String: Any])?["name"] as? String, "attach_notes")
            XCTAssertNotNil((body["system"] as! [[String: Any]]).last?["cache_control"])
            XCTAssertNotNil((body["tools"] as! [[String: Any]]).last?["cache_control"])
            let resp = """
            {"content":[{"type":"tool_use","name":"attach_notes","input":
              {"notes":[{"cue":1,"text":"keep it dim"},{"cue":2,"text":"hit harder"}]}}]}
            """
            return (Data(resp.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let router = AnthropicNoteRouter(apiKey: "sk-ant", transport: mock)
        let edits = try await router.route(transcript: "dim intro, chorus harder", project: project(), targetCue: nil)
        XCTAssertEqual(edits, [NoteEdit(cue: 1, text: "keep it dim"), NoteEdit(cue: 2, text: "hit harder")])
    }

    func testPinnedTargetCueReachesPrompt() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as! [String: Any]
            let content = (body["messages"] as! [[String: Any]]).last?["content"] as? String ?? ""
            XCTAssertTrue(content.contains("cue 2"))
            let resp = #"{"content":[{"type":"tool_use","name":"attach_notes","input":{"notes":[{"cue":2,"text":"hit harder"}]}}]}"#
            return (Data(resp.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let router = AnthropicNoteRouter(apiKey: "sk-ant", transport: mock)
        let edits = try await router.route(transcript: "make it punch", project: project(), targetCue: 2)
        XCTAssertEqual(edits, [NoteEdit(cue: 2, text: "hit harder")])
    }

    func testEmptyKeyThrowsMissingKey() async {
        let router = AnthropicNoteRouter(apiKey: "", transport: MockHTTPTransport())
        do { _ = try await router.route(transcript: "x", project: project(), targetCue: nil); XCTFail("expected throw") }
        catch VoiceError.missingKey(let who) { XCTAssertEqual(who, "Anthropic") }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testNon200ThrowsApi() async {
        let mock = MockHTTPTransport()
        mock.handler = { req in (Data(#"{"error":{}}"#.utf8), HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!) }
        let router = AnthropicNoteRouter(apiKey: "sk-ant", transport: mock)
        do { _ = try await router.route(transcript: "x", project: project(), targetCue: nil); XCTFail("expected throw") }
        catch let VoiceError.api(status, _) { XCTAssertEqual(status, 500) }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testMissingToolUseThrowsBadResponse() async {
        let mock = MockHTTPTransport()
        mock.handler = { req in (Data(#"{"content":[{"type":"text","text":"sorry"}]}"#.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        let router = AnthropicNoteRouter(apiKey: "sk-ant", transport: mock)
        do { _ = try await router.route(transcript: "x", project: project(), targetCue: nil); XCTFail("expected throw") }
        catch VoiceError.badResponse(_) { }
        catch { XCTFail("wrong error: \(error)") }
    }
}
