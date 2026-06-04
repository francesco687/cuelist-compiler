import Foundation

public struct Action: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()              // identity for SwiftUI lists; NOT persisted (omitted from CodingKeys)
    public var group: String
    public var color: String            // UI-only tag (hex or ""), not used by the compiler
    /// Always carries all six pools (empty Preset when unset), matching web `newAction()`.
    public var presets: [Pool: Preset]

    public init(group: String = "", color: String = "", presets: [Pool: Preset]? = nil) {
        self.group = group
        self.color = color
        if let presets {
            self.presets = presets
        } else {
            var p: [Pool: Preset] = [:]
            for pool in Pool.allCases { p[pool] = Preset() }
            self.presets = p
        }
    }

    private enum CodingKeys: String, CodingKey { case group, color, presets }

    private struct PoolKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ pool: Pool) { self.stringValue = pool.rawValue }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
        var result: [Pool: Preset] = [:]
        for pool in Pool.allCases { result[pool] = Preset() }
        if let pc = try? c.nestedContainer(keyedBy: PoolKey.self, forKey: .presets) {
            for pool in Pool.allCases {
                if let preset = try? pc.decode(Preset.self, forKey: PoolKey(pool)) {
                    result[pool] = preset
                }
            }
        }
        presets = result
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(group, forKey: .group)
        try c.encode(color, forKey: .color)
        var pc = c.nestedContainer(keyedBy: PoolKey.self, forKey: .presets)
        for pool in Pool.allCases {
            try pc.encode(presets[pool] ?? Preset(), forKey: PoolKey(pool))
        }
    }
}
