import Foundation

public struct Cue: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()              // identity for SwiftUI lists; not persisted
    public var n: Double
    public var name: String
    public var fade: String
    public var delay: String
    public var position: String         // UI-only label (NOT the Pool.position pool)
    public var collapsed: Bool
    public var actions: [Action]
    public var notes: String

    public init(n: Double = 1, name: String = "", fade: String = "", delay: String = "",
                position: String = "", collapsed: Bool = false, actions: [Action] = [Action()],
                notes: String = "") {
        self.n = n; self.name = name; self.fade = fade; self.delay = delay
        self.position = position; self.collapsed = collapsed; self.actions = actions
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case n, name, fade, delay, position, collapsed, actions, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = try c.decodeIfPresent(Double.self, forKey: .n) ?? 1
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        fade = try c.decodeIfPresent(String.self, forKey: .fade) ?? ""
        delay = try c.decodeIfPresent(String.self, forKey: .delay) ?? ""
        position = try c.decodeIfPresent(String.self, forKey: .position) ?? ""
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        actions = try c.decodeIfPresent([Action].self, forKey: .actions) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}
