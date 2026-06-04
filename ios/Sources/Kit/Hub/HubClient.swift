import Foundation
import Observation

public enum ConnectionState: Equatable, Sendable {
    case offline, connecting, online
    case error(String)

    public var isOnline: Bool { self == .online }
}

public struct SendProgress: Equatable, Sendable { public var sent: Int; public var total: Int }

public enum SendResult: Equatable, Sendable {
    case done(total: Int)
    case failed(String)
}

/// The observable the send bar binds to. Drives a HubConnection, tracks state,
/// sends compile-send, and surfaces streamed progress/result.
@MainActor
@Observable
public final class HubClient {
    public private(set) var state: ConnectionState = .offline
    public private(set) var progress: SendProgress?
    public private(set) var lastResult: SendResult?

    public var host: String { didSet { defaults.set(host, forKey: Keys.host) } }
    public var port: Int    { didSet { defaults.set(port, forKey: Keys.port) } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeConnection: (URL) -> HubConnection
    @ObservationIgnored private var connection: HubConnection?

    private enum Keys { static let host = "hubHost"; static let port = "hubPort" }

    public init(defaults: UserDefaults = .standard,
                makeConnection: @escaping (URL) -> HubConnection) {
        self.defaults = defaults
        self.makeConnection = makeConnection
        self.host = defaults.string(forKey: Keys.host) ?? ""
        let p = defaults.integer(forKey: Keys.port)
        self.port = p == 0 ? 9000 : p
    }

    public var url: URL? { URL(string: "ws://\(host):\(port)") }

    public func connect() {
        guard let url else { state = .error("set hub host first"); return }
        state = .connecting
        connection?.close()                 // tear down any prior socket before replacing
        let conn = makeConnection(url)
        connection = conn
        conn.connect { [weak self] event in
            guard let self else { return }
            switch event {
            case .opened:
                self.state = .online
            case let .text(text):
                self.handle(text)
            case let .closed(reason):
                self.state = reason.map(ConnectionState.error) ?? .offline
            }
        }
    }

    public func send(project: Project, defaults: Defaults, selection: Selection) {
        if !state.isOnline { connect() }
        guard let conn = connection else { return }
        do {
            let text = try OutgoingMessage
                .compileSend(project: project, defaults: defaults, selection: selection)
                .jsonString()
            progress = nil
            lastResult = nil
            conn.send(text)
        } catch {
            lastResult = .failed("encode failed: \(error.localizedDescription)")
        }
    }

    private func handle(_ text: String) {
        guard let msg = try? IncomingMessage.decode(text) else { return }
        switch msg {
        case let .progress(sent, total):
            progress = SendProgress(sent: sent, total: total)
        case let .done(total):
            progress = nil
            lastResult = .done(total: total)
        case let .error(message):
            progress = nil
            lastResult = .failed(message)
        case .other:
            break
        }
    }
}
