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
    case cmd(line: String)
    case join(room: String, role: String)

    private struct CompileSend: Encodable {
        let type = "compile-send"
        let project: Project
        let defaults: Defaults
        let selection: String
    }

    private struct PullSequences: Encodable { let type = "pull-sequences" }

    private struct Cmd: Encodable { let type = "cmd"; let line: String }

    private struct Join: Encodable { let type = "join"; let room: String; let role: String }

    public func jsonData() throws -> Data {
        let enc = JSONEncoder()
        switch self {
        case let .compileSend(project, defaults, selection):
            return try enc.encode(CompileSend(project: project, defaults: defaults,
                                              selection: selection.rawValue))
        case .pullSequences:
            return try enc.encode(PullSequences())
        case let .cmd(line):
            return try enc.encode(Cmd(line: line))
        case let .join(room, role):
            return try enc.encode(Join(room: room, role: role))
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
    case joined                                      // relay: this side joined a room
    case peer(connected: Bool)                       // relay: the other side connected/dropped
    case joinError(message: String)                  // relay: join rejected (bad/taken code, relay full)
    case other                                        // pong / sent / unknown — ignored by the client

    private struct Envelope: Decodable {
        let type: String
        let sent: Int?
        let total: Int?
        let message: String?
        let version: Int?
        let sequences: [PulledSequence]?
        let connected: Bool?
    }

    public static func decode(_ text: String) throws -> IncomingMessage {
        let e = try JSONDecoder().decode(Envelope.self, from: Data(text.utf8))
        switch e.type {
        case "progress":   return .progress(sent: e.sent ?? 0, total: e.total ?? 0)
        case "done":       return .done(total: e.total ?? 0)
        case "error":      return .error(message: e.message ?? "unknown error")
        case "sequences":  return .sequences(version: e.version ?? 1, e.sequences ?? [])
        case "pull-error": return .pullError(message: e.message ?? "pull failed")
        case "joined":     return .joined
        case "peer":       return .peer(connected: e.connected ?? false)
        case "join-error": return .joinError(message: e.message ?? "pairing rejected")
        default:           return .other
        }
    }
}
