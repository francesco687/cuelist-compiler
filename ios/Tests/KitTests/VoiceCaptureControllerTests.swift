import XCTest
@testable import CuelistCompilerKit

@MainActor
final class VoiceCaptureControllerTests: XCTestCase {

    final class MockRecorder: AudioRecorder, @unchecked Sendable {
        var permission = true
        var fileToReturn: URL? = FileManager.default.temporaryDirectory.appendingPathComponent("x.m4a")
        private(set) var started = false
        nonisolated init() {}
        func requestPermission() async -> Bool { permission }
        func start() throws { started = true }
        func stop() async -> URL? { started = false; return fileToReturn }
    }
    struct StubTranscriber: Transcriber { let text: String
        func transcribe(_ audio: URL) async throws -> String { text } }
    struct StubInterpreter: CommandInterpreter { let cmd: InterpretedCommand
        func interpret(transcript: String, project: Project, defaults: Defaults) async throws -> InterpretedCommand { cmd } }

    private func make(_ transcriber: Transcriber, _ interp: CommandInterpreter, _ rec: MockRecorder = MockRecorder())
        -> VoiceCaptureController {
        VoiceCaptureController(recorder: rec, transcriber: transcriber, interpreter: interp)
    }

    func testHappyPathProducesPendingPreview() async {
        let interp = StubInterpreter(cmd: InterpretedCommand(
            transcript: "set group 1 to blue",
            edits: [.setGroup(song: nil, cue: 1, group: "1", block: nil)]))
        let c = make(StubTranscriber(text: "set group 1 to blue"), interp)
        var p = Project.empty(); p.songs[0].cues = [Cue(n: 1)]
        await c.startRecording()
        await c.stopAndProcess(project: p, defaults: Defaults())
        guard case .preview = c.phase else { return XCTFail("expected preview, got \(c.phase)") }
        XCTAssertEqual(c.pending?.transcript, "set group 1 to blue")
        XCTAssertEqual(c.pending?.summary, ["Cue 1 · group = 1"])
        XCTAssertEqual(c.pending?.result.project.songs[0].cues[0].actions[0].group, "1")
    }

    func testTranscribeErrorGoesToError() async {
        struct Boom: Transcriber { func transcribe(_ u: URL) async throws -> String { throw VoiceError.emptyTranscript } }
        let c = make(Boom(), StubInterpreter(cmd: InterpretedCommand(transcript: "", edits: [])))
        await c.startRecording()
        await c.stopAndProcess(project: Project.empty(), defaults: Defaults())
        guard case .error = c.phase else { return XCTFail("expected error, got \(c.phase)") }
    }

    func testClarificationShowsPreviewWithNoEdits() async {
        let interp = StubInterpreter(cmd: InterpretedCommand(transcript: "do it", edits: [], clarification: "Which song?"))
        let c = make(StubTranscriber(text: "do it"), interp)
        await c.startRecording()
        await c.stopAndProcess(project: Project.empty(), defaults: Defaults())
        guard case .preview = c.phase else { return XCTFail("expected preview") }
        XCTAssertEqual(c.pending?.clarification, "Which song?")
        XCTAssertTrue(c.pending?.summary.isEmpty ?? false)
    }
}
