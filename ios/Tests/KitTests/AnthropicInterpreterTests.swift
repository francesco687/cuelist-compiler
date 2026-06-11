import XCTest
@testable import SaettaKit

final class AnthropicInterpreterTests: XCTestCase {
    private func project() -> Project {
        Project(songs: [Song(id: "a", name: "Opener", sequence: 1, cues: [Cue(n: 1)])], activeSongId: "a")
    }

    func testBuildsCachedToolRequestAndParsesEdits() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
            XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "claude-sonnet-4-6")
            XCTAssertEqual((body["tool_choice"] as? [String: Any])?["name"] as? String, "apply_show_edits")
            // system + tools carry cache_control
            let system = body["system"] as! [[String: Any]]
            XCTAssertNotNil(system.last?["cache_control"])
            let tools = body["tools"] as! [[String: Any]]
            XCTAssertNotNil(tools.last?["cache_control"])
            // transcript reached the user turn
            let messages = body["messages"] as! [[String: Any]]
            let content = messages.last?["content"] as? String ?? ""
            XCTAssertTrue(content.contains("set group 1 to blue"))

            let resp = """
            {"content":[{"type":"tool_use","name":"apply_show_edits","input":
              {"edits":[{"op":"setGroup","cue":1,"group":"1"}]}}]}
            """
            return (Data(resp.utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let interp = AnthropicInterpreter(apiKey: "sk-ant", transport: mock)
        let cmd = try await interp.interpret(transcript: "set group 1 to blue",
                                             project: project(), defaults: Defaults())
        XCTAssertEqual(cmd.edits, [.setGroup(song: nil, cue: 1, group: "1", block: nil)])
        XCTAssertNil(cmd.clarification)
    }

    func testParsesClarification() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            let resp = """
            {"content":[{"type":"tool_use","name":"apply_show_edits","input":
              {"edits":[],"clarification":"Which song?"}}]}
            """
            return (Data(resp.utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let interp = AnthropicInterpreter(apiKey: "sk-ant", transport: mock)
        let cmd = try await interp.interpret(transcript: "do the thing", project: project(), defaults: Defaults())
        XCTAssertTrue(cmd.edits.isEmpty)
        XCTAssertEqual(cmd.clarification, "Which song?")
    }

    func testEmptyKeyThrowsMissingKey() async {
        let interp = AnthropicInterpreter(apiKey: "", transport: MockHTTPTransport())
        do { _ = try await interp.interpret(transcript: "x", project: project(), defaults: Defaults())
             XCTFail("expected throw") }
        catch VoiceError.missingKey(let who) { XCTAssertEqual(who, "Anthropic") }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testNon200ThrowsApi() async {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            (Data(#"{"error":{"message":"bad key"}}"#.utf8),
             HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        let interp = AnthropicInterpreter(apiKey: "sk-ant", transport: mock)
        do { _ = try await interp.interpret(transcript: "x", project: project(), defaults: Defaults())
             XCTFail("expected throw") }
        catch let VoiceError.api(status, _) { XCTAssertEqual(status, 401) }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testMissingToolUseThrowsBadResponse() async {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            (Data(#"{"content":[{"type":"text","text":"sorry"}]}"#.utf8),
             HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let interp = AnthropicInterpreter(apiKey: "sk-ant", transport: mock)
        do { _ = try await interp.interpret(transcript: "x", project: project(), defaults: Defaults())
             XCTFail("expected throw") }
        catch VoiceError.badResponse(_) { }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testTruncatedResponseThrowsBadResponse() async {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            (Data(#"{"stop_reason":"max_tokens","content":[{"type":"tool_use","name":"apply_show_edits","input":{"edits":[]}}]}"#.utf8),
             HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let interp = AnthropicInterpreter(apiKey: "sk-ant", transport: mock)
        do { _ = try await interp.interpret(transcript: "x", project: project(), defaults: Defaults())
             XCTFail("expected throw") }
        catch VoiceError.badResponse(_) { }
        catch { XCTFail("wrong error: \(error)") }
    }
}
