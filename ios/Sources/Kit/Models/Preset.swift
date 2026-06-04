import Foundation

/// One preset slot for a pool. fade/delay are Strings (the hub's compiler trims and
/// checks emptiness, so string fidelity matters).
public struct Preset: Codable, Equatable, Sendable {
    public var name: String
    public var fade: String
    public var delay: String

    public init(name: String = "", fade: String = "", delay: String = "") {
        self.name = name
        self.fade = fade
        self.delay = delay
    }
}
