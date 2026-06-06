import XCTest
import Network
@testable import SaettaKit

@MainActor
final class URLSessionWebSocketConnectionTests: XCTestCase {

    /// Minimal ws server: on the first text frame it receives, replies with
    /// progress then done. Returns the bound port.
    final class FakeHubServer {
        let listener: NWListener
        var conn: NWConnection?
        init() throws {
            let params = NWParameters.tcp
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
            listener = try NWListener(using: params, on: .any)
        }
        func start() {
            listener.newConnectionHandler = { [weak self] c in
                self?.conn = c
                c.start(queue: .global())
                self?.receive(c)
            }
            listener.start(queue: .global())
        }
        private func receive(_ c: NWConnection) {
            c.receiveMessage { [weak self] _, _, _, _ in
                self?.sendText(c, #"{"type":"progress","sent":1,"total":1}"#)
                self?.sendText(c, #"{"type":"done","total":1}"#)
            }
        }
        private func sendText(_ c: NWConnection, _ s: String) {
            let meta = NWProtocolWebSocket.Metadata(opcode: .text)
            let ctx = NWConnection.ContentContext(identifier: "t", metadata: [meta])
            c.send(content: Data(s.utf8), contentContext: ctx, completion: .contentProcessed { _ in })
        }
        func stop() { listener.cancel(); conn?.cancel() }
        func port() async throws -> Int {
            for _ in 0..<100 {
                if let p = listener.port?.rawValue, p != 0 { return Int(p) }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            throw XCTSkip("server never bound a port")
        }
    }

    func testRealSocketReachesDoneAgainstFakeServer() async throws {
        let server = try FakeHubServer()
        server.start()
        defer { server.stop() }
        let port = try await server.port()

        let suite = "cc-ws-\(UUID().uuidString)"
        let client = HubClient(defaults: UserDefaults(suiteName: suite)!,
                               makeConnection: { url in URLSessionWebSocketConnection(url: url) })
        client.host = "127.0.0.1"
        client.port = port
        client.connect()

        // Wait for online.
        try await poll { client.state == .online }
        client.send(project: Project.empty(), defaults: Defaults(), selection: .all)
        try await poll { client.lastResult == .done(total: 1) }
        XCTAssertEqual(client.lastResult, .done(total: 1))
    }

    /// Poll a main-actor condition up to ~3s.
    private func poll(_ cond: @MainActor () -> Bool) async throws {
        for _ in 0..<150 {
            if cond() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("condition not met in time")
    }
}
