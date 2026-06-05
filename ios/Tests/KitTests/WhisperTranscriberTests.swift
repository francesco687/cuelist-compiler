import XCTest
@testable import CuelistCompilerKit

final class WhisperTranscriberTests: XCTestCase {
    func testBuildsMultipartAndParsesText() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            let ct = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            XCTAssertTrue(ct.hasPrefix("multipart/form-data; boundary="))
            let body = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
            XCTAssertTrue(body.contains(#"name="model""#))
            XCTAssertTrue(body.contains("whisper-1"))
            XCTAssertTrue(body.contains(#"name="file"; filename="audio.m4a""#))
            return (Data(#"{"text":"set group one to blue"}"#.utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("audio.m4a")
        try Data([0x00, 0x01, 0x02]).write(to: tmp)
        let t = WhisperTranscriber(apiKey: "sk-test", transport: mock)
        let text = try await t.transcribe(tmp)
        XCTAssertEqual(text, "set group one to blue")
    }

    func testHTTPErrorThrows() async {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            (Data(#"{"error":{"message":"bad key"}}"#.utf8),
             HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("a.m4a")
        try? Data([0x00]).write(to: tmp)
        let t = WhisperTranscriber(apiKey: "x", transport: mock)
        do { _ = try await t.transcribe(tmp); XCTFail("expected throw") }
        catch let VoiceError.api(status, _) { XCTAssertEqual(status, 401) }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testEmptyKeyThrowsMissingKey() async {
        let t = WhisperTranscriber(apiKey: "", transport: MockHTTPTransport())
        do { _ = try await t.transcribe(URL(fileURLWithPath: "/tmp/x.m4a")); XCTFail("expected throw") }
        catch VoiceError.missingKey(let provider) { XCTAssertEqual(provider, "OpenAI") }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testMalformed200ThrowsBadResponse() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            (Data("<html>error</html>".utf8),
             HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bad.m4a")
        try Data([0x00]).write(to: tmp)
        let t = WhisperTranscriber(apiKey: "sk-test", transport: mock)
        do { _ = try await t.transcribe(tmp); XCTFail("expected throw") }
        catch VoiceError.badResponse(_) { }
        catch { XCTFail("wrong error: \(error)") }
    }
}
