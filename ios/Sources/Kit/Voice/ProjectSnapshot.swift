import Foundation

/// A compact JSON projection of the show the LLM reads to resolve references.
/// 1-based song indices; UUIDs and empty fields omitted to keep the prompt small.
public enum ProjectSnapshot {
    public static func json(_ p: Project) -> String {
        let activeIdx = (p.songs.firstIndex { $0.id == p.activeSongId } ?? 0) + 1
        let songs: [[String: Any]] = p.songs.enumerated().map { (i, song) in
            [
                "index": i + 1,
                "name": song.name,
                "sequence": song.sequence,
                "cues": song.cues.map { cue in cueDict(cue) }
            ]
        }
        let root: [String: Any] = ["activeSong": activeIdx, "storeMode": p.storeMode.rawValue, "songs": songs]
        let data = (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func cueDict(_ cue: Cue) -> [String: Any] {
        var d: [String: Any] = ["n": cue.n]
        if !cue.name.isEmpty { d["name"] = cue.name }
        if !cue.fade.isEmpty { d["fade"] = cue.fade }
        if !cue.delay.isEmpty { d["delay"] = cue.delay }
        if !cue.position.isEmpty { d["position"] = cue.position }
        let acts = cue.actions.compactMap { actionDict($0) }
        if !acts.isEmpty { d["actions"] = acts }
        return d
    }

    private static func actionDict(_ a: Action) -> [String: Any]? {
        var presets: [String: Any] = [:]
        for pool in Pool.allCases {
            guard let preset = a.presets[pool] else { continue }
            if preset.name.isEmpty && preset.fade.isEmpty && preset.delay.isEmpty { continue }
            var pd: [String: Any] = [:]
            if !preset.name.isEmpty { pd["name"] = preset.name }
            if !preset.fade.isEmpty { pd["fade"] = preset.fade }
            if !preset.delay.isEmpty { pd["delay"] = preset.delay }
            presets[pool.rawValue] = pd
        }
        var d: [String: Any] = [:]
        if !a.group.isEmpty { d["group"] = a.group }
        if !presets.isEmpty { d["presets"] = presets }
        return d.isEmpty ? nil : d
    }
}
