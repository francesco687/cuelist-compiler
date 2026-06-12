import Foundation

/// A parameter-free grandMA3 command-line action that fires on the desk-selected
/// executor. Assignable to a slot on the Live tab's macro pad. `command` is the literal
/// command-line string sent through the hub's `cmd` passthrough — the same channel the
/// console-message uses.
public struct MacroAction: Identifiable, Equatable, Sendable {
    /// Stable key persisted to UserDefaults. Never reuse an id for a different action.
    public let id: String
    /// Short label shown on the button (e.g. "OFF").
    public let title: String
    /// SF Symbol name for the button glyph.
    public let symbol: String
    /// The literal command-line string fired at the desk (e.g. "Go+").
    public let command: String

    public init(id: String, title: String, symbol: String, command: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.command = command
    }

    /// The curated, parameter-free library. Append entries to grow it — ids must stay
    /// stable so existing assignments survive.
    public static let library: [MacroAction] = [
        MacroAction(id: "go_plus",  title: "GO+",   symbol: "arrow.right.circle.fill",  command: "Go+"),
        MacroAction(id: "go_minus", title: "GO\u{2212}", symbol: "arrow.left.circle.fill", command: "Go-"),
        MacroAction(id: "pause",    title: "PAUSE", symbol: "pause.circle.fill",         command: "Pause"),
        MacroAction(id: "off",      title: "OFF",   symbol: "stop.circle.fill",          command: "Off"),
        MacroAction(id: "on",       title: "ON",    symbol: "power.circle.fill",         command: "On"),
        MacroAction(id: "top",      title: "TOP",   symbol: "arrow.up.circle.fill",      command: "Top"),
    ]

    /// Look up a library action by its persisted id.
    public static func find(_ id: String) -> MacroAction? {
        library.first { $0.id == id }
    }
}
