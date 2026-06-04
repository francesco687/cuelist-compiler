import Foundation

/// Mirrors web `cueSummary` — the one-line text under a collapsed cue.
public enum CueSummary {
    public static func text(for cue: Cue) -> String {
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var parts: [String] = []
        if !clean(cue.position).isEmpty { parts.append(clean(cue.position)) }
        let groups = cue.actions.filter { !clean($0.group).isEmpty }.count
        if groups > 0 { parts.append("\(groups) group\(groups > 1 ? "s" : "")") }
        if !clean(cue.fade).isEmpty { parts.append("fade \(clean(cue.fade))") }
        if !clean(cue.delay).isEmpty { parts.append("delay \(clean(cue.delay))") }
        return parts.joined(separator: " · ")
    }
}
