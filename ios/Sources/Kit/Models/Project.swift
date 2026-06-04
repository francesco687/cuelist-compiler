import Foundation

/// Mirrors web `genId()` shape. Ids never appear in command output, so the exact
/// format is not contractual — only stable + unique.
public enum IDGen {
    public static func next() -> String {
        let t = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let r = String(UInt32.random(in: 0..<UInt32.max), radix: 36)
        return "s_\(t)_\(r.prefix(6))"
    }
}

public struct Project: Codable, Equatable, Sendable {
    public var songs: [Song]
    public var activeSongId: String
    public var storeMode: StoreMode

    public init(songs: [Song], activeSongId: String, storeMode: StoreMode = .overwrite) {
        self.songs = songs; self.activeSongId = activeSongId; self.storeMode = storeMode
    }

    private enum CodingKeys: String, CodingKey { case songs, activeSongId, storeMode }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        songs = try c.decodeIfPresent([Song].self, forKey: .songs) ?? []
        activeSongId = try c.decodeIfPresent(String.self, forKey: .activeSongId) ?? ""
        let mode = try c.decodeIfPresent(String.self, forKey: .storeMode)
        storeMode = (mode == "Merge") ? .merge : .overwrite
    }

    /// A fresh project with one empty song (mirrors web `newProject()`).
    public static func empty() -> Project {
        let song = Song(id: IDGen.next(), sequence: 1, cues: [])
        return Project(songs: [song], activeSongId: song.id, storeMode: .overwrite)
    }

    public var activeSong: Song? {
        songs.first(where: { $0.id == activeSongId }) ?? songs.first
    }
}
