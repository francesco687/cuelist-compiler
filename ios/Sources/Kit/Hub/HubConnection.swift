import Foundation

/// Events a connection reports back to the client.
public enum HubConnectionEvent: Sendable {
    case opened
    case text(String)
    case closed(String?)      // non-nil message = error reason
}

/// A minimal socket abstraction so `HubClient` can be tested without a real WebSocket.
@MainActor
public protocol HubConnection: AnyObject {
    func connect(onEvent: @escaping (HubConnectionEvent) -> Void)
    func send(_ text: String)
    func close()
}
