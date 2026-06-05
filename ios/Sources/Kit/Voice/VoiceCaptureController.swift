import Foundation
import Observation

@MainActor @Observable
public final class VoiceCaptureController {

    /// What the preview sheet renders.
    public struct Pending: Equatable, Sendable {
        public var transcript: String
        public var summary: [String]
        public var warnings: [String]
        public var clarification: String?
        public var result: ApplyResult
        public var canApply: Bool { clarification == nil && !result.summary.isEmpty }
    }

    public enum Phase: Equatable {
        case idle, recording, transcribing, interpreting, preview, error(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var pending: Pending?

    @ObservationIgnored private let recorder: AudioRecorder
    @ObservationIgnored private let transcriber: Transcriber
    @ObservationIgnored private let interpreter: CommandInterpreter

    public init(recorder: AudioRecorder, transcriber: Transcriber, interpreter: CommandInterpreter) {
        self.recorder = recorder; self.transcriber = transcriber; self.interpreter = interpreter
    }

    public func startRecording() async {
        guard await recorder.requestPermission() else { phase = .error("Microphone access denied"); return }
        do { try recorder.start(); phase = .recording }
        catch { phase = .error("Couldn't start recording") }
    }

    public func stopAndProcess(project: Project, defaults: Defaults) async {
        guard let audio = await recorder.stop() else { phase = .error("No audio captured"); return }
        do {
            phase = .transcribing
            let transcript = try await transcriber.transcribe(audio)
            phase = .interpreting
            let cmd = try await interpreter.interpret(transcript: transcript, project: project, defaults: defaults)
            let result = ShowEditApplier.apply(cmd.edits, to: project, defaults: defaults)
            pending = Pending(transcript: transcript, summary: result.summary, warnings: result.warnings,
                              clarification: cmd.clarification, result: result)
            phase = .preview
        } catch let VoiceError.api(status, _) {
            phase = .error("Service error (\(status))")
        } catch VoiceError.emptyTranscript {
            phase = .error("Didn't catch that — try again")
        } catch let VoiceError.missingKey(p) {
            phase = .error("Add your \(p) API key in Settings")
        } catch {
            phase = .error("Couldn't interpret that — try rephrasing")
        }
    }

    public func cancel() { phase = .idle; pending = nil }
}
