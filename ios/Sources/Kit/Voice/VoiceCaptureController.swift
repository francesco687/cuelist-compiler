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

    @ObservationIgnored private var processingTask: Task<Void, Never>?

    public func stopAndProcess(project: Project, defaults: Defaults) async {
        let task = Task { @MainActor in
            guard let audio = await recorder.stop() else { phase = .error("No audio captured"); return }
            do {
                phase = .transcribing
                try Task.checkCancellation()
                let transcript = try await transcriber.transcribe(audio)
                phase = .interpreting
                try Task.checkCancellation()
                let cmd = try await interpreter.interpret(transcript: transcript, project: project, defaults: defaults)
                try Task.checkCancellation()
                let result = ShowEditApplier.apply(cmd.edits, to: project, defaults: defaults)
                pending = Pending(transcript: transcript, summary: result.summary, warnings: result.warnings,
                                  clarification: cmd.clarification, result: result)
                phase = .preview
            } catch is CancellationError {
                // user cancelled mid-flight; leave whatever cancel() already set (.idle)
            } catch let VoiceError.api(status, _) {
                phase = .error("Service error (\(status))")
            } catch VoiceError.emptyTranscript {
                phase = .error("Didn't catch that — try again")
            } catch let VoiceError.missingKey(p) {
                phase = .error("Add your \(p) API key in Settings")
            } catch VoiceError.badResponse {
                phase = .error("Service returned an unexpected response — try again")
            } catch {
                phase = .error("Couldn't interpret that — try rephrasing")
            }
        }
        processingTask = task
        await task.value
    }

    public func cancel() {
        processingTask?.cancel()
        processingTask = nil
        phase = .idle
        pending = nil
    }
}

public extension VoiceCaptureController.Phase {
    /// Label for the bottom talk bar. Pure presentation — kept in Kit so it's testable.
    var talkBarLabel: String {
        switch self {
        case .idle, .error:                 return "Tap to talk"
        case .recording:                    return "Listening\u{2026} tap to stop"
        case .transcribing, .interpreting:  return "Thinking\u{2026}"
        case .preview:                      return "Reviewing\u{2026}"
        }
    }
    /// Short label for the compact bottom-cluster Talk button.
    var talkButtonLabel: String {
        switch self {
        case .idle, .error:                 return "Talk"
        case .recording:                    return "Stop"
        case .transcribing, .interpreting:  return "\u{2026}"
        case .preview:                      return "\u{2026}"
        }
    }
    var isRecording: Bool { if case .recording = self { return true } else { return false } }
    var isBusy: Bool {
        switch self { case .transcribing, .interpreting: return true; default: return false }
    }
}
