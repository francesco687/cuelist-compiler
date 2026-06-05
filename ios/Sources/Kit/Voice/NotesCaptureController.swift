import Foundation
import Observation

/// Captures a note by text or voice and routes it onto cue(s) via a NoteInterpreter.
@MainActor @Observable
public final class NotesCaptureController {

    public enum Phase: Equatable {
        case idle, recording, transcribing, routing, preview, error(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var routed: [NoteEdit] = []
    public private(set) var transcript: String = ""

    @ObservationIgnored private let recorder: AudioRecorder
    @ObservationIgnored private let transcriber: Transcriber
    @ObservationIgnored private let router: NoteInterpreter

    public init(recorder: AudioRecorder, transcriber: Transcriber, router: NoteInterpreter) {
        self.recorder = recorder; self.transcriber = transcriber; self.router = router
    }

    public func startRecording() async {
        guard await recorder.requestPermission() else { phase = .error("Microphone access denied"); return }
        do { try recorder.start(); phase = .recording }
        catch { phase = .error("Couldn't start recording") }
    }

    /// Stop recording and transcribe; returns the transcript (also stored on `transcript`).
    /// Caller then passes the text to `routeText` to route and preview.
    @discardableResult
    public func stopAndTranscribe() async -> String {
        guard let audio = await recorder.stop() else { phase = .error("No audio captured"); return "" }
        do {
            phase = .transcribing
            let t = try await transcriber.transcribe(audio)
            transcript = t
            phase = .idle
            return t
        } catch {
            phase = .error("Didn't catch that -- try again")
            return ""
        }
    }

    public func routeText(_ text: String, project: Project, targetCue: Double?) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { phase = .error("Nothing to add"); return }
        do {
            phase = .routing
            let edits = try await router.route(transcript: trimmed, project: project, targetCue: targetCue)
            routed = edits
            phase = edits.isEmpty ? .error("Couldn't place that note") : .preview
        } catch let VoiceError.api(status, _) {
            phase = .error("Service error (\(status))")
        } catch let VoiceError.missingKey(p) {
            phase = .error("Add your \(p) API key in Settings")
        } catch VoiceError.badResponse {
            phase = .error("Service returned an unexpected response — try again")
        } catch {
            phase = .error("Couldn't route that -- try rephrasing")
        }
    }

    public func reset() { phase = .idle; routed = []; transcript = "" }
}

public extension NotesCaptureController.Phase {
    var isNotesRecording: Bool { if case .recording = self { return true } else { return false } }
}
