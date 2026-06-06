import Foundation
import Observation

/// Owns the in-memory show + defaults and persists them as JSON. The UI binds to this.
///
/// ## Migration fallback
/// `Project.init(from:)` uses `decodeIfPresent` for every field, so it never throws
/// on old-format data — it just produces an empty-songs Project. A valid saved file
/// always has at least one song (we never write zero-song Projects), so an empty-songs
/// result is the reliable signal that the file is in the old single-song format.
/// In that case we fall through to `Migration.project(fromShowJSON:)`.
@MainActor
@Observable
public final class ProjectStore {
    public var project: Project { didSet { scheduleSave() } }
    public var defaults: Defaults { didSet { scheduleSave() } }

    /// Cues (by `Cue.id`) ticked for the next Send Timecode. TRANSIENT: it is a
    /// plain property (not part of `project`), so it is never written to disk and
    /// resets to empty on every launch. Cleared after a successful TC send.
    public var tcSelection: Set<UUID> = []

    @ObservationIgnored let directory: URL
    @ObservationIgnored private let projectURL: URL
    @ObservationIgnored private let defaultsURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = dir
        self.projectURL = dir.appendingPathComponent("project.json")
        self.defaultsURL = dir.appendingPathComponent("defaults.json")

        let dec = JSONDecoder()
        if let data = try? Data(contentsOf: projectURL) {
            let decoded = try? dec.decode(Project.self, from: data)
            if let p = decoded, !p.songs.isEmpty {
                // Current format: decoded cleanly and has songs.
                self.project = p
            } else if let migrated = try? Migration.project(fromShowJSON: data) {
                // Old format (or decoded to empty songs): upgrade via Migration.
                self.project = migrated
            } else {
                self.project = Project.empty()
            }
        } else {
            self.project = Project.empty()
        }
        if let data = try? Data(contentsOf: defaultsURL),
           let d = try? dec.decode(Defaults.self, from: data) {
            self.defaults = d
        } else {
            self.defaults = Defaults()
        }
    }

    /// Debounced background save (mirrors web saveState on each mutation).
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            self?.saveNow()
        }
    }

    public func isTcSelected(_ id: UUID) -> Bool { tcSelection.contains(id) }

    public func toggleTc(_ id: UUID) {
        if tcSelection.contains(id) { tcSelection.remove(id) } else { tcSelection.insert(id) }
    }

    public func clearTcSelection() { tcSelection.removeAll() }

    public func removeTc(_ id: UUID) { tcSelection.remove(id) }

    /// Synchronous write — used by tests and on background/terminate.
    public func saveNow() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let p = try? enc.encode(project) { try? p.write(to: projectURL) }
        if let d = try? enc.encode(defaults) { try? d.write(to: defaultsURL) }
    }
}
