import XCTest
@testable import CuelistCompilerKit

@MainActor
final class NotesCaptureControllerTests: XCTestCase {
    private struct StubRouter: NoteInterpreter {
        let result: [NoteEdit]
        func route(transcript: String, project: Project, targetCue: Double?) async throws -> [NoteEdit] { result }
    }
    private func project() -> Project {
        Project(songs: [Song(id: "a", name: "S", sequence: 1, cues: [Cue(n: 1)])], activeSongId: "a")
    }
    func testRouteTextSetsPreviewEdits() async {
        let c = NotesCaptureController(recorder: NoopRecorder(), transcriber: NoopTranscriber(text: ""),
                                       router: StubRouter(result: [NoteEdit(cue: 1, text: "dim")]))
        await c.routeText("dim the intro", project: project(), targetCue: nil)
        XCTAssertEqual(c.routed, [NoteEdit(cue: 1, text: "dim")])
        XCTAssertEqual(c.phase, .preview)
    }
    func testRouterErrorSurfacesAsErrorPhase() async {
        struct Failing: NoteInterpreter {
            func route(transcript: String, project: Project, targetCue: Double?) async throws -> [NoteEdit] {
                throw VoiceError.missingKey("Anthropic")
            }
        }
        let c = NotesCaptureController(recorder: NoopRecorder(), transcriber: NoopTranscriber(text: ""),
                                       router: Failing())
        await c.routeText("x", project: project(), targetCue: nil)
        if case .error = c.phase {} else { XCTFail("expected error phase") }
    }
}

// Stubs adjusted to match real AudioRecorder/Transcriber protocol signatures:
// AudioRecorder.stop() -> URL?, Transcriber.transcribe(_ audio: URL) -> String
private final class NoopRecorder: AudioRecorder {
    func requestPermission() async -> Bool { true }
    func start() throws {}
    func stop() async -> URL? { FileManager.default.temporaryDirectory.appendingPathComponent("noop.m4a") }
}
private struct NoopTranscriber: Transcriber {
    let text: String
    func transcribe(_ audio: URL) async throws -> String { text }
}
