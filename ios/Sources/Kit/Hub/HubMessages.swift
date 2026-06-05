import Foundation

/// Selection for a send: just the active song, or every song with cues.
public enum Selection: String, Sendable { case current, all }

/// One sequence as listed by the desk's list_sequences plugin (number + name).
public struct PulledSequence: Equatable, Sendable, Identifiable, Decodable {
    public let no: Double
    public let name: String
    public var id: Double { no }
    public init(no: Double, name: String) { self.no = no; self.name = name }
}

/// What the phone sends to the hub.
public enum OutgoingMessage {
    case compileSend(project: Project, defaults: Defaults, selection: Selection)
    case pullSequences

    private struct CompileSend: Encodable {
        let type = "compile-send"
        let project: Project
        let defaults: Defaults
        let selection: String
    }

    private struct PullSequences: Encodable { let type = "pull-sequences" }

    public func jsonData() throws -> Data {
        let enc = JSONEncoder()
        switch self {
        case let .compileSend(project, defaults, selection):
            return try enc.encode(CompileSend(project: project, defaults: defaults,
                                              selection: selection.rawValue))
        case .pullSequences:
            return try enc.encode(PullSequences())
        }
    }

    public func jsonString() throws -> String {
        String(decoding: try jsonData(), as: UTF8.self)
    }
}

/// What the hub sends back.
public enum IncomingMessage: Equatable, Sendable {
    case progress(sent: Int, total: Int)
    case done(total: Int)
    case error(message: String)
    case sequences(version: Int, [PulledSequence])   // pull result: the showfile's sequence list
    case pullError(message: String)                  // pull failed (trigger/timeout/parse)
    case other                                        // pong / sent / unknown — ignored by the client

    private struct Envelope: Decodable {
        let type: String
        let sent: Int?
        let total: Int?
        let message: String?
        let version: Int?
        let sequences: [PulledSequence]?
    }

    public static func decode(_ text: String) throws -> IncomingMessage {
        let e = try JSONDecoder().decode(Envelope.self, from: Data(text.utf8))
        switch e.type {
        case "progress":   return .progress(sent: e.sent ?? 0, total: e.total ?? 0)
        case "done":       return .done(total: e.total ?? 0)
        case "error":      return .error(message: e.message ?? "unknown error")
        case "sequences":  return .sequences(version: e.version ?? 1, e.sequences ?? [])
        case "pull-error": return .pullError(message: e.message ?? "pull failed")
        default:           return .other
        }
    }
}
