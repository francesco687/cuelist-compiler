import Foundation

/// The value held by one Live-tab macro-pad slot: either a curated parameter-free
/// action, or an executor toggle targeting a numbered executor on the desk's
/// current page. Encodes to/from the single `String` per slot that `MacroPad`
/// persists — an `"exec:"` prefix marks executor slots; anything else is an
/// action id, so pads saved by older builds load unchanged.
public enum MacroSlot: Equatable, Sendable {
    case action(MacroAction)
    /// `number == nil` — assigned but not yet loaded; renders as pending, never fires.
    case executor(number: Int?)

    /// Executor numbers the load sheet and the decoder accept.
    public static let executorRange = 1...9999

    private static let execPrefix = "exec:"

    /// Decode a persisted slot string. Unknown action ids and malformed or
    /// out-of-range executor numbers decode to nil (empty slot) — never a crash
    /// or a bad command.
    public init?(rawValue: String) {
        if rawValue.hasPrefix(Self.execPrefix) {
            let digits = rawValue.dropFirst(Self.execPrefix.count)
            if digits.isEmpty {
                self = .executor(number: nil)
            } else if let number = Int(digits), Self.executorRange.contains(number) {
                self = .executor(number: number)
            } else {
                return nil
            }
        } else if let action = MacroAction.find(rawValue) {
            self = .action(action)
        } else {
            return nil
        }
    }

    /// The string `MacroPad` persists for this slot.
    public var rawValue: String {
        switch self {
        case .action(let action): action.id
        case .executor(let number): Self.execPrefix + (number.map(String.init) ?? "")
        }
    }

    /// The command-line string a tap fires, or nil if this slot can't fire yet.
    public var command: String? {
        switch self {
        case .action(let action): action.command
        case .executor(let number): number.map { "Toggle Executor \($0)" }
        }
    }
}
