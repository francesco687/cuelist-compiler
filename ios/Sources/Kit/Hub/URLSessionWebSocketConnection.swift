import Foundation

/// Production HubConnection backed by URLSessionWebSocketTask. Hops all events to
/// the main actor so HubClient (a @MainActor @Observable) updates safely.
@MainActor
public final class URLSessionWebSocketConnection: NSObject, HubConnection, URLSessionWebSocketDelegate {
    private let url: URL
    private var task: URLSessionWebSocketTask?
    private var onEvent: ((HubConnectionEvent) -> Void)?
    private lazy var session: URLSession =
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    public init(url: URL) { self.url = url }

    public func connect(onEvent: @escaping (HubConnectionEvent) -> Void) {
        self.onEvent = onEvent
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receive()
    }

    public func send(_ text: String) {
        task?.send(.string(text)) { [weak self] err in
            guard let err else { return }
            Task { @MainActor in self?.onEvent?(.closed(err.localizedDescription)) }
        }
    }

    public func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(.string(text)):
                    self.onEvent?(.text(text))
                    self.receive()
                case .success(.data):
                    self.receive()                       // ignore binary
                case .success:
                    self.receive()
                case let .failure(err):
                    self.onEvent?(.closed(err.localizedDescription))
                }
            }
        }
    }

    // URLSessionWebSocketDelegate — open/close signals.
    nonisolated public func urlSession(_ session: URLSession,
                                       webSocketTask: URLSessionWebSocketTask,
                                       didOpenWithProtocol proto: String?) {
        Task { @MainActor in self.onEvent?(.opened) }
    }

    nonisolated public func urlSession(_ session: URLSession,
                                       webSocketTask: URLSessionWebSocketTask,
                                       didCloseWith code: URLSessionWebSocketTask.CloseCode,
                                       reason: Data?) {
        Task { @MainActor in self.onEvent?(.closed(nil)) }
    }
}
