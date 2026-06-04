import Foundation

public struct Song: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var sequence: Int
    public var cues: [Cue]
    public var audioFileName: String

    public init(id: String, name: String = "", sequence: Int = 1,
                cues: [Cue] = [], audioFileName: String = "") {
        self.id = id; self.name = name; self.sequence = sequence
        self.cues = cues; self.audioFileName = audioFileName
    }

    private enum CodingKeys: String, CodingKey { case id, name, sequence, cues, audioFileName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? IDGen.next()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        if let i = try? c.decode(Int.self, forKey: .sequence) {
            sequence = i
        } else if let s = try? c.decode(String.self, forKey: .sequence), let i = Int(s) {
            sequence = i
        } else {
            sequence = 1
        }
        cues = try c.decodeIfPresent([Cue].self, forKey: .cues) ?? []
        audioFileName = try c.decodeIfPresent(String.self, forKey: .audioFileName) ?? ""
    }
}
