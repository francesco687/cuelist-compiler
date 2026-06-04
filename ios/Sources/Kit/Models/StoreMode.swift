import Foundation

/// Show store mode. Mirrors web `state.storeMode`.
public enum StoreMode: String, Codable, Sendable, CaseIterable {
    case overwrite = "Overwrite"
    case merge = "Merge"

    public var flag: String { "/" + rawValue }
}
