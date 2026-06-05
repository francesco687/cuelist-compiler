import Foundation

/// Which scalar field of a cue `setCue` targets.
public enum CueField: String, Codable, Sendable { case name, fade, delay, position, number }

/// One validated edit operation. The LLM emits these via the apply_show_edits tool;
/// `song`/`cue`/`pool`/`block` are human references resolved by ShowEditApplier.
public enum ShowEdit: Equatable, Sendable {
    case addSong(name: String?, sequence: Int?)
    case renameSong(song: String, name: String)
    case setSequence(song: String, sequence: Int)
    case selectSong(song: String)
    case deleteSong(song: String)
    case addCue(song: String?, n: Double?, name: String?, fade: String?, delay: String?, position: String?)
    case setCue(song: String?, cue: Double, field: CueField, value: String)
    case deleteCue(song: String?, cue: Double)
    case sortCues(song: String?)
    case setGroup(song: String?, cue: Double, group: String, block: Int?)
    case setPreset(song: String?, cue: Double, pool: Pool, name: String?, fade: String?, delay: String?, block: Int?)
    case clearPreset(song: String?, cue: Double, pool: Pool, block: Int?)
    case addActionBlock(song: String?, cue: Double)
    case removeActionBlock(song: String?, cue: Double, block: Int)
    case copyActions(song: String?, fromCue: Double, toCue: Double)
    case setDefault(pool: Pool, fade: String?, delay: String?)
    case setStoreMode(mode: StoreMode)
}

/// The whole tool input: the edit list plus an optional clarification question.
public struct ToolInput: Decodable, Equatable, Sendable {
    public let edits: [ShowEdit]
    public let clarification: String?
}

extension ShowEdit: Decodable {
    private enum K: String, CodingKey {
        case op, song, name, sequence, cue, n, fade, delay, position
        case field, value, group, block, pool, fromCue, toCue, mode
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let op = try c.decode(String.self, forKey: .op)
        func str(_ k: K) throws -> String { try c.decode(String.self, forKey: k) }
        func optStr(_ k: K) -> String? { try? c.decode(String.self, forKey: k) }
        func optInt(_ k: K) -> Int? { try? c.decode(Int.self, forKey: k) }
        func dbl(_ k: K) throws -> Double { try c.decode(Double.self, forKey: k) }
        func pool(_ k: K) throws -> Pool {
            guard let p = Pool(rawValue: try str(k)) else {
                throw DecodingError.dataCorruptedError(forKey: k, in: c, debugDescription: "bad pool")
            }
            return p
        }
        switch op {
        case "addSong":     self = .addSong(name: optStr(.name), sequence: optInt(.sequence))
        case "renameSong":  self = .renameSong(song: try str(.song), name: try str(.name))
        case "setSequence": self = .setSequence(song: try str(.song), sequence: try c.decode(Int.self, forKey: .sequence))
        case "selectSong":  self = .selectSong(song: try str(.song))
        case "deleteSong":  self = .deleteSong(song: try str(.song))
        case "addCue":      self = .addCue(song: optStr(.song), n: try? dbl(.n), name: optStr(.name),
                                           fade: optStr(.fade), delay: optStr(.delay), position: optStr(.position))
        case "setCue":      self = .setCue(song: optStr(.song), cue: try dbl(.cue),
                                           field: try c.decode(CueField.self, forKey: .field), value: try str(.value))
        case "deleteCue":   self = .deleteCue(song: optStr(.song), cue: try dbl(.cue))
        case "sortCues":    self = .sortCues(song: optStr(.song))
        case "setGroup":    self = .setGroup(song: optStr(.song), cue: try dbl(.cue), group: try str(.group), block: optInt(.block))
        case "setPreset":   self = .setPreset(song: optStr(.song), cue: try dbl(.cue), pool: try pool(.pool),
                                              name: optStr(.name), fade: optStr(.fade), delay: optStr(.delay), block: optInt(.block))
        case "clearPreset": self = .clearPreset(song: optStr(.song), cue: try dbl(.cue), pool: try pool(.pool), block: optInt(.block))
        case "addActionBlock":    self = .addActionBlock(song: optStr(.song), cue: try dbl(.cue))
        case "removeActionBlock": self = .removeActionBlock(song: optStr(.song), cue: try dbl(.cue), block: try c.decode(Int.self, forKey: .block))
        case "copyActions": self = .copyActions(song: optStr(.song), fromCue: try dbl(.fromCue), toCue: try dbl(.toCue))
        case "setDefault":  self = .setDefault(pool: try pool(.pool), fade: optStr(.fade), delay: optStr(.delay))
        case "setStoreMode":
            self = .setStoreMode(mode: (try str(.mode)) == "Merge" ? .merge : .overwrite)
        default:
            throw DecodingError.dataCorruptedError(forKey: .op, in: c, debugDescription: "unknown op \(op)")
        }
    }
}
