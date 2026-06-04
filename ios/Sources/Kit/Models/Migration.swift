import Foundation

/// Upgrades any saved show JSON (old single-song OR current multi-song format)
/// into a current `Project`. Mirrors web migrateState/migrateCues/migrateActions.
public enum Migration {

    public static func project(fromShowJSON data: Data) throws -> Project {
        let raw = try JSONSerialization.jsonObject(with: data)
        guard var dict = raw as? [String: Any] else { throw MigrationError.notAnObject }

        // Old single-song format: { songName, sequence, cues:[...] } with no `songs`.
        if dict["songs"] == nil, let cues = dict["cues"] {
            let song: [String: Any] = [
                "id": IDGen.next(),
                "name": dict["songName"] as? String ?? "",
                "sequence": dict["sequence"] ?? 1,
                "cues": cues,
                "audioFileName": ""
            ]
            dict = ["songs": [song], "activeSongId": song["id"]!, "storeMode": "Overwrite"]
        }

        var songs = (dict["songs"] as? [[String: Any]]) ?? []
        for i in songs.indices {
            songs[i]["cues"] = normalizeCues(songs[i]["cues"] as? [[String: Any]] ?? [])
            if (songs[i]["id"] as? String) == nil { songs[i]["id"] = IDGen.next() }
            if (songs[i]["audioFileName"] as? String) == nil { songs[i]["audioFileName"] = "" }
        }
        dict["songs"] = songs

        let normalized = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(Project.self, from: normalized)
    }

    private static func normalizeCues(_ cues: [[String: Any]]) -> [[String: Any]] {
        cues.map { cue in
            var c = cue
            if (c["collapsed"] as? Bool) == nil { c["collapsed"] = false }
            if (c["position"] as? String) == nil { c["position"] = "" }
            c["actions"] = normalizeActions(c["actions"] as? [[String: Any]] ?? [])
            return c
        }
    }

    private static func normalizeActions(_ actions: [[String: Any]]) -> [[String: Any]] {
        actions.map { action in
            var a = action
            let rawPresets = a["presets"] as? [String: Any] ?? [:]
            var presets: [String: Any] = [:]
            for pool in Pool.allCases {
                let key = pool.rawValue
                switch rawPresets[key] {
                case let s as String:
                    presets[key] = ["name": s, "fade": "", "delay": ""]
                case let o as [String: Any]:
                    presets[key] = [
                        "name": o["name"] as? String ?? "",
                        "fade": stringify(o["fade"]),
                        "delay": stringify(o["delay"])
                    ]
                default:
                    presets[key] = ["name": "", "fade": "", "delay": ""]
                }
            }
            a["presets"] = presets
            if (a["group"] as? String) == nil { a["group"] = "" }
            if (a["color"] as? String) == nil { a["color"] = "" }
            return a
        }
    }

    /// fade/delay may arrive as number or string; store as string (matches JS String()).
    private static func stringify(_ v: Any?) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return numberString(n)
        default: return ""
        }
    }

    private static func numberString(_ n: NSNumber) -> String {
        if n === kCFBooleanTrue as NSNumber || n === kCFBooleanFalse as NSNumber { return "" }
        let d = n.doubleValue
        if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    }

    public enum MigrationError: Error { case notAnObject }
}
