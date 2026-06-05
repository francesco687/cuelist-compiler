import Foundation

/// Result of interpreting one transcript: the validated edits + an optional
/// clarification question (when the model couldn't act).
public struct InterpretedCommand: Equatable, Sendable {
    public var transcript: String
    public var edits: [ShowEdit]
    public var clarification: String?
    public init(transcript: String, edits: [ShowEdit], clarification: String? = nil) {
        self.transcript = transcript; self.edits = edits; self.clarification = clarification
    }
}

/// Errors surfaced to the UI as toasts.
public enum VoiceError: Error, Equatable {
    case missingKey(String)        // which provider
    case api(status: Int, message: String)
    case emptyTranscript
    case badResponse(String)
}
