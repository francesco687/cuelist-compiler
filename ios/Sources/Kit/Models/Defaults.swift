import Foundation

/// Per-pool fallback fade/delay. Mirrors web `defaults`. Stored separately from Project.
public struct Defaults: Codable, Equatable, Sendable {
    public var values: [Pool: Preset]   // only fade/delay used; name ignored

    public init(values: [Pool: Preset]? = nil) {
        if let values {
            self.values = values
        } else {
            var v: [Pool: Preset] = [:]
            for pool in Pool.allCases { v[pool] = Preset() }
            self.values = v
        }
    }

    public func fade(_ pool: Pool) -> String { values[pool]?.fade ?? "" }
    public func delay(_ pool: Pool) -> String { values[pool]?.delay ?? "" }

    private struct PoolKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ pool: Pool) { self.stringValue = pool.rawValue }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PoolKey.self)
        var v: [Pool: Preset] = [:]
        for pool in Pool.allCases {
            v[pool] = (try? c.decode(Preset.self, forKey: PoolKey(pool))) ?? Preset()
        }
        values = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PoolKey.self)
        for pool in Pool.allCases {
            try c.encode(values[pool] ?? Preset(), forKey: PoolKey(pool))
        }
    }
}
