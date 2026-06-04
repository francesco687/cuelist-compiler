import Foundation

/// Selection for a send: just the active song, or every song with cues.
public enum Selection: String, Sendable { case current, all }

/// What the phone sends to the hub.
public enum OutgoingMessage {
    case compileSend(project: Project, defaults: Defaults, selection: Selection)

    private struct CompileSend: Encodable {
        let type = "compile-send"
        let project: Project
        let defaults: Defaults
        let selection: String
    }

    public func jsonData() throws -> Data {
        switch self {
        case let .compileSend(project, defaults, selection):
            let enc = JSONEncoder()
            return try enc.encode(CompileSend(project: project, defaults: defaults,
                                              selection: selection.rawValue))
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
    case other                                  // pong / sent / unknown — ignored by the client

    private struct Envelope: Decodable {
        let type: String
        let sent: Int?
        let total: Int?
        let message: String?
    }

    public static func decode(_ text: String) throws -> IncomingMessage {
        let e = try JSONDecoder().decode(Envelope.self, from: Data(text.utf8))
        switch e.type {
        case "progress": return .progress(sent: e.sent ?? 0, total: e.total ?? 0)
        case "done":     return .done(total: e.total ?? 0)
        case "error":    return .error(message: e.message ?? "unknown error")
        default:         return .other
        }
    }
}
