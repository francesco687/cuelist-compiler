import Foundation

public extension Pool {
    /// Mirrors web POOL_ABBR.
    var abbreviation: String {
        switch self {
        case .color:    return "COL"
        case .dimmer:   return "DIM"
        case .position: return "POS"
        case .gobo:     return "GOB"
        case .beam:     return "BEM"
        case .focus:    return "FOC"
        }
    }

    /// Mirrors web POOL_ACCENT (hex).
    var accentHex: String {
        switch self {
        case .color:    return "#c44d8f"
        case .dimmer:   return "#d8d8d8"
        case .position: return "#5fb86a"
        case .gobo:     return "#e8a23a"
        case .beam:     return "#56c2d6"
        case .focus:    return "#a574d6"
        }
    }
}

public enum PoolDisplay {
    /// Mirrors web ACTION_COLORS — the group-block swatch palette.
    public static let actionColors = [
        "#d63a3a", "#e8552d", "#e88332", "#f0a830", "#e8c83a",
        "#d8d83a", "#b8d83a", "#6fc850", "#3aa860", "#2c8470",
        "#3ac8c8", "#56b0e0", "#4a7ed6", "#3a5ad8", "#6a52d6",
        "#a050d6", "#d650b8", "#e85a8e", "#d8d8d8"
    ]
}
