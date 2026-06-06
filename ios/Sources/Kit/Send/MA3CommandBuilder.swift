import Foundation

/// Native Swift port of the cue/notes half of `web/js/compile.js`.
/// Splits what the web compiler entangles: cue STRUCTURE (no notes) and NOTES are
/// produced by separate functions so the Send tab can fire them independently.
/// Output ordering and quoting mirror `buildCmdLines()` exactly.
public enum MA3CommandBuilder {

    /// Collapse a free-text note to one safe command-line token:
    /// newlines/tabs/whitespace runs → single space, trimmed, then `"` → `\"`.
    /// Returns "" for empty/whitespace-only input.
    public static func sanitizeNote(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "[\\r\\n\\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return collapsed.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func escapeQuotes(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func formatN(_ n: Double) -> String {
        n.rounded() == n ? String(Int(n)) : String(n)
    }

    /// The songs a selection targets, mirroring `hub/src/compile-bridge.js`:
    /// `.current` = active song (by id, fallback first) iff it has cues; else none.
    /// `.all` = every song that has at least one cue.
    public static func songsInScope(_ project: Project, selection: Selection) -> [Song] {
        switch selection {
        case .current:
            let active = project.songs.first(where: { $0.id == project.activeSongId }) ?? project.songs.first
            guard let active, !active.cues.isEmpty else { return [] }
            return [active]
        case .all:
            return project.songs.filter { !$0.cues.isEmpty }
        }
    }

    /// Cue-structure command lines (ClearAll / Group / At Preset / Fade / Delay /
    /// Store / Set Fade / Set Delay), NO note lines. Mirrors `buildCmdLines`.
    public static func cueLines(songs: [Song], defaults: Defaults, storeMode: StoreMode) -> [String] {
        let flag = storeMode.flag   // "/Overwrite" or "/Merge"
        var out: [String] = []
        for song in songs {
            let seq = song.sequence
            for cue in song.cues {
                out.append("ClearAll")
                let actions = cue.actions.filter { !$0.group.trimmingCharacters(in: .whitespaces).isEmpty }
                for a in actions {
                    out.append("Group \"\(escapeQuotes(a.group))\"")
                    for pool in Pool.allCases {
                        let p = a.presets[pool] ?? Preset()
                        let name = p.name.trimmingCharacters(in: .whitespaces)
                        if name.isEmpty { continue }
                        out.append("At Preset \(pool.number).\"\(escapeQuotes(p.name))\"")
                        let fade = p.fade.trimmingCharacters(in: .whitespaces).isEmpty ? defaults.fade(pool) : p.fade
                        let delay = p.delay.trimmingCharacters(in: .whitespaces).isEmpty ? defaults.delay(pool) : p.delay
                        if !fade.trimmingCharacters(in: .whitespaces).isEmpty {
                            out.append("Fade \(fade) FeatureGroup \(pool.number)")
                        }
                        if !delay.trimmingCharacters(in: .whitespaces).isEmpty {
                            out.append("Delay \(delay) FeatureGroup \(pool.number)")
                        }
                    }
                }
                let cueName = escapeQuotes(cue.name)
                if !cueName.isEmpty {
                    out.append("Store Sequence \(seq) Cue \(formatN(cue.n)) \"\(cueName)\" \(flag) /NoConfirmation")
                } else {
                    out.append("Store Sequence \(seq) Cue \(formatN(cue.n)) \(flag) /NoConfirmation")
                }
                if !cue.fade.trimmingCharacters(in: .whitespaces).isEmpty {
                    out.append("Set Sequence \(seq) Cue \(formatN(cue.n)) Fade \(cue.fade)")
                }
                if !cue.delay.trimmingCharacters(in: .whitespaces).isEmpty {
                    out.append("Set Sequence \(seq) Cue \(formatN(cue.n)) Delay \(cue.delay)")
                }
            }
        }
        out.append("ClearAll")
        return out
    }

    /// `Set Sequence N Cue n "Note" "..."` for every cue with a non-empty
    /// sanitized note. Emits nothing for empty/whitespace-only notes.
    public static func noteLines(songs: [Song]) -> [String] {
        var out: [String] = []
        for song in songs {
            for cue in song.cues {
                let note = sanitizeNote(cue.notes)
                if note.isEmpty { continue }
                out.append("Set Sequence \(song.sequence) Cue \(formatN(cue.n)) \"Note\" \"\(note)\"")
            }
        }
        return out
    }
}
