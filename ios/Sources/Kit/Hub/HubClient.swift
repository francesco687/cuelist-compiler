import Foundation
import Observation

public enum ConnectionState: Equatable, Sendable {
    case offline, connecting, online
    case error(String)

    public var isOnline: Bool { self == .online }
}

public enum HubMode: String, Sendable { case direct, relay }

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

    // Pull side: request the showfile's sequence list from the desk.
    public private(set) var isPulling = false
    public private(set) var sequences: [PulledSequence]?
    public private(set) var pullError: String?

    public var host: String { didSet { defaults.set(host, forKey: Keys.host) } }
    public var port: Int    { didSet { defaults.set(port, forKey: Keys.port) } }

    public var mode: HubMode { didSet { defaults.set(mode.rawValue, forKey: Keys.mode) } }
    public var relayURL: String { didSet { defaults.set(relayURL, forKey: Keys.relayURL) } }
    public var pairingCode: String { didSet { defaults.set(pairingCode, forKey: Keys.pairingCode) } }

    public private(set) var roster: [Operator] = []
    public var operatorName: String = ""

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeConnection: (URL) -> HubConnection
    @ObservationIgnored private let scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void
    @ObservationIgnored private var connection: HubConnection?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var ownCid: String?
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var backoff: TimeInterval = 1
    @ObservationIgnored private var generation = 0

    private enum Keys {
        static let host = "hubHost"; static let port = "hubPort"
        static let mode = "hubMode"; static let relayURL = "hubRelayURL"; static let pairingCode = "hubPairingCode"
    }

    public init(defaults: UserDefaults = .standard,
                makeConnection: @escaping (URL) -> HubConnection,
                scheduleAfter: @escaping (TimeInterval, @escaping () -> Void) -> Void
                    = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }) {
        self.scheduleAfter = scheduleAfter
        self.defaults = defaults
        self.makeConnection = makeConnection
        self.host = defaults.string(forKey: Keys.host) ?? ""
        let p = defaults.integer(forKey: Keys.port)
        self.port = p == 0 ? 9000 : p
        self.mode = HubMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .direct
        self.relayURL = defaults.string(forKey: Keys.relayURL) ?? ""
        self.pairingCode = defaults.string(forKey: Keys.pairingCode) ?? ""
    }

    public var url: URL? {
        switch mode {
        case .direct: return URL(string: "ws://\(host):\(port)")
        case .relay:  return relayURL.isEmpty ? nil : URL(string: relayURL)
        }
    }

    public func connect() {
        stopped = false
        if mode == .relay && pairingCode.isEmpty {
            state = .error("enter the pairing code")
            return
        }
        guard let url else {
            state = .error(mode == .relay ? "set the relay URL" : "set the hub host first")
            return
        }
        state = .connecting
        connection?.close()                 // tear down any prior socket before replacing
        generation += 1
        let gen = generation
        let conn = makeConnection(url)
        connection = conn
        conn.connect { [weak self] event in
            guard let self else { return }
            guard gen == self.generation else { return }
            switch event {
            case .opened:
                switch self.mode {
                case .direct:
                    self.state = .online
                case .relay:
                    // Join the room first; stay .connecting until the hub (roster) is present.
                    if let join = try? OutgoingMessage.join(room: self.pairingCode, role: "phone",
                                                            name: self.operatorName.isEmpty ? nil : self.operatorName).jsonString() {
                        conn.send(join)
                    }
                }
            case let .text(text):
                self.handle(text)
            case let .closed(reason):
                self.state = reason.map(ConnectionState.error) ?? .offline
                if self.mode == .relay && !self.stopped { self.scheduleReconnect() }
            }
        }
    }

    public func disconnect() {
        stopped = true
        generation += 1                     // invalidate any pending connection's events (defense in depth)
        backoff = 1                         // reset backoff so next connect() starts fresh
        roster = []                         // clear stale operator list immediately
        connection?.close()
        connection = nil
        state = .offline
    }

    private func scheduleReconnect() {
        let wait = backoff
        backoff = min(backoff * 2, 15)
        scheduleAfter(wait) { [weak self] in
            guard let self, !self.stopped else { return }
            self.connect()
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

    /// Ask the desk for the sequence list currently in the loaded showfile.
    public func pullSequences() {
        if !state.isOnline { connect() }
        guard let conn = connection else { return }
        do {
            let text = try OutgoingMessage.pullSequences.jsonString()
            isPulling = true
            pullError = nil
            conn.send(text)
        } catch {
            isPulling = false
            pullError = "encode failed: \(error.localizedDescription)"
        }
    }

    /// Fire a single command-line string at the desk (e.g. "Go+", "Go-", "Pause").
    /// Optimistic: the caller provides its own visual/haptic feedback; no ack is awaited.
    public func sendCommand(_ line: String) {
        if !state.isOnline { connect() }
        guard let conn = connection else { return }
        guard let text = try? OutgoingMessage.cmd(line: line).jsonString() else { return }
        conn.send(text)
    }

    /// Pop a free-text note as a `MessageBox` on the desk. Builds the command-line
    /// string via `ConsoleMessage` and forwards it over the same optimistic `cmd`
    /// passthrough as the transport buttons. No-ops if the note sanitizes to empty.
    public func sendConsoleMessage(_ text: String) {
        guard let line = ConsoleMessage.line(text: text) else { return }
        sendCommand(line)
    }

    /// Send a batch of command lines as individual `cmd` frames, throttled to
    /// match the hub's compile-send pacing (the hub forwards single `cmd` frames
    /// immediately, so spacing must happen here). Drives the same progress/result
    /// the Send tab already binds to. No desk ack is awaited.
    public func sendLines(_ lines: [String], intervalMs: Int = 20) {
        if !state.isOnline { connect() }
        guard connection != nil else { lastResult = .failed("not connected"); return }
        guard !lines.isEmpty else { return }
        progress = SendProgress(sent: 0, total: lines.count)
        lastResult = nil
        sendTask?.cancel()                              // supersede any in-flight batch
        sendTask = Task { [weak self] in
            guard let self else { return }
            for (i, line) in lines.enumerated() {
                if Task.isCancelled { return }          // superseded — leave state to the newer task
                guard let conn = self.connection else { break }
                if let text = try? OutgoingMessage.cmd(line: line).jsonString() {
                    conn.send(text)
                }
                self.progress = SendProgress(sent: i + 1, total: lines.count)
                if i < lines.count - 1, intervalMs > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(intervalMs) * 1_000_000)
                }
            }
            if Task.isCancelled { return }              // don't stomp the newer task's completion
            self.progress = nil
            self.lastResult = .done(total: lines.count)
        }
    }

    /// Send cue STRUCTURE only (no notes) for the selection.
    public func sendCues(project: Project, defaults: Defaults, selection: Selection) {
        let songs = MA3CommandBuilder.songsInScope(project, selection: selection)
        guard !songs.isEmpty else { lastResult = .failed("no cues to send"); return }
        sendLines(MA3CommandBuilder.cueLines(songs: songs, defaults: defaults, storeMode: project.storeMode))
    }

    /// Send NOTES only for the selection.
    public func sendNotes(project: Project, selection: Selection) {
        let songs = MA3CommandBuilder.songsInScope(project, selection: selection)
        let lines = MA3CommandBuilder.noteLines(songs: songs)
        guard !lines.isEmpty else { lastResult = .failed("no notes to send"); return }
        sendLines(lines)
    }

    /// Append the ticked cues' timecode to the active song's sequence (append-only).
    public func sendTimecode(song: Song, ticked: Set<UUID>) {
        let lines = TimecodeBuilder.lines(song: song, ticked: ticked)
        guard !lines.isEmpty else { lastResult = .failed("no timecode to send"); return }
        sendLines(lines)
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
        case let .sequences(_, seqs):
            isPulling = false
            sequences = seqs
        case let .pullError(message):
            isPulling = false
            pullError = message
        case let .joined(cid):
            ownCid = cid                            // remember our id for self-marking
        case let .roster(hub, phones):
            roster = phones
            if mode == .relay { state = hub ? .online : .connecting }
            if hub { backoff = 1 }                  // healthy link → reset backoff
        case let .peer(connected):                  // legacy relay; harmless if it arrives
            if mode == .relay { state = connected ? .online : .connecting }
        case let .joinError(message):
            stopped = true
            state = .error(message)                // surface the relay's reason (bad/taken code, full)
        case .other:
            break
        }
    }
}
