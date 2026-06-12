import Foundation

/// Which grandMA3 function an executor macro button performs.
/// `rawValue` doubles as the persisted codec segment.
public enum ExecutorFunction: String, CaseIterable, Sendable {
    case toggle, flash, on

    /// The grandMA3 keyword that engages the function.
    var keyword: String {
        switch self {
        case .toggle: "Toggle"
        case .flash: "Flash"
        case .on: "On"
        }
    }

    /// Caption rendered under the target on the macro cell.
    public var caption: String { rawValue.uppercased() }
}

/// What an executor macro button targets: an executor number on the desk's
/// current page, or an executor by its desk label.
public enum ExecutorTarget: Equatable, Sendable {
    case number(Int)      // 1...9999, current page
    case name(String)     // non-empty, trimmed

    /// The form persisted inside the slot string (no quoting).
    var encoded: String {
        switch self {
        case .number(let n): String(n)
        case .name(let s): s
        }
    }

    /// How the target renders in a grandMA3 command: bare number, quoted name.
    var commandForm: String {
        switch self {
        case .number(let n): String(n)
        case .name(let s): "\"\(s)\""
        }
    }

    /// What the macro cell displays.
    public var display: String {
        switch self {
        case .number(let n): String(n)
        case .name(let s): s
        }
    }
}

/// The value held by one Live-tab macro-pad slot: either a curated parameter-free
/// action, or an executor button (toggle / flash / on) targeting a desk executor
/// by number (current page) or by name. Encodes to/from the single `String` per
/// slot that `MacroPad` persists — an `"exec:"` prefix marks executor slots;
/// anything else is an action id. New form is `exec:<function>:<target>`; legacy
/// `exec:` / `exec:<digits>` (PR #32) decodes as a toggle, so saved pads load
/// unchanged.
public enum MacroSlot: RawRepresentable, Equatable, Sendable {
    case action(MacroAction)
    /// `target == nil` — assigned but not yet loaded; renders as pending, never fires.
    case executor(function: ExecutorFunction, target: ExecutorTarget?)

    /// Executor numbers the load sheet and the decoder accept.
    public static let executorRange: ClosedRange<Int> = 1...9999

    private static let execPrefix = "exec:"

    /// Decode a persisted slot string. Unknown action ids, unknown functions,
    /// out-of-range numbers, and whitespace-only names decode to nil (empty
    /// slot) — never a crash or a bad command.
    public init?(rawValue: String) {
        guard rawValue.hasPrefix(Self.execPrefix) else {
            guard let action = MacroAction.find(rawValue) else { return nil }
            self = .action(action)
            return
        }
        let body = rawValue.dropFirst(Self.execPrefix.count)
        let function: ExecutorFunction
        let targetRaw: Substring
        if let colon = body.firstIndex(of: ":") {
            guard let parsed = ExecutorFunction(rawValue: String(body[..<colon])) else { return nil }
            function = parsed
            targetRaw = body[body.index(after: colon)...]
        } else {
            // Legacy form only ever held digits (or nothing) and meant toggle.
            guard body.isEmpty || body.allSatisfy(\.isNumber) else { return nil }
            function = .toggle
            targetRaw = body
        }
        if targetRaw.isEmpty {
            self = .executor(function: function, target: nil)
        } else if targetRaw.allSatisfy(\.isNumber) {
            // All-digits is always a number — an executor *named* "201" resolves
            // to executor 201, which addresses the same object on MA3.
            guard let n = Int(targetRaw), Self.executorRange.contains(n) else { return nil }
            self = .executor(function: function, target: .number(n))
        } else {
            let name = targetRaw.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            self = .executor(function: function, target: .name(name))
        }
    }

    /// The string `MacroPad` persists for this slot — always the new
    /// three-segment form for executors.
    public var rawValue: String {
        switch self {
        case .action(let action): action.id
        case .executor(let function, let target):
            Self.execPrefix + function.rawValue + ":" + (target?.encoded ?? "")
        }
    }

    /// The command-line string a tap (toggle/on) or touch-down (flash) fires,
    /// or nil if this slot can't fire yet.
    public var command: String? {
        switch self {
        case .action(let action): action.command
        case .executor(let function, let target):
            target.map { "\(function.keyword) Executor \($0.commandForm)" }
        }
    }

    /// The command touch-up fires — only flash needs a release.
    public var releaseCommand: String? {
        guard case .executor(function: .flash, target: let target?) = self else { return nil }
        return "FlashOff Executor \(target.commandForm)"
    }
}
