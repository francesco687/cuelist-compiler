import Foundation

public struct ApplyResult: Equatable, Sendable {
    public var project: Project
    public var defaults: Defaults
    public var summary: [String]
    public var warnings: [String]
}

/// Pure: resolves human references, applies the ops to copies, and records a
/// deterministic plain-language summary + warnings for skipped/unresolved ops.
public enum ShowEditApplier {

    public static func apply(_ edits: [ShowEdit], to project: Project, defaults: Defaults) -> ApplyResult {
        var p = project, d = defaults, summary: [String] = [], warnings: [String] = []
        for edit in edits { applyOne(edit, &p, &d, &summary, &warnings) }
        return ApplyResult(project: p, defaults: d, summary: summary, warnings: warnings)
    }

    // MARK: reference resolution

    /// nil ref → active song; an integer ref → 1-based index; else case-insensitive name.
    static func songIndex(_ ref: String?, _ p: Project) -> Int? {
        guard let ref else { return p.songs.firstIndex { $0.id == p.activeSongId } ?? (p.songs.isEmpty ? nil : 0) }
        let trimmed = ref.trimmingCharacters(in: .whitespaces)
        if let i = Int(trimmed), i >= 1, i <= p.songs.count { return i - 1 }
        return p.songs.firstIndex { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    static func cueIndex(_ cue: Double, _ songIdx: Int, _ p: Project) -> Int? {
        p.songs[songIdx].cues.firstIndex { $0.n == cue }
    }

    static func warn(_ warnings: inout [String], _ ref: String?, _ op: String) {
        warnings.append("Song \u{201C}\(ref ?? "active")\u{201D} not found \u{2014} skipped \(op)")
    }

    // MARK: dispatch (song ops here; cue/action ops added in later tasks)

    static func applyOne(_ edit: ShowEdit, _ p: inout Project, _ d: inout Defaults,
                         _ summary: inout [String], _ warnings: inout [String]) {
        switch edit {
        case let .addSong(name, sequence):
            let s = Song(id: IDGen.next(), name: name ?? "", sequence: sequence ?? 1, cues: [])
            p.songs.append(s); p.activeSongId = s.id
            summary.append("Add song \u{201C}\(s.name)\u{201D} (sequence \(s.sequence))")

        case let .renameSong(song, name):
            guard let i = songIndex(song, p) else { return warn(&warnings, song, "renameSong") }
            p.songs[i].name = name
            summary.append("Rename song \(i + 1) \u{2192} \u{201C}\(name)\u{201D}")

        case let .setSequence(song, sequence):
            guard let i = songIndex(song, p) else { return warn(&warnings, song, "setSequence") }
            p.songs[i].sequence = sequence
            summary.append("Song \(i + 1) sequence \u{2192} \(sequence)")

        case let .selectSong(song):
            guard let i = songIndex(song, p) else { return warn(&warnings, song, "selectSong") }
            p.activeSongId = p.songs[i].id
            summary.append("Select song \(i + 1) (\u{201C}\(p.songs[i].name)\u{201D})")

        case let .deleteSong(song):
            guard let i = songIndex(song, p) else { return warn(&warnings, song, "deleteSong") }
            let name = p.songs[i].name
            p.songs.remove(at: i)
            if p.songs.isEmpty {
                let ns = Song(id: IDGen.next(), sequence: 1, cues: [])
                p.songs = [ns]; p.activeSongId = ns.id
            } else if !p.songs.contains(where: { $0.id == p.activeSongId }) {
                p.activeSongId = p.songs[max(0, i - 1)].id
            }
            summary.append("Delete song \u{201C}\(name)\u{201D}")

        default:
            break   // cue/action/defaults/project ops handled in Tasks 4–5
        }
    }
}
