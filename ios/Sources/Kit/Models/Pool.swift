import Foundation

/// The six grandMA3 preset pools. `allCases` order is the canonical iteration
/// order (mirrors web `POOLS`). `number` mirrors web `POOL_NUM` (the MA3 pool
/// index, which is NOT the iteration order).
public enum Pool: String, CaseIterable, Codable, Hashable, Sendable {
    case color, dimmer, position, gobo, beam, focus

    public var number: Int {
        switch self {
        case .dimmer:   return 1
        case .position: return 2
        case .gobo:     return 3
        case .color:    return 4
        case .beam:     return 5
        case .focus:    return 6
        }
    }
}
